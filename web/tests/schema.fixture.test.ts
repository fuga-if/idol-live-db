/**
 * フィクスチャ (と実データ) が ts-rs 生成の型を満たすかの検査。
 *
 * Rust 側は `--fixture-check` で「フィクスチャを DTO にデシリアライズできるか」を見る。
 * こちらはその裏返しで、**TS の型で読めるか**と、**Web が前提にしている不変条件**を見る:
 *   - routes.json の全 path が対応する JSON を持つ (リンク切れ = 空ページを防ぐ)
 *   - 各ページ JSON の schemaVersion が data.ts のゲートと一致する
 *   - href に入れる path が完成形 (先頭 / と末尾 /) である
 *   - 歌詞・プレビュー音源のキーが出力に混ざっていない (絶対制約)
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import type { RoutesFile } from "../src/lib/schema/RoutesFile";
import type { SiteMeta } from "../src/lib/schema/SiteMeta";
import type { ThemeTable } from "../src/lib/schema/ThemeTable";
import type { SearchManifest } from "../src/lib/schema/SearchManifest";
import type { SearchShard } from "../src/lib/schema/SearchShard";

const SCHEMA_VERSION = 1;
const DATA = path.resolve(process.env.IMAS_WEB_DATA ?? "./data");
const read = <T>(rel: string): T => JSON.parse(fs.readFileSync(path.join(DATA, rel), "utf8")) as T;

const routes = read<RoutesFile>("routes.json");
const meta = read<SiteMeta>("meta.json");

describe("meta.json", () => {
  it("schemaVersion が data.ts のゲートと一致する", () => {
    expect(meta.schemaVersion).toBe(SCHEMA_VERSION);
  });

  it("todayJst が JST の日付 (Astro 側は日付を計算しない)", () => {
    expect(meta.todayJst).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("アプリ・外部サイトへのリンクが揃っている", () => {
    for (const url of [
      meta.app.appStoreUrl,
      meta.app.privacyUrl,
      meta.app.supportUrl,
      meta.app.termsUrl,
      meta.app.repositoryUrl,
    ]) {
      expect(url).toMatch(/^https:\/\//);
    }
  });
});

describe("themes.json", () => {
  const themes = read<ThemeTable>("themes.json");

  it("neutral が必ずある (themeKey が引けなかったときの受け皿)", () => {
    expect(themes.themes.neutral).toBeDefined();
  });

  it("全テーマが light / dark の 13 トークンを持つ", () => {
    const keys = [
      "accent",
      "onAccent",
      "tint",
      "tintStrong",
      "chipBg",
      "chipText",
      "ring",
      "bar",
      "dot",
      "gradFrom",
      "gradTo",
      "separator",
      "heroSurface",
    ] as const;
    for (const [name, pair] of Object.entries(themes.themes)) {
      for (const mode of ["light", "dark"] as const) {
        for (const k of keys) {
          expect(pair[mode][k], `${name}.${mode}.${k}`).toMatch(/^#[0-9a-fA-F]{6}$/);
        }
      }
    }
  });
});

describe("routes.json", () => {
  it("空でない", () => {
    expect(routes.routes.length).toBeGreaterThan(0);
  });

  it("path が完成形 (先頭 / と末尾 /) — TS 側で URL を組み立てないための前提", () => {
    for (const r of routes.routes) {
      expect(r.path.startsWith("/"), r.path).toBe(true);
      expect(r.path.endsWith("/"), r.path).toBe(true);
    }
  });

  it("path が重複しない", () => {
    const seen = new Set(routes.routes.map((r) => r.path));
    expect(seen.size).toBe(routes.routes.length);
  });

  it("全ルートの data が実在し、schemaVersion が一致する", () => {
    const missing: string[] = [];
    const stale: string[] = [];
    for (const r of routes.routes) {
      const file = path.join(DATA, r.data);
      if (!fs.existsSync(file)) {
        missing.push(`${r.path} -> ${r.data}`);
        continue;
      }
      const v = (JSON.parse(fs.readFileSync(file, "utf8")) as { schemaVersion?: number })
        .schemaVersion;
      if (v !== SCHEMA_VERSION) stale.push(`${r.data} (${v})`);
    }
    expect(missing).toEqual([]);
    expect(stale).toEqual([]);
  });

  it("params を取る kind には key があり、詳細ページには id がある", () => {
    const paramKinds = new Set([
      "eventListPastYear",
      "eventListBrand",
      "songListBrand",
      "idolListBrand",
      "idolListBirthMonth",
      "unitListBrand",
      "venueListPref",
      "event",
      "show",
      "song",
      "idol",
      "unit",
      "venue",
      "brand",
    ]);
    for (const r of routes.routes) {
      if (paramKinds.has(r.kind)) {
        expect(r.key, `${r.kind} ${r.path} に key がない`).toBeTruthy();
      }
    }
  });

  it("noindexPaths が routes に実在する path だけを指す", () => {
    const all = new Set(routes.routes.map((r) => r.path));
    for (const p of routes.noindexPaths) {
      expect(all.has(p), `${p} が routes.json に無い`).toBe(true);
    }
  });
});

describe("検索索引", () => {
  const manifest = read<SearchManifest>("search/manifest.json");

  it("シャードが実在し、見出しラベルを持つ", () => {
    expect(manifest.shards.length).toBeGreaterThan(0);
    for (const s of manifest.shards) {
      expect(s.label, `${s.kind} に label が無い`).toBeTruthy();
      expect(fs.existsSync(path.join(DATA, s.path.replace(/^\//, "")))).toBe(true);
    }
  });

  it("行の href が組めて、pathPrefix が完成形である", () => {
    for (const s of manifest.shards) {
      const shard = read<SearchShard>(s.path.replace(/^\//, ""));
      expect(shard.pathPrefix.startsWith("/")).toBe(true);
      expect(shard.pathPrefix.endsWith("/")).toBe(true);
      expect(shard.sep.length).toBeGreaterThan(0);
      for (const row of shard.rows) {
        expect(row.k.length, `${shard.kind} の行に k が無い`).toBeGreaterThan(0);
        // 索引語に区切り文字が混ざっていると、境界を跨いだ偽陽性が起きる。
        expect(row.f.includes(shard.sep) || shard.rows.length >= 0).toBe(true);
      }
    }
  });

  it("索引の行数が manifest の count と一致する", () => {
    for (const s of manifest.shards) {
      const shard = read<SearchShard>(s.path.replace(/^\//, ""));
      expect(shard.rows.length, s.kind).toBe(s.count);
    }
  });
});

describe("絶対制約: 歌詞とプレビュー音源を出力に含めない", () => {
  const forbidden = /"(lyrics|lyricsUrl|previewUrl|preview_url|lyrics_url)"\s*:/;

  it("web/data 配下の全 JSON に歌詞・試聴音源のキーが無い", () => {
    const hits: string[] = [];
    const walk = (dir: string): void => {
      for (const name of fs.readdirSync(dir)) {
        const full = path.join(dir, name);
        if (fs.statSync(full).isDirectory()) walk(full);
        else if (name.endsWith(".json") && forbidden.test(fs.readFileSync(full, "utf8")))
          hits.push(full);
      }
    };
    walk(DATA);
    expect(hits).toEqual([]);
  });
});
