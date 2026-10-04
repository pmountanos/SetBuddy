export type SqlValue = string | number | null;

/**
 * The small synchronous SQLite surface the data layer needs. The app backs it with `expo-sqlite`
 * (`expoDb.ts`); tests back it with `better-sqlite3`, so repositories and importers run unchanged in Node.
 */
export interface Db {
  /** Runs one or more statements with no parameters (DDL, PRAGMA). */
  exec(sql: string): void;
  run(sql: string, params?: SqlValue[]): void;
  all<T>(sql: string, params?: SqlValue[]): T[];
  first<T>(sql: string, params?: SqlValue[]): T | null;
  /** Commits if `task` returns, rolls back if it throws. */
  transaction(task: () => void): void;
}
