// みんなの投票 (お題) の特性テスト。ローカル D1 で index.ts の入口から通す。
//
// ⚠️ 投票の read-modify-write の原子性と、本文を検証する前に枠を消費する順序は P2-16 で直すので、
//    ここでは固定しない (test/poll_votes_atomic.test.ts が直した後の挙動を固定する)。

import { describe, expect, it } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";

const OWNER = "001094.poll-owner";
const VOTER = "001094.poll-voter";
const ADMIN = "001094.poll-admin";

// is_own_poll (呼び出した人のお題か) は Q-10 で足した。created_by はアプリの移行後に消す。
const POLL_KEYS = [
  "candidate_scope", "created_at", "created_by", "description", "ends_at", "entry_count", "id",
  "is_own_poll", "scope_brand_ids", "scope_entity_ids", "status", "target_type", "title", "total_votes",
];

/** お題を直接入れる。ends_at は SQLite の datetime 修飾子 ("+1 day" 等)。 */
async function insertPoll(
  id: string,
  opts: { endsIn?: string; status?: string; scope?: string; entities?: string[]; createdBy?: string } = {}
) {
  await exec(
    `INSERT INTO polls (id, title, description, target_type, created_by, ends_at, status,
                        candidate_scope, scope_entity_ids)
     VALUES (?, ?, NULL, 'song', ?, datetime('now', ?), ?, ?, ?)`,
    id,
    `title-${id}`,
    opts.createdBy ?? OWNER,
    opts.endsIn ?? "+1 day",
    opts.status ?? "active",
    opts.scope ?? "all",
    opts.entities ? JSON.stringify(opts.entities) : null
  );
}

async function vote(pollId: string, entityId: string, uid = VOTER) {
  return callJson("POST", `/polls/${pollId}/votes`, { headers: await bearer(uid), body: { entity_id: entityId } });
}

describe("POST /polls (お題の作成)", () => {
  it("未ログインは 401、BAN は 403", async () => {
    expect((await callJson("POST", "/polls", { body: { title: "x" } })).status).toBe(401);
    await insertUser(OWNER, { isBanned: true });
    const res = await callJson("POST", "/polls", { headers: await bearer(OWNER), body: { title: "x" } });
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Banned" });
  });

  it("本文を検証する", async () => {
    await insertUser(OWNER);
    const cases: Array<[unknown, string]> = [
      ["{", "invalid JSON body"],
      [{ target_type: "song" }, "title is required"],
      [{ title: "  ", target_type: "song" }, "title is required"],
      [{ title: "t".repeat(81), target_type: "song" }, "title must be 80 characters or less"],
      [{ title: "ok", description: 1, target_type: "song" }, "description must be 280 characters or less"],
      [{ title: "ok", target_type: "event" }, "target_type must be 'song', 'idol', or 'unit'"],
      [{ title: "ok", target_type: "song", candidate_scope: "x" }, "candidate_scope must be 'all', 'brand', or 'manual'"],
      [{ title: "ok", target_type: "song", candidate_scope: "manual", scope_entity_ids: ["a"] },
        "scope_entity_ids must contain at least 2 entries"],
      [{ title: "ok", target_type: "song", candidate_scope: "manual", scope_entity_ids: ["a", "a"] },
        "scope_entity_ids contains duplicates"],
      [{ title: "ok", target_type: "song", candidate_scope: "brand", scope_brand_ids: ["nope"] },
        "scope_brand_ids contains unknown id"],
    ];
    const env = makeEnv();
    for (const [body, message] of cases) {
      // 作成は 1 日 5 件の枠を先に消費するので、ケースごとに枠を戻す。
      await exec("DELETE FROM rate_limits");
      const res = await callJson("POST", "/polls", { headers: await bearer(OWNER), body, env });
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body).toEqual({ error: message });
    }
  });

  it("201 で作ったお題を返す。締切は日数 (1〜30、既定 14) で決まる", async () => {
    await insertUser(OWNER);
    const res = await callJson("POST", "/polls", {
      headers: await bearer(OWNER),
      body: { title: "  好きな曲  ", description: "説明", target_type: "idol", days: 99,
              candidate_scope: "manual", scope_entity_ids: ["b", "a"] },
    });
    expect(res.status).toBe(201);
    expect(Object.keys(res.body).sort()).toEqual(POLL_KEYS);
    expect(res.body).toMatchObject({
      title: "好きな曲", description: "説明", target_type: "idol", created_by: OWNER, is_own_poll: true, status: "active",
      candidate_scope: "manual", scope_brand_ids: null, scope_entity_ids: ["b", "a"],
      total_votes: 0, entry_count: 0,
    });
    expect(res.body.ends_at - res.body.created_at).toBeGreaterThanOrEqual(30 * 86400 - 5);
    expect(res.body.ends_at - res.body.created_at).toBeLessThanOrEqual(30 * 86400 + 5);
  });

  it("brand スコープは D1 の brands に在る id だけ受け付ける (重複は畳む)", async () => {
    await insertUser(OWNER);
    await exec("INSERT INTO brands (id, name, short_name, sort_order) VALUES ('765', '765', '765', 1)");
    const res = await callJson("POST", "/polls", {
      headers: await bearer(OWNER),
      body: { title: "ok", target_type: "song", candidate_scope: "brand", scope_brand_ids: ["765", "765"] },
    });
    expect(res.status).toBe(201);
    expect(res.body.scope_brand_ids).toEqual(["765"]);
  });

  it("1 日 5 件まで。6 件目は 429 と使用量", async () => {
    await insertUser(OWNER);
    for (let i = 0; i < 5; i++) {
      const res = await callJson("POST", "/polls", {
        headers: await bearer(OWNER), body: { title: `p${i}`, target_type: "song" },
      });
      expect(res.status).toBe(201);
    }
    const res = await callJson("POST", "/polls", {
      headers: await bearer(OWNER), body: { title: "p5", target_type: "song" },
    });
    expect(res.status).toBe(429);
    expect(res.body).toMatchObject({ error: "rate_limit_exceeded", limit: 5, used: 6 });
    expect(Number(res.res.headers.get("Retry-After"))).toBeGreaterThan(0);
  });
});

describe("GET /polls と GET /polls/:id", () => {
  it("一覧: 開催中は締切の近い順、past は終了したもの。自分の票数と 1 位を載せる", async () => {
    await insertPoll("later", { endsIn: "+3 days" });
    await insertPoll("sooner", { endsIn: "+1 day" });
    await insertPoll("ended", { endsIn: "-1 day" });
    await insertPoll("removed", { status: "removed" });
    await insertUser(VOTER);
    await insertUser("001094.other");
    await vote("sooner", "s1");
    await vote("sooner", "s2");
    await vote("sooner", "s2", "001094.other");

    const res = await callJson("GET", "/polls", { headers: await bearer(VOTER) });
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBeNull();
    expect(res.body.map((p: any) => p.id)).toEqual(["sooner", "later"]);
    expect(Object.keys(res.body[0]).sort()).toEqual(
      [...POLL_KEYS, "my_vote_count", "top_entity_id"].sort()
    );
    expect(res.body[0]).toMatchObject({ total_votes: 3, entry_count: 2, my_vote_count: 2, top_entity_id: "s2" });
    expect(res.body[1]).toMatchObject({ total_votes: 0, entry_count: 0, my_vote_count: 0, top_entity_id: null });

    const past = await callJson("GET", "/polls?status=past");
    expect(past.body.map((p: any) => p.id)).toEqual(["ended"]);
  });

  it("is_own_poll: 呼び出した人が作ったお題だけ true。未ログインはすべて false", async () => {
    await insertPoll("mine", { createdBy: VOTER });
    await insertPoll("theirs");
    const mine = await callJson("GET", "/polls", { headers: await bearer(VOTER) });
    expect(Object.fromEntries(mine.body.map((p: any) => [p.id, p.is_own_poll]))).toEqual({ mine: true, theirs: false });
    const anon = await callJson("GET", "/polls?anon=1");
    expect(anon.body.map((p: any) => p.is_own_poll)).toEqual([false, false]);

    expect((await callJson("GET", "/polls/mine", { headers: await bearer(VOTER) })).body.poll.is_own_poll).toBe(true);
    expect((await callJson("GET", "/polls/mine", { headers: await bearer(OWNER) })).body.poll.is_own_poll).toBe(false);
    expect((await callJson("GET", "/polls/mine")).body.poll.is_own_poll).toBe(false);
  });

  it("詳細: 候補を票数順で返し、自分が入れた候補に印を付ける。manual は 0 票の候補も並べる", async () => {
    await insertPoll("m", { scope: "manual", entities: ["s1", "s2", "s3"] });
    await insertUser(VOTER);
    await insertUser("001094.other");
    await vote("m", "s2");
    await vote("m", "s2", "001094.other");
    await vote("m", "s1", "001094.other");

    const res = await callJson("GET", "/polls/m", { headers: await bearer(VOTER) });
    expect(res.status).toBe(200);
    expect(Object.keys(res.body).sort()).toEqual(["entries", "my_vote_count", "poll"]);
    expect(Object.keys(res.body.poll).sort()).toEqual(POLL_KEYS);
    expect(res.body.poll).toMatchObject({ total_votes: 3, entry_count: 2, scope_entity_ids: ["s1", "s2", "s3"] });
    expect(res.body.entries).toEqual([
      { entity_id: "s2", vote_count: 2, has_user_voted: true },
      { entity_id: "s1", vote_count: 1, has_user_voted: false },
      { entity_id: "s3", vote_count: 0, has_user_voted: false },
    ]);
    expect(res.body.my_vote_count).toBe(1);

    expect((await callJson("GET", "/polls/none")).body).toEqual({ error: "Poll not found" });
  });
});

describe("POST /polls/:id/votes と DELETE /polls/:id/votes/:entityId", () => {
  it("未ログインは 401。無いお題は 404、終了・削除は 409、候補外は 422", async () => {
    await insertUser(VOTER);
    expect((await callJson("POST", "/polls/p/votes", { body: { entity_id: "s1" } })).status).toBe(401);
    expect((await vote("none", "s1")).body).toEqual({ error: "Poll not found" });

    await insertPoll("removed", { status: "removed" });
    const removed = await vote("removed", "s1");
    expect(removed.status).toBe(409);
    expect(removed.body).toEqual({ error: "Poll is not active" });

    await insertPoll("ended", { endsIn: "-1 minute" });
    const ended = await vote("ended", "s1");
    expect(ended.status).toBe(409);
    expect(ended.body).toEqual({ error: "Poll has ended" });

    await insertPoll("m", { scope: "manual", entities: ["s1", "s2"] });
    const outside = await vote("m", "s9");
    expect(outside.status).toBe(422);
    expect(outside.body).toEqual({ error: "entity_id is not in poll candidates" });
  });

  it("entity_id を検証する", async () => {
    await insertUser(VOTER);
    await insertPoll("p");
    const res = await callJson("POST", "/polls/p/votes", { headers: await bearer(VOTER), body: {} });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "entity_id is required" });
  });

  it("投票は 201 で票数と自分の票数。同じ候補への再投票は 200 で数を変えない。1 人 3 票まで", async () => {
    await insertUser(VOTER);
    await insertUser("001094.other");
    await insertPoll("p");
    const first = await vote("p", "s1");
    expect(first.status).toBe(201);
    expect(first.body).toEqual({ entity_id: "s1", vote_count: 1, my_vote_count: 1 });

    const again = await vote("p", "s1");
    expect(again.status).toBe(200);
    expect(again.body).toEqual({ entity_id: "s1", vote_count: 1, my_vote_count: 1 });

    expect((await vote("p", "s1", "001094.other")).body).toEqual({ entity_id: "s1", vote_count: 2, my_vote_count: 1 });
    expect((await vote("p", "s2")).status).toBe(201);
    expect((await vote("p", "s3")).body).toEqual({ entity_id: "s3", vote_count: 1, my_vote_count: 3 });

    const fourth = await vote("p", "s4");
    expect(fourth.status).toBe(409);
    expect(fourth.body).toEqual({ error: "vote limit" });
    expect(await row("SELECT first_voted_by FROM poll_entries WHERE poll_id = 'p' AND entity_id = 's1'"))
      .toEqual({ first_voted_by: VOTER });
  });

  it("取り消しは票数と自分の票数を返し、0 票の候補は消える。入れていなければそのままの数を返す", async () => {
    await insertUser(VOTER);
    await insertUser("001094.other");
    await insertPoll("p");
    await vote("p", "s1");
    await vote("p", "s1", "001094.other");
    await vote("p", "s2");

    const auth = await bearer(VOTER);
    expect((await callJson("DELETE", "/polls/p/votes/s9", { headers: auth })).body)
      .toEqual({ entity_id: "s9", vote_count: 0, my_vote_count: 2 });

    const res = await callJson("DELETE", "/polls/p/votes/s1", { headers: auth });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ entity_id: "s1", vote_count: 1, my_vote_count: 1 });

    expect((await callJson("DELETE", "/polls/p/votes/s2", { headers: auth })).body)
      .toEqual({ entity_id: "s2", vote_count: 0, my_vote_count: 0 });
    expect(await rows("SELECT entity_id FROM poll_entries WHERE poll_id = 'p'")).toEqual([{ entity_id: "s1" }]);

    expect((await callJson("DELETE", "/polls/p/votes/s1")).status).toBe(401);
  });
});

describe("DELETE /polls/:id", () => {
  it("作成者か admin だけが removed にできる", async () => {
    await insertPoll("p");
    expect((await callJson("DELETE", "/polls/p")).status).toBe(401);
    expect((await callJson("DELETE", "/polls/none", { headers: await bearer(OWNER) })).status).toBe(404);

    const other = await callJson("DELETE", "/polls/p", { headers: await bearer(VOTER) });
    expect(other.status).toBe(403);
    expect(other.body).toEqual({ error: "Forbidden" });

    const res = await callJson("DELETE", "/polls/p", { headers: await bearer(OWNER) });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ id: "p", status: "removed" });

    await insertPoll("q");
    const admin = await callJson("DELETE", "/polls/q", {
      headers: await bearer(ADMIN), env: makeEnv({ ADMIN_USER_IDS: ADMIN }),
    });
    expect(admin.body).toEqual({ id: "q", status: "removed" });
  });
});

describe("GET /polls/results と GET /polls/achievements/:entityId", () => {
  async function seedEnded() {
    await insertPoll("old", { endsIn: "-3 days" });
    await insertPoll("new", { endsIn: "-1 day" });
    await insertPoll("open", { endsIn: "+1 day" });
    await exec(
      `INSERT INTO poll_entries (poll_id, entity_id, vote_count) VALUES
         ('old', 's1', 5), ('old', 's2', 7),
         ('new', 's1', 4), ('new', 's3', 4), ('new', 's4', 1),
         ('open', 's1', 9)`
    );
  }

  it("results: 終了したお題の 1 位を新しい順に。同点は 1 件だけ。公開キャッシュ", async () => {
    await seedEnded();
    const res = await callJson("GET", "/polls/results");
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe("public, max-age=300");
    expect(res.body.map((r: any) => [r.poll_id, r.vote_count])).toEqual([["new", 4], ["old", 7]]);
    expect(Object.keys(res.body[0]).sort()).toEqual(
      ["ends_at", "entity_id", "poll_id", "target_type", "title", "vote_count"]
    );
    expect(res.body[1].entity_id).toBe("s2");
  });

  it("achievements: その候補が終了したお題で取った 3 位以内。公開キャッシュ", async () => {
    await seedEnded();
    const res = await callJson("GET", "/polls/achievements/s1");
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe("public, max-age=300");
    expect(res.body.map((r: any) => [r.poll_id, r.rnk])).toEqual([["new", 1], ["old", 2]]);
    expect(Object.keys(res.body[0]).sort()).toEqual(
      ["ends_at", "poll_id", "rnk", "target_type", "title", "vote_count"]
    );
  });
});
