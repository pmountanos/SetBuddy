import { strToU8, zipSync } from 'fflate';

/** A text cell or a numeric cell. */
export type Cell = string | number;

export class ExportError extends Error {}

/** 0-based index → Excel column letters ("A", …, "Z", "AA", …). */
export function columnLetters(index: number): string {
  let n = index;
  let letters = '';
  do {
    letters = String.fromCharCode(65 + (n % 26)) + letters;
    n = Math.floor(n / 26) - 1;
  } while (n >= 0);
  return letters;
}

export function escapeXmlText(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

export function csvEscape(text: string): string {
  return /[,"\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/** UTF-8 with a byte-order mark (so Excel reads accents correctly), lines joined by `\n`. */
export function csvBytes(lines: string[]): Uint8Array {
  const body = strToU8(lines.join('\n'));
  const bytes = new Uint8Array(body.length + 3);
  bytes.set([0xef, 0xbb, 0xbf]);
  bytes.set(body, 3);
  return bytes;
}

/** One worksheet part from a grid of rows. */
export function worksheetXml(rows: Cell[][]): string {
  const body = rows
    .map((row, rowIndex) => {
      const r = rowIndex + 1;
      const cells = row
        .map((cell, colIndex) => {
          const ref = `${columnLetters(colIndex)}${r}`;
          return typeof cell === 'number'
            ? `<c r="${ref}"><v>${Number.isFinite(cell) ? cell : 0}</v></c>`
            : `<c r="${ref}" t="inlineStr"><is><t>${escapeXmlText(cell)}</t></is></c>`;
        })
        .join('');
      return `<row r="${r}">${cells}</row>\n`;
    })
    .join('');
  return (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n' +
    `<sheetData>\n${body}</sheetData></worksheet>`
  );
}

const XML_HEADER = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const numbered = (count: number, each: (n: number) => string) => Array.from({ length: count }, (_, i) => each(i + 1)).join('\n');

/** The smallest valid `.xlsx`: one worksheet part per sheet, text stored inline (no shared strings or styles). */
export function makeWorkbook(sheets: { name: string; rows: Cell[][] }[]): Uint8Array {
  if (sheets.length === 0) throw new ExportError('Could not create the spreadsheet file.');
  const files: Record<string, Uint8Array> = {
    '[Content_Types].xml': strToU8(
      `${XML_HEADER}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
${numbered(sheets.length, (n) => `<Override PartName="/xl/worksheets/sheet${n}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`)}
</Types>`,
    ),
    '_rels/.rels': strToU8(
      `${XML_HEADER}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`,
    ),
    'xl/_rels/workbook.xml.rels': strToU8(
      `${XML_HEADER}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${numbered(sheets.length, (n) => `<Relationship Id="rId${n}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${n}.xml"/>`)}
</Relationships>`,
    ),
    'xl/workbook.xml': strToU8(
      `${XML_HEADER}<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
${sheets.map((sheet, i) => `<sheet name="${escapeXmlText(sheet.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join('')}
</sheets>
</workbook>`,
    ),
  };
  sheets.forEach((sheet, i) => {
    files[`xl/worksheets/sheet${i + 1}.xml`] = strToU8(worksheetXml(sheet.rows));
  });
  return zipSync(files);
}

/** Sheet names: no `: \ / ? * [ ]`, at most 31 characters, unique within the workbook. */
export function uniqueSheetName(rawName: string, used: Set<string>): string {
  let base = rawName.replace(/[:\\/?*[\]]/g, '').trim() || 'Workout';
  if (base.length > 31) base = base.slice(0, 31);
  let candidate = base;
  for (let suffixIndex = 2; used.has(candidate); suffixIndex++) {
    const suffix = ` (${suffixIndex})`;
    candidate = base.slice(0, 31 - suffix.length) + suffix;
  }
  used.add(candidate);
  return candidate;
}
