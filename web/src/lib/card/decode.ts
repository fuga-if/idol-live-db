/**
 * P名刺の読み解き — **差し替え可能な import 面 (配管であって規則ではない)**。
 *
 * 実体は `imas_core::domain::producer_card` を wasm にしたもの
 * (`web/wasm/imas-query-wasm` の `decode_producer_card_json`)。
 * ここがやるのは「wasm をロードし、返ってきた JSON 文字列を parse する」ことだけで、
 * URL の形を確かめる・base64url を外す・名刺かどうかを判断する、といった読み解きは
 * 一切書かない (`src/lib/search/fold.ts` / `src/lib/listfilter/query.ts` と同じ流儀)。
 *
 * `Query` (生テーブル 10MB を組み直す側) は経由しない。名刺の読み解きに Snapshot は
 * 要らないので、wasm モジュールだけ (640KB 級) を取りに行く。
 */
import type { CardView } from "./types";

let cached: Promise<typeof import("../query/imas_query_wasm")> | null = null;

function loadModule(): Promise<typeof import("../query/imas_query_wasm")> {
  cached ??= (async () => {
    const mod = await import("../query/imas_query_wasm");
    await mod.default();
    return mod;
  })();
  return cached;
}

/**
 * URL (または `#` の後ろだけ) を名刺として読み解く。名刺でなければ `null`。
 * 失敗しても呼び出し側が「読み取れませんでした」と案内できるよう、例外はそのまま投げる。
 */
export async function decodeCard(text: string): Promise<CardView | null> {
  const mod = await loadModule();
  const result = mod.decode_producer_card_json(text);
  if (typeof result !== "string") return null;
  return JSON.parse(result) as CardView;
}
