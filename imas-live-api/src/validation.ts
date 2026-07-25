import type { Env } from "./env";

// validation.ts — リクエスト入力の共通バリデータ
//
// index.ts と routes/ の双方から使うため独立させている (index.ts に置くと
// ルートモジュールからの import が循環する)。

/** クエリの正整数。範囲外・非数値は defaultValue、上限は max で頭打ち。 */
export function parsePositiveInt(v: string | null, defaultValue: number, max: number = 1000): number {
  const n = parseInt(v ?? "");
  if (!Number.isFinite(n) || n < 1) return defaultValue;
  return Math.min(n, max);
}

// predictions / performers / likes / poll votes / favorites は songs・idols マスタの
// 実在チェックをせず「不透明キー」として保存する設計 (CloudKit 新曲が D1 未同期でも
// 投票できるようにするため。各エンドポイントのコメント参照)。実在チェックの代わりに
// 長さ上限 + 空文字拒否だけを行い、無制限文字列によるストレージ濫用を防ぐ。
const OPAQUE_KEY_MAX_LEN = 200;

export function validateOpaqueKey(value: unknown, fieldName: string): string | null {
  if (typeof value !== "string" || value.length === 0) return `${fieldName} is required`;
  if (value.length > OPAQUE_KEY_MAX_LEN) return `${fieldName} must be ${OPAQUE_KEY_MAX_LEN} characters or less`;
  return null;
}

export function escapeLike(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_");
}

export function parseScopeIds(raw: string | null | undefined): string[] | null {
  if (raw == null) return null;
  try {
    const v = JSON.parse(raw);
    if (Array.isArray(v) && v.every((x) => typeof x === "string")) return v;
  } catch {
    /* fallthrough */
  }
  return null;
}

export async function validateScopeIdsAgainstTable(
  db: D1Database,
  input: any,
  opts: {
    minLen: number;
    maxLen: number;
    maxEntryLen: number;
    allowDuplicates: boolean;
    /**
     * 実在チェック対象テーブル。 null の場合は実在チェックをスキップ。
     * - `brands`: 件数が少なく typo を弾きたいので必須
     * - `songs`/`idols`: バンドル master.sqlite と server D1 の同期ラグで
     *   クライアント側に存在する ID が server に未投入のことがあるため null 推奨
     */
    table: "brands" | "songs" | "idols" | null;
    fieldName: string;
  }
): Promise<{ json: string } | { error: string }> {
  if (!Array.isArray(input) || input.length < opts.minLen) {
    return { error: `${opts.fieldName} must contain at least ${opts.minLen} ${opts.minLen === 1 ? "entry" : "entries"}` };
  }
  if (input.length > opts.maxLen) {
    return { error: `${opts.fieldName} must contain at most ${opts.maxLen} entries` };
  }
  if (!input.every((v: any) => typeof v === "string" && v.length > 0 && v.length <= opts.maxEntryLen)) {
    return { error: `${opts.fieldName} entries must be non-empty strings` };
  }
  const unique = Array.from(new Set(input as string[]));
  if (!opts.allowDuplicates && unique.length !== input.length) {
    return { error: `${opts.fieldName} contains duplicates` };
  }
  if (opts.table != null) {
    const rows = await db
      .prepare(`SELECT id FROM ${opts.table} WHERE id IN (${unique.map(() => "?").join(",")})`)
      .bind(...unique)
      .all<{ id: string }>();
    if ((rows.results?.length ?? 0) !== unique.length) {
      return { error: `${opts.fieldName} contains unknown id` };
    }
  }
  return { json: JSON.stringify(unique) };
}
