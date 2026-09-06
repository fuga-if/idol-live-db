/**
 * 一覧の絞り込み・並べ替え island (曲・アイドル共通の実装)。
 *
 * **ここに条件も並び順も無い。** 条件を組み立てて `imas-core` の関数を wasm 越しに
 * 呼び、返ってきた id の順に行を並べ替えて見せ隠しするだけ。アプリと同じ関数を
 * 通るので、当たり方も並びも食い違わない。
 *
 * 土台の条件 (`queryBase`) はページを組んだ Rust が出す。JS が
 * 「/songs/ なら既定フィルタ」と書き直すと、ページの中身と絞り込みの出発点が
 * 二重定義になる。
 *
 * 状態は URL のクエリに置く。戻る/進むで復元でき、絞った状態のまま共有できる
 * (「選択 = URL」という、この出面の基本を崩さない)。
 *
 * **軸は 1 本の表 ([`FieldSpec`]) で決まる。** 以前は「型・初期値・URL の鍵・
 * 描画・重ね方・絞り込み中かの判定」が別々に書かれていて、軸を 1 本足すと
 * 6 箇所を直す必要があった (1 つ忘れても型は通り、URL 復元だけが壊れる)。
 */
import type { SortOption } from "./query";

/** 選択肢 1 件。値はそのまま条件に渡す文字列。 */
export interface Option {
  value: string;
  label: string;
}

/** 入力欄 1 つ。**この 1 行が軸のすべて**を決める。 */
export interface FieldSpec {
  /** 条件・状態・URL で共通の鍵。 */
  key: string;
  kind: "text" | "select";
  /** プレースホルダ / 「すべて」の前に出す名前。 */
  label: string;
  /** select のときの選択肢。 */
  options?: Option[];
  /**
   * 条件側が配列で受ける軸。画面は単一選択で足りる
   * (アプリのピッカーに相当する UI は持たない)。
   */
  multi?: boolean;
  /** 条件側が数値で受ける軸 (誕生月)。 */
  numeric?: boolean;
}

/** 一覧ごとの違いだけを持つ設定。 */
export interface ListFilterSpec<F> {
  /** ログに出す名前。 */
  name: string;
  /** 行を抱えている要素 (tbody / ul)。 */
  container: string;
  /** 行そのもの。`data-<idAttr>` を持っていること。 */
  item: string;
  /** 行の id を持つ dataset のキー。 */
  idAttr: string;
  /** 未指定時の並び (コアの `from_key` の落とし先と同じ鍵)。 */
  fallbackSort: string;
  /** wasm から選択肢を取る。 */
  facets(engine: Engine): F;
  /** wasm に条件を渡して id 列を得る。 */
  ids(engine: Engine, queryJson: string): string[];
  /** 選択肢から並べ替えの一覧を取り出す。 */
  sorts(facets: F): SortOption[];
  /** 選択肢から入力欄の並びを組む。 */
  fields(facets: F): FieldSpec[];
  /**
   * 絞り込み/並べ替えの状態が変わったときの付随処理
   * (かな目次のように、既定の並びを前提にした飛び先を隠す等)。
   */
  onApply?(view: { narrowed: boolean; sort: string; ascending: boolean | null }): void;
}

/** wasm ハンドル。ここは呼ぶだけなので、メソッド名は設定側が知っている。 */
type Engine = unknown;

type Value = string | string[] | number | null;
type State = Record<string, Value> & { __sort: string; __ascending: boolean | null };

const DEBOUNCE_MS = 120;

export function mountListFilter<F>(
  root: HTMLElement,
  spec: ListFilterSpec<F>,
  loadEngine: () => Promise<Engine>,
): void {
  const base = root.dataset.queryBase;
  const container = document.querySelector<HTMLElement>(spec.container);
  if (!base || !container) return;

  const el = {
    root,
    container,
    status: must(root, "[data-filter-status]"),
    fields: must(root, "[data-filter-fields]"),
    sorts: must<HTMLElement>(root, "[data-filter-sorts]"),
    dir: must<HTMLButtonElement>(root, "[data-filter-dir]"),
    reset: must<HTMLButtonElement>(root, "[data-filter-reset]"),
  };

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
  let state = emptyState(fields, spec.fallbackSort);
  let engine: Engine | null = null;
  let timer = 0;

  setEnabled(false);
  void start();

  async function start(): Promise<void> {
    try {
      engine = await loadEngine();
      const facets = spec.facets(engine);
      fields = spec.fields(facets);
      sorts = spec.sorts(facets);
      // 軸が確定してから URL を読む (未知の鍵を拾わない)。
      state = readUrl(fields, spec.fallbackSort);
      renderFields();
      renderSorts();
      setEnabled(true);
      apply();
    } catch (e) {
      // 絞り込めないだけで一覧は読める。壊れた見た目のまま黙らない。
      el.status.textContent = "絞り込みを読み込めませんでした。再読み込みしてください。";
      el.root.dataset.state = "failed";
      console.error(`${spec.name}: 読み込みに失敗`, e);
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
    state = emptyState(fields, state.__sort);
    renderFieldValues();
    apply();
  });
  window.addEventListener("popstate", () => {
    state = readUrl(fields, spec.fallbackSort);
    renderFieldValues();
    renderSorts();
    apply();
  });

  function apply(): void {
    if (!engine) return;

    // 土台 (ページを組んだ条件) に、**入力のあった軸だけ**を重ねる。
    // 空の軸で土台を上書きしない (ブランド別ページで名前を打った瞬間に
    // 全ブランドへ広がってしまう)。
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

    // 返ってきた順に並べ、載っていない行は隠す。
    const shown = new Set(ids);
    const frag = document.createDocumentFragment();
    let visible = 0;
    for (const id of ids) {
      const row = rows.get(id);
      if (!row) continue; // 一覧に載っていない行 (土台の外) は無視する。
      row.hidden = false;
      frag.appendChild(row);
      visible += 1;
    }
    for (const [id, row] of rows) if (!shown.has(id)) row.hidden = true;
    // appendChild で frag は空になるので、件数はここへ来る前に数えておく。
    el.container.appendChild(frag);

    const narrowed = isNarrowed(fields, state);
    el.status.textContent = narrowed ? `${visible} 件 / ${total} 件` : `${total} 件`;
    el.root.dataset.filtered = String(narrowed);
    spec.onApply?.({ narrowed, sort: state.__sort, ascending: state.__ascending });
    writeUrl(fields, state, spec.fallbackSort);
  }

  // --- 描画 ---------------------------------------------------------------

  function setEnabled(on: boolean): void {
    // 入力欄は素材 (facets) が来てから描くので、ここで触るものは無い。
    // 器の側 (sort/dir/reset と列見出し) だけを止めておく。
    for (const c of [el.dir, el.reset]) c.disabled = !on;
    for (const b of el.sorts.querySelectorAll("button")) b.disabled = !on;
    el.root.dataset.state = on ? "ready" : "loading";
  }

  function currentAscending(): boolean {
    if (state.__ascending !== null) return state.__ascending;
    return sorts.find((x) => x.key === state.__sort)?.defaultAscending ?? true;
  }

  function syncDir(): void {
    const asc = currentAscending();
    el.dir.textContent = asc ? "↑" : "↓";
    el.dir.setAttribute("aria-label", asc ? "昇順（クリックで降順）" : "降順（クリックで昇順）");
  }

  /**
   * 並べ替えの札。押すと「その並びにする → もう一度押すと向きを反転」と巡る (表の列見出しと
   * 同じ一押しの手触り)。状態は向きボタンと同じ 1 つ (`state.__sort` / `state.__ascending`)。
   * どの並びがあるかは Rust の素材 (`sorts`) が決め、ここは並べるだけ。
   */
  function renderSorts(): void {
    if (!sorts.some((o) => o.key === state.__sort)) state.__sort = spec.fallbackSort;
    el.sorts.replaceChildren(
      ...sorts.map((o) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "song-filter__sort";
        button.dataset.sortKey = o.key;
        button.textContent = o.label;
        button.addEventListener("click", () => {
          if (state.__sort === o.key) {
            state.__ascending = !currentAscending();
          } else {
            state.__sort = o.key;
            state.__ascending = null; // その並びの既定方向 (決めるのはコア)。
          }
          syncDir();
          syncSorts();
          onChange();
        });
        return button;
      }),
    );
    syncDir();
    syncSorts();
  }

  function syncSorts(): void {
    for (const b of el.sorts.querySelectorAll<HTMLButtonElement>("[data-sort-key]")) {
      const active = b.dataset.sortKey === state.__sort;
      b.setAttribute("aria-pressed", String(active));
      b.dataset.dir = active ? (currentAscending() ? "asc" : "desc") : "";
    }
  }


  /** 入力欄。値の集合は wasm (= Snapshot) が出したものをそのまま並べる。 */
  function renderFields(): void {
    el.fields.replaceChildren(...fields.map(fieldElement));
    el.fields.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-key]").forEach((c) => {
      const field = fields.find((f) => f.key === c.dataset.key)!;
      c.addEventListener(field.kind === "select" ? "change" : "input", () => {
        state[field.key] = toValue(field, c.value);
        onChange();
      });
    });
    renderFieldValues();
  }

  function renderFieldValues(): void {
    el.fields.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-key]").forEach((c) => {
      c.value = toInput(state[c.dataset.key!]);
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

function fieldElement(f: FieldSpec): HTMLLabelElement {
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
  for (const f of fields) s[f.key] = f.multi ? [] : f.numeric ? null : "";
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

function readUrl(fields: FieldSpec[], fallbackSort: string): State {
  const q = new URLSearchParams(location.search);
  const s = emptyState(fields, q.get("sort") ?? fallbackSort);
  for (const f of fields) {
    const v = q.get(f.key);
    if (!v) continue;
    s[f.key] = f.multi ? v.split(",").filter(Boolean) : f.numeric ? Number(v) : v;
  }
  const dir = q.get("dir");
  s.__ascending = dir === "asc" ? true : dir === "desc" ? false : null;
  return s;
}

function writeUrl(fields: FieldSpec[], state: State, fallbackSort: string): void {
  const q = new URLSearchParams();
  for (const f of fields) {
    const v = state[f.key];
    if (!hasValue(v)) continue;
    q.set(f.key, Array.isArray(v) ? v.join(",") : String(v).trim());
  }
  if (state.__sort !== fallbackSort) q.set("sort", state.__sort);
  if (state.__ascending !== null) q.set("dir", state.__ascending ? "asc" : "desc");
  const next = q.toString() ? `${location.pathname}?${q}` : location.pathname;
  if (next !== location.pathname + location.search) history.replaceState(null, "", next);
}
