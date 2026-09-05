/**
 * 楽曲一覧の絞り込み設定。
 *
 * **軸の並びと、どの wasm 関数を呼ぶかだけ。** 実装は
 * [`mountListFilter`](./island.ts) が持ち、条件も並び順も `imas-core` が持つ。
 */
import { loadQuery, type SongFacets, type SortOption } from "./query";
import { mountListFilter, type FieldSpec, type ListFilterSpec } from "./island";

type Engine = Awaited<ReturnType<typeof loadQuery>>;

export function mountSongFilter(root: HTMLElement): void {
  // かな目次は既定の並びを前提にした飛び先なので、絞り込み/並べ替え中は隠す。
  const kana = document.querySelector<HTMLElement>("[data-kana-index]");

  const spec: ListFilterSpec<SongFacets> = {
    name: "song filter",
    container: "[data-song-table] tbody",
    item: "tr[data-song-id]",
    idAttr: "songId",
    fallbackSort: "kana",
    facets: (e) => JSON.parse((e as Engine).facets()) as SongFacets,
    ids: (e, json) => (e as Engine).song_ids(json),
    sorts: (f) => f.sorts as SortOption[],
    fields: (f): FieldSpec[] => [
      { key: "title", kind: "text", label: "曲名で絞り込み" },
      { key: "idolIds", kind: "select", label: "原唱者", options: f.idols, multi: true },
      { key: "songwriter", kind: "text", label: "作家名" },
      { key: "liveName", kind: "text", label: "ライブ名" },
      { key: "cdSeries", kind: "select", label: "CD シリーズ", options: f.cdSeries },
      { key: "seriesGroup", kind: "select", label: "シリーズ", options: f.seriesGroups },
      { key: "brandIds", kind: "select", label: "ブランド", options: f.brands, multi: true },
      {
        key: "songType",
        kind: "select",
        label: "曲種別",
        // 曲種別だけは Snapshot に選択肢の集合が無い (songs.song_type の語彙)。
        options: [
          { value: "all", label: "全体曲" },
          { value: "unit", label: "ユニット曲" },
          { value: "solo", label: "ソロ曲" },
        ],
      },
    ],
    onApply: ({ narrowed, sort, ascending }) => {
      if (kana) kana.hidden = narrowed || sort !== "kana" || ascending === false;
    },
  };

  mountListFilter(root, spec, loadQuery);
}
