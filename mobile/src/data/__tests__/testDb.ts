import Database from 'better-sqlite3';
import { randomUUID } from 'node:crypto';

import type { Db, SqlValue } from '../db';

/** `Db` over better-sqlite3 — the Node stand-in for the app's expo-sqlite adapter. */
export function openTestDb(path = ':memory:', options: { readonly?: boolean } = {}): Db & { close(): void } {
  const raw = new Database(path, { readonly: options.readonly ?? false });
  return {
    exec: (sql) => {
      raw.exec(sql);
    },
    run: (sql, params: SqlValue[] = []) => {
      raw.prepare(sql).run(...params);
    },
    all: <T>(sql: string, params: SqlValue[] = []) => raw.prepare(sql).all(...params) as T[],
    first: <T>(sql: string, params: SqlValue[] = []) => (raw.prepare(sql).get(...params) as T | undefined) ?? null,
    transaction: (task) => {
      raw.transaction(task)();
    },
    close: () => {
      raw.close();
    },
  };
}

export const newId = (): string => randomUUID();
