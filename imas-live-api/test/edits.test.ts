// POST /edits (オープン編集) の特性テストと、失敗時の応答。CloudKit は fetchMock で返す。

import { env, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { insertUser, row, rows } from "./support/d1";

const UID = "001094.editor";
const CK_ORIGIN = "https://api.apple-cloudkit.com";
const CK_MODIFY = "/database/1/iCloud.com.fugaif.ImasLiveDB/production/public/records/modify";

let ckEnv: ReturnType<typeof makeEnv>;

/** CloudKit の S2S 署名に使う P-256 の鍵 (テスト専用に作る)。 */
async function testCloudKitKey(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----`;
}

beforeAll(async () => {
  ckEnv = makeEnv({ CLOUDKIT_KEY_ID: "test-key", CLOUDKIT_PRIVATE_KEY: await testCloudKitKey() });
});

afterEach(() => vi.restoreAllMocks());

function serveModify(status = 200, body: object = { records: [] }) {
  fetchMock.get(CK_ORIGIN).intercept({ path: CK_MODIFY, method: "POST" }).reply(status, body);
}

const VIDEO_OP = {
  op: "create",
  recordType: "SongVideo",
  fields: { songId: "s1", youtubeUrl: "https://youtu.be/abcdef" },
};

describe("POST /edits", () => {
  it("未ログインは 401。本文を検証する", async () => {
    expect((await callJson("POST", "/edits", { body: { ops: [VIDEO_OP] }, env: ckEnv })).status).toBe(401);
    await insertUser(UID);
    const auth = await bearer(UID);
    expect((await callJson("POST", "/edits", { headers: auth, body: "{", env: ckEnv })).body)
      .toEqual({ error: "invalid json body" });
    expect((await callJson("POST", "/edits", { headers: auth, body: { ops: [] }, env: ckEnv })).body)
      .toEqual({ error: "ops is required (non-empty array)" });
  });

  it("一般ユーザーのマスタ編集は 422、廃止したコーレスは 410", async () => {
    await insertUser(UID);
    const auth = await bearer(UID);
    const master = await callJson("POST", "/edits", {
      headers: auth, env: ckEnv,
      body: { ops: [{ op: "update", recordType: "Song", recordName: "s1", fields: { title: "x" } }] },
    });
    expect(master.status).toBe(422);
    const call = await callJson("POST", "/edits", {
      headers: auth, env: ckEnv, body: { ops: [{ op: "create", recordType: "SongCall", fields: {} }] },
    });
    expect(call.status).toBe(410);
  });

  it("参考動画の投稿は CloudKit に書き、編集 batch と履歴を記録する", async () => {
    await insertUser(UID);
    serveModify();
    const res = await callJson("POST", "/edits", { headers: await bearer(UID), env: ckEnv, body: { ops: [VIDEO_OP] } });
    expect(res.status).toBe(200);
    expect(Object.keys(res.body).sort()).toEqual(["batchId", "ok", "results"]);
    expect(res.body.ok).toBe(true);
    const [result] = res.body.results;
    expect(result).toMatchObject({ recordType: "SongVideo", op: "create", ok: true });
    expect(result.recordName).toMatch(/^ytref_/);
    expect(result.fields).toMatchObject({ songId: "s1", youtubeUrl: "https://youtu.be/abcdef" });
    expect(typeof result.fields.createdAt).toBe("number");
    expect(typeof result.fields.modifiedAt).toBe("number");

    expect(await row("SELECT editor_id, source, op, cloudkit_ok FROM edit_batch WHERE id = ?", res.body.batchId))
      .toEqual({ editor_id: UID, source: "app", op: "create", cloudkit_ok: 1 });
    expect(await rows("SELECT record_type, op FROM edit_history")).toEqual([{ record_type: "SongVideo", op: "create" }]);
    expect(await row("SELECT contribution_count FROM users WHERE id = ?", UID)).toEqual({ contribution_count: 1 });
  });

  it("CloudKit が失敗したら 502 で、履歴を書かない", async () => {
    await insertUser(UID);
    serveModify(503, { reason: "unavailable" });
    const res = await callJson("POST", "/edits", { headers: await bearer(UID), env: ckEnv, body: { ops: [VIDEO_OP] } });
    expect(res.status).toBe(502);
    expect(await rows("SELECT cloudkit_ok FROM edit_batch")).toEqual([{ cloudkit_ok: 0 }]);
    expect(await rows("SELECT * FROM edit_history")).toEqual([]);
  });

  it("編集 batch を作れなかったら 500。D1 のエラー文は応答に出さず、request id と一緒にログに残す", async () => {
    await insertUser(UID);
    const failing = {
      ...env.DB,
      prepare: (sql: string) => {
        const stmt = env.DB.prepare(sql);
        if (!sql.includes("INSERT INTO edit_batch")) return stmt;
        const boom = () => Promise.reject(new Error("D1_ERROR: no such table: edit_batch_secret_detail"));
        return { bind: () => ({ first: boom, run: boom, all: boom }) } as unknown as D1PreparedStatement;
      },
      batch: env.DB.batch.bind(env.DB),
    } as unknown as D1Database;
    const logged: unknown[][] = [];
    vi.spyOn(console, "error").mockImplementation((...args: unknown[]) => void logged.push(args));

    const res = await callJson("POST", "/edits", {
      headers: await bearer(UID), env: { ...ckEnv, DB: failing }, body: { ops: [VIDEO_OP] },
    });
    expect(res.status).toBe(500);
    const requestId = res.res.headers.get("X-Request-Id");
    expect(requestId).toBeTruthy();
    expect(res.body.error).not.toContain("edit_batch_secret_detail");
    expect(res.body.error).toContain(requestId);
    expect(JSON.stringify(logged)).toContain("edit_batch_secret_detail");
    expect(JSON.stringify(logged)).toContain(requestId);
  });
});
