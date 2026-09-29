// routes/transfer.ts — 引き継ぎコード。
//
//   POST /transfer        ユーザー生成ローカルデータ (お気に入り/担当/投票履歴等) を
//                          サーバーに一時保管し、ワンタイムコードを発行する
//   GET  /transfer/:code   コードでペイロードを取得し、取得と同時にサーバー側から削除する
//
// payload の中身 (JSON 妥当性含む) はクライアント側の責務。Worker はただの文字列ストレージ。

import { getAuthUser } from "../auth";
import { checkRateLimit } from "../rate_limit";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody, requireActiveUser } from "./guards";

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 紛らわしい 0/O/1/I/L を除いた32文字
const CODE_LENGTH = 10;
const MAX_PAYLOAD_BYTES = 200_000;
const EXPIRES_IN_MS = 24 * 60 * 60 * 1000;
const MAX_INSERT_RETRIES = 5;

/** POST /transfer と GET /transfer/:code。どちらでもなければ null。 */
export async function handleTransfer(ctx: RouteContext): Promise<Response | null> {
  const { request, path } = ctx;
  if (path === "/transfer" && request.method === "POST") return createTransfer(ctx);
  const fetchMatch = path.match(/^\/transfer\/([^/]+)$/);
  if (fetchMatch && request.method === "GET") {
    const code = decodePathParam(ctx, fetchMatch[1], "code");
    if (code instanceof Response) return code;
    return fetchTransfer(ctx, code);
  }
  return null;
}

function generateCode(): string {
  const bytes = new Uint8Array(CODE_LENGTH);
  crypto.getRandomValues(bytes);
  let code = "";
  for (const b of bytes) {
    code += CODE_ALPHABET[b % CODE_ALPHABET.length];
  }
  return code;
}

// ---------------------------------------------------------------------------
// POST /transfer
// ---------------------------------------------------------------------------

async function createTransfer(ctx: RouteContext): Promise<Response> {
  const { request, env, json, error, rateLimitResponse } = ctx;

  const user = await getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const [inactive, rl] = await Promise.all([
    requireActiveUser(ctx, user),
    checkRateLimit(env.DB, user.uid, "transfer_create"),
  ]);
  if (inactive) return inactive;
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const body = await readJsonBody(ctx, "invalid_json");
  if (body instanceof Response) return body;

  const payload = body.payload;
  if (typeof payload !== "string") return error("payload must be a string", 400);
  if (payload.length > MAX_PAYLOAD_BYTES) return error("payload_too_large", 400);

  const now = new Date();
  const createdAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + EXPIRES_IN_MS).toISOString();

  let code: string | null = null;
  for (let attempt = 0; attempt < MAX_INSERT_RETRIES; attempt++) {
    const candidate = generateCode();
    try {
      await env.DB.prepare(
        `INSERT INTO transfer_codes (code, user_id, payload, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?)`
      )
        .bind(candidate, user.uid, payload, createdAt, expiresAt)
        .run();
      code = candidate;
      break;
    } catch (e: any) {
      // PRIMARY KEY 衝突 (コード重複、確率的に極めて低い) のみリトライし、他のエラーは伝播させる。
      if (!String(e?.message ?? e).includes("UNIQUE")) throw e;
    }
  }
  if (!code) return error("failed to generate a unique transfer code", 500);

  return json({ code, expiresAt }, 201);
}

// ---------------------------------------------------------------------------
// GET /transfer/:code
// ---------------------------------------------------------------------------

async function fetchTransfer(ctx: RouteContext, code: string): Promise<Response> {
  const { request, env, json, error, rateLimitResponse } = ctx;

  const user = await getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const [inactive, rl] = await Promise.all([
    requireActiveUser(ctx, user),
    checkRateLimit(env.DB, user.uid, "transfer_fetch"),
  ]);
  if (inactive) return inactive;
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const normalizedCode = code.toUpperCase().trim();
  // SELECT→DELETE の2文だと同一コードへの同時複数GETがどちらもDELETE前にSELECT成功し
  // 「ワンタイム消費」の保証が破れる (TOCTOU)。DELETE...RETURNING で削除と取得を1文に原子化する。
  const row = await env.DB.prepare(
    "DELETE FROM transfer_codes WHERE code = ? RETURNING payload, created_at, expires_at"
  )
    .bind(normalizedCode)
    .first<{ payload: string; created_at: string; expires_at: string }>();

  if (!row || new Date(row.expires_at).getTime() < Date.now()) {
    return error("not_found_or_expired", 404);
  }

  return json({ payload: row.payload, createdAt: row.created_at }, 200);
}
