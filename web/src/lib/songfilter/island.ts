/**
 * 楽曲一覧の絞り込み・並べ替え island。
 *
 * **ここに条件も並び順の規則も無い。** 素材 (`/filters/*.json`) は Rust が
 * core 自身のフィルタで組んだもので、この島がやるのは 3 つだけ:
 *   1. 選ばれた値の行集合を、軸をまたいで積 (AND)・軸内で和 (OR) にする
 *   2. 名前入力を `imas-text-fold` の wasm で畳み、行の畳み済み文字列に含まれるか見る
 *      (`/search/` と同じ照合。索引側は Rust が畳んで載せてある)
 *   3. 渡された順列どおりに行を並べ替える
 *
 * 素材は**絞り込みを開いたときに初めて取りに行く**。一覧を読むだけの人に
 * 数百 KB を配らないため。
 *
 * 状態は URL のクエリに置く。戻る/進むで復元でき、絞った状態のまま共有できる
 * (「選択 = URL」という、この出面の基本を崩さない)。
 */
import { loadFold, type Fold } from "../search/fold";
import type { SongListFilterData } from "../schema/SongListFilterData";
import type { SongFacet } from "../schema/SongFacet";

interface Elements {
  root: HTMLElement;
  table: HTMLElement;
  tbody: HTMLElement;
  status: HTMLElement;
  name: HTMLInputElement;
  sort: HTMLSelectElement;
  dir: HTMLButtonElement;
  facets: HTMLElement;
  reset: HTMLButtonElement;
  kana?: HTMLElement | null;
}

/** 選択状態。値は facet の `value` (Rust が決めた文字列) をそのまま持つ。 */
interface State {
  name: string;
  sort: string;
  ascending: boolean;
  selected: Map<string, Set<string>>;
}

const DEBOUNCE_MS = 80;

export function mountSongFilter(root: HTMLElement): void {
  const src = root.dataset.filterSrc;
  const table = document.querySelector<HTMLElement>("[data-song-table]");
  const tbody = table?.querySelector<HTMLElement>("tbody");
  if (!src || !table || !tbody) return;

  const el: Elements = {
    root,
    table,
    tbody,
    status: must(root, "[data-filter-status]"),
    name: must(root, "[data-filter-name]"),
    sort: must(root, "[data-filter-sort]"),
    dir: must(root, "[data-filter-dir]"),
    facets: must(root, "[data-filter-facets]"),
    reset: must(root, "[data-filter-reset]"),
    kana: document.querySelector<HTMLElement>("[data-kana-index]"),
  };

  // 行は初期並び (Rust が出した items の順) の添字を持っている。
  const rows = [...tbody.querySelectorAll<HTMLElement>("tr[data-row]")];
  const total = rows.length;

  let data: SongListFilterData | null = null;
  let fold: Fold | null = null;
  let timer = 0;

  const state: State = readUrl();

  // 素材を取るまでは触らせない (押しても何も起きない時間を作らない)。
  setEnabled(el, false);
  void load();

  async function load(): Promise<void> {
    try {
      const [json, f] = await Promise.all([
        fetch(src!).then((r) => {
          if (!r.ok) throw new Error(`${r.status}`);
          return r.json() as Promise<SongListFilterData>;
        }),
        loadFold(),
      ]);
      if (json.rowCount !== total) {
        throw new Error(`行数が合わない (素材 ${json.rowCount} / 表 ${total})`);
      }
      data = json;
      fold = f;
      renderFacets(el, data, state, onChange);
      renderOrders(el, data, state);
      setEnabled(el, true);
      apply();
    } catch (e) {
      // 絞り込めないだけで一覧は読める。黙って壊れた見た目にしない。
      el.status.textContent = "絞り込みを読み込めませんでした。再読み込みしてください。";
      el.root.dataset.state = "failed";
      console.error("song filter: 素材の読み込みに失敗", e);
    }
  }

  function onChange(): void {
    window.clearTimeout(timer);
    timer = window.setTimeout(apply, DEBOUNCE_MS);
  }

  el.name.addEventListener("input", () => {
    state.name = el.name.value;
    onChange();
  });
  el.sort.addEventListener("change", () => {
    state.sort = el.sort.value;
    state.ascending = defaultAscending(data, state.sort);
    syncDir(el, state);
    onChange();
  });
  el.dir.addEventListener("click", () => {
    state.ascending = !state.ascending;
    syncDir(el, state);
    onChange();
  });
  el.reset.addEventListener("click", () => {
    state.name = "";
    state.selected.clear();
    el.name.value = "";
    el.facets.querySelectorAll<HTMLInputElement>("input").forEach((i) => (i.checked = false));
    el.facets.querySelectorAll<HTMLSelectElement>("select").forEach((s) => (s.value = ""));
    apply();
  });
  window.addEventListener("popstate", () => {
    const next = readUrl();
    Object.assign(state, next);
    state.selected = next.selected;
    if (data) {
      renderFacets(el, data, state, onChange);
      renderOrders(el, data, state);
    }
    el.name.value = state.name;
    apply();
  });

  function apply(): void {
    if (!data || !fold) return;

    // 1) 軸ごとの積。選択の無い軸は素通し。
    let visible: Set<number> | null = null;
    for (const facet of data.facets) {
      const picked = state.selected.get(facet.key);
      if (!picked || picked.size === 0) continue;
      const allowed = new Set<number>();
      picked.forEach((value) => {
        const vi = facet.values.findIndex((v) => v.value === value);
        if (vi < 0) return;
        facet.rowValues.forEach((values, row) => {
          if (values.includes(vi)) allowed.add(row);
        });
      });
      visible = visible === null ? allowed : intersect(visible, allowed);
    }

    // 2) 名前。索引と同じ規則で畳んだ語の部分一致。
    const needle = state.name.trim() ? fold(state.name.trim()) : "";
    if (needle && !needle.includes(data.separator)) {
      const hit = new Set<number>();
      data.haystacks.forEach((h, row) => {
        if (h.includes(needle)) hit.add(row);
      });
      visible = visible === null ? hit : intersect(visible, hit);
    }

    // 3) 並べ替え。順列をそのまま当てる。
    const order = data.orders.find((o) => o.key === state.sort) ?? data.orders[0];
    const sequence = order ? (state.ascending ? order.ascending : order.descending) : null;
    const sequenceRows = sequence ?? rows.map((_, i) => i);

    const frag = document.createDocumentFragment();
    let shown = 0;
    for (const row of sequenceRows) {
      const tr = rows[row];
      if (!tr) continue;
      const ok = visible === null || visible.has(row);
      tr.hidden = !ok;
      if (ok) shown += 1;
      frag.appendChild(tr);
    }
    el.tbody.appendChild(frag);

    const filtered = visible !== null || !!needle;
    el.status.textContent = filtered ? `${shown} 件 / ${total} 件` : `${total} 件`;
    el.root.dataset.filtered = String(filtered);
    // かな目次は初期の並びを前提にした飛び先なので、並べ替え/絞り込み中は隠す。
    if (el.kana) el.kana.hidden = filtered || state.sort !== data.orders[0]?.key || !state.ascending;
    writeUrl(state, data);
  }
}

// --- 部品 -----------------------------------------------------------------

function must<T extends HTMLElement>(root: HTMLElement, selector: string): T {
  const found = root.querySelector<T>(selector);
  if (!found) throw new Error(`絞り込みの部品が無い: ${selector}`);
  return found;
}

function intersect(a: Set<number>, b: Set<number>): Set<number> {
  const out = new Set<number>();
  a.forEach((v) => {
    if (b.has(v)) out.add(v);
  });
  return out;
}

function defaultAscending(data: SongListFilterData | null, key: string): boolean {
  return data?.orders.find((o) => o.key === key)?.defaultAscending ?? true;
}

function setEnabled(el: Elements, on: boolean): void {
  for (const c of [el.name, el.sort, el.dir, el.reset]) c.disabled = !on;
  el.root.dataset.state = on ? "ready" : "loading";
}

function syncDir(el: Elements, state: State): void {
  el.dir.dataset.ascending = String(state.ascending);
  el.dir.setAttribute("aria-label", state.ascending ? "昇順（クリックで降順）" : "降順（クリックで昇順）");
  el.dir.textContent = state.ascending ? "↑" : "↓";
}

function renderOrders(el: Elements, data: SongListFilterData, state: State): void {
  el.sort.innerHTML = data.orders
    .map((o) => `<option value="${escapeAttr(o.key)}">${escapeText(o.label)}</option>`)
    .join("");
  if (!data.orders.some((o) => o.key === state.sort)) {
    state.sort = data.orders[0]?.key ?? "";
    state.ascending = defaultAscending(data, state.sort);
  }
  el.sort.value = state.sort;
  syncDir(el, state);
}

/** 軸の描画。値が多い軸は `select`、少ない軸はチップ (チェックボックス)。 */
function renderFacets(
  el: Elements,
  data: SongListFilterData,
  state: State,
  onChange: () => void,
): void {
  el.facets.innerHTML = data.facets.map((f) => facetHtml(f, state)).join("");
  el.facets.querySelectorAll<HTMLInputElement>("input[data-facet]").forEach((input) => {
    input.addEventListener("change", () => {
      const key = input.dataset.facet!;
      const set = state.selected.get(key) ?? new Set<string>();
      if (input.checked) set.add(input.value);
      else set.delete(input.value);
      state.selected.set(key, set);
      onChange();
    });
  });
  el.facets.querySelectorAll<HTMLSelectElement>("select[data-facet]").forEach((select) => {
    select.addEventListener("change", () => {
      const key = select.dataset.facet!;
      state.selected.set(key, select.value ? new Set([select.value]) : new Set());
      onChange();
    });
  });
}

/** チップで出すか `select` で出すかの境目。多い軸を全部並べると読めない。 */
const CHIP_LIMIT = 12;

function facetHtml(facet: SongFacet, state: State): string {
  const picked = state.selected.get(facet.key) ?? new Set<string>();
  const label = escapeText(facet.label);
  if (facet.values.length > CHIP_LIMIT || !facet.multi) {
    const options = [`<option value="">${label}: すべて</option>`]
      .concat(
        facet.values.map(
          (v) =>
            `<option value="${escapeAttr(v.value)}"${picked.has(v.value) ? " selected" : ""}>` +
            `${escapeText(v.label)} (${v.count})</option>`,
        ),
      )
      .join("");
    return `<label class="song-filter__field"><span class="u-visually-hidden">${label}</span>
      <select class="song-filter__select" data-facet="${escapeAttr(facet.key)}">${options}</select></label>`;
  }
  const chips = facet.values
    .map(
      (v) =>
        `<label class="song-filter__chip"><input type="checkbox" data-facet="${escapeAttr(facet.key)}"` +
        ` value="${escapeAttr(v.value)}"${picked.has(v.value) ? " checked" : ""}>` +
        `<span>${escapeText(v.label)}</span><b>${v.count}</b></label>`,
    )
    .join("");
  return `<fieldset class="song-filter__group"><legend>${label}</legend>${chips}</fieldset>`;
}

// --- URL との往復 ---------------------------------------------------------

function readUrl(): State {
  const q = new URLSearchParams(location.search);
  const selected = new Map<string, Set<string>>();
  for (const [key, value] of q.entries()) {
    if (key === "q" || key === "sort" || key === "dir") continue;
    const set = selected.get(key) ?? new Set<string>();
    value.split(",").filter(Boolean).forEach((v) => set.add(v));
    selected.set(key, set);
  }
  return {
    name: q.get("q") ?? "",
    sort: q.get("sort") ?? "",
    ascending: q.get("dir") !== "desc",
    selected,
  };
}

function writeUrl(state: State, data: SongListFilterData): void {
  const q = new URLSearchParams();
  if (state.name.trim()) q.set("q", state.name.trim());
  state.selected.forEach((set, key) => {
    if (set.size > 0) q.set(key, [...set].join(","));
  });
  const isDefaultSort =
    state.sort === data.orders[0]?.key && state.ascending === defaultAscending(data, state.sort);
  if (!isDefaultSort) {
    q.set("sort", state.sort);
    q.set("dir", state.ascending ? "asc" : "desc");
  }
  const next = q.toString() ? `${location.pathname}?${q}` : location.pathname;
  if (next !== location.pathname + location.search) {
    history.replaceState(null, "", next);
  }
}

function escapeText(s: string): string {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]!);
}
function escapeAttr(s: string): string {
  return escapeText(s).replace(/"/g, "&quot;");
}
