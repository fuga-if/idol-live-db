/**
 * 楽曲一覧の絞り込み・並べ替え island。
 *
 * **ここに条件も並び順も無い。** 条件を組み立てて `imas-core` の
 * `song_list_indexes` を wasm 越しに呼び、返ってきた曲 id の順に行を並べ替えて
 * 見せ隠しするだけ。アプリと同じ関数を通るので、当たり方も並びも食い違わない。
 *
 * 土台の条件 (`query_base`) はページを組んだ Rust が出す。JS が
 * 「/songs/ なら既定フィルタ」と書き直すと、ページの中身と絞り込みの出発点が
 * 二重定義になる。
 *
 * 状態は URL のクエリに置く。戻る/進むで復元でき、絞った状態のまま共有できる
 * (「選択 = URL」という、この出面の基本を崩さない)。
 */
import { loadQuery, type Facets, type SongQuery, type SortOption } from "./query";

interface Elements {
  root: HTMLElement;
  tbody: HTMLElement;
  status: HTMLElement;
  fields: HTMLElement;
  sort: HTMLSelectElement;
  dir: HTMLButtonElement;
  reset: HTMLButtonElement;
  kana?: HTMLElement | null;
}

/** 画面に出す入力。`SongQuery` のうち web で意味のあるものだけ。 */
interface State {
  title: string;
  idolIds: string[];
  songwriter: string;
  cdSeries: string;
  seriesGroup: string;
  liveName: string;
  brandIds: string[];
  songType: string;
  sort: string;
  ascending: boolean | null;
}

const DEBOUNCE_MS = 120;

/** 既定の並び。コアが返す一覧の先頭 (`SongListSort::from_key` の落とし先と同じ)。 */
const FALLBACK_SORT = "kana";

export function mountSongFilter(root: HTMLElement): void {
  const base = root.dataset.queryBase;
  const tbody = document.querySelector<HTMLElement>("[data-song-table] tbody");
  if (!base || !tbody) return;

  const el: Elements = {
    root,
    tbody,
    status: must(root, "[data-filter-status]"),
    fields: must(root, "[data-filter-fields]"),
    sort: must(root, "[data-filter-sort]"),
    dir: must(root, "[data-filter-dir]"),
    reset: must(root, "[data-filter-reset]"),
    kana: document.querySelector<HTMLElement>("[data-kana-index]"),
  };

  // 曲 id → 行。wasm は id を返すので、添字で結び付けない。
  const rows = new Map<string, HTMLElement>();
  for (const tr of tbody.querySelectorAll<HTMLElement>("tr[data-song-id]")) {
    rows.set(tr.dataset.songId!, tr);
  }
  const total = rows.size;

  const baseQuery = JSON.parse(base) as SongQuery;
  const state = readUrl();
  let engine: Awaited<ReturnType<typeof loadQuery>> | null = null;
  // 並べ替えの一覧はコアが出す (鍵・文言・既定方向)。素材が来るまでは空。
  let sorts: SortOption[] = [];
  let timer = 0;

  setEnabled(el, false);
  void start();

  async function start(): Promise<void> {
    try {
      engine = await loadQuery();
      const facets = JSON.parse(engine.facets()) as Facets;
      sorts = facets.sorts;
      renderFields(el, facets, state, onChange);
      renderSorts(el, sorts, state);
      setEnabled(el, true);
      apply();
    } catch (e) {
      // 絞り込めないだけで一覧は読める。壊れた見た目のまま黙らない。
      el.status.textContent = "絞り込みを読み込めませんでした。再読み込みしてください。";
      el.root.dataset.state = "failed";
      console.error("song filter: 読み込みに失敗", e);
    }
  }

  function onChange(): void {
    window.clearTimeout(timer);
    timer = window.setTimeout(apply, DEBOUNCE_MS);
  }

  el.sort.addEventListener("change", () => {
    state.sort = el.sort.value;
    state.ascending = null; // その並びの既定方向に戻す (決めるのはコア)。
    syncDir(el, sorts, state);
    onChange();
  });
  el.dir.addEventListener("click", () => {
    state.ascending = !currentAscending(sorts, state);
    syncDir(el, sorts, state);
    onChange();
  });
  el.reset.addEventListener("click", () => {
    Object.assign(state, emptyState(state.sort));
    renderFieldValues(el, state);
    apply();
  });
  window.addEventListener("popstate", () => {
    Object.assign(state, readUrl());
    renderFieldValues(el, state);
    renderSorts(el, sorts, state);
    apply();
  });

  function apply(): void {
    if (!engine) return;

    // 土台 (ページを組んだ条件) に、**入力のあった軸だけ**を重ねる。
    // 空の軸で土台を上書きしない (ブランド別ページで曲名を打った瞬間に
    // 全ブランドへ広がってしまう)。軸ごとに条件を書き分けないのは、
    // 軸を 1 本足したときに「重ね方」を書き忘れないため。
    const query: SongQuery = {
      ...baseQuery,
      ...filled(state),
      sort: state.sort,
      ascending: state.ascending,
    };

    let ids: string[];
    try {
      ids = engine.song_ids(JSON.stringify(query));
    } catch (e) {
      el.status.textContent = "絞り込みに失敗しました。";
      console.error("song filter: 条件の適用に失敗", e);
      return;
    }

    // 返ってきた順に並べ、載っていない行は隠す。
    const shown = new Set(ids);
    const frag = document.createDocumentFragment();
    let visible = 0;
    for (const id of ids) {
      const tr = rows.get(id);
      if (!tr) continue; // 一覧に載っていない曲 (土台の外) は無視する。
      tr.hidden = false;
      frag.appendChild(tr);
      visible += 1;
    }
    for (const [id, tr] of rows) if (!shown.has(id)) tr.hidden = true;
    // appendChild で frag は空になるので、件数はここへ来る前に数えておく。
    el.tbody.appendChild(frag);

    const narrowed = isNarrowed(state);
    el.status.textContent = narrowed ? `${visible} 件 / ${total} 件` : `${total} 件`;
    el.root.dataset.filtered = String(narrowed);
    // かな目次は既定の並びを前提にした飛び先なので、絞り込み/並べ替え中は隠す。
    if (el.kana)
      el.kana.hidden = narrowed || state.sort !== FALLBACK_SORT || state.ascending === false;
    writeUrl(state);
  }
}

// --- 部品 -----------------------------------------------------------------

function must<T extends HTMLElement>(root: HTMLElement, selector: string): T {
  const found = root.querySelector<T>(selector);
  if (!found) throw new Error(`絞り込みの部品が無い: ${selector}`);
  return found;
}

function emptyState(sort: string): State {
  return {
    title: "",
    idolIds: [],
    songwriter: "",
    cdSeries: "",
    seriesGroup: "",
    liveName: "",
    brandIds: [],
    songType: "",
    sort,
    ascending: null,
  };
}

/** 入力のあった軸だけを取り出す。空欄は「指定なし」で、土台をそのまま残す。 */
function filled(s: State): Partial<SongQuery> {
  const out: Partial<SongQuery> = {};
  const text = (v: string) => v.trim() || null;
  if (text(s.title)) out.title = text(s.title);
  if (text(s.songwriter)) out.songwriter = text(s.songwriter);
  if (text(s.liveName)) out.liveName = text(s.liveName);
  if (s.cdSeries) out.cdSeries = s.cdSeries;
  if (s.seriesGroup) out.seriesGroup = s.seriesGroup;
  if (s.songType) out.songType = s.songType;
  if (s.idolIds.length > 0) out.idolIds = s.idolIds;
  if (s.brandIds.length > 0) out.brandIds = s.brandIds;
  return out;
}

function isNarrowed(s: State): boolean {
  return (
    !!s.title.trim() ||
    s.idolIds.length > 0 ||
    !!s.songwriter.trim() ||
    !!s.cdSeries ||
    !!s.seriesGroup ||
    !!s.liveName.trim() ||
    s.brandIds.length > 0 ||
    !!s.songType
  );
}

function currentAscending(sorts: SortOption[], s: State): boolean {
  if (s.ascending !== null) return s.ascending;
  return sorts.find((x) => x.key === s.sort)?.defaultAscending ?? true;
}

function setEnabled(el: Elements, on: boolean): void {
  // 入力欄は素材 (facets) が来てから描くので、ここで触るものは無い。
  // 器の側 (sort/dir/reset) だけを止めておく。
  for (const c of [el.sort, el.dir, el.reset]) c.disabled = !on;
  el.root.dataset.state = on ? "ready" : "loading";
}

function syncDir(el: Elements, sorts: SortOption[], state: State): void {
  const asc = currentAscending(sorts, state);
  el.dir.textContent = asc ? "↑" : "↓";
  el.dir.setAttribute("aria-label", asc ? "昇順（クリックで降順）" : "降順（クリックで昇順）");
}

function renderSorts(el: Elements, sorts: SortOption[], state: State): void {
  el.sort.innerHTML = sorts
    .map((o) => `<option value="${escapeAttr(o.key)}">${escapeText(o.label)}</option>`)
    .join("");
  if (!sorts.some((o) => o.key === state.sort)) state.sort = FALLBACK_SORT;
  el.sort.value = state.sort;
  syncDir(el, sorts, state);
}

/** 入力欄。値の集合は wasm (= Snapshot) が出したものをそのまま並べる。 */
function renderFields(el: Elements, f: Facets, state: State, onChange: () => void): void {
  const select = (key: string, label: string, opts: { value: string; label: string }[]) =>
    `<label class="song-filter__field"><span class="u-visually-hidden">${escapeText(label)}</span>
      <select class="song-filter__select" data-key="${key}">
        <option value="">${escapeText(label)}: すべて</option>
        ${opts.map((o) => `<option value="${escapeAttr(o.value)}">${escapeText(o.label)}</option>`).join("")}
      </select></label>`;
  const text = (key: string, placeholder: string) =>
    `<label class="song-filter__field"><span class="u-visually-hidden">${escapeText(placeholder)}</span>
      <input class="song-filter__input" type="search" data-key="${key}"
        placeholder="${escapeAttr(placeholder)}" autocomplete="off" spellcheck="false"></label>`;

  el.fields.innerHTML = [
    text("title", "曲名で絞り込み"),
    select("idolIds", "原唱者", f.idols),
    text("songwriter", "作家名"),
    text("liveName", "ライブ名"),
    select("cdSeries", "CD シリーズ", f.cdSeries),
    select("seriesGroup", "シリーズ", f.seriesGroups),
    select("brandIds", "ブランド", f.brands),
    select("songType", "曲種別", [
      { value: "all", label: "全体曲" },
      { value: "unit", label: "ユニット曲" },
      { value: "solo", label: "ソロ曲" },
    ]),
  ].join("");

  el.fields.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-key]").forEach((c) => {
    c.addEventListener(c.tagName === "SELECT" ? "change" : "input", () => {
      const key = c.dataset.key as keyof State;
      // 複数値の軸も、画面では単一選択で足りる (アプリのピッカーに相当する UI は持たない)。
      if (key === "idolIds" || key === "brandIds") {
        (state[key] as string[]) = c.value ? [c.value] : [];
      } else {
        (state[key] as string) = c.value;
      }
      onChange();
    });
  });
  renderFieldValues(el, state);
}

function renderFieldValues(el: Elements, state: State): void {
  el.fields.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-key]").forEach((c) => {
    const key = c.dataset.key as keyof State;
    const v = state[key];
    c.value = Array.isArray(v) ? (v[0] ?? "") : typeof v === "string" ? v : "";
  });
}

// --- URL との往復 ---------------------------------------------------------

const URL_KEYS: (keyof State)[] = [
  "title",
  "idolIds",
  "songwriter",
  "cdSeries",
  "seriesGroup",
  "liveName",
  "brandIds",
  "songType",
];

function readUrl(): State {
  const q = new URLSearchParams(location.search);
  const s = emptyState(q.get("sort") ?? FALLBACK_SORT);
  for (const key of URL_KEYS) {
    const v = q.get(key);
    if (!v) continue;
    if (key === "idolIds" || key === "brandIds") (s[key] as string[]) = v.split(",").filter(Boolean);
    else (s[key] as string) = v;
  }
  const dir = q.get("dir");
  s.ascending = dir === "asc" ? true : dir === "desc" ? false : null;
  return s;
}

function writeUrl(state: State): void {
  const q = new URLSearchParams();
  for (const key of URL_KEYS) {
    const v = state[key];
    const text = Array.isArray(v) ? v.join(",") : String(v ?? "");
    if (text.trim()) q.set(key, text.trim());
  }
  if (state.sort !== FALLBACK_SORT) q.set("sort", state.sort);
  if (state.ascending !== null) q.set("dir", state.ascending ? "asc" : "desc");
  const next = q.toString() ? `${location.pathname}?${q}` : location.pathname;
  if (next !== location.pathname + location.search) history.replaceState(null, "", next);
}

function escapeText(s: string): string {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]!);
}
function escapeAttr(s: string): string {
  return escapeText(s).replace(/"/g, "&quot;");
}
