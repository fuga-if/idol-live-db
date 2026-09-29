/**
 * アイドル一覧の絞り込み設定。
 *
 * アプリの絞り込み (`filter_idol_list`) と同じ軸: ブランド / 属性 / 誕生月 /
 * 名前の検索 / CV 名の検索 (名前と CV 名は別の欄。混ぜて当てない)。**誕生月は今までどおり別ページとしても残っていて**、
 * ここでは他の軸と組み合わせられる形にしてある。
 */
import type { IdolFacets } from "../schema/IdolFacets";
import { loadQuery } from "./query";
import { mountListFilter, type FieldSpec, type ListFilterSpec } from "./island";

export function mountIdolFilter(root: HTMLElement): void {
  const spec: ListFilterSpec<IdolFacets> = {
    name: "idol filter",
    // 行は表の中。並べ替えは tbody の直下で入れ替わる。
    container: "[data-idol-table]",
    item: "tr[data-entity-id]",
    idAttr: "entityId",
    // 並べ替えは表の列見出しを押す (表計算と同じ)。どの列が押せるかは Rust の
    // `IdolColumn.sortKey` が決めていて、ここは押し場所の在り処だけを言う。
    sortHeaders: "[data-sort-headers]",
    facets: (e) => JSON.parse(e.idol_facets()) as IdolFacets,
    ids: (e, json) => e.idol_ids(json),
    fields: (f): FieldSpec[] => [
      { key: "searchText", kind: "text", label: "名前で絞り込み" },
      { key: "voiceActor", kind: "text", label: "CV 名" },
      { key: "brandIds", kind: "select", label: "ブランド", options: f.brands, multi: true },
      { key: "attribute", kind: "select", label: "属性", options: f.attributes },
      { key: "birthMonth", kind: "select", label: "誕生月", options: f.birthMonths, numeric: true },
    ],
  };

  mountListFilter(root, spec, loadQuery);
}
