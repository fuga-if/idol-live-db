/**
 * 配信物のリンク切れ検査。
 *
 * Rust 側は `routes.json` のリンクグラフを BFS して到達性を固定しているが、
 * それは **JSON の中の話**で、「テンプレートが実際に書き出した href」までは見ていない。
 * 実際に、ブランド一覧を作っていない組み合わせ (`/songs/brand/other/` など) を
 * パンくずが指していた不具合が出ている。ここは描画結果そのものを突き合わせる。
 *
 * dist が無いとき (型検査だけ回す開発) は skip する。
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { walk } from "../scripts/walk.mjs";

const DIST = path.resolve("./dist");
const distExists = fs.existsSync(DIST);

/** `href="/..."` の内部リンク (フラグメントとクエリは落とす)。 */
const HREF = /href="(\/[^"#?]*)"/g;

describe("配信物の内部リンク", () => {
  it.skipIf(!distExists)("すべて dist の中のファイルに解決する", () => {
    const pages = walk(DIST, { include: (p) => p.endsWith(".html") });
    expect(pages.length, "dist に HTML が無い").toBeGreaterThan(0);

    const hrefs = new Set<string>();
    for (const file of pages) {
      for (const m of fs.readFileSync(file, "utf8").matchAll(HREF)) hrefs.add(m[1]!);
    }
    expect(hrefs.size).toBeGreaterThan(0);

    const missing = [...hrefs].filter((href) => {
      // href は percent-encode 済み。ファイル名は生の UTF-8 なので戻して照合する。
      let rel: string;
      try {
        rel = decodeURIComponent(href);
      } catch {
        return true; // 不正なエスケープはその時点で壊れている
      }
      const target = path.join(DIST, rel.replace(/^\//, ""));
      return !fs.existsSync(rel.endsWith("/") ? path.join(target, "index.html") : target);
    });
    expect(missing.sort().slice(0, 20), `リンク切れ ${missing.length} 件`).toEqual([]);
  });
});
