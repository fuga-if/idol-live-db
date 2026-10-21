// 引き継ぎコード (routes/transfer.ts)。
//   POST /transfer        ペイロードを預けてワンタイムコードを発行する
//   GET  /transfer/:code  コードで取り出し、同時にサーバーから消す

import { afterEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row } from "./support/d1";

const UID = "001094.transfer";
const OTHER = "001094.newphone";
const ALPHABET = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}$/;

afterEach(() => vi.restoreAllMocks());

async function create(body: unknown, uid = UID) {
  return callJson("POST", "/transfer", { headers: await bearer(uid), body });
}

async function fetchCode(code: string, uid = OTHER) {
  return callJson("GET", `/transfer/${code}`, { headers: await bearer(uid) });
}

describe("POST /transfer → GET /transfer/:code", () => {
  it("紛らわしい文字を除いた 10 文字のコードを発行し、別の端末で 1 回だけ取り出せる", async () => {
    await insertUser(UID);
    await insertUser(OTHER);
    const created = await create({ payload: '{"favorites":["s1"]}' });
    expect(created.status).toBe(201);
    expect(created.body.code).toMatch(ALPHABET);
    const expiresIn = Date.parse(created.body.expiresAt) - Date.now();
    expect(expiresIn).toBeGreaterThan(23.9 * 3600_000);
    expect(expiresIn).toBeLessThanOrEqual(24 * 3600_000);

    // 小文字・前後の空白で打ち込んでも通る
    const fetched = await fetchCode(`%20${created.body.code.toLowerCase()}%20`);
    expect(fetched.status).toBe(200);
    expect(fetched.body).toEqual({ payload: '{"favorites":["s1"]}', createdAt: expect.any(String) });

    // ワンタイム: 2 回目は無い
    expect((await fetchCode(created.body.code)).status).toBe(404);
  });

  it("期限切れのコードは 404 (取り出しと同時に消える)", async () => {
    await insertUser(OTHER);
    await exec(
      "INSERT INTO transfer_codes (code, user_id, payload, created_at, expires_at) VALUES ('EXPIRED234', ?, 'x', ?, ?)",
      UID, "2026-01-01T00:00:00.000Z", "2026-01-02T00:00:00.000Z"
    );
    const res = await fetchCode("EXPIRED234");
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "not_found_or_expired" });
    expect(await row("SELECT code FROM transfer_codes WHERE code = 'EXPIRED234'")).toBeNull();
  });

  it("payload は文字列で 200,000 文字まで", async () => {
    await insertUser(UID);
    expect((await create({ payload: { a: 1 } })).body).toEqual({ error: "payload must be a string" });
    expect((await create({ payload: "x".repeat(200_001) })).body).toEqual({ error: "payload_too_large" });
    expect((await create("{")).status).toBe(400);
    expect((await create({ payload: "x".repeat(200_000) })).status).toBe(201);
  });

  it("未ログインは 401", async () => {
    expect((await callJson("POST", "/transfer", { body: { payload: "x" } })).status).toBe(401);
    expect((await callJson("GET", "/transfer/ABCDEFGHJK")).status).toBe(401);
  });

  it("発行は 1 日 5 回まで", async () => {
    await insertUser(UID);
    for (let i = 0; i < 5; i++) expect((await create({ payload: String(i) })).status).toBe(201);
    expect((await create({ payload: "6" })).status).toBe(429);
  });

  it("コードが既存と衝突したら作り直す。5 回続けて衝突したら 500", async () => {
    await insertUser(UID);
    // 乱数を全部 0 にすると、コードは先頭の文字 ('A') の 10 連になる
    await exec(
      "INSERT INTO transfer_codes (code, user_id, payload, created_at, expires_at) VALUES ('AAAAAAAAAA', ?, 'x', '', '')",
      UID
    );
    const zeros = <T extends ArrayBufferView | null>(arr: T): T => {
      if (arr) new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength).fill(0);
      return arr;
    };
    const spy = vi.spyOn(crypto, "getRandomValues").mockImplementationOnce(zeros);
    const retried = await create({ payload: "retry" });
    expect(retried.status).toBe(201);
    expect(retried.body.code).not.toBe("AAAAAAAAAA");

    spy.mockImplementation(zeros);
    const failed = await create({ payload: "give up" });
    expect(failed.status).toBe(500);
    expect(failed.body).toEqual({ error: "failed to generate a unique transfer code" });
  });
});
