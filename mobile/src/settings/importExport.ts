import * as DocumentPicker from 'expo-document-picker';
import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import { Platform } from 'react-native';

import type { ImportedCycleDay } from '@/domain/carryoverMatcher';
import { parseProgramXlsx } from '@/xlsx/readWorkbook';

const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/** Older workbooks named after the app import as plain "Set Buddy" rather than their file name. */
const LEGACY_FILE_TITLES = new Set(['workout buddy', 'workout buddy-2', 'workout buddy 2', 'set buddy-2', 'set buddy 2']);

/** Program name for an imported workbook: its file name without the extension. */
export function programNameFromFileName(fileName: string): string {
  const title = fileName.replace(/\.xlsx$/i, '').trim();
  if (LEGACY_FILE_TITLES.has(title.toLowerCase())) return 'Set Buddy';
  return title || 'Imported program';
}

export interface PickedWorkbook {
  programName: string;
  cycle: ImportedCycleDay[];
}

/** Lets the user pick an `.xlsx` file and parses it. Resolves to `null` if they cancel; throws if it can't be read. */
export async function pickProgramWorkbook(): Promise<PickedWorkbook | null> {
  const result = await DocumentPicker.getDocumentAsync({
    // Some Android file providers report spreadsheets as generic binary files.
    type: Platform.OS === 'android' ? [XLSX_MIME, 'application/octet-stream'] : XLSX_MIME,
    copyToCacheDirectory: true,
  });
  if (result.canceled) return null;
  const asset = result.assets[0];
  const file = new File(asset.uri);
  try {
    return { programName: programNameFromFileName(asset.name), cycle: parseProgramXlsx(await file.bytes()) };
  } finally {
    if (file.exists) file.delete();
  }
}

/** `yyyy-MM-dd_HHmmss` in local time, for export file names. */
function fileStamp(now: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

/**
 * Writes an export to a temporary file and opens the share sheet. Prefers `.xlsx`, falling back to `.csv` if the
 * workbook can't be built. The temporary file is removed once the share sheet closes.
 */
export async function shareExport(prefix: string, buildXlsx: () => Uint8Array, buildCsv: () => Uint8Array): Promise<void> {
  let bytes: Uint8Array;
  let extension = 'xlsx';
  let mimeType = XLSX_MIME;
  let UTI = 'org.openxmlformats.spreadsheetml.sheet';
  try {
    bytes = buildXlsx();
  } catch {
    bytes = buildCsv();
    extension = 'csv';
    mimeType = 'text/csv';
    UTI = 'public.comma-separated-values-text';
  }
  const file = new File(Paths.cache, `${prefix}_${fileStamp(new Date())}.${extension}`);
  if (file.exists) file.delete();
  file.create();
  try {
    await file.write(bytes);
    await Sharing.shareAsync(file.uri, { mimeType, UTI, dialogTitle: file.name });
  } finally {
    if (file.exists) file.delete();
  }
}
