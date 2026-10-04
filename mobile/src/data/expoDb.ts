import type { SQLiteDatabase } from 'expo-sqlite';

import type { Db, SqlValue } from './db';

/** `Db` over an open expo-sqlite database. */
export function expoDb(database: SQLiteDatabase): Db {
  // expo-sqlite can't nest transactions; repositories compose (one transactional method calling another), so
  // an inner call simply joins the outer transaction.
  let depth = 0;
  return {
    exec: (sql) => database.execSync(sql),
    run: (sql, params: SqlValue[] = []) => {
      database.runSync(sql, params);
    },
    all: <T>(sql: string, params: SqlValue[] = []) => database.getAllSync<T>(sql, params),
    first: <T>(sql: string, params: SqlValue[] = []) => database.getFirstSync<T>(sql, params),
    transaction: (task) => {
      if (depth > 0) {
        task();
        return;
      }
      depth += 1;
      try {
        database.withTransactionSync(task);
      } finally {
        depth -= 1;
      }
    },
  };
}
