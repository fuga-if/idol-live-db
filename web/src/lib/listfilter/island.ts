/**
 * 一覧の絞り込み・並べ替え island (曲・アイドル共通の実装)。
 *
 * **ここに条件も並び順も無い。** 条件を組み立てて `imas-core` の関数を wasm 越しに
 * 呼び、返ってきた id の順に行を並べ替えて見せ隠しするだけ。アプリと同じ関数を
 * 通るので、当たり方も並びも食い違わない。
 *
 * **絞り込む母集団はページに描かれた行そのもの。** エンジンが返した id のうち、ページに無いものは
 * 捨てる。土台の条件 (`queryBase`) は Rust が「ページの行を必ず含む」ように組んで出す
 * (アイドルのブランド別ページには 2 つ目のブランドの人も載るので、ブランドで絞った条件を
 * 土台にすると行が消える)。JS が「/songs/ なら既定フィルタ」と書き直すと二重定義になる。
 * ページが値を決めている軸 (`fixedAxes`: ブランド別ページのブランド等) は島に出さない。
 * 切り替えは畳んだメニューのリンク (= 別のページ) が受け持つ。
 *
 * 状態は URL のクエリに置く。戻る/進むで復元でき、絞った状態のまま共有できる
 * (「選択 = URL」という、この出面の基本を崩さない)。
 *
 * **起動するのは最初の操作 (「絞り込み・並べ替え」か列見出しを押す) か、URL に条件が
 * あるときだけ** (Q-14)。一覧を眺めるだけの人には、生テーブル (約 10MB) も wasm も配らない。
 *
 * **軸は 1 本の表 ([`FieldSpec`]) で決まる。** 以前は「型・初期値・URL の鍵・
 * 描画・重ね方・絞り込み中かの判定」が別々に書かれていて、軸を 1 本足すと
 * 6 箇所を直す必要があった (1 つ忘れても型は通り、URL 復元だけが壊れる)。
 */
import type { Query } from "../query/imas_query_wasm";
import type { FacetOption } from "../schema/FacetOption";
import type { SortOption } from "../schema/SortOption";
import { hasIslandQuery } from "./start";

/** 入力欄 1 つ。**この 1 行が軸のすべて**を決める。 */
export interface FieldSpec {
  /** 条件・状態・URL で共通の鍵。 */
  key: string;
  /**
   * `toggle` は 2 択の帯 (押した方が見える状態で並ぶボタン列)。
   * `options` に「すべて (値 `""`)」「絞る (値 `"true"`)」の 2 件を渡す。
   * 値の多い軸はプルダウンを開かせる `select` のままにする。
   */
  kind: "text" | "select" | "toggle";
  /** プレースホルダ / 「すべて」の前に出す名前。`toggle` では帯の `aria-label`。 */
  label: string;
  /** select / toggle のときの選択肢。 */
  options?: FacetOption[];
  /**
   * 条件側が配列で受ける軸。画面は単一選択で足りる
   * (アプリのピッカーに相当する UI は持たない)。
   */
  multi?: boolean;
  /** 条件側が数値で受ける軸 (誕生月)。 */
  numeric?: boolean;
  /**
   * 条件側が真偽値で受ける軸 (KAMISABI 収録)。画面の raw 値は文字列
   * (`""` / `"true"`) のままで、ここが立っていれば真偽値に変換して渡す。
   * 未選択 (`""`) は「指定なし」= `null` (土台をそのまま残す) で、`false` は使わない。
   */
  boolean?: boolean;
}

/**
 * 並べ替えの一覧と既定。曲・アイドルの選択肢 (`SongFacets` / `IdolFacets`) が共通に持つ。
 * どちらも Rust (`domain::list_facets`) が決める。
 */
interface ListFacets {
  sorts: SortOption[];
  /** 未指定・未知の鍵が倒れる先 (= ページに描いた並び)。 */
  defaultSort: string;
}

/** 一覧ごとの違いだけを持つ設定。 */
export interface ListFilterSpec<F extends ListFacets> {
  /** ログに出す名前。 */
  name: string;
  /** 行を抱えている要素 (tbody / ul)。 */
  container: string;
  /** 行そのもの。`data-<idAttr>` を持っていること。 */
  item: string;
  /** 行の id を持つ dataset のキー。 */
  idAttr: string;
  /**
   * 並べ替えを表の列見出しで行う一覧の、その見出しを抱えている要素。
   *
   * 指定すると札の列を描かず、**すでに HTML にある `[data-sort-key]` の見出しに
   * 動きだけを結ぶ** (表計算と同じ手触り)。どの列が押せるかは Rust が決めているので、
   * ここで列と並びの対応を書き直さない。向きは見出しの矢印が示すので向きボタンは出さない。
   */
  sortHeaders?: string;
  /** wasm から選択肢を取る。 */
  facets(engine: Engine): F;
  /** wasm に条件を渡して id 列を得る。 */
  ids(engine: Engine, queryJson: string): string[];
  /** 選択肢から入力欄の並びを組む。 */
  fields(facets: F): FieldSpec[];
  /**
   * 絞り込み/並べ替えの状態が変わったときの付随処理
   * (かな目次のように、ページに描いた並びを前提にした飛び先を隠す等)。
   * `pageOrder` は「既定の並びを既定の向きで」= 行がページに描いた順のままか。
   */
  onApply?(view: { narrowed: boolean; pageOrder: boolean }): void;
}

/** wasm のハンドル (曲もアイドルも同じ `Query`。どのメソッドを呼ぶかは設定側が知っている)。 */
type Engine = Query;

type Value = string | string[] | number | boolean | null;
type State = Record<string, Value> & { __sort: string; __ascending: boolean | null };

const DEBOUNCE_MS = 120;

export function mountListFilter<F extends ListFacets>(
  root: HTMLElement,
  spec: ListFilterSpec<F>,
  loadEngine: () => Promise<Engine>,
): void {
  const base = root.dataset.queryBase;
  const container = document.querySelector<HTMLElement>(spec.container);
  if (!base || !container) return;
  const fixedAxes = new Set(JSON.parse(root.dataset.fixedAxes ?? "[]") as string[]);

  const el = {
    root,
    container,
    status: must(root, "[data-filter-status]"),
    open: must<HTMLButtonElement>(root, "[data-filter-open]"),
    controls: must(root, "[data-filter-controls]"),
    fields: must(root, "[data-filter-fields]"),
    sorts: must<HTMLElement>(root, "[data-filter-sorts]"),
    dir: must<HTMLButtonElement>(root, "[data-filter-dir]"),
    reset: must<HTMLButtonElement>(root, "[data-filter-reset]"),
  };

  // 並べ替えの押し場所。表の見出し (指定があれば) か、絞り込みバーの札の列。
  const headerScope = spec.sortHeaders
    ? document.querySelector<HTMLElement>(spec.sortHeaders)
    : null;
  const sortButtons = (): HTMLButtonElement[] => [
    ...(headerScope ?? el.sorts).querySelectorAll<HTMLButtonElement>("[data-sort-key]"),
  ];

  // id → 行。wasm は id を返すので、添字で結び付けない
  // (添字で渡すと、配った生テーブルとページの生成が同じ版である前提になる)。
  const rows = new Map<string, HTMLElement>();
  for (const row of container.querySelectorAll<HTMLElement>(spec.item)) {
    rows.set(row.dataset[spec.idAttr]!, row);
  }
  const total = rows.size;

  const baseQuery = JSON.parse(base) as Record<string, unknown>;
  let fields: FieldSpec[] = [];
  let sorts: SortOption[] = [];
  let defaultSort = "";
  let state = emptyState(fields, defaultSort);
  let engine: Engine | null = null;
  let ready: Promise<boolean> | null = null;
  let timer = 0;

  el.open.addEventListener("click", () => {
    void start().then((ok) => {
      // 押したボタンは消えるので、フォーカスを最初の入力欄へ移す。
      if (ok) el.fields.querySelector<HTMLElement>("input, select, button")?.focus();
    });
  });
  bindSortHeaders();
  // 共有された絞り込み・戻る/進む で来たときは、すぐ起動して URL の条件を復元する。
  // 島が読む軸・並べ替えが URL に無ければ (utm などだけなら) 起動しない。
  const urlHasQuery = (): boolean => hasIslandQuery(location.search, baseQuery, fixedAxes);
  if (urlHasQuery()) void start();

  /** 島を起動する (何度呼んでも 1 回だけ)。生テーブルと wasm はここで初めて取りに行く。 */
  function start(): Promise<boolean> {
    ready ??= boot();
    return ready;
  }

  async function boot(): Promise<boolean> {
    el.open.disabled = true;
    el.root.dataset.state = "loading";
    el.status.textContent = "絞り込みを準備しています…";
    try {
      engine = await loadEngine();
      const facets = spec.facets(engine);
      // ページが決めている軸 (ブランド別ページのブランド・誕生月別ページの誕生月) は出さない。
      fields = spec.fields(facets).filter((f) => !fixedAxes.has(f.key));
      sorts = facets.sorts;
      defaultSort = facets.defaultSort;
      // 軸が確定してから URL を読む (未知の鍵を拾わない)。
      state = readUrl(fields, defaultSort);
      renderFields();
      hideDuplicateAxes();
      renderSorts();
      el.open.hidden = true;
      el.controls.hidden = false;
      for (const c of [el.dir, el.reset]) c.disabled = false;
      el.root.dataset.state = "ready";
      apply();
      return true;
    } catch (e) {
      // 絞り込めないだけで一覧は読める。壊れた見た目のまま黙らない。
      el.status.textContent = "絞り込みを読み込めませんでした。再読み込みしてください。";
      el.root.dataset.state = "failed";
      console.error(`${spec.name}: 読み込みに失敗`, e);
      return false;
    }
  }

  function onChange(): void {
    window.clearTimeout(timer);
    timer = window.setTimeout(apply, DEBOUNCE_MS);
  }

  el.dir.addEventListener("click", () => {
    state.__ascending = !currentAscending();
    syncDir();
    syncSorts();
    onChange();
  });
  el.reset.addEventListener("click", () => {
    // **並べ替えも既定に戻す。** 一覧の既定の並び (アイドルなら公式順) は列見出しに
    // 対応する列が無いので、ここが唯一の戻り道になる。「クリア」= 開いた直後の状態。
    state = emptyState(fields, defaultSort);
    renderFieldValues();
    syncDir();
    syncSorts();
    apply();
  });
  window.addEventListener("popstate", () => {
    if (!engine) {
      if (urlHasQuery()) void start();
      return;
    }
    state = readUrl(fields, defaultSort);
    renderFieldValues();
    renderSorts();
    apply();
  });

  function apply(): void {
    if (!engine) return;

    // 土台 (ページの行を必ず含む条件) に、**入力のあった軸だけ**を重ねる。
    // 空の軸で土台を上書きしない。返ってきた id のうちページに無いものは下で捨てる。
    const query = {
      ...baseQuery,
      ...filled(fields, state),
      sort: state.__sort,
      ascending: state.__ascending,
    };

    let ids: string[];
    try {
      ids = spec.ids(engine, JSON.stringify(query));
    } catch (e) {
      el.status.textContent = "絞り込みに失敗しました。";
      console.error(`${spec.name}: 条件の適用に失敗`, e);
      return;
    }

    // 返ってきた順に並べ、載っていない行は隠す。ページに無い id (母集団の外) は無視する。
    const order: HTMLElement[] = [];
    for (const id of ids) {
      const row = rows.get(id);
      if (row) order.push(row);
    }
    const visible = order.length;
    // 並びも見え方も今と同じなら DOM を動かさない (開いた直後の既定の状態がほとんどこれ。
    // 数千行を同じ順に付け替えるだけの移動をしない)。
    if (!sameAsShown(order)) {
      const shown = new Set(order);
      const frag = document.createDocumentFragment();
      for (const row of order) {
        row.hidden = false;
        frag.appendChild(row);
      }
      for (const row of rows.values()) if (!shown.has(row)) row.hidden = true;
      el.container.appendChild(frag);
    }

    const narrowed = isNarrowed(fields, state);
    el.status.textContent = narrowed ? `${visible} 件 / ${total} 件` : `${total} 件`;
    el.root.dataset.filtered = String(narrowed);
    const pageOrder = state.__sort === defaultSort && currentAscending() === defaultAscendingOf(defaultSort);
    spec.onApply?.({ narrowed, pageOrder });
    writeUrl(fields, state, defaultSort);
  }

  /** 今見えている行が、この順のまま `order` と同じか。 */
  function sameAsShown(order: readonly HTMLElement[]): boolean {
    const shown = [...el.container.querySelectorAll<HTMLElement>(spec.item)].filter((r) => !r.hidden);
    return shown.length === order.length && shown.every((row, i) => row === order[i]);
  }

  // --- 描画 ---------------------------------------------------------------

  /** その並びの既定の向き (決めるのはコア)。 */
  function defaultAscendingOf(key: string): boolean {
    return sorts.find((x) => x.key === key)?.defaultAscending ?? true;
  }

  function currentAscending(): boolean {
    return state.__ascending ?? defaultAscendingOf(state.__sort);
  }

  function syncDir(): void {
    const asc = currentAscending();
    el.dir.textContent = asc ? "↑" : "↓";
    el.dir.setAttribute("aria-label", asc ? "昇順（クリックで降順）" : "降順（クリックで昇順）");
  }

  /**
   * その並びにする。**同じところをもう一度押したら向きを反転**する
   * (札でも表の列見出しでも同じ一押しの手触り)。状態は 1 つ
   * (`state.__sort` / `state.__ascending`) で、向きボタンとも共有する。
   */
  function pickSort(key: string): void {
    if (state.__sort === key) {
      state.__ascending = !currentAscending();
    } else {
      state.__sort = key;
      state.__ascending = null; // その並びの既定方向 (決めるのはコア)。
    }
    syncDir();
    syncSorts();
    onChange();
  }

  /**
   * 表の列見出しに動きを結ぶ。見出しそのものは Astro が (JS 無しでは押せないよう
   * `disabled` で) 出しているので、ここは押せるようにして反応を結ぶだけ。
   * 見出しを押すのも「最初の操作」なので、起動を待ってからその並びにする。
   * **1 回しか呼ばない** (呼び直すと二重に結ばれる)。
   */
  function bindSortHeaders(): void {
    if (!headerScope) return;
    // 向きは見出しの矢印が示すので、独立した向きボタンは出さない。
    el.dir.hidden = true;
    for (const b of sortButtons()) {
      b.disabled = false;
      b.addEventListener("click", () => {
        void start().then((ok) => ok && pickSort(b.dataset.sortKey!));
      });
    }
  }

  /**
   * 島が同じ軸を持っている畳んだメニューを隠す。**同じ絞り込みを 2 つ並べない。**
   * 対応は Rust (`FilterAxis.islandKey`) が持つので、ここで軸名を突き合わせない。
   * HTML には残るので、リンクとしての到達性は落ちない。
   */
  function hideDuplicateAxes(): void {
    const keys = new Set(fields.map((f) => f.key));
    for (const menu of document.querySelectorAll<HTMLElement>("[data-island-key]")) {
      if (keys.has(menu.dataset.islandKey!)) menu.hidden = true;
    }
  }

  /**
   * 並べ替えの札。どの並びがあるかは Rust の素材 (`sorts`) が決め、ここは並べるだけ。
   * 表の列見出しで並べ替える一覧 (`spec.sortHeaders`) では札を出さない。
   */
  function renderSorts(): void {
    if (!sorts.some((o) => o.key === state.__sort)) state.__sort = defaultSort;
    if (!headerScope) {
      el.sorts.replaceChildren(
        ...sorts.map((o) => {
          const button = bandButton(o.label);
          button.dataset.sortKey = o.key;
          button.addEventListener("click", () => pickSort(o.key));
          return button;
        }),
      );
    }
    syncDir();
    syncSorts();
  }

  function syncSorts(): void {
    for (const b of sortButtons()) {
      const active = b.dataset.sortKey === state.__sort;
      // 選ばれていない列からは属性ごと外す。空文字で残すと `[data-dir]` が全列に当たる。
      if (active) b.dataset.dir = currentAscending() ? "asc" : "desc";
      else delete b.dataset.dir;
      // 表の列見出しは `aria-sort` が正しい語 (読み上げが「昇順で並んだ列」と言う)。
      // 札は押した状態を示すだけなので `aria-pressed`。
      const th = b.closest("th");
      if (th) th.setAttribute("aria-sort", active ? (currentAscending() ? "ascending" : "descending") : "none");
      else b.setAttribute("aria-pressed", String(active));
    }
  }


  /** 入力欄。値の集合は wasm (= Snapshot) が出したものをそのまま並べる。 */
  function renderFields(): void {
    el.fields.replaceChildren(...fields.map(fieldElement));
    el.fields.querySelectorAll<HTMLInputElement | HTMLSelectElement>("input[data-key], select[data-key]").forEach((c) => {
      const field = fields.find((f) => f.key === c.dataset.key)!;
      c.addEventListener(field.kind === "select" ? "change" : "input", () => {
        state[field.key] = toValue(field, c.value);
        onChange();
      });
    });
    // 帯 (toggle) は 1 鍵に 2 ボタンあるので、上と同じ input/select の一般経路には乗らない。
    el.fields.querySelectorAll<HTMLButtonElement>("[data-toggle-key]").forEach((b) => {
      b.addEventListener("click", () => {
        const field = fields.find((f) => f.key === b.dataset.toggleKey)!;
        state[field.key] = toValue(field, b.dataset.toggleValue!);
        syncToggles();
        onChange();
      });
    });
    renderFieldValues();
  }

  function renderFieldValues(): void {
    el.fields.querySelectorAll<HTMLInputElement | HTMLSelectElement>("input[data-key], select[data-key]").forEach((c) => {
      c.value = toInput(state[c.dataset.key!]);
    });
    syncToggles();
  }

  /** 帯の押した方を今の状態に合わせる。 */
  function syncToggles(): void {
    el.fields.querySelectorAll<HTMLButtonElement>("[data-toggle-key]").forEach((b) => {
      const on = state[b.dataset.toggleKey!] === true;
      b.setAttribute("aria-checked", String((b.dataset.toggleValue === "true") === on));
    });
  }
}

// --- 部品 -------------------------------------------------------------------

function must<T extends HTMLElement>(root: HTMLElement, selector: string): T {
  const found = root.querySelector<T>(selector);
  if (!found) throw new Error(`絞り込みの部品が無い: ${selector}`);
  return found;
}

/** `textContent` で入れるので、エスケープを自前で書かない。 */
function option(value: string, label: string): HTMLOptionElement {
  const o = document.createElement("option");
  o.value = value;
  o.textContent = label;
  return o;
}

/**
 * 帯 (`.song-filter__sorts`) の中の 1 ボタン。並べ替えの札と `toggle` フィールド
 * (KAMISABI など) は見た目が同じ帯なので、ボタンの組み立てをここに 1 本化する。
 * どの `data-*` 鍵を持たせるか・選ばれた状態をどの属性で示すかは呼び出し側の責務
 * (並べ替えは表の見出しとも共有する `data-sort-key` + `aria-pressed`、`toggle` は
 * 排他選択なので `role="radio"` + `aria-checked`)。
 */
function bandButton(label: string, role?: "radio"): HTMLButtonElement {
  const b = document.createElement("button");
  b.type = "button";
  b.className = "song-filter__sort";
  if (role) b.setAttribute("role", role);
  b.textContent = label;
  return b;
}

function fieldElement(f: FieldSpec): HTMLElement {
  if (f.kind === "toggle") {
    // 排他選択 (どちらか一方だけが真) なので `radiogroup` / `radio` が実体と合う
    // (`group` + `aria-pressed` はトグルボタンの語で、独立に on/off できる場合の語)。
    // 帯そのもの (`.song-filter__sorts` / `.song-filter__sort`) は並べ替えの札と同じ見た目
    // なので流用する (別の CSS を足すと、ここがそうだったように padding 等が容易にドリフトする)。
    const group = document.createElement("div");
    group.className = "song-filter__sorts";
    group.setAttribute("role", "radiogroup");
    group.setAttribute("aria-label", f.label);
    for (const opt of f.options ?? []) {
      const btn = bandButton(opt.label, "radio");
      btn.dataset.toggleKey = f.key;
      btn.dataset.toggleValue = opt.value;
      group.appendChild(btn);
    }
    return group;
  }

  const label = document.createElement("label");
  label.className = "song-filter__field";
  const name = document.createElement("span");
  name.className = "u-visually-hidden";
  name.textContent = f.label;

  let control: HTMLInputElement | HTMLSelectElement;
  if (f.kind === "select") {
    const select = document.createElement("select");
    select.className = "song-filter__select";
    select.append(option("", `${f.label}: すべて`), ...(f.options ?? []).map((o) => option(o.value, o.label)));
    control = select;
  } else {
    const input = document.createElement("input");
    input.className = "song-filter__input";
    input.type = "search";
    input.placeholder = f.label;
    input.autocomplete = "off";
    input.spellcheck = false;
    control = input;
  }
  control.dataset.key = f.key;
  label.append(name, control);
  return label;
}

/** 画面の文字列を、条件が受け取る形へ。 */
function toValue(f: FieldSpec, raw: string): Value {
  if (f.multi) return raw ? [raw] : [];
  if (f.boolean) return raw === "true" ? true : null;
  if (f.numeric) return raw ? Number(raw) : null;
  return raw;
}

/** 条件の値を、入力欄に戻せる文字列へ。 */
function toInput(v: Value | undefined): string {
  if (Array.isArray(v)) return v[0] ?? "";
  return v === null || v === undefined ? "" : String(v);
}

function emptyState(fields: FieldSpec[], sort: string): State {
  const s = { __sort: sort, __ascending: null } as State;
  for (const f of fields) s[f.key] = f.multi ? [] : f.boolean || f.numeric ? null : "";
  return s;
}

/** その軸に入力があるか。 */
function hasValue(v: Value | undefined): boolean {
  if (Array.isArray(v)) return v.length > 0;
  if (typeof v === "string") return v.trim() !== "";
  return v !== null && v !== undefined;
}

/** 入力のあった軸だけを取り出す。空欄は「指定なし」で、土台をそのまま残す。 */
function filled(fields: FieldSpec[], state: State): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const f of fields) {
    const v = state[f.key];
    if (!hasValue(v)) continue;
    out[f.key] = typeof v === "string" ? v.trim() : v;
  }
  return out;
}

function isNarrowed(fields: FieldSpec[], state: State): boolean {
  return fields.some((f) => hasValue(state[f.key]));
}

// --- URL との往復 -----------------------------------------------------------

function readUrl(fields: FieldSpec[], defaultSort: string): State {
  const q = new URLSearchParams(location.search);
  const s = emptyState(fields, q.get("sort") ?? defaultSort);
  for (const f of fields) {
    const v = q.get(f.key);
    if (!v) continue;
    s[f.key] = f.multi
      ? v.split(",").filter(Boolean)
      : f.boolean
        ? (v === "true" ? true : null)
        : f.numeric
          ? Number(v)
          : v;
  }
  const dir = q.get("dir");
  s.__ascending = dir === "asc" ? true : dir === "desc" ? false : null;
  return s;
}

function writeUrl(fields: FieldSpec[], state: State, defaultSort: string): void {
  const q = new URLSearchParams();
  for (const f of fields) {
    const v = state[f.key];
    if (!hasValue(v)) continue;
    q.set(f.key, Array.isArray(v) ? v.join(",") : String(v).trim());
  }
  if (state.__sort !== defaultSort) q.set("sort", state.__sort);
  if (state.__ascending !== null) q.set("dir", state.__ascending ? "asc" : "desc");
  const next = q.toString() ? `${location.pathname}?${q}` : location.pathname;
  if (next !== location.pathname + location.search) history.replaceState(null, "", next);
}
