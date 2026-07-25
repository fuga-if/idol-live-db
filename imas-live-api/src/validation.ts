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
