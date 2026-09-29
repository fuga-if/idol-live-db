/**
 * 1 ページの重さの方針 (HTML 1 枚が圧縮後 1 MiB 未満)。
 *
 * 配信は gzip / brotli で圧縮されるので、閲覧者が受け取る大きさで測る。`/songs/` は 3,000 曲を
 * 1 枚に並べていて生の HTML は 2 MB を超えるが、圧縮後は 300 KB 弱に収まる (Q-14 で、生の
 * 大きさではなく圧縮後で測ると決めた)。規則は `scripts/page-weight.mjs` で、ビルドの門番
 * (`check-limits.mjs`) と同じものを見る。dist が無いとき (型検査だけ回す開発) は skip する。
 */
import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { walk } from "../scripts/walk.mjs";
import { MAX_PAGE_COMPRESSED_BYTES, measurePages } from "../scripts/page-weight.mjs";

const DIST = path.resolve("./dist");

describe("1 ページの重さ", () => {
  it.skipIf(!fs.existsSync(DIST))("どの HTML も圧縮後 1 MiB 未満", () => {
    const pages = walk(DIST, { include: (p) => p.endsWith(".html") });
    expect(pages.length, "dist に HTML が無い").toBeGreaterThan(0);
    const { largest, over } = measurePages(pages);
    expect(largest.bytes).toBeGreaterThan(0);
    expect(
      over.map((p) => `${path.relative(DIST, p.file)} (${p.bytes} バイト)`),
      `上限 ${MAX_PAGE_COMPRESSED_BYTES} バイト`,
    ).toEqual([]);
  });
});
