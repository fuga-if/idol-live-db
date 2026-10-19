// GET /master/:type/:name/history を limit と before (直前の応答の next) で続きを読む。
import { describe, expect, it } from "vitest";
import { callJson } from "./support/worker";
import { exec, insertUser } from "./support/d1";

describe("GET /master/:type/:name/history のページング", () => {
  it("新しい順に limit 件と next。next を before に渡すと続き、最後は next なし", async () => {
    await insertUser("001094.editor");
    await exec(
      "INSERT INTO edit_batch (id, editor_id, op, cloudkit_ok, created_at) VALUES (1, '001094.editor', 'update', 1, 1000)"
    );
    for (let i = 1; i <= 5; i++) {
      await exec(
        `INSERT INTO edit_history (id, batch_id, record_type, record_name, op, before_json, after_json, modified_at, created_at)
         VALUES (?, 1, 'Song', 'song_x', 'update', '{"title":"a"}', '{"title":"b"}', ?, ?)`,
        i, i * 1000, i * 1000
      );
    }
    const p1 = await callJson("GET", "/master/Song/song_x/history?limit=2");
    expect(p1.body.history.map((h: any) => h.id)).toEqual([5, 4]);
    expect(p1.body.next).toBe("4000|4");
    const p2 = await callJson("GET", `/master/Song/song_x/history?limit=2&before=${encodeURIComponent(p1.body.next)}`);
    expect(p2.body.history.map((h: any) => h.id)).toEqual([3, 2]);
    const p3 = await callJson("GET", `/master/Song/song_x/history?limit=2&before=${encodeURIComponent(p2.body.next)}`);
    expect(p3.body.history.map((h: any) => h.id)).toEqual([1]);
    expect(p3.body.next).toBeNull();
  });
});
