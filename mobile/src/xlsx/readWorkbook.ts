import { strFromU8, unzipSync } from 'fflate';

import type { ImportedCycleDay } from '../domain/carryoverMatcher';
import { type ArchiveReader, parseProgramWorkbook, ProgramImportError } from './programXlsxParser';

/** Looks entries up by exact path first, then case-insensitively (some writers vary the casing). */
export function archiveReader(xlsx: Uint8Array): ArchiveReader {
  let entries: Record<string, Uint8Array>;
  try {
    entries = unzipSync(xlsx);
  } catch {
    throw new ProgramImportError("That file isn't a valid .xlsx workbook.");
  }
  const byLowerPath = new Map(Object.keys(entries).map((path) => [path.toLowerCase(), path]));
  return (entryPath) => {
    const normalized = entryPath.replace(/\\/g, '/');
    const path = normalized in entries ? normalized : byLowerPath.get(normalized.toLowerCase());
    return path === undefined ? undefined : strFromU8(entries[path]);
  };
}

/** Parses the bytes of an `.xlsx` file into the rotation it describes, one entry per worksheet. */
export function parseProgramXlsx(xlsx: Uint8Array): ImportedCycleDay[] {
  return parseProgramWorkbook(archiveReader(xlsx));
}
