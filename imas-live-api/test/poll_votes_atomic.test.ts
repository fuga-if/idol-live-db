// お題の投票 (POST /polls/:id/votes, DELETE /polls/:id/votes/:entityId) の原子性と、1 日の枠が無いこと。
//   - 票数は read-modify-write せず相対で動かすので、同時に投票・取り消ししても取りこぼさない。
//   - 1 日の枠は持たない (1 お題 3 票の上限だけ)。rate_limits に行を書かない。
// ⚠️ 1 人 3 票の上限は、書き込み前の COUNT で判定する (出演者予想と同じ)。同じ人が同時に
//    投げた投票の上限のすり抜けは、D1 の読み取りを増やさずには防げないので残している。

import { describe, expect, it } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { exec, insertUser, meterD1, row, rows } from "./support/d1";

const UID = "001094.voter";

async function insertPoll(id: string, opts: { endsIn?: string; scope?: string; entities?: string[] } = {}) {
  await exec(
    `INSERT INTO polls (id, title, target_type, created_by, ends_at, candidate_scope, scope_entity_ids)
     VALUES (?, 't', 'song', 'owner', datetime('now', ?), ?, ?)`,
    id, opts.endsIn ?? "+1 day", opts.scope ?? "all", opts.entities ? JSON.stringify(opts.entities) : null
  );
}

async function vote(pollId: string, entityId: unknown, uid = UID, env = makeEnv()) {
  return callJson("POST", `/polls/${pollId}/votes`, { headers: await bearer(uid), body: { entity_id: entityId }, env });
}

async function unvote(pollId: string, entityId: string, uid = UID, env = makeEnv()) {
  return callJson("DELETE", `/polls/${pollId}/votes/${entityId}`, { headers: await bearer(uid), env });
}

describe("お題の投票に 1 日の枠は無い (1 お題 3 票の上限だけ)", () => {
  it("お題をまたいで何票入れても断られず、rate_limits に行を書かない", async () => {
    await insertUser(UID);
    // 旧枠 (60) を超える 25 お題 × 3 票 = 75 票。
    for (let i = 0; i < 25; i++) {
      await insertPoll(`p${i}`);
      for (const e of ["s1", "s2", "s3"]) expect((await vote(`p${i}`, e)).status).toBe(201);
    }
    expect(await rows("SELECT * FROM rate_limits WHERE user_id = ?", UID)).toHaveLength(0);
  });

  it("1 お題 3 票の上限は今までどおり 409", async () => {
    await insertUser(UID);
    await insertPoll("p");
    for (const e of ["s1", "s2", "s3"]) expect((await vote("p", e)).status).toBe(201);
    expect((await vote("p", "s1")).status).toBe(409);
    expect((await vote("p", "s4")).status).toBe(409);
  });
});

describe("同時の投票・取り消し", () => {
  it("別々の人が同時に同じ候補へ投票しても、票を取りこぼさない", async () => {
    await insertPoll("p");
    const voters = Array.from({ length: 6 }, (_, i) => `001094.v${i}`);
    for (const v of voters) await insertUser(v);
    const results = await Promise.all(voters.map((v) => vote("p", "s1", v)));
    expect(results.every((r) => r.status === 201)).toBe(true);
    expect(await row("SELECT vote_count FROM poll_entries WHERE poll_id = 'p' AND entity_id = 's1'"))
      .toEqual({ vote_count: 6 });
  });

  it("別々の人が同時に取り消しても、票を取りこぼさない", async () => {
    await insertPoll("p");
    const voters = Array.from({ length: 6 }, (_, i) => `001094.v${i}`);
    for (const v of voters) {
      await insertUser(v);
      await vote("p", "s1", v);
    }
    await vote("p", "s2", voters[0]);
    const results = await Promise.all(voters.slice(1).map((v) => unvote("p", "s1", v)));
    expect(results.every((r) => r.status === 200)).toBe(true);
    expect(await rows("SELECT entity_id, vote_count FROM poll_entries WHERE poll_id = 'p' ORDER BY entity_id"))
      .toEqual([{ entity_id: "s1", vote_count: 1 }, { entity_id: "s2", vote_count: 1 }]);
  });

  it("同じ票の取り消しを同時に送っても、二重に減らない", async () => {
    await insertPoll("p");
    await insertUser(UID);
    await insertUser("001094.other");
    await vote("p", "s1");
    await vote("p", "s1", "001094.other");
    const results = await Promise.all([unvote("p", "s1"), unvote("p", "s1"), unvote("p", "s1")]);
    expect(results.every((r) => r.status === 200)).toBe(true);
    expect(await row("SELECT vote_count FROM poll_entries WHERE poll_id = 'p' AND entity_id = 's1'"))
      .toEqual({ vote_count: 1 });
  });

  it("同じ候補への投票を同時に送っても、二重に数えない", async () => {
    await insertPoll("p");
    await insertUser(UID);
    const results = await Promise.all([vote("p", "s1"), vote("p", "s1"), vote("p", "s1")]);
    expect(results.filter((r) => r.status === 201).length).toBeGreaterThanOrEqual(1);
    expect(await row("SELECT vote_count FROM poll_entries WHERE poll_id = 'p' AND entity_id = 's1'"))
      .toEqual({ vote_count: 1 });
    expect(await rows("SELECT * FROM poll_votes WHERE poll_id = 'p'")).toHaveLength(1);
  });
});

describe("D1 の読み取り行数は変更前を超えない", () => {
  it("投票と取り消し", async () => {
    await insertUser(UID);
    await insertPoll("p");
    await exec("INSERT INTO poll_entries (poll_id, entity_id, vote_count) VALUES ('p', 'e1', 1), ('p', 'e2', 1)");
    const m = meterD1();
    const env = makeEnv({ DB: m.db });
    const measure = async (work: () => Promise<{ status: number }>, expected: number) => {
      m.reset();
      expect((await work()).status).toBe(expected);
      return m.usage.rowsRead;
    };
    // 変更前の実測 (この順で流したとき)。
    expect(await measure(() => vote("p", "e1", UID, env), 201)).toBeLessThanOrEqual(6);  // 自分 0 票・既存の候補
    expect(await measure(() => vote("p", "n1", UID, env), 201)).toBeLessThanOrEqual(6);  // 自分 1 票・新しい候補
    expect(await measure(() => vote("p", "e1", UID, env), 200)).toBeLessThanOrEqual(9);  // 同じ候補への再投票
    expect(await measure(() => vote("p", "e2", UID, env), 201)).toBeLessThanOrEqual(9);  // 自分 2 票・既存の候補
    expect(await measure(() => vote("p", "n2", UID, env), 409)).toBeLessThanOrEqual(8);  // 上限
    expect(await measure(() => unvote("p", "zz", UID, env), 200)).toBeLessThanOrEqual(3); // 入れていない候補
    expect(await measure(() => unvote("p", "e2", UID, env), 200)).toBeLessThanOrEqual(6); // 取り消し
    expect(await measure(() => unvote("p", "n1", UID, env), 200)).toBeLessThanOrEqual(5); // 取り消して 0 票
  });
});
