// 1 ページの重さの方針。check-limits.mjs (ビルドの門番) と tests/page-weight.test.ts が同じ規則を見る。
//
// 方針は「HTML 1 枚が 1 MiB 未満」。**配信は圧縮される** (Cloudflare が gzip / brotli で返す) ので、
// 閲覧者が受け取る大きさ = 圧縮後で測る。`/songs/` は 3,000 曲を 1 枚に並べていて、生の HTML は
// 2 MB を超えるが、同じ骨格の行の繰り返しなので圧縮後は 1 割ほどになる。
// 測るのは gzip (既定の圧縮率)。brotli はこれより小さくなるので、gzip で収まれば必ず収まる。
import fs from "node:fs";
import zlib from "node:zlib";

/** HTML 1 枚の上限 (圧縮後)。 */
export const MAX_PAGE_COMPRESSED_BYTES = 1024 * 1024;

/** HTML 1 枚の gzip 後の大きさ。 */
export function compressedSize(file) {
  return zlib.gzipSync(fs.readFileSync(file)).length;
}

/**
 * 圧縮後の大きさを測り、いちばん重いページと、上限を超えたページを返す。
 * @param {string[]} files HTML の絶対パス
 * @returns {{ largest: { file: string, bytes: number }, over: { file: string, bytes: number }[] }}
 */
export function measurePages(files) {
  let largest = { file: "(none)", bytes: 0 };
  /** @type {{ file: string, bytes: number }[]} */
  const over = [];
  for (const file of files) {
    const bytes = compressedSize(file);
    if (bytes > largest.bytes) largest = { file, bytes };
    if (bytes >= MAX_PAGE_COMPRESSED_BYTES) over.push({ file, bytes });
  }
  return { largest, over };
}
