/**
 * `/search/` の island — このサイトで唯一のブラウザ JS。
 *
 * やること: 索引 JSON を取り、Rust と同じ規則で畳んだ検索語で `includes` して、
 * 見つかったページへのリンクを並べる。**ページを探すためのナビゲーション補助**であって、
 * 状態を持つ機能ではない (フォームは送信せず、履歴も書かず、結果に色も付けない)。
 *
 * 照合が Rust の `TextSearchIndex::matches` と等価になる根拠:
 *   索引側は Rust が畳んで `f` に入れてある。検索語は同じ `imas-text-fold` を wasm 経由で
 *   畳む。両方が同じ規則を通っているので、あとは部分一致を見るだけでよい。
 *   フィールド境界 (`sep`) を跨いだ偽陽性だけは、検索語に `sep` が入り得ないことを
 *   確認して弾く (これは規則ではなく前提条件の確認)。
 */
import { loadFold, type Fold } from "./fold";
import type { SearchManifest } from "../schema/SearchManifest";
import type { SearchShard } from "../schema/SearchShard";
import type { SearchShardMeta } from "../schema/SearchShardMeta";
import type { SearchRow } from "../schema/SearchRow";

const LIMIT_PER_KIND = 30;
const DEBOUNCE_MS = 80;
/** 歌詞は Worker (D1) を叩くので、打鍵ごとには飛ばさない。 */
const LYRICS_DEBOUNCE_MS = 500;
/** 1 文字の歌詞検索は索引で絞れず全走査になる。2 文字から。 */
const LYRICS_MIN_CHARS = 2;

/** 歌詞検索 (Worker) の応答。曲 id と一致箇所の窓だけで、本文は無い。 */
interface LyricsHit {
  songId: string;
  snippets: { snippet: string; matchStart: number; matchLength: number }[];
}
interface LyricsResponse {
  query: string;
  hits: LyricsHit[];
}

/** 索引 1 本 = manifest の見出し情報 + 本体。 */
interface Shard {
  meta: SearchShardMeta;
  body: SearchShard;
}

interface Loaded {
  fold: Fold;
  shards: Shard[];
}

interface Group {
  shard: Shard;
  hits: SearchRow[];
  total: number;
}

interface Elements {
  form: HTMLFormElement;
  input: HTMLInputElement;
  status: HTMLElement;
  results: HTMLElement;
  fallback: HTMLElement | null;
  /** 歌詞検索の取得先 (Rust が meta.json に出したもの)。無ければ名前だけ。 */
  lyricsSearchUrl: string | null;
  modes: HTMLInputElement[];
}

function elements(): Elements | null {
  const form = document.querySelector<HTMLFormElement>("[data-search-form]");
  const input = document.querySelector<HTMLInputElement>("[data-search-input]");
  const status = document.querySelector<HTMLElement>("[data-search-status]");
  const results = document.querySelector<HTMLElement>("[data-search-results]");
  if (!form || !input || !status || !results) return null;
  return {
    form,
    input,
    status,
    results,
    fallback: document.querySelector<HTMLElement>("[data-search-fallback]"),
    lyricsSearchUrl: form.dataset.lyricsSearch ?? null,
    modes: [...form.querySelectorAll<HTMLInputElement>("[data-search-mode]")],
  };
}

function init({ form, input, status, results, fallback, lyricsSearchUrl, modes }: Elements): void {
  form.addEventListener("submit", (e) => e.preventDefault());
  // 歌詞の一致箇所は本文の断片。選択・コピー・右クリック・ドラッグを止める
  // (曲ページの歌詞と同じ扱い。完全には防げないが、まとめ取りの手間を上げる)。
  for (const type of ["copy", "cut", "contextmenu", "dragstart", "selectstart"]) {
    results.addEventListener(type, (e) => {
      if ((e.target as Element | null)?.closest?.(".search-snippet")) e.preventDefault();
    });
  }
  // JS が動いた時点で「JS を有効にすると検索できます」の案内を下げる。
  fallback?.setAttribute("hidden", "");
  // 入力欄は最初から使える (disabled にすると支援技術から要素ごと消え、
  // フォーカスも当たらないので「準備中」であることすら伝わらない)。
  // 打鍵は受け付けたうえで、準備中であることは aria-busy と status で伝える。
  input.removeAttribute("aria-busy");
  status.textContent = "";

  let loading: Promise<Loaded> | null = null;
  let timer: number | undefined;
  let latest = 0;

  const start = (): Promise<Loaded> => (loading ??= load());

  const lyricsMode = (): boolean =>
    lyricsSearchUrl !== null && modes.some((m) => m.checked && m.value === "lyrics");

  input.addEventListener("focus", start, { once: true });
  input.addEventListener("input", () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(
      () => void run(input.value),
      lyricsMode() ? LYRICS_DEBOUNCE_MS : DEBOUNCE_MS,
    );
  });
  for (const m of modes) {
    m.addEventListener("change", () => {
      window.clearTimeout(timer);
      void run(input.value);
    });
  }

  const params = new URLSearchParams(location.search);
  const initial = params.get("q");
  if (params.get("mode") === "lyrics") {
    for (const m of modes) m.checked = m.value === "lyrics";
  }
  if (initial) {
    input.value = initial;
    void run(initial);
  }

  async function run(raw: string): Promise<void> {
    const seq = ++latest;
    const text = raw.trim();
    if (!text) {
      results.textContent = "";
      status.textContent = "";
      return;
    }
    if (lyricsMode()) {
      await runLyrics(text, seq);
      return;
    }
    status.textContent = "検索中…";
    let loaded: Loaded;
    try {
      loaded = await start();
    } catch {
      status.textContent =
        "検索の準備に失敗しました。ページを再読み込みするか、上の一覧から辿ってください。";
      return;
    }
    if (seq !== latest) return;

    const needle = loaded.fold(text);
    const groups = loaded.shards.map((shard) => search(shard, needle));
    const total = groups.reduce((n, g) => n + g.total, 0);
    render(results, groups, total);
    status.textContent =
      total === 0 ? `「${text}」に一致するものはありません` : `${total} 件見つかりました`;
  }

  /**
   * 歌詞の中の言葉で探す。照合は Worker (D1 の索引) がやり、返るのは曲 id と一致箇所の窓だけ。
   * 曲名は楽曲の索引から引く (Worker はマスタを持たない)。
   */
  async function runLyrics(text: string, seq: number): Promise<void> {
    if (Array.from(text).length < LYRICS_MIN_CHARS) {
      results.textContent = "";
      status.textContent = `歌詞は ${LYRICS_MIN_CHARS} 文字以上で探せます`;
      return;
    }
    status.textContent = "歌詞を検索中…";
    let loaded: Loaded;
    try {
      loaded = await start();
    } catch {
      status.textContent = "検索の準備に失敗しました。ページを再読み込みしてください。";
      return;
    }
    let data: LyricsResponse;
    try {
      // 取得先は data 属性 (Rust が出した URL)。ここで URL を組まない。
      const res = await fetch(`${lyricsSearchUrl}?q=${encodeURIComponent(text)}`, {
        headers: { Accept: "application/json" },
      });
      if (res.status === 429) {
        if (seq === latest) status.textContent = "検索の回数が上限に達しました。しばらく待ってからお試しください。";
        return;
      }
      if (!res.ok) throw new Error(String(res.status));
      data = (await res.json()) as LyricsResponse;
    } catch {
      if (seq === latest) status.textContent = "歌詞の検索に失敗しました。時間をおいてお試しください。";
      return;
    }
    if (seq !== latest) return;
    const songs = loaded.shards.find((s) => s.meta.kind === "song");
    const rows = new Map<string, SearchRow>();
    for (const row of songs?.body.rows ?? []) rows.set(row.i ?? row.k, row);
    const hits = data.hits.filter((h) => rows.has(h.songId));
    results.textContent = "";
    if (hits.length === 0) {
      status.textContent = `歌詞に「${text}」を含む曲は見つかりませんでした`;
      return;
    }
    results.append(lyricsSection(hits, rows, songs!));
    status.textContent = `歌詞に「${text}」を含む曲が ${hits.length} 件`;
  }
}

/** 歌詞検索の結果 1 区画。行は名前の検索と同じ骨格に、一致箇所の窓を 1 本添える。 */
function lyricsSection(hits: LyricsHit[], rows: Map<string, SearchRow>, songs: Shard): HTMLElement {
  const el = document.createElement("section");
  el.className = "section";
  const head = document.createElement("div");
  head.className = "section__head";
  const h = document.createElement("h2");
  h.className = "section__title";
  h.textContent = "歌詞";
  const count = document.createElement("span");
  count.className = "section__count";
  count.textContent = String(hits.length);
  head.append(h, count);

  const list = document.createElement("ul");
  list.className = "card";
  for (const hit of hits) {
    const row = rows.get(hit.songId)!;
    const li = item(row, songs);
    const first = hit.snippets[0];
    if (first) li.querySelector(".row__body")?.append(snippet(first));
    list.append(li);
  }
  el.append(head, list);
  return el;
}

/** 一致箇所の窓。一致した部分だけ <mark> で示す。 */
function snippet(s: { snippet: string; matchStart: number; matchLength: number }): HTMLElement {
  const p = document.createElement("span");
  p.className = "row__meta search-snippet";
  const chars = Array.from(s.snippet);
  const before = chars.slice(0, s.matchStart).join("");
  const match = chars.slice(s.matchStart, s.matchStart + s.matchLength).join("");
  const after = chars.slice(s.matchStart + s.matchLength).join("");
  const mark = document.createElement("mark");
  mark.textContent = match;
  p.append(before, mark, after);
  return p;
}

/**
 * 1 シャードを走査する。
 * 表示は上位 `LIMIT_PER_KIND` 件だけなので、行の保持もそこで打ち切る
 * (楽曲 3,153 行が全部当たるような 1 文字検索でも配列が伸びない)。
 */
function search(shard: Shard, needle: string): Group {
  // sep はフィールド境界。空だと includes が常に真になり全行が当たってしまう。
  if (!shard.body.sep) throw new Error(`${shard.meta.kind}: sep が空`);
  // 検索語が境界を含むなら、跨いだ偽陽性しか起きない。
  if (needle.includes(shard.body.sep)) return { shard, hits: [], total: 0 };

  const hits: SearchRow[] = [];
  let total = 0;
  for (const row of shard.body.rows) {
    if (!row.f.includes(needle)) continue;
    total += 1;
    if (hits.length < LIMIT_PER_KIND) hits.push(row);
  }
  return { shard, hits, total };
}

/** 結果を組み立てて 1 回だけ差し替える (種別ごとに reflow させない)。 */
function render(results: HTMLElement, groups: readonly Group[], total: number): void {
  results.textContent = "";
  if (total === 0) return;
  const frag = document.createDocumentFragment();
  for (const g of groups) {
    if (g.hits.length === 0) continue;
    frag.append(section(g));
  }
  results.append(frag);
}

function section(g: Group): HTMLElement {
  const el = document.createElement("section");
  el.className = "section";

  const head = document.createElement("div");
  head.className = "section__head";
  const h = document.createElement("h2");
  h.className = "section__title";
  h.textContent = g.shard.meta.label;
  const count = document.createElement("span");
  count.className = "section__count";
  count.textContent = String(g.total);
  head.append(h, count);

  const list = document.createElement("ul");
  list.className = "card";
  for (const row of g.hits) list.append(item(row, g.shard));

  el.append(head, list);

  if (g.total > g.hits.length) {
    const more = document.createElement("p");
    more.className = "u-dim";
    more.textContent = `ほか ${g.total - g.hits.length} 件`;
    el.append(more);
  }
  return el;
}

/** 結果の 1 行。一覧の行 (`DatedRow.astro`) と同じ骨格・クラスで描く (見た目を 2 つ持たない)。 */
function item(row: SearchRow, shard: Shard): HTMLLIElement {
  const li = document.createElement("li");
  const a = document.createElement("a");
  a.className = "row row--bar";
  // `k` は Rust が path_key で安全化したキー。encode は配管であって規則ではない。
  a.href = `${shard.body.pathPrefix}${encodeURIComponent(row.k)}/`;

  const body = document.createElement("span");
  body.className = "row__body";
  const title = document.createElement("span");
  title.className = "row__title";
  title.textContent = row.n;
  body.append(title);
  if (row.s) {
    const meta = document.createElement("span");
    meta.className = "row__meta";
    const sub = document.createElement("span");
    sub.className = "row__meta-item";
    sub.textContent = row.s;
    meta.append(sub);
    body.append(meta);
  }

  const trailing = document.createElement("span");
  trailing.className = "row__trailing";
  const chev = document.createElement("span");
  chev.className = "chevron";
  chev.setAttribute("aria-hidden", "true");
  chev.textContent = "›";
  trailing.append(chev);

  a.append(body, trailing);
  li.append(a);
  return li;
}

async function load(): Promise<Loaded> {
  const [fold, manifest] = await Promise.all([
    loadFold(),
    fetchJson<SearchManifest>("/search/manifest.json"),
  ]);
  const shards = await Promise.all(
    manifest.shards.map(async (meta) => ({
      meta,
      body: await fetchJson<SearchShard>(meta.url),
    })),
  );
  return { fold, shards };
}

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  return (await res.json()) as T;
}

const els = elements();
if (els) init(els);
