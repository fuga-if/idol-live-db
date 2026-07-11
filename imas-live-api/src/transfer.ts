// transfer.ts — 引き継ぎコード。
//
//   POST /transfer        ユーザー生成ローカルデータ (お気に入り/担当/投票履歴等) を
//                          サーバーに一時保管し、ワンタイムコードを発行する
//   GET  /transfer/:code   コードでペイロードを取得し、取得と同時にサーバー側から削除する
//
// payload の中身 (JSON 妥当性含む) はクライアント側の責務。Worker はただの文字列ストレージ。

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 紛らわしい 0/O/1/I/L を除いた32文字
const CODE_LENGTH = 10;
const MAX_PAYLOAD_BYTES = 200_000;
const EXPIRES_IN_MS = 24 * 60 * 60 * 1000;
const MAX_INSERT_RETRIES = 5;

export interface TransferEnv {
  DB: D1Database;
}

export interface TransferDeps<E extends TransferEnv> {
  getAuthUser: (request: Request, env: E) => Promise<{ uid: string; email?: string } | null>;
  checkRateLimit: (
    db: D1Database,
    uid: string,
    action: string
  ) => Promise<{ allowed: boolean; used: number; limit: number; reset_at: string }>;
  json: (data: unknown, status?: number) => Response;
  error: (message: string, status?: number) => Response;
  rateLimitResponse: (used: number, limit: number, resetAt: string) => Response;
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

export async function handleCreateTransfer<E extends TransferEnv>(
  request: Request,
  env: E,
  deps: TransferDeps<E>
): Promise<Response> {
  const { json, error, rateLimitResponse } = deps;

  const user = await deps.getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const [dbUser, rl] = await Promise.all([
    env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
      .bind(user.uid)
      .first<{ is_banned: number }>(),
    deps.checkRateLimit(env.DB, user.uid, "transfer_create"),
  ]);
  if (dbUser?.is_banned) return error("Banned", 403);
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  let body: { payload?: unknown } | null;
  try {
    body = (await request.json()) as { payload?: unknown };
  } catch {
    return error("invalid_json", 400);
  }

  const payload = body?.payload;
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

export async function handleFetchTransfer<E extends TransferEnv>(
  request: Request,
  env: E,
  code: string,
  deps: TransferDeps<E>
): Promise<Response> {
  const { json, error, rateLimitResponse } = deps;

  const user = await deps.getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const [dbUser, rl] = await Promise.all([
    env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
      .bind(user.uid)
      .first<{ is_banned: number }>(),
    deps.checkRateLimit(env.DB, user.uid, "transfer_fetch"),
  ]);
  if (dbUser?.is_banned) return error("Banned", 403);
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
