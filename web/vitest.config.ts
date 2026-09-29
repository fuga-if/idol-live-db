import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    // 配信物を丸ごと走査する検査 (dist 7,600 ファイル / 169MB、web/data 7,640 ファイル)
    // があるので、既定の 5 秒では中身と関係なく時間で落ちる。ファイル数に比例して
    // 伸びる種類の検査なので、上限は実行時間ではなく「明らかに止まっている」線で引く。
    testTimeout: 120_000,
  },
});
