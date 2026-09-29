// お題の投票 (POST /polls/:id/votes, DELETE /polls/:id/votes/:entityId) の原子性と、枠の消費の順序。
//   - 票数は read-modify-write せず相対で動かすので、同時に投票・取り消ししても取りこぼさない。
//   - 本文やお題の状態で断る投票・同じ候補への再投票は、投票の枠 (poll_vote) を消費しない。
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

const usedVoteQuota = async (uid = UID) =>
  (await row<{ count: number }>("SELECT count FROM rate_limits WHERE user_id = ? AND action = 'poll_vote'", uid))
    ?.count ?? 0;

describe("投票の枠 (poll_vote) は、実際に票を入れるときだけ消費する", () => {
  it("本文が不正・無いお題・終了・候補外は消費しない", async () => {
    await insertUser(UID);
    await insertPoll("ended", { endsIn: "-1 minute" });
    await insertPoll("m", { scope: "manual", entities: ["s1", "s2"] });
    expect((await vote("m", undefined)).status).toBe(400);
    expect((await vote("none", "s1")).status).toBe(404);
    expect((await vote("ended", "s1")).status).toBe(409);
    expect((await vote("m", "s9")).status).toBe(422);
    expect(await usedVoteQuota()).toBe(0);
  });

  it("同じ候補への再投票 (200) と、3 票を使い切った後の投票 (409) は消費しない", async () => {
    await insertUser(UID);
    await insertPoll("p");
    expect((await vote("p", "s1")).status).toBe(201);
    expect((await vote("p", "s1")).status).toBe(200);
    expect(await usedVoteQuota()).toBe(1);
    for (const e of ["s2", "s3"]) expect((await vote("p", e)).status).toBe(201);
    expect((await vote("p", "s4")).status).toBe(409);
    // 使い切った後は、同じ候補への再投票も今までどおり上限の 409 を返す。
    expect((await vote("p", "s1")).status).toBe(409);
    expect(await usedVoteQuota()).toBe(3);
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
