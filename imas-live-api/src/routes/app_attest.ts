// routes/app_attest.ts — アプリ証明 (App Attest) の口と、コミュニティ集計の読み取りのゲート。
//
// 正規アプリだけが集計を読めるようにする (クローンのただ乗り対策)。検証そのものは appattest.ts。
//   GET  /app/challenge — チャレンジの発行 (D1 を使わない)
//   POST /app/attest    — 鍵の登録 → アプリ実体トークン
//   POST /app/assert    — アサーションの検証 → アプリ実体トークン
// ゲート (gateCommunityRead) は、集計の読み取りにアプリ実体トークンかログインを求める。
// APP_ATTEST_MODE が monitor の間はログだけで通し、enforce で 401 にする。

import { getAuthUser } from "../auth";
import {
  verifyAttestation, verifyAssertion,
  mintAppToken, verifyAppToken, makeChallenge, checkChallenge,
} from "../appattest";
import { base64ToBytes, bytesToBase64Url } from "../bytes";
import { checkRateLimit } from "../rate_limit";
import type { RouteContext } from "./context";
import { isNonEmptyString } from "../validation";
import { clientIp, readJsonBody } from "./guards";

/** アプリ証明 (App Attest) の口。IP 単位の日次上限 (app_attest) を掛ける。 */
const APP_ATTEST_PATHS = new Set(["/app/challenge", "/app/attest", "/app/assert"]);

/** /app/challenge・/app/attest・/app/assert。どれでもなければ null。 */
export async function handleAppAttest(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error } = ctx;
  if (!APP_ATTEST_PATHS.has(path)) return null;
  const secret = env.SESSION_JWT_SECRET;

  // アプリ証明の口は IP 単位レート制限 (クォータ枯渇による自爆 DoS 防止)。
  // 同じ /app/ の下にある共有リンクの着地ページ (/app/{events,shows,polls}/:id) には掛けない。
  // 閲覧や OGP のクローラーで、同じ IP の端末のアプリ証明が 429 になるため。
  const rl = await checkRateLimit(env.DB, "ip:" + clientIp(request), "app_attest");
  if (!rl.allowed) return error("rate limited", 429);

  if (path === "/app/challenge" && request.method === "GET") {
    if (!secret) return error("server not configured", 500);
    return json({ challenge: bytesToBase64Url(await makeChallenge(secret)) });
  }
  if (path === "/app/attest" && request.method === "POST") {
    if (!secret) return error("server not configured", 500);
    const req = await readProof(ctx, "attestation");
    if (req instanceof Response) return req;
    const { keyId, proof, challenge } = req;
    if (!(await checkChallenge(challenge, secret))) return error("bad challenge", 400);
    try {
      const { spki, counter } = await verifyAttestation(challenge, base64ToBytes(keyId), proof, env.APP_ATTEST_ALLOW_DEV === "true");
      const now = Date.now();
      // OR IGNORE: 既存 keyId への再 attest (リプレイ) で counter を 0 に戻させない
      await env.DB.prepare(
        "INSERT OR IGNORE INTO app_attest_keys (key_id, public_key, counter, created_at, updated_at) VALUES (?,?,?,?,?)"
      ).bind(keyId, bytesToBase64Url(spki), counter, now, now).run();
      return json({ appToken: await mintAppToken(keyId, secret) });
    } catch (e) {
      return proofFailed(ctx, "attestation", e);
    }
  }
  if (path === "/app/assert" && request.method === "POST") {
    if (!secret) return error("server not configured", 500);
    const req = await readProof(ctx, "assertion");
    if (req instanceof Response) return req;
    const { keyId, proof, challenge } = req;
    if (!(await checkChallenge(challenge, secret))) return error("bad challenge", 400);
    const row = await env.DB.prepare("SELECT public_key, counter FROM app_attest_keys WHERE key_id=?")
      .bind(keyId)
      .first<{ public_key: string; counter: number }>();
    if (!row) return error("unknown key", 401);
    try {
      const newCounter = await verifyAssertion(challenge, proof, base64ToBytes(row.public_key), row.counter);
      await env.DB.prepare("UPDATE app_attest_keys SET counter=?, updated_at=? WHERE key_id=?").bind(newCounter, Date.now(), keyId).run();
      return json({ appToken: await mintAppToken(keyId, secret) });
    } catch (e) {
      return proofFailed(ctx, "assertion", e);
    }
  }
  return null;
}

/**
 * 証明の検証 (と、その後の鍵の保存) に失敗したときの 401 "<attestation|assertion> failed"。
 * 理由 (内部の例外メッセージ) は本文に載せず、request id と一緒にログにだけ出す
 * (どこで落ちたかの手がかりを外に渡さない)。
 */
function proofFailed(ctx: RouteContext, step: "attestation" | "assertion", e: unknown): Response {
  console.error(JSON.stringify({
    event: "app_attest_failed",
    requestId: ctx.requestId,
    step,
    error: e instanceof Error ? e.message : String(e),
  }));
  return ctx.error(`${step} failed`, 401);
}

/**
 * /app/attest・/app/assert の本文: keyId・challenge と、証明 (attestation / assertion) の文字列。
 * どれかが無い・文字列でなければ 400 "bad request"、challenge が base64 として読めなければ
 * 400 "bad challenge" (チャレンジの検証に通らないときと同じ応答)。
 */
async function readProof(
  ctx: RouteContext,
  field: "attestation" | "assertion"
): Promise<{ keyId: string; proof: string; challenge: Uint8Array } | Response> {
  const body = await readJsonBody(ctx, "bad request");
  if (body instanceof Response) return body;
  const { keyId, challenge } = body;
  const proof = body[field];
  if (!isNonEmptyString(keyId) || !isNonEmptyString(proof) || !isNonEmptyString(challenge)) {
    return ctx.error("bad request", 400);
  }
  try {
    return { keyId, proof, challenge: base64ToBytes(challenge) };
  } catch {
    return ctx.error("bad challenge", 400);
  }
}

/** ゲートの対象 = 認証不要で開いているコミュニティ集計の読み取り。 */
function isCommunityRead(path: string, method: string): boolean {
  if (method !== "GET") return false;
  // D1 固定無料枠に乗る集計 read を網羅する (CLAUDE.md 名指しの予想/いいね/ランキング含む)
  if (/^\/(polls|favorites|penlight|tags|master)(\/|$)/.test(path)) return true;
  if (/^\/songs\/[^/]+\/(tags|similar|detail)$/.test(path)) return true;
  if (/^\/idols\/[^/]+\/similar$/.test(path)) return true;
  if (/^\/units\/[^/]+\/similar$/.test(path)) return true;
  if (/^\/shows\/[^/]+\/(predictions|likes)$/.test(path)) return true;
  // コールガイドの整備状況。歌詞本文もコール本文も含まない件数・日時・表示名だけの
  // 集計なので、歌詞の枠 (認証必須・no-store) ではなくこちら側に置く。
  if (path === "/calls/dashboard") return true;
  return false;
}

/**
 * コミュニティ集計の読み取りを、正規アプリ (アプリ実体トークン) かログイン済みだけに開く。
 * 通すなら null、enforce で断るなら 401 を返す。
 */
export async function gateCommunityRead(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, error } = ctx;
  const attestMode = env.APP_ATTEST_MODE || "monitor";
  if (attestMode === "off" || !isCommunityRead(path, request.method)) return null;
  const secret = env.SESSION_JWT_SECRET;
  const appTok = request.headers.get("X-App-Token");
  const genuine =
    (!!appTok && !!secret && (await verifyAppToken(appTok, secret))) ||
    (await getAuthUser(request, env)) !== null;
  if (!genuine) {
    if (attestMode === "enforce") return error("app attestation required", 401);
    console.log(`[appattest:monitor] ungated community read ${path}`);
  }
  return null;
}
