// ディレクトリを再帰的に辿ってファイルパスを集める。
//
// check-limits.mjs (dist の集計) と tests/no-api-exposure.test.ts (src と dist の
// 走査) が同じ形を別々に持っていたので 1 本にする。
import fs from "node:fs";
import path from "node:path";

/**
 * `dir` 以下のファイルを深さ優先で列挙する。
 *
 * @param {string} dir 起点
 * @param {{ include?: (fullPath: string) => boolean, skipDir?: (name: string) => boolean }} [options]
 *   `include` は残すファイルの判定 (既定: すべて)。
 *   `skipDir` が真を返すディレクトリには降りない (生成物の除外など)。
 * @returns {string[]} ファイルの絶対パス
 */
export function walk(dir, options = {}) {
  const { include = () => true, skipDir = () => false } = options;
  /** @type {string[]} */
  const out = [];
  const visit = (d) => {
    for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, entry.name);
      if (entry.isDirectory()) {
        if (!skipDir(entry.name)) visit(full);
      } else if (entry.isFile() && include(full)) {
        out.push(full);
      }
    }
  };
  visit(dir);
  return out;
}
