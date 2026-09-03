/**
 * 「API の引き方が Web から見えない」ことを機械的に固定する。
 *
 * このサイトは完全に静的で、実行時の通信は **同一オリジンの `/search/*.json` と wasm だけ**。
 * 既存の Worker (`imas-live-api`) や CloudKit / iTunes Search の存在を、
 * ソースにも配信物にも一切書かない。
 *
 * ここが赤くなるのは「うっかり実データ API を叩くコードを足した」ときなので、
 * 直し方は endpoint を隠すことではなく **足したコードを消すこと**。
 * データはビルド時に Rust (`web-export`) が JSON に落としてある。
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { walk } from "../scripts/walk.mjs";
import { readJson } from "../src/lib/data";
import type { SearchManifest } from "../src/lib/schema/SearchManifest";

const SRC = path.resolve("./src");
const DIST = path.resolve("./dist");
const CONFIG = path.resolve("./astro.config.mjs");

/** 生成物 (ts-rs / wasm-pack) は検査対象外。中身は Rust 側が保証する。 */
const SKIP_DIRS = new Set(["schema", "fold"]);

/** ソースに書いてよい外部ホスト。増やすときは「なぜ必要か」をレビューで問うこと。 */
const ALLOWED_HOSTS = new Set([
  "imas-live-web.tokata3011.workers.dev", // 自サイト (canonical / OGP / sitemap の絶対 URL)
  "apps.apple.com", // App Store
  "music.apple.com", // Apple Music (曲ページの外部リンク)
  "github.com", // リポジトリ / 生成物のコメント (Aleph-Alpha/ts-rs)
  "fuga-if.github.io", // プライバシー・サポート・利用規約 (既存 GitHub Pages)
  "polyformproject.org", // ライセンス
  "ogp.me", // OGP の名前空間
  "schema.org", // JSON-LD の @context
  "www.w3.org",
  "docs.astro.build",
  "astro.build",
]);

/** 出てはいけないホスト / 語。データ取得経路が推測できるものを名指しで禁じる。 */
const FORBIDDEN = [
  "imas-live-api", // 既存 Worker (共有リンクの着地・投票 API)
  "workers.dev/app/", // その Worker のルート
  "icloud.com",
  "apple-cloudkit.com",
  "api.apple-cloudkit.com",
  "itunes.apple.com", // iTunes Search API (データ補完に使っている経路)
  "music765plus",
  "sparql",
];

const srcFiles = walk(SRC, {
  include: (p) => /\.(ts|astro|css|mjs)$/.test(p),
  skipDir: (name) => SKIP_DIRS.has(name),
});
const rel = (p: string): string => path.relative(path.resolve("."), p);

describe("実行時の通信は同一オリジンだけ", () => {
  it("fetch を書いてよいのは検索 island だけ", () => {
    const offenders = srcFiles
      .filter((f) => /\bfetch\s*\(/.test(fs.readFileSync(f, "utf8")))
      .map(rel)
      .filter((f) => f !== "src/lib/search/island.ts");
    expect(offenders, "fetch は /search/ の island 以外に置かない").toEqual([]);
  });

  it("island の fetch 先は `/search/` 始まりの相対パスだけ", () => {
    const island = fs.readFileSync(path.join(SRC, "lib/search/island.ts"), "utf8");
    const targets = [...island.matchAll(/fetchJson<[^>]*>\(\s*(["'`])([^"'`]*)\1/g)].map(
      (m) => m[2]!,
    );
    expect(targets.length, "fetch 先が 1 つも読み取れていない").toBeGreaterThan(0);
    for (const t of targets) {
      expect(t.startsWith("/search/"), `${t} は /search/ 配下ではない`).toBe(true);
    }
    // 変数経由の URL 組み立て (manifest の path) も、シャードの path が
    // /search/ 始まりであることをフィクスチャ側のテストで固定してある。
    expect(/fetch\s*\(\s*["'`]https?:/.test(island)).toBe(false);
  });

  it("XHR / WebSocket / EventSource / sendBeacon を使わない", () => {
    const banned = [
      "XMLHttpRequest",
      "new WebSocket",
      "EventSource",
      "navigator.sendBeacon",
      "importScripts",
    ];
    const hits: string[] = [];
    for (const f of srcFiles) {
      const text = fs.readFileSync(f, "utf8");
      for (const b of banned) if (text.includes(b)) hits.push(`${rel(f)}: ${b}`);
    }
    expect(hits).toEqual([]);
  });
});

describe("ソースに書かれた外部ホスト", () => {
  const files = [...srcFiles, CONFIG];

  it("allowlist 外のホストが無い", () => {
    const found = new Map<string, string>();
    for (const f of files) {
      for (const m of fs.readFileSync(f, "utf8").matchAll(/https?:\/\/([A-Za-z0-9.-]+)/g)) {
        const host = m[1]!;
        if (!ALLOWED_HOSTS.has(host)) found.set(host, rel(f));
      }
    }
    expect([...found].map(([h, f]) => `${h} (${f})`)).toEqual([]);
  });

  it("禁止語が 1 つも無い", () => {
    const hits: string[] = [];
    for (const f of files) {
      const text = fs.readFileSync(f, "utf8");
      for (const w of FORBIDDEN) if (text.includes(w)) hits.push(`${rel(f)}: ${w}`);
    }
    expect(hits).toEqual([]);
  });
});

const distExists = fs.existsSync(DIST);

describe("配信物 (dist)", () => {
  it.skipIf(!distExists)("HTML と JS に禁止ホストが出てこない", () => {
    const files = walk(DIST, { include: (p) => /\.(html|js)$/.test(p) });
    expect(files.length, "dist に HTML/JS が無い").toBeGreaterThan(0);
    const hits: string[] = [];
    for (const f of files) {
      const text = fs.readFileSync(f, "utf8");
      for (const w of FORBIDDEN) if (text.includes(w)) hits.push(`${rel(f)}: ${w}`);
    }
    expect(hits).toEqual([]);
  });

  /**
   * ブラウザが**自動で取りに行く**先 (サブリソース) だけを縛る。
   *
   * `<a href>` の行き先は公式サイト・チケット・映像商品などデータ由来の外部リンクで、
   * DB に入り得るホストを列挙することはできないし、列挙する意味も無い
   * (踏むかどうかは人が決める)。一方サブリソースは**ページを開いただけで発火する**
   * ので、自分と Apple Music の CDN 以外が混ざったら事故。CSP と同じ線を張る。
   */
  it.skipIf(!distExists)("自動で取りに行く先は自分と Apple Music CDN だけ", () => {
    const files = walk(DIST, { include: (p) => p.endsWith(".html") });
    const hosts = new Map<string, string>();
    for (const f of files) {
      const text = fs.readFileSync(f, "utf8");
      const subresources = [
        ...text.matchAll(/\ssrc=["']https?:\/\/([A-Za-z0-9.-]+)/g),
        ...text.matchAll(/<link\b[^>]*?\shref=["']https?:\/\/([A-Za-z0-9.-]+)/g),
        ...text.matchAll(/\ssrcset=["']https?:\/\/([A-Za-z0-9.-]+)/g),
      ];
      for (const m of subresources) hosts.set(m[1]!, rel(f));
    }
    const allowed = (h: string): boolean =>
      h === "imas-live-web.tokata3011.workers.dev" || /^is\d-ssl\.mzstatic\.com$/.test(h);
    expect([...hosts].filter(([h]) => !allowed(h)).map(([h, f]) => `${h} (${f})`)).toEqual([]);
  });
});

describe("検索索引の参照", () => {
  it("manifest の path が同一オリジンの相対パス", () => {
    const manifest = readJson<SearchManifest>("search/manifest.json");
    for (const s of manifest.shards) {
      expect(s.url.startsWith("/search/"), `${s.url} が /search/ 始まりでない`).toBe(true);
      expect(/^https?:/.test(s.url), `${s.url} が絶対 URL`).toBe(false);
    }
  });
});
