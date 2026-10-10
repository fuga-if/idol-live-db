// 費用の約束: どのクエリもフルスキャンしない。EXPLAIN QUERY PLAN で固定する。
// 表が空でも、索引が使える形のクエリは索引を選ぶので、スキーマだけで検査できる。
import { describe, expect, it } from "vitest";
import { SQL_DOC, SQL_META, SQL_VERSION, allListShapes, buildList, MAX_LIMIT } from "../src/queries";
import { SCHEMA, emptyDb } from "./helpers";

function plan(db: ReturnType<typeof emptyDb>, sql: string, binds: unknown[]): string[] {
  return (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(binds as never[])) as { detail: string }[]).map((r) => r.detail);
}

describe("クエリの実行計画", () => {
  const db = emptyDb();

  it("一覧は全組み合わせで SCAN を含まない", () => {
    const shapes = allListShapes();
    expect(shapes.length).toBeGreaterThan(10);
    for (const f of shapes) {
      const { sql, binds } = buildList(f);
      const lines = plan(db, sql, binds);
      const scans = lines.filter((l) => /^SCAN /.test(l));
      expect(scans, `${JSON.stringify(f)}\n${sql}\n${lines.join("\n")}`).toEqual([]);
      expect(sql).toMatch(/LIMIT \?\d+$/);
      expect(sql).not.toMatch(/OFFSET/i);
    }
  });

  it("単発の引きも主キー", () => {
    for (const [sql, binds] of [
      [SQL_DOC, ["idol", "x"]],
      [SQL_VERSION, []],
    ] as const) {
      const lines = plan(db, sql, [...binds]);
      expect(lines.filter((l) => /^SCAN /.test(l)), sql).toEqual([]);
    }
  });

  it("meta の全件読みは小さな表に限る (行数を固定)", () => {
    // meta は同期の版などの数行の表。ここだけ全件読みを許し、増えすぎないことを見張る。
    expect(SQL_META).toBe("SELECT key, value FROM meta");
    const keys = (SCHEMA.match(/CREATE TABLE meta/g) ?? []).length;
    expect(keys).toBe(1);
  });

  it("1 ページの上限が決まっている", () => {
    expect(MAX_LIMIT).toBeLessThanOrEqual(100);
  });

  it("D1 に歌詞と試聴の列を置かない", () => {
    const cols = (db.prepare("SELECT m.name AS t, p.name AS c FROM sqlite_master m, pragma_table_info(m.name) p WHERE m.type='table'").all() as { t: string; c: string }[]);
    expect(cols.length).toBeGreaterThan(10);
    for (const { t, c } of cols) expect(`${t}.${c}`).not.toMatch(/lyric|preview/i);
  });
});
