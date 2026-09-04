// test/support/stub_d1.ts — ルートハンドラを実 D1 なしで試すためのスタブ。
//
// test/edit_requests.test.ts の stubDb を「発行した SQL を全部記録する」形に広げたもの。
// 記録があると、応答の形だけでなく「どんな SQL を投げたか」も assert できる。
// コールガイドの一覧では **歌詞本文の列を絶対に SELECT しない**ことが契約なので、
// 発行 SQL そのものを検査する必要がある (応答の中身を見るだけでは将来の追加を防げない)。

export type StatementKind = "first" | "all" | "run" | "batch";

export interface RecordedCall {
  sql: string;
  params: unknown[];
  kind: StatementKind;
}

/** SQL とバインド値から結果を返す。undefined を返すと種別ごとの既定値になる
 *  (first → null / all → 空 / run → changes 0)。throw すれば D1 の失敗を再現できる。 */
export type Responder = (sql: string, params: unknown[]) => unknown;

export interface StubD1 {
  db: D1Database;
  /** 発行された文 (batch に積まれた文を含む) を発行順に。 */
  calls: RecordedCall[];
  /** 発行された SQL を 1 つの文字列に連結したもの (禁止列の混入チェック用)。 */
  sql(): string;
}

export function stubD1(reply: Responder = () => undefined): StubD1 {
  const calls: RecordedCall[] = [];

  function statement(sql: string, params: unknown[]): any {
    const record = (kind: StatementKind) => calls.push({ sql, params, kind });
    return {
      sql,
      params,
      bind: (...next: unknown[]) => statement(sql, next),
      first: async () => {
        record("first");
        const v = reply(sql, params);
        return v === undefined ? null : v;
      },
      all: async () => {
        record("all");
        const v = reply(sql, params);
        return { results: v === undefined ? [] : v, success: true, meta: {} };
      },
      run: async () => {
        record("run");
        const v = reply(sql, params);
        return v === undefined ? { success: true, meta: { changes: 0 } } : v;
      },
      raw: async () => [],
    };
  }

  const db = {
    prepare: (sql: string) => statement(sql, []),
    batch: async (statements: any[]) => {
      for (const s of statements) {
        calls.push({ sql: s.sql, params: s.params, kind: "batch" });
        // responder に書き込みを見せる (書いた内容を後続の SELECT に反映させたい
        // テストのため)。戻り値は使わない — batch の結果形は D1 が決める。
        reply(s.sql, s.params);
      }
      return statements.map(() => ({ success: true, meta: { changes: 1 }, results: [] }));
    },
  } as unknown as D1Database;

  return { db, calls, sql: () => calls.map((c) => c.sql).join("\n") };
}

/** index.ts の makeResponders と同じ形のレスポンダ (CORS ヘッダは省く)。 */
export const responders = {
  json: (data: unknown, status = 200, extraHeaders: Record<string, string> = {}) =>
    new Response(JSON.stringify(data), {
      status,
      headers: { "Content-Type": "application/json; charset=utf-8", ...extraHeaders },
    }),
  error: (message: string, status = 400) =>
    new Response(JSON.stringify({ error: message }), {
      status,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    }),
  rateLimitResponse: (used: number, limit: number, resetAt: string) =>
    new Response(JSON.stringify({ error: "rate_limit_exceeded", limit, used, reset_at: resetAt }), {
      status: 429,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    }),
  rateLimitSimple: (retryAfter = 60) =>
    new Response(JSON.stringify({ error: "rate_limit_exceeded" }), {
      status: 429,
      headers: { "Content-Type": "application/json; charset=utf-8", "Retry-After": String(retryAfter) },
    }),
};
