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

const form = document.querySelector<HTMLFormElement>("[data-search-form]");
const input = document.querySelector<HTMLInputElement>("[data-search-input]");
const status = document.querySelector<HTMLElement>("[data-search-status]");
const results = document.querySelector<HTMLElement>("[data-search-results]");
const fallback = document.querySelector<HTMLElement>("[data-search-fallback]");

if (form && input && status && results) {
  form.addEventListener("submit", (e) => e.preventDefault());
  // JS が動いた時点で「JS を有効にすると検索できます」の案内を下げる。
  fallback?.setAttribute("hidden", "");
  input.disabled = false;

  let loading: Promise<Loaded> | null = null;
  let timer: number | undefined;
  let latest = 0;

  const start = () => (loading ??= load());

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
      render([], 0);
      setStatus("");
      return;
    }
    setStatus("検索中…");
    let loaded: Loaded;
    try {
      loaded = await start();
    } catch {
      setStatus("検索の準備に失敗しました。ページを再読み込みするか、上の一覧から辿ってください。");
      return;
    }
    if (seq !== latest) return;

    const needle = loaded.fold(text);
    // sep はフィールド境界。検索語がそれを含むなら、境界を跨いだ偽陽性しか起きない。
    const groups: Group[] = loaded.shards.map((shard) => {
      const matched = needle.includes(shard.body.sep)
        ? []
        : shard.body.rows.filter((r) => r.f.includes(needle));
      return { shard, hits: matched.slice(0, LIMIT_PER_KIND), total: matched.length };
    });
    const total = groups.reduce((n, g) => n + g.total, 0);
    render(groups, total);
    setStatus(total === 0 ? `「${text}」に一致するものはありません` : `${total} 件見つかりました`);
  }

  function setStatus(text: string): void {
    if (status) status.textContent = text;
  }

  function render(groups: readonly Group[], total: number): void {
    if (!results) return;
    results.textContent = "";
    if (total === 0) return;
    for (const g of groups) {
      if (g.hits.length === 0) continue;
      const section = document.createElement("section");
      section.className = "section";

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

      section.append(head, list);
      results.append(section);

      if (g.total > g.hits.length) {
        const more = document.createElement("p");
        more.className = "u-dim";
        more.textContent = `ほか ${g.total - g.hits.length} 件`;
        section.append(more);
      }
    }
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
  hits: readonly SearchRow[];
  total: number;
}

async function load(): Promise<Loaded> {
  const [fold, manifest] = await Promise.all([
    loadFold(),
    fetchJson<SearchManifest>("/search/manifest.json"),
  ]);
  const shards = await Promise.all(
    manifest.shards.map(async (meta) => ({
      meta,
      body: await fetchJson<SearchShard>(meta.path),
    })),
  );
  return { fold, shards };
}

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  return (await res.json()) as T;
}
