/**
 * セトリの歌唱者をどの名前で出すか — 閲覧者ごとの表示の好み。
 *
 * **規則は持たない。** どの名前を主/副にするかは `imas-core` の
 * `performer_display_name` が決めており、ここはモードの保存と読み出しだけ。
 * 保存先は localStorage で、サーバには送らない (この出面は書き込まない)。
 *
 * サーバ側で描いた HTML は既定モード (アイドル名) で出ているので、
 * 既定のままの閲覧者には JS が 1 バイトも要らない。
 */
export const PERFORMER_NAME_MODES = ["idol", "cast", "both", "show"] as const;
export type PerformerNameMode = (typeof PERFORMER_NAME_MODES)[number];

export const PERFORMER_NAME_LABELS: Record<PerformerNameMode, string> = {
  idol: "アイドル名",
  cast: "CV名",
  both: "アイドル名 + CV名",
  show: "公演に合わせる",
};

const KEY = "performerName";
export const DEFAULT_MODE: PerformerNameMode = "idol";

export function readMode(): PerformerNameMode {
  try {
    const v = localStorage.getItem(KEY);
    return (PERFORMER_NAME_MODES as readonly string[]).includes(v ?? "")
      ? (v as PerformerNameMode)
      : DEFAULT_MODE;
  } catch {
    // プライベートウィンドウ等で localStorage が投げることがある。既定で続ける。
    return DEFAULT_MODE;
  }
}

export function writeMode(mode: PerformerNameMode): void {
  try {
    if (mode === DEFAULT_MODE) localStorage.removeItem(KEY);
    else localStorage.setItem(KEY, mode);
  } catch {
    // 保存できなくても表示は切り替わる (次の訪問で既定に戻るだけ)。
  }
}
