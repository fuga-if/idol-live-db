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
  };
}

function init({ form, input, status, results, fallback }: Elements): void {
  form.addEventListener("submit", (e) => e.preventDefault());
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

  input.addEventListener("focus", start, { once: true });
  input.addEventListener("input", () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => void run(input.value), DEBOUNCE_MS);
  });

  const initial = new URLSearchParams(location.search).get("q");
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

function item(row: SearchRow, shard: Shard): HTMLLIElement {
  const li = document.createElement("li");
  const a = document.createElement("a");
  a.className = "lead-row";
  // `k` は Rust が path_key で安全化したキー。encode は配管であって規則ではない。
  a.href = `${shard.body.pathPrefix}${encodeURIComponent(row.k)}/`;

  const body = document.createElement("span");
  body.className = "lead-row__body";
  const title = document.createElement("span");
  title.className = "lead-row__title";
  title.textContent = row.n;
  body.append(title);
  if (row.s) {
    const sub = document.createElement("span");
    sub.className = "lead-row__sub";
    sub.textContent = row.s;
    body.append(sub);
  }

  const trailing = document.createElement("span");
  trailing.className = "lead-row__trailing";
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
