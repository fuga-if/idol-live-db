import { describe, expect, it } from "vitest";
import { hasIslandQuery } from "../src/lib/listfilter/start";

// 一覧の島は約 10MB の生テーブルと wasm を取りに行く。URL を見てすぐ起動するのは、
// 島が復元できる条件 (絞り込みの軸・並べ替え) が URL にあるときだけ (RedTeam L-7)。
describe("絞り込みの島を URL で起動する条件", () => {
  const songBase = { brandIds: [], title: null, songType: null, kamisabiOnly: false, sort: "kana", ascending: null };

  it("軸・並べ替え・向きがあれば起動する", () => {
    expect(hasIslandQuery("?songType=solo", songBase, [])).toBe(true);
    expect(hasIslandQuery("?title=%E6%9C%AA%E6%9D%A5", songBase, [])).toBe(true);
    expect(hasIslandQuery("?sort=release", songBase, [])).toBe(true);
    expect(hasIslandQuery("?dir=desc", songBase, [])).toBe(true);
    expect(hasIslandQuery("?utm_source=x&songType=solo", songBase, [])).toBe(true);
  });

  it("関係の無いクエリや空では起動しない", () => {
    expect(hasIslandQuery("", songBase, [])).toBe(false);
    expect(hasIslandQuery("?", songBase, [])).toBe(false);
    expect(hasIslandQuery("?utm_source=x&utm_medium=social", songBase, [])).toBe(false);
    expect(hasIslandQuery("?fbclid=abc", songBase, [])).toBe(false);
    // 値が空の軸は「指定なし」(島も読まない)。
    expect(hasIslandQuery("?songType=", songBase, [])).toBe(false);
  });

  it("ページが決めている軸 (島に出さない軸) だけなら起動しない", () => {
    expect(hasIslandQuery("?brandIds=ml", songBase, ["brandIds"])).toBe(false);
    expect(hasIslandQuery("?brandIds=ml", songBase, [])).toBe(true);
  });
});
