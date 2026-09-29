/**
 * 楽曲一覧の絞り込み設定。
 *
 * **軸の並びと、どの wasm 関数を呼ぶかだけ。** 実装は
 * [`mountListFilter`](./island.ts) が持ち、条件も並び順も選択肢も `imas-core` が持つ。
 */
import type { SongFacets } from "../schema/SongFacets";
import { loadQuery } from "./query";
import { mountListFilter, type FieldSpec, type ListFilterSpec } from "./island";

export function mountSongFilter(root: HTMLElement): void {
  // かな目次はページに描いた並びを前提にした飛び先なので、絞り込み/並べ替え中は隠す。
  const kana = document.querySelector<HTMLElement>("[data-kana-index]");

  const spec: ListFilterSpec<SongFacets> = {
    name: "song filter",
    container: "[data-song-list]",
    item: "li[data-song-id]",
    idAttr: "songId",
    facets: (e) => JSON.parse(e.facets()) as SongFacets,
    ids: (e, json) => e.song_ids(json),
    fields: (f): FieldSpec[] => [
      { key: "title", kind: "text", label: "曲名で絞り込み" },
      { key: "idolIds", kind: "select", label: "歌唱アイドル", options: f.idols, multi: true },
      { key: "songwriter", kind: "text", label: "作家名" },
      { key: "liveName", kind: "text", label: "ライブ名" },
      { key: "cdSeries", kind: "select", label: "CD シリーズ", options: f.cdSeries },
      { key: "seriesGroup", kind: "select", label: "シリーズ", options: f.seriesGroups },
      { key: "brandIds", kind: "select", label: "ブランド", options: f.brands, multi: true },
      { key: "songType", kind: "select", label: "曲種別", options: f.songTypes },
      {
        key: "kamisabiOnly",
        kind: "toggle",
        boolean: true,
        label: "KAMISABI 収録",
        // 2 択なのでプルダウンではなく帯 (押した方が見える状態で並ぶボタン列)。
        options: [
          { value: "", label: "すべて" },
          { value: "true", label: "収録のみ" },
        ],
      },
    ],
    onApply: ({ narrowed, pageOrder }) => {
      if (kana) kana.hidden = narrowed || !pageOrder;
    },
  };

  mountListFilter(root, spec, loadQuery);
}
