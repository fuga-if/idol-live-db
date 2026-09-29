// Discord のロール受け取り (routes/discord.ts) と、#更新通知 のまとめ投稿 (discord_digest.ts)。
// Discord / GitHub への通信は fetchMock で返す。

import { fetchMock } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { bearer, BASE, call, callJson, fetchWorker, makeEnv, runScheduled } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";
import { createLiveThreads, jstToday } from "../src/discord_live_threads";
import { classifyCommit, postAppRelease, postDevWeekly } from "../src/discord_releases";

const UID = "001094.discorder";
const DISCORD = "https://discord.com";
const GITHUB = "https://github.com";
const GITHUB_API = "https://api.github.com";
const GUILD = "1530435001231868076";
const DATA_ROLE = "1552703794733645986";
const CONTRIBUTOR_ROLE = "1552703793081090259";
const CHANNEL = "1552704747939565681";
const DISCORD_USER = "900000000000000001";

const configured = () =>
  makeEnv({
    DISCORD_BOT_TOKEN: "bot-token",
    DISCORD_CLIENT_SECRET: "client-secret",
    GITHUB_OAUTH_CLIENT_ID: "gh-client",
    GITHUB_OAUTH_CLIENT_SECRET: "gh-secret",
  });

/** CloudKit の S2S 署名に使う P-256 の鍵 (テスト専用に作る)。 */
async function testCloudKitKey(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----`;
}

afterEach(() => {
  fetchMock.assertNoPendingInterceptors();
});

async function seedEdits(uid: string, n: number) {
  for (let i = 0; i < n; i++) {
    await exec(
      "INSERT INTO edit_batch (editor_id, source, op, summary, cloudkit_ok, created_at) VALUES (?, 'app', 'update', ?, 1, ?)",
      uid, "SetlistItem.create x3, Song.update x1 — クライアントの文字列", Date.now()
    );
  }
}

async function startLink(): Promise<string> {
  const res = await callJson("POST", "/discord/link", { headers: await bearer(UID), body: {}, env: configured() });
  expect(res.status).toBe(200);
  const url = new URL(res.body.url);
  expect(url.origin + url.pathname).toBe("https://discord.com/oauth2/authorize");
  expect(url.searchParams.get("redirect_uri")).toBe(`${BASE}/discord/callback`);
  expect(url.searchParams.get("scope")).toBe("identify guilds.join");
  return url.searchParams.get("state")!;
}

function serveDiscordLogin(memberStatus = 201) {
  fetchMock.get(DISCORD).intercept({ path: "/api/v10/oauth2/token", method: "POST" })
    .reply(200, { access_token: "user-access" });
  fetchMock.get(DISCORD).intercept({ path: "/api/v10/users/@me", method: "GET" })
    .reply(200, { id: DISCORD_USER });
  fetchMock.get(DISCORD).intercept({ path: `/api/v10/guilds/${GUILD}/members/${DISCORD_USER}`, method: "PUT" })
    .reply(memberStatus, "");
}

describe("POST /discord/link", () => {
  it("未ログインは 401、設定が無ければ 503", async () => {
    expect((await callJson("POST", "/discord/link", { body: {}, env: configured() })).status).toBe(401);
    await insertUser(UID);
    const res = await callJson("POST", "/discord/link", { headers: await bearer(UID), body: {} });
    expect(res.status).toBe(503);
    expect(res.body).toEqual({ error: "discord_not_configured" });
  });
});

describe("GET /discord/callback", () => {
  it("知らない state は期限切れのページ", async () => {
    const res = await call("GET", "/discord/callback?code=c&state=nope", { env: configured() });
    expect(res.status).toBe(400);
    expect(await res.text()).toContain("リンクの期限が切れました");
  });

  it("編集 10 件以上ならサーバーに参加させて「データ協力」を付ける。state は 1 回で消える", async () => {
    await insertUser(UID);
    await seedEdits(UID, 10);
    const state = await startLink();
    serveDiscordLogin(201);
    fetchMock.get(DISCORD)
      .intercept({ path: `/api/v10/guilds/${GUILD}/members/${DISCORD_USER}/roles/${DATA_ROLE}`, method: "PUT" })
      .reply(204, "");

    const res = await call("GET", `/discord/callback?code=c&state=${state}`, { env: configured() });
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toContain("text/html");
    expect(await res.text()).toContain("「データ協力」ロールを付けました");
    expect(await row("SELECT discord_user_id FROM discord_links WHERE user_id = ?", UID)).toEqual({
      discord_user_id: DISCORD_USER,
    });

    const again = await call("GET", `/discord/callback?code=c&state=${state}`, { env: configured() });
    expect(again.status).toBe(400);
  });

  it("差し戻された編集は数えない", async () => {
    await insertUser(UID);
    await seedEdits(UID, 10);
    await exec("UPDATE edit_batch SET reverted_at = ? WHERE id = (SELECT MIN(id) FROM edit_batch)", Date.now());
    const state = await startLink();
    serveDiscordLogin(204);
    const res = await call("GET", `/discord/callback?code=c&state=${state}`, { env: configured() });
    expect(await res.text()).toContain("あと 1 件編集すると");
  });

  it("認可画面でキャンセルしたら code が無い", async () => {
    await insertUser(UID);
    const state = await startLink();
    const res = await call("GET", `/discord/callback?error=access_denied&state=${state}`, { env: configured() });
    expect(await res.text()).toContain("キャンセルしました");
  });
});

// ---------------------------------------------------------------------------
// Interactions
// ---------------------------------------------------------------------------

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function signer() {
  const keys = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const publicKey = toHex((await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer);
  async function send(payload: unknown, opts: { tamper?: boolean } = {}) {
    const body = JSON.stringify(payload);
    const timestamp = String(Math.floor(Date.now() / 1000));
    const sig = await crypto.subtle.sign("Ed25519", keys.privateKey, new TextEncoder().encode(timestamp + body));
    const req = new Request(`${BASE}/discord/interactions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Signature-Ed25519": toHex(sig),
        "X-Signature-Timestamp": timestamp,
      },
      body: opts.tamper ? body.replace("}", ',"x":1}') : body,
    });
    const res = await fetchWorker(req, makeEnv({ ...configured(), DISCORD_PUBLIC_KEY: publicKey }));
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  }
  return { send };
}

const command = (role: string) => ({
  type: 2,
  data: { name: "申請", options: [{ name: "ロール", value: role }] },
  member: { user: { id: DISCORD_USER } },
});

describe("POST /discord/interactions", () => {
  it("署名が合わなければ 401、PING には PONG", async () => {
    const { send } = await signer();
    expect((await send({ type: 1 }, { tamper: true })).status).toBe(401);
    expect(await send({ type: 1 })).toEqual({ status: 200, body: { type: 1 } });
  });

  it("/申請 データ協力 はアプリへの案内を本人にだけ返す", async () => {
    const { send } = await signer();
    const res = await send(command("data"));
    expect(res.body.type).toBe(4);
    expect(res.body.data.flags).toBe(64);
    expect(res.body.data.content).toContain("マイページ");
  });

  it("/申請 コントリビューター は GitHub の認可リンクを返し、Discord のユーザーを state に積む", async () => {
    const { send } = await signer();
    const res = await send(command("contributor"));
    const link = new URL(res.body.data.components[0].components[0].url);
    expect(link.origin + link.pathname).toBe("https://github.com/login/oauth/authorize");
    expect(link.searchParams.get("redirect_uri")).toBe(`${BASE}/github/callback`);
    expect(await row("SELECT kind, discord_user_id FROM discord_oauth_states WHERE state = ?", link.searchParams.get("state"))).toEqual({
      kind: "github",
      discord_user_id: DISCORD_USER,
    });
  });
});

describe("GET /github/callback", () => {
  async function githubState(): Promise<string> {
    const { send } = await signer();
    const res = await send(command("contributor"));
    return new URL(res.body.data.components[0].components[0].url).searchParams.get("state")!;
  }

  function serveGithub(merged: number) {
    fetchMock.get(GITHUB).intercept({ path: "/login/oauth/access_token", method: "POST" })
      .reply(200, { access_token: "gh-access" });
    fetchMock.get(GITHUB_API).intercept({ path: "/user", method: "GET" }).reply(200, { login: "someone" });
    fetchMock.get(GITHUB_API).intercept({ path: (p) => p.startsWith("/search/issues"), method: "GET" })
      .reply(200, { total_count: merged });
  }

  it("マージ済みの PR があれば「コントリビューター」を付ける", async () => {
    const state = await githubState();
    serveGithub(2);
    fetchMock.get(DISCORD)
      .intercept({ path: `/api/v10/guilds/${GUILD}/members/${DISCORD_USER}/roles/${CONTRIBUTOR_ROLE}`, method: "PUT" })
      .reply(204, "");
    const res = await call("GET", `/github/callback?code=c&state=${state}`, { env: configured() });
    expect(await res.text()).toContain("「コントリビューター」ロールを付けました");
  });

  it("マージ済みの PR が無ければ付けない", async () => {
    const state = await githubState();
    serveGithub(0);
    const res = await call("GET", `/github/callback?code=c&state=${state}`, { env: configured() });
    expect(await res.text()).toContain("マージされた PR が見つかりませんでした");
  });

  it("Discord の state では通らない (種類違い)", async () => {
    await insertUser(UID);
    const state = await startLink();
    const res = await call("GET", `/github/callback?code=c&state=${state}`, { env: configured() });
    expect(res.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// #更新通知
// ---------------------------------------------------------------------------

describe("#更新通知 のまとめ投稿 (5 分 cron)", () => {
  const cron = "*/5 * * * *";
  const digestEnv = () =>
    makeEnv({ DISCORD_BOT_TOKEN: "bot-token", CLOUDKIT_KEY_ID: "", CLOUDKIT_PRIVATE_KEY: "" });

  it("初回は位置を覚えるだけで、過去の分は流さない。増えた分だけ 1 通にまとめ、編集者と利用者の文字列を出さない", async () => {
    await insertUser(UID);
    await seedEdits(UID, 1);
    await runScheduled(cron, digestEnv()); // 投稿なし (interceptor を置いていないので、投げれば落ちる)

    await seedEdits(UID, 2);
    await exec("INSERT INTO call_edit_history (song_id, user_id, call_lines_before, call_lines_after, call_count_before, call_count_after) VALUES ('s1', ?, 0, 3, 0, 5)", UID);
    await exec("INSERT INTO tags (id, name, created_by, created_at, updated_at, status) VALUES ('t1', '蒼い', 'd', 1, 1, 'active')");
    await exec("INSERT INTO device_song_tag (device_id, song_id, tag_id, created_at) VALUES ('d1', 's1', 't1', 0)");
    await exec("INSERT INTO polls (id, title, target_type, created_by, ends_at) VALUES ('p1', '@everyone 推し曲は？', 'song', ?, datetime('now', '+1 day'))", UID);

    let posted: any = null;
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${CHANNEL}/messages`, method: "POST" })
      .reply(200, (opts) => {
        posted = JSON.parse(String(opts.body));
        return {};
      });
    await runScheduled(cron, digestEnv());

    expect(posted.allowed_mentions).toEqual({ parse: [] });
    const text: string = posted.content;
    expect(text).toContain("データの編集** 2件（セトリ ×6、曲 ×2）");
    expect(text).toContain("コールガイド** [s1](<https://idollivedb.fugaapp.site/songs/s1/>)");
    expect(text).toContain("曲にタグ** 1曲");
    expect(posted.embeds).toEqual([
      { title: "s1", url: "https://idollivedb.fugaapp.site/songs/s1/", description: "#蒼い", color: 0xe85a9b },
    ]);
    expect(text).toContain("新しいお題** 「\\@everyone 推し曲は？」");
    expect(text).not.toContain("クライアントの文字列");
    expect(text).not.toContain(UID);

    // 何も増えていなければ投稿しない。
    await runScheduled(cron, digestEnv());
  });

  it("タグ付けは対象の名前・付いたタグ名・ジャケ写つきで出す (公開中でないタグは出さない)", async () => {
    const env = makeEnv({ DISCORD_BOT_TOKEN: "bot-token", CLOUDKIT_KEY_ID: "test-key", CLOUDKIT_PRIVATE_KEY: await testCloudKitKey() });
    await runScheduled(cron, digestEnv()); // 位置を覚えるだけ
    await exec(
      `INSERT INTO tags (id, name, created_by, created_at, updated_at, status) VALUES
       ('t1', '蒼い', 'd', 1, 1, 'active'), ('t2', '*エモい*', 'd', 1, 1, 'active'), ('t3', '消えた', 'd', 1, 1, 'removed')`
    );
    await exec("INSERT INTO idol_tag_master (id, name, created_by, created_at, updated_at, status) VALUES ('it1', '歌姫', 'd', 1, 1, 'active')");
    await exec(
      `INSERT INTO device_song_tag (device_id, song_id, tag_id, created_at) VALUES
       ('d1', 'song-a', 't1', 0), ('d2', 'song-a', 't1', 0), ('d1', 'song-a', 't2', 0), ('d1', 'song-b', 't3', 0)`
    );
    await exec("INSERT INTO device_idol_tag (device_id, idol_id, tag_id, created_at) VALUES ('d1', 'idol-c', 'it1', 0)");

    fetchMock.get("https://api.apple-cloudkit.com")
      .intercept({ path: /\/records\/lookup$/, method: "POST" })
      .reply(200, {
        records: [
          { recordName: "song-a", recordType: "Song", fields: { title: { value: "Thank You!" }, artworkUrl: { value: "https://is1-ssl.mzstatic.com/a.jpg" } } },
          { recordName: "idol-c", recordType: "Idol", fields: { name: { value: "如月千早" } } },
        ],
      });
    let posted: any = null;
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${CHANNEL}/messages`, method: "POST" })
      .reply(200, (opts) => {
        posted = JSON.parse(String(opts.body));
        return {};
      });
    await runScheduled(cron, env);

    expect(posted.embeds).toEqual([
      {
        title: "Thank You!",
        url: "https://idollivedb.fugaapp.site/songs/song-a/",
        description: "#蒼い #\\*エモい\\*",
        color: 0xe85a9b,
        thumbnail: { url: "https://is1-ssl.mzstatic.com/a.jpg" },
      },
    ]);
    expect(posted.content).toContain("曲にタグ** 1曲");
    expect(posted.content).toContain("アイドルにタグ** [如月千早](<https://idollivedb.fugaapp.site/idols/idol-c/>) #歌姫");
    expect(posted.content).not.toContain("消えた");
  });

  it("編集は項目ごとの変更前→変更後と、セトリの追加・削除・曲順を出す", async () => {
    await insertUser(UID);
    await runScheduled(cron, digestEnv()); // 位置を覚えるだけ
    const addBatch = async (summary: string) => {
      await exec(
        "INSERT INTO edit_batch (editor_id, source, op, summary, cloudkit_ok, created_at) VALUES (?, 'app', 'update', ?, 1, ?)",
        UID, summary, Date.now()
      );
      return Number((await row<{ id: number }>("SELECT MAX(id) AS id FROM edit_batch"))!.id);
    };
    const hist = (batch: number, type: string, name: string, op: string, before: unknown, after: unknown) =>
      exec(
        "INSERT INTO edit_history (batch_id, record_type, record_name, op, before_json, after_json, modified_at, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, 0)",
        batch, type, name, op, before === null ? null : JSON.stringify(before), after === null ? null : JSON.stringify(after)
      );

    const b1 = await addBatch("Song.update x1");
    await hist(b1, "Song", "s1", "update",
      { title: "Thank You!", composer: "", lyricist: "A", modifiedAt: 1 },
      { title: "Thank You!", composer: "*作曲者*", lyricist: "A", modifiedAt: 2 });

    const b2 = await addBatch("SetlistItem.create x1, SetlistItem.delete x1");
    const item = (id: string, pos: number, song: string) => ({ recordName: id, fields: { position: pos, songId: song } });
    await hist(b2, "SetlistItem", "i9", "create", null, { songId: "s9" });
    await hist(b2, "ShowSetlist", "sh1", "snapshot",
      { items: [item("i1", 1, "s1"), item("i2", 2, "s2"), item("i3", 3, "s3")], performers: [] },
      { items: [item("i1", 1, "s1"), item("i3", 2, "s3"), item("i9", 3, "s9")], performers: [{ recordName: "p1", fields: { setlistItemId: "i9", idolId: "idol1" } }] });

    let posted: any = null;
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${CHANNEL}/messages`, method: "POST" })
      .reply(200, (opts) => {
        posted = JSON.parse(String(opts.body));
        return {};
      });
    await runScheduled(cron, digestEnv());

    expect(posted.embeds[0]).toEqual({
      title: "📝 曲「Thank You!」の編集",
      url: "https://idollivedb.fugaapp.site/songs/s1/",
      description: "・作曲：（なし） → \\*作曲者\\*",
      color: 0x4a8fe7,
    });
    expect(posted.embeds[1].title).toBe("📝 セトリ「sh1」の編集");
    expect(posted.embeds[1].url).toBe("https://idollivedb.fugaapp.site/shows/sh1/");
    expect(posted.embeds[1].description).toBe("・追加：♪s9\n・削除：♪s2\n・出演者：＋1 －0");
    expect(JSON.stringify(posted)).not.toContain(UID);
  });

  it("Bot トークンが無ければ何もしない", async () => {
    await runScheduled(cron, makeEnv());
    expect(await rows("SELECT * FROM discord_digest_cursors")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// #投票結果
// ---------------------------------------------------------------------------

describe("#投票結果 (5 分 cron)", () => {
  const cron = "*/5 * * * *";
  const RESULTS = "1541819917370654851";
  const pollEnv = () =>
    makeEnv({ DISCORD_BOT_TOKEN: "bot-token", CLOUDKIT_KEY_ID: "", CLOUDKIT_PRIVATE_KEY: "" });

  it("初回は位置を覚えるだけ。その後に締め切ったお題の上位 3 つを出して公開する。票が無いお題と締切前のお題は出さない", async () => {
    await insertUser(UID);
    await exec("INSERT INTO polls (id, title, target_type, created_by, ends_at) VALUES ('old', '前のお題', 'song', ?, datetime('now', '-1 day'))", UID);
    // #更新通知 への投稿は digest 側が位置を覚えるだけなので、ここでは interceptor 不要。
    await runScheduled(cron, pollEnv());

    // 位置を過去に戻して、「その後に締め切った」お題を作る。
    await exec("UPDATE discord_digest_cursors SET last_rowid = CAST(strftime('%s', 'now', '-1 hour') AS INTEGER) WHERE source = 'poll_results'");
    await exec(
      `INSERT INTO polls (id, title, target_type, created_by, ends_at) VALUES
       ('p1', '夏に聴きたい曲', 'song', ?, datetime('now', '-10 minutes')),
       ('p2', '票なし', 'song', ?, datetime('now', '-5 minutes')),
       ('p3', 'まだ締切前', 'idol', ?, datetime('now', '+1 day'))`,
      UID, UID, UID
    );
    await exec(
      `INSERT INTO poll_entries (poll_id, entity_id, vote_count, first_voted_at) VALUES
       ('p1', 's1', 5, '2026-01-01'), ('p1', 's2', 3, '2026-01-01'), ('p1', 's3', 3, '2026-01-02'), ('p1', 's4', 1, '2026-01-01')`
    );
    // p2 (票なし) と p3 (締切前) のイベントは digest の「新しいお題」に出るので、それも受ける。
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${CHANNEL}/messages`, method: "POST" }).reply(200, {});

    let posted: any = null;
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${RESULTS}/messages`, method: "POST" })
      .reply(200, (opts) => {
        posted = JSON.parse(String(opts.body));
        return { id: "m1" };
      });
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${RESULTS}/messages/m1/crosspost`, method: "POST" }).reply(200, {});
    await runScheduled(cron, pollEnv());

    expect(posted.allowed_mentions).toEqual({ parse: [] });
    expect(posted.embeds).toHaveLength(1);
    expect(posted.embeds[0].title).toBe("🗳️ 「夏に聴きたい曲」の結果");
    expect(posted.embeds[0].description).toBe(
      "🥇 [s1](<https://idollivedb.fugaapp.site/songs/s1/>)　5票\n" +
        "🥈 [s2](<https://idollivedb.fugaapp.site/songs/s2/>)　3票\n" +
        "🥉 [s3](<https://idollivedb.fugaapp.site/songs/s3/>)　3票\n\n合計 12票"
    );

    // 出し終わったので、次の回は何も出さない。
    await runScheduled(cron, pollEnv());
  });
});


// ---------------------------------------------------------------------------
// #ライブ実況・感想
// ---------------------------------------------------------------------------

describe("#ライブ実況・感想 のスレッド (日次 cron)", () => {
  const LIVE = "1552704776884719676";

  it("JST の日付は UTC 15 時で変わる", () => {
    expect(jstToday(Date.parse("2026-09-24T14:59:00Z"))).toBe("2026-09-24");
    expect(jstToday(Date.parse("2026-09-24T15:17:00Z"))).toBe("2026-09-25");
  });

  it("今日の公演ごとに開演順でスレッドを立て、同じ日は 2 回立てない", async () => {
    const env = makeEnv({ DISCORD_BOT_TOKEN: "bot-token", CLOUDKIT_KEY_ID: "test-key", CLOUDKIT_PRIVATE_KEY: await testCloudKitKey() });
    const now = Date.parse("2026-09-24T15:17:00Z");
    let queried: any = null;
    fetchMock.get("https://api.apple-cloudkit.com")
      .intercept({ path: /\/records\/query$/, method: "POST" })
      .reply(200, (opts) => {
        queried = JSON.parse(String(opts.body));
        return {
          records: [
            { recordName: "sh_night", recordType: "Show", fields: { name: { value: "M@STERS DAY2 夜公演" }, startTime: { value: "18:00" }, venue: { value: "東京ドーム" } } },
            { recordName: "sh_day", recordType: "Show", fields: { name: { value: "M@STERS DAY2 昼公演" }, startTime: { value: "13:00" } } },
          ],
        };
      });
    const threads: any[] = [];
    const messages: any[] = [];
    for (const id of ["th1", "th2"]) {
      fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${LIVE}/threads`, method: "POST" })
        .reply(200, (opts) => {
          threads.push(JSON.parse(String(opts.body)));
          return { id };
        });
      fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${id}/messages`, method: "POST" })
        .reply(200, (opts) => {
          messages.push(JSON.parse(String(opts.body)));
          return {};
        });
    }
    await createLiveThreads(env, now);

    expect(queried.query.filterBy[0].fieldValue.value).toBe("2026-09-25");
    expect(threads.map((t) => t.name)).toEqual(["9/25 M@STERS DAY2 昼公演", "9/25 M@STERS DAY2 夜公演"]);
    expect(messages[1].content).toContain("開演 18:00　東京ドーム");
    expect(messages[1].content).toContain("<https://idollivedb.fugaapp.site/shows/sh_night/>");
    expect(messages[0].allowed_mentions).toEqual({ parse: [] });

    // 同じ日にもう一度呼んでも何もしない (interceptor が無いので、呼べば落ちる)。
    await createLiveThreads(env, now);
  });
});

// ---------------------------------------------------------------------------
// #お知らせ (リリース) と #開発中 (毎週)
// ---------------------------------------------------------------------------

describe("リリースと開発中の変更", () => {
  const ANNOUNCE = "1530435001974526074";
  const DEV = "1552866674783559751";
  const env = () => makeEnv({ DISCORD_BOT_TOKEN: "bot-token" });
  const serveItunes = (version: string, date: string) =>
    fetchMock.get("https://itunes.apple.com")
      .intercept({ path: /^\/lookup/, method: "GET" })
      .reply(200, { results: [{ version, currentVersionReleaseDate: date, releaseNotes: "- 検索を速くしました", trackViewUrl: "https://apps.apple.com/jp/app/id6763342297" }] });

  it("初回は今のバージョンを覚えるだけ。新しいバージョンが出たら #お知らせ に投稿して公開する", async () => {
    serveItunes("2.2.0", "2026-09-04T06:42:12Z");
    await postAppRelease(env());
    serveItunes("2.2.0", "2026-09-04T06:42:12Z");
    await postAppRelease(env()); // 変わっていないので投稿しない

    serveItunes("2.3.0", "2026-09-30T01:00:00Z");
    let posted: any = null;
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${ANNOUNCE}/messages`, method: "POST" })
      .reply(200, (opts) => {
        posted = JSON.parse(String(opts.body));
        return { id: "r1" };
      });
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${ANNOUNCE}/messages/r1/crosspost`, method: "POST" }).reply(200, {});
    await postAppRelease(env());
    expect(posted.embeds[0].title).toBe("📱 iPhone 版 2.3.0 を公開しました");
    expect(posted.embeds[0].description).toBe("- 検索を速くしました");
  });

  it("コミットの 1 行目を場所ごとに分け、利用者に関係しないものは外す", () => {
    expect(classifyCommit("feat(ios): 曲詳細に補足を出す")).toEqual({ area: "📱 iPhone", text: "曲詳細に補足を出す" });
    expect(classifyCommit("fix(android): 落ちるのを直す")).toEqual({ area: "🤖 Android", text: "落ちるのを直す" });
    expect(classifyCommit("web: 紙面デザインの土台")).toEqual({ area: "🌐 Web", text: "紙面デザインの土台" });
    expect(classifyCommit("worker: 投票結果を出す")).toEqual({ area: "☁️ サーバー", text: "投票結果を出す" });
    expect(classifyCommit("feat: 歌詞クイズ")).toEqual({ area: "🧩 アプリ共通", text: "歌詞クイズ" });
    expect(classifyCommit("data: UNION!! の補足")).toBeNull();
    expect(classifyCommit("test(core): 足す")).toBeNull();
    expect(classifyCommit("Merge pull request #1")).toBeNull();
  });

  it("月曜だけ、直近 7 日の develop の変更を #開発中 にまとめる", async () => {
    const monday = Date.parse("2026-09-27T15:17:00Z"); // JST 9/28 (月)
    await postDevWeekly(env(), Date.parse("2026-09-26T15:17:00Z")); // JST 日曜: 何もしない

    fetchMock.get("https://api.github.com")
      .intercept({ path: /^\/repos\/fuga-if\/idol-live-db\/commits/, method: "GET" })
      .reply(200, [
        { commit: { message: "feat(ios): 曲詳細に補足を出す\n\n本文" } },
        { commit: { message: "data: 投入" } },
        { commit: { message: "web: 紙面デザインの土台" } },
      ]);
    let posted: any = null;
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${DEV}/messages`, method: "POST" })
      .reply(200, (opts) => {
        posted = JSON.parse(String(opts.body));
        return { id: "d1" };
      });
    fetchMock.get(DISCORD).intercept({ path: `/api/v10/channels/${DEV}/messages/d1/crosspost`, method: "POST" }).reply(200, {});
    await postDevWeekly(env(), monday);

    expect(posted.embeds[0].fields).toEqual([
      { name: "📱 iPhone（1件）", value: "・曲詳細に補足を出す" },
      { name: "🌐 Web（1件）", value: "・紙面デザインの土台" },
    ]);
    await postDevWeekly(env(), monday); // 同じ日は 2 回出さない
  });
});
