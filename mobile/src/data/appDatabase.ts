import { randomUUID } from 'expo-crypto';
import { Directory, File, Paths } from 'expo-file-system';
import { defaultDatabaseDirectory, deleteDatabaseSync, openDatabaseSync } from 'expo-sqlite';
import { Platform } from 'react-native';

import { calendarDateOf } from '../domain/calendarDate';
import type { Db } from './db';
import { expoDb } from './expoDb';
import { importSwiftDataStore, isSetBuddySwiftDataStore, type SwiftDataImportSummary } from './legacy/swiftDataStore';
import type { Env } from './models';
import { prepareDatabase, schemaVersion } from './schema';

const DATABASE_NAME = 'setbuddy.db';
/** Working copy of the native iOS store, opened read-only-in-spirit and deleted after the import. */
const SWIFTDATA_COPY_NAME = 'legacy-import.store';
/** SQLite keeps recent writes in sidecar files; they must travel with the main file or those writes are lost. */
const SQLITE_SIDECARS = ['', '-wal', '-shm', '-journal'];

export const appEnv: Env = {
  newId: () => randomUUID(),
  now: () => Date.now(),
  today: () => calendarDateOf(new Date()),
};

/** What happened to data left behind by the native app this build replaces, on this launch. */
export type LegacyImport =
  | { source: 'none' }
  | { source: 'android-database' }
  | { source: 'swiftdata-store'; summary: SwiftDataImportSummary };

export interface AppDatabase {
  db: Db;
  legacyImport: LegacyImport;
}

function sqliteDirectory(): Directory {
  const path: string = defaultDatabaseDirectory;
  const directory = new Directory(path.startsWith('file://') ? path : `file://${path}`);
  if (!directory.exists) directory.create({ intermediates: true, idempotent: true });
  return directory;
}

/** Copies a SQLite database and whichever of its sidecar files exist. Returns false if there is no database. */
async function copySqliteFiles(from: Directory, fromName: string, to: Directory, toName: string): Promise<boolean> {
  if (!new File(from, fromName).exists) return false;
  for (const suffix of SQLITE_SIDECARS) {
    const source = new File(from, fromName + suffix);
    const destination = new File(to, toName + suffix);
    if (destination.exists) destination.delete();
    if (source.exists) await source.copy(destination);
  }
  return true;
}

function deleteSqliteFiles(directory: Directory, name: string): void {
  for (const suffix of SQLITE_SIDECARS) {
    const file = new File(directory, name + suffix);
    if (file.exists) file.delete();
  }
}

/**
 * Opens the app database, creating or migrating it as needed. On the first launch after upgrading from a native
 * build it first brings that build's data across:
 *
 * - **Android:** the Kotlin app's `databases/setbuddy.db` has the same schema, so it is copied into place and
 *   migrated forward like any other existing database.
 * - **iOS:** the SwiftData store in `Library/Application Support/default.store` is copied, read, and imported.
 *
 * The native app's own files are only ever read, never changed or removed — reinstalling the native build finds
 * its data exactly as it left it. If the iOS import fails, the new database is discarded so the next launch
 * retries from scratch instead of starting empty.
 */
export async function openAppDatabase(): Promise<AppDatabase> {
  const directory = sqliteDirectory();
  const appData = Paths.document.parentDirectory;
  let legacyImport: LegacyImport = { source: 'none' };

  const isFirstLaunch = !new File(directory, DATABASE_NAME).exists;
  if (isFirstLaunch && Platform.OS === 'android') {
    const copied = await copySqliteFiles(new Directory(appData, 'databases'), DATABASE_NAME, directory, DATABASE_NAME);
    if (copied) legacyImport = { source: 'android-database' };
  }

  const database = openDatabaseSync(DATABASE_NAME);
  const db = expoDb(database);
  const isEmpty = schemaVersion(db) === 0;
  prepareDatabase(db);

  if (isEmpty && Platform.OS === 'ios') {
    const nativeStore = new Directory(appData, 'Library', 'Application Support');
    try {
      if (await copySqliteFiles(nativeStore, 'default.store', directory, SWIFTDATA_COPY_NAME)) {
        const storeDatabase = openDatabaseSync(SWIFTDATA_COPY_NAME);
        try {
          const store = expoDb(storeDatabase);
          if (isSetBuddySwiftDataStore(store)) {
            legacyImport = { source: 'swiftdata-store', summary: importSwiftDataStore(store, db, appEnv.newId) };
          }
        } finally {
          storeDatabase.closeSync();
        }
      }
    } catch (error) {
      database.closeSync();
      deleteDatabaseSync(DATABASE_NAME);
      throw error;
    } finally {
      deleteSqliteFiles(directory, SWIFTDATA_COPY_NAME);
    }
  }

  return { db, legacyImport };
}
