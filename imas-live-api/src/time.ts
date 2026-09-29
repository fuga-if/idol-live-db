// time.ts — D1 (SQLite) の日時と epoch 秒の変換。

/**
 * "2026-08-05 12:00:00" (SQLite datetime('now') 形式・UTC) を epoch 秒に変換する。読めなければ 0。
 * iOS の APIClient が .secondsSince1970 でデコードするため、応答の日時は必ず秒 epoch の数値。
 * ミリ秒や ISO 文字列にすると iOS 側のデコードが落ちる。
 */
export function sqliteTimestampToEpochSeconds(ts: string | null | undefined): number {
  if (!ts) return 0;
  const ms = Date.parse(ts.replace(" ", "T") + "Z");
  return Number.isNaN(ms) ? 0 : Math.floor(ms / 1000);
}
