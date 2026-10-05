/**
 * P名刺 (`/p/`) が wasm から受け取る JSON の形。
 *
 * **読み解きの正は Rust (`imas_core::domain::producer_card`) で、ここは型注釈だけ**
 * (`decode_producer_card_json` が返す JSON 文字列を `JSON.parse` した結果の形を書いた
 * だけで、判断は一切していない)。ts-rs の生成物 (`../schema/`) に無いのは、この形が
 * `web/wasm/imas-query-wasm` 内だけの出力用 struct であって、Astro の静的ページが
 * 読む DTO (`web_dto!`) ではないため。
 */

/** 画面に出すリンク 1 本 (`card_link_view` まで通した形)。 */
export interface CardLinkView {
  label: string;
  display: string;
  url: string;
}

/** 名刺の中身。フィールド名・形は Rust の `CardView` (wasm 側) と 1:1。 */
export interface CardView {
  name: string;
  message: string;
  sinceYear: number | null;
  /** `p/catalog.json` の `idols` と id で突き合わせる。並び順は名刺の並び順のまま。 */
  oshiIdolIds: string[];
  links: CardLinkView[];
  showCount: number | null;
  songCount: number | null;
  /** `p/catalog.json` の `upcomingShows` と id で突き合わせる。無ければ過去の公演。 */
  nextShowId: string | null;
  attendedCount: number;
  attendedTruncated: boolean;
  /** `"2026.10.06 時点"` のように、既に整形済み。 */
  issuedOnDisplay: string;
  /** 名前の書体のキー (`gothic` / `mincho` …)。名前の `data-font` にそのまま置く。 */
  nameFont: string;
  /** 自分の QR (題は「QR」のリンクの形)。無ければ `null`。 */
  qrLink: CardLinkView | null;
}
