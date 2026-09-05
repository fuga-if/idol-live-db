/**
 * セトリの歌唱者をどの名前で出すか — 閲覧者ごとの表示の好み。
 *
 * **モードもラベルもここに無い。** どの名前を主/副にするかも、選択肢の順も文言も
 * `imas-core` の `performer_name_options` が持ち、`meta.json` 越しに配られる。
 * ここがやるのは localStorage への出し入れだけ (保存値の文字列も向こうの `raw`)。
 *
 * サーバ側で描いた HTML は既定モード (アイドル名) で出ているので、
 * 既定のままの閲覧者には JS が 1 バイトも要らない。
 */
const KEY = "performerName";

/** 既定。`PerformerNameMode::default_mode()` の `raw` と同じ文字列。 */
export const DEFAULT_MODE = "idol";

export function readMode(known: readonly string[]): string {
  try {
    const v = localStorage.getItem(KEY);
    return v && known.includes(v) ? v : DEFAULT_MODE;
  } catch {
    // プライベートウィンドウ等で localStorage が投げることがある。既定で続ける。
    return DEFAULT_MODE;
  }
}

export function writeMode(mode: string): void {
  try {
    if (mode === DEFAULT_MODE) localStorage.removeItem(KEY);
    else localStorage.setItem(KEY, mode);
  } catch {
    // 保存できなくても表示は切り替わる (次の訪問で既定に戻るだけ)。
  }
}
