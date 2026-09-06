/**
 * アイドル一覧の絞り込み設定。
 *
 * アプリの絞り込み (`filter_idol_list`) と同じ軸: ブランド / 属性 / 誕生月 /
 * 名前・CV 名の検索。**誕生月は今までどおり別ページとしても残っていて**、
 * ここでは他の軸と組み合わせられる形にしてある。
 */
import { loadQuery, type IdolFacets, type SortOption } from "./query";
import { mountListFilter, type FieldSpec, type ListFilterSpec } from "./island";

type Engine = Awaited<ReturnType<typeof loadQuery>>;

/** 誕生月の選択肢。`--MM-DD` の月と 1:1 なので、ここは数の並びそのもの。 */
const BIRTH_MONTHS = Array.from({ length: 12 }, (_, i) => ({
  value: String(i + 1),
  label: `${i + 1}月`,
}));

export function mountIdolFilter(root: HTMLElement): void {
  const spec: ListFilterSpec<IdolFacets> = {
    name: "idol filter",
    // 行は表の中。並べ替えは tbody の直下で入れ替わる。
    container: "[data-idol-table]",
    item: "tr[data-entity-id]",
    idAttr: "entityId",
    fallbackSort: "official",
    facets: (e) => JSON.parse((e as Engine).idol_facets()) as IdolFacets,
    ids: (e, json) => (e as Engine).idol_ids(json),
    sorts: (f) => f.sorts as SortOption[],
    fields: (f): FieldSpec[] => [
      { key: "searchText", kind: "text", label: "名前・CV 名で絞り込み" },
      { key: "brandIds", kind: "select", label: "ブランド", options: f.brands, multi: true },
      { key: "attribute", kind: "select", label: "属性", options: f.attributes },
      { key: "birthMonth", kind: "select", label: "誕生月", options: BIRTH_MONTHS, numeric: true },
    ],
  };

  mountListFilter(root, spec, loadQuery);
}
