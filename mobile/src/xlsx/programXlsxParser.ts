import type { ImportedCycleDay, ImportedCycleExercise } from '../domain/carryoverMatcher';
import { parseXml } from './miniSax';

/**
 * Parses `.xlsx` workbooks where each **worksheet** is one day in the rotation.
 *
 * Workout days: **A** = exercise name (unless row-1 headers say otherwise). **Notes** and **per-side** columns
 * are detected from row-1 headers (`Notes`, `Per side`, `Per Set`, …). Legacy default if no headers: **B** = note,
 * **C** = per-side. Rest days: sheet name contains "rest" (case-insensitive) **or** the sheet has no exercise rows.
 *
 * Cardio: a row whose columns read **Minutes** / **Peak HR** (or a close synonym) marks the start of a cardio
 * section — every name below it, to the end of the sheet, becomes a cardio exercise (minutes/max heart rate
 * instead of weight/reps). A sheet can be all cardio (whole cardio day) or strength rows followed by a cardio
 * section (e.g. finishing a lift day with a cardio set). A **Type** column, as written by this app's own program
 * export, also marks cardio rows, so an exported program imports back unchanged.
 */

export const DEFAULT_SET_COUNT_PER_EXERCISE = 4;

export class ProgramImportError extends Error {}

/** Cell text by `A1`-style address; empty cells are absent. */
export type SheetCells = ReadonlyMap<string, string>;

/** Reads one file out of the workbook archive as text, or `undefined` if it isn't there. */
export type ArchiveReader = (entryPath: string) => string | undefined;

export function parseProgramWorkbook(readEntry: ArchiveReader): ImportedCycleDay[] {
  const required = (path: string) => {
    const text = readEntry(path);
    if (text === undefined) throw new ProgramImportError(`This doesn't look like a spreadsheet Set Buddy can read (missing ${path}).`);
    return text;
  };
  const sheets = parseWorkbookSheets(required('xl/workbook.xml'));
  const targets = parseWorkbookRels(required('xl/_rels/workbook.xml.rels'));
  const sharedStringsXml = readEntry('xl/sharedStrings.xml');
  const sharedStrings = sharedStringsXml === undefined ? [] : parseSharedStrings(sharedStringsXml);

  const cycle: ImportedCycleDay[] = [];
  for (const sheet of sheets) {
    const target = targets.get(sheet.relationshipId);
    if (!target) continue;
    // Targets are relative to xl/ unless they start with a slash (then they're relative to the archive root).
    const entryPath = target.startsWith('/') ? target.replace(/^\/+/, '') : `xl/${target}`;
    const exercises = exercisesFromSheet(parseSheetCells(required(entryPath), sharedStrings));
    const isRestDay = /rest/i.test(sheet.name) || exercises.length === 0;
    cycle.push({ sheetName: sheet.name, isRestDay, exercises: isRestDay ? [] : exercises });
  }
  if (cycle.length === 0) throw new ProgramImportError('The workbook has no worksheets.');
  return cycle;
}

// -- Column mapping ----------------------------------------------------------

const HEADER_SCAN_COLUMNS = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

const isPerSideTitle = (low: string) => ['per set', 'perset', 'per-side', 'per side', 'perside'].includes(low);
const isNotesTitle = (low: string) => low === 'notes' || low === 'note' || low.startsWith('note ');
const isExerciseTitle = (low: string) =>
  low.includes('excercise') || (low.includes('exercise') && low.includes('name')) || low === 'exercise' || low === 'movement';
const isMinutesTitle = (low: string) => ['minutes', 'min', 'mins'].includes(low);
const isMaxHeartRateTitle = (low: string) =>
  ['peak hr', 'max hr', 'max heart rate', 'peak heart rate', 'heart rate', 'hr'].includes(low);

interface ColumnMapping {
  nameCol: string;
  noteCol: string | undefined;
  perSideCol: string;
  /** A **Type** column (as written by this app's own program export): `cardio` marks a cardio exercise. */
  typeCol: string | undefined;
}

const cellText = (cells: SheetCells, col: string, row: number) => cells.get(`${col}${row}`)?.trim() ?? '';

function columnMapping(cells: SheetCells): ColumnMapping {
  let nameCol: string | undefined;
  let noteCol: string | undefined;
  let perSideCol: string | undefined;
  let typeCol: string | undefined;
  for (const col of HEADER_SCAN_COLUMNS) {
    const low = cellText(cells, col, 1).toLowerCase();
    if (!low) continue;
    if (isPerSideTitle(low)) perSideCol ??= col;
    else if (isNotesTitle(low)) noteCol ??= col;
    else if (isExerciseTitle(low)) nameCol ??= col;
    else if (low === 'type') typeCol ??= col;
  }
  const resolvedName = nameCol ?? 'A';
  const resolvedPerSide = perSideCol ?? 'C';
  let resolvedNote = noteCol;
  if (!resolvedNote) {
    if (resolvedPerSide === 'B') resolvedNote = resolvedName === 'C' ? 'D' : 'C';
    else if (resolvedPerSide === 'C') resolvedNote = resolvedName === 'B' ? 'D' : 'B';
    else resolvedNote = ['B', 'C'].find((col) => col !== resolvedName && col !== resolvedPerSide);
  }
  return { nameCol: resolvedName, noteCol: resolvedNote, perSideCol: resolvedPerSide, typeCol };
}

function isLikelyHeaderRow(cells: SheetCells, mapping: ColumnMapping): boolean {
  const name = cellText(cells, mapping.nameCol, 1).toLowerCase();
  if (name.includes('excercise') || (name.includes('exercise') && name.includes('name'))) return true;
  return ['B', 'C', 'D'].some((col) => {
    const header = cellText(cells, col, 1).toLowerCase();
    return isPerSideTitle(header) || isNotesTitle(header);
  });
}

/** Marker set is exact-equality (not substring), case-insensitive, trimmed. */
export function marksRepsPerSide(text: string | undefined): boolean {
  return ['x', '×', '✓', '✔', 'yes', 'y', '1', 'true'].includes((text ?? '').trim().toLowerCase());
}

function rowNumber(address: string): number {
  return Number(address.replace(/^[A-Za-z]+/, '')) || 0;
}

function sortedRows(cells: SheetCells): number[] {
  return [...new Set([...cells.keys()].map(rowNumber))].filter((row) => row >= 1).sort((a, b) => a - b);
}

/**
 * Row (1-based) of a **Minutes** / **Peak HR** (or synonym) header pair marking where a cardio section starts,
 * if the sheet has one — searched left-to-right, top-to-bottom, first match wins.
 */
export function cardioSectionHeaderRow(cells: SheetCells): number | undefined {
  for (const row of sortedRows(cells)) {
    for (let index = 0; index < HEADER_SCAN_COLUMNS.length - 1; index++) {
      if (!isMinutesTitle(cellText(cells, HEADER_SCAN_COLUMNS[index], row).toLowerCase())) continue;
      if (isMaxHeartRateTitle(cellText(cells, HEADER_SCAN_COLUMNS[index + 1], row).toLowerCase())) return row;
    }
  }
  return undefined;
}

/** Strength rows, then (if the sheet has a cardio section header) the cardio rows below it. */
export function exercisesFromSheet(cells: SheetCells): ImportedCycleExercise[] {
  const mapping = columnMapping(cells);
  const cardioHeaderRow = cardioSectionHeaderRow(cells);
  const headerRow = isLikelyHeaderRow(cells, mapping);
  const result: ImportedCycleExercise[] = [];
  for (const row of sortedRows(cells)) {
    if (row === cardioHeaderRow) continue;
    const name = cellText(cells, mapping.nameCol, row);
    if (!name) continue;
    if (cardioHeaderRow !== undefined && row > cardioHeaderRow) {
      // Name only — minutes/max heart rate are logged per session, not imported.
      result.push({ name, note: null, repsArePerSide: false, kind: 'cardio' });
      continue;
    }
    if (row === 1 && headerRow) continue;
    const note = mapping.noteCol ? cellText(cells, mapping.noteCol, row) || null : null;
    const isCardio = mapping.typeCol !== undefined && cellText(cells, mapping.typeCol, row).toLowerCase() === 'cardio';
    result.push({
      name,
      note,
      repsArePerSide: !isCardio && marksRepsPerSide(cells.get(`${mapping.perSideCol}${row}`)),
      kind: isCardio ? 'cardio' : 'strength',
    });
  }
  return result;
}

// -- Workbook XML ------------------------------------------------------------

function parseWorkbookSheets(xml: string): { name: string; relationshipId: string }[] {
  const sheets: { name: string; relationshipId: string }[] = [];
  parseXml(xml, {
    start(name, attributes) {
      if (name !== 'sheet' || attributes.name === undefined) return;
      const relationshipId = attributes['r:id'] ?? Object.values(attributes).find((value) => value.startsWith('rId'));
      if (relationshipId) sheets.push({ name: attributes.name, relationshipId });
    },
  });
  return sheets;
}

function parseWorkbookRels(xml: string): Map<string, string> {
  const targets = new Map<string, string>();
  parseXml(xml, {
    start(name, attributes) {
      if (name !== 'Relationship') return;
      const id = attributes.Id ?? attributes.id;
      const target = attributes.Target ?? attributes.target;
      if (id && target) targets.set(id, target);
    },
  });
  return targets;
}

function parseSharedStrings(xml: string): string[] {
  const strings: string[] = [];
  let current: string | undefined;
  parseXml(xml, {
    start(name) {
      if (name === 'si') current = '';
    },
    text(text) {
      if (current !== undefined) current += text;
    },
    end(name) {
      if (name === 'si' && current !== undefined) {
        strings.push(current.trim());
        current = undefined;
      }
    },
  });
  return strings;
}

export function parseSheetCells(xml: string, sharedStrings: readonly string[]): Map<string, string> {
  const cells = new Map<string, string>();
  let ref: string | undefined;
  let type: string | undefined;
  let value = '';
  let inline = '';
  let inValue = false;
  let inInlineText = false;
  parseXml(xml, {
    start(name, attributes) {
      if (name === 'c') {
        ref = attributes.r;
        type = attributes.t;
        value = '';
        inline = '';
      } else if (name === 'v') {
        inValue = true;
        value = '';
      } else if (name === 't' && type === 'inlineStr') {
        inInlineText = true;
      }
    },
    text(text) {
      if (inValue) value += text;
      if (inInlineText) inline += text;
    },
    end(name) {
      if (name === 'v') inValue = false;
      else if (name === 't') inInlineText = false;
      else if (name === 'c') {
        if (ref) {
          const raw = value.trim();
          let resolved = raw;
          if (type === 's') resolved = sharedStrings[Number(raw)] ?? raw;
          else if (type === 'b') resolved = raw === '1' ? 'TRUE' : 'FALSE';
          else if (type === 'inlineStr') resolved = inline.trim();
          if (resolved) cells.set(ref, resolved);
        }
        ref = undefined;
        type = undefined;
      }
    },
  });
  return cells;
}
