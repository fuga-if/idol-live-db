// test/support/worker.ts — Worker の fetch / scheduled を、migrations を当てたローカル D1 で呼ぶ。
//
// ルートハンドラを直接呼ぶのではなく index.ts の入口から通すので、ルーティング・
// App Attest のゲート・エッジキャッシュ・セキュリティヘッダまで本番と同じ経路を通る。
// 公開キャッシュ (Cache-Control: public) の応答は caches.default に載るため、同じテストの中で
// 同じ URL を 2 回 GET すると 2 回目はキャッシュから返る。読み直すときはクエリで URL を変える。

import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import worker from "../../src/index";
import { signSessionToken } from "../../src/auth";
import type { Env } from "../../src/env";

export const TEST_SECRET = "test-session-secret-that-is-long-enough";
export const TEST_IP = "203.0.113.10";
export const BASE = "https://api.example.com";

/** テスト用の Env。App Attest のゲートは既定で切る (ゲート自体のテストだけ上書きする)。 */
export function makeEnv(overrides: Partial<Env> = {}): Env {
  return { ...env, SESSION_JWT_SECRET: TEST_SECRET, APP_ATTEST_MODE: "off", ...overrides };
}

type Body = unknown;

export interface RequestOptions {
  headers?: Record<string, string>;
  /** JSON にして送る。文字列はそのまま送る (不正な JSON を試すため)。 */
  body?: Body;
}

export function request(method: string, path: string, opts: RequestOptions = {}): Request {
  const headers: Record<string, string> = { "CF-Connecting-IP": TEST_IP, ...opts.headers };
  let body: string | undefined;
  if (opts.body !== undefined) {
    body = typeof opts.body === "string" ? opts.body : JSON.stringify(opts.body);
    headers["Content-Type"] ??= "application/json";
  }
  return new Request(`${BASE}${path}`, { method, headers, body });
}

/** Worker の fetch を呼び、waitUntil に積まれた副作用 (キャッシュ書き込み等) まで待つ。 */
export async function fetchWorker(req: Request, e: Env = makeEnv()): Promise<Response> {
  const ctx = createExecutionContext();
  const res = await worker.fetch(req, e, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

export async function call(
  method: string,
  path: string,
  opts: RequestOptions & { env?: Env } = {}
): Promise<Response> {
  return fetchWorker(request(method, path, opts), opts.env ?? makeEnv());
}

export async function callJson<T = any>(
  method: string,
  path: string,
  opts: RequestOptions & { env?: Env } = {}
): Promise<{ status: number; body: T; res: Response }> {
  const res = await call(method, path, opts);
  const text = await res.text();
  return { status: res.status, body: text ? (JSON.parse(text) as T) : (null as T), res };
}

/** scheduled ハンドラを cron 式つきで呼ぶ。 */
export async function runScheduled(cron: string, e: Env = makeEnv()): Promise<void> {
  const ctx = createExecutionContext();
  await worker.scheduled({ cron, scheduledTime: Date.now(), noRetry() {} } as ScheduledEvent, e, ctx);
  await waitOnExecutionContext(ctx);
}

/** 自前セッション JWT の Authorization ヘッダ。 */
export async function bearer(uid: string): Promise<Record<string, string>> {
  return { Authorization: `Bearer ${await signSessionToken(uid, TEST_SECRET)}` };
}

/** 端末 ID ヘッダ (タグ・お気に入り・ペンライトの主体)。 */
export function device(id: string): Record<string, string> {
  return { "X-Device-Id": id };
}
