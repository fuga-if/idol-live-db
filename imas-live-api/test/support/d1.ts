// test/support/d1.ts — ローカル D1 (migrations 適用済み) を直接読み書きするテスト用ヘルパ。

import { env } from "cloudflare:test";

/** 1 文を実行して全行を返す。 */
export async function rows<T = Record<string, unknown>>(sql: string, ...params: unknown[]): Promise<T[]> {
  const { results } = await env.DB.prepare(sql).bind(...params).all<T>();
  return results ?? [];
}

/** 1 文を実行して先頭行を返す (無ければ null)。 */
export async function row<T = Record<string, unknown>>(sql: string, ...params: unknown[]): Promise<T | null> {
  return env.DB.prepare(sql).bind(...params).first<T>();
}

/** 書き込みを 1 文実行する。 */
export async function exec(sql: string, ...params: unknown[]): Promise<void> {
  await env.DB.prepare(sql).bind(...params).run();
}

/** users に 1 行入れる (ログイン済みユーザーの前提を作る)。 */
export async function insertUser(
  uid: string,
  opts: { displayName?: string; isAdmin?: boolean; isBanned?: boolean } = {}
): Promise<void> {
  await exec(
    "INSERT INTO users (id, display_name, is_admin, is_banned) VALUES (?, ?, ?, ?)",
    uid,
    opts.displayName ?? "テストユーザー",
    opts.isAdmin ? 1 : 0,
    opts.isBanned ? 1 : 0
  );
}

/** 1 リクエストで使った D1 の行数 (D1 の課金単位。miniflare が meta に載せる値)。 */
export interface D1Usage {
  rowsRead: number;
  rowsWritten: number;
  statements: number;
  /** 文ごとの内訳 (発行順)。どの文が読んでいるかを見るため。 */
  log: Array<{ sql: string; rowsRead: number; rowsWritten: number }>;
}

/**
 * D1 を包んで、発行した文の meta.rows_read / rows_written を合算する。
 * エンドポイントの 1 リクエストあたりの読み書き行数を、変更の前後で比べるために使う。
 *
 * first() も all() で実行して meta を拾う。D1 は first() でも文を最後まで実行するので、
 * 読み取り行数は変わらない。
 */
export function meterD1(db: D1Database = env.DB): { db: D1Database; usage: D1Usage; reset(): void } {
  const usage: D1Usage = { rowsRead: 0, rowsWritten: 0, statements: 0, log: [] };
  const record = (sql: string, meta: { rows_read?: number; rows_written?: number } | undefined) => {
    const rowsRead = meta?.rows_read ?? 0;
    const rowsWritten = meta?.rows_written ?? 0;
    usage.rowsRead += rowsRead;
    usage.rowsWritten += rowsWritten;
    usage.statements += 1;
    usage.log.push({ sql: sql.replace(/\s+/g, " ").trim(), rowsRead, rowsWritten });
  };

  const wrap = (inner: D1PreparedStatement, sql: string): D1PreparedStatement =>
    ({
      inner,
      sql,
      bind: (...values: unknown[]) => wrap(inner.bind(...values), sql),
      first: async (column?: string) => {
        const result = await inner.all<Record<string, unknown>>();
        record(sql, result.meta);
        const first = result.results[0] ?? null;
        return column === undefined ? first : (first?.[column] ?? null);
      },
      all: async () => {
        const result = await inner.all();
        record(sql, result.meta);
        return result;
      },
      run: async () => {
        const result = await inner.run();
        record(sql, result.meta);
        return result;
      },
      raw: async () => {
        throw new Error("meterD1: raw() is not supported");
      },
    }) as unknown as D1PreparedStatement;

  const metered = {
    prepare: (sql: string) => wrap(db.prepare(sql), sql),
    batch: async (statements: D1PreparedStatement[]) => {
      const wrapped = statements as unknown as Array<{ inner: D1PreparedStatement; sql: string }>;
      const results = await db.batch(wrapped.map((s) => s.inner));
      results.forEach((r, i) => record(`[batch] ${wrapped[i].sql}`, r.meta));
      return results;
    },
    exec: (sql: string) => db.exec(sql),
    dump: () => db.dump(),
  } as unknown as D1Database;

  return {
    db: metered,
    usage,
    reset() {
      usage.rowsRead = 0;
      usage.rowsWritten = 0;
      usage.statements = 0;
      usage.log = [];
    },
  };
}
