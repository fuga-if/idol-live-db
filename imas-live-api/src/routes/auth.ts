// routes/auth.ts — ログインとセッション。
//
//   POST /auth/login   — Apple の identityToken / Google の ID トークン → 1 年有効のセッション JWT
//   POST /auth/refresh — 期限切れ間近・直後のセッション JWT を再発行 (sliding session)
//   GET  /auth/me      — 自分の表示名・admin・BAN・貢献の 2 指標
//
// トークンの検証そのものは auth.ts。ここは HTTP の入口だけ。

import {
  verifyAppleToken, verifyGoogleToken, signSessionToken,
  verifySessionTokenForRefresh, getAuthUser, peekJwtIssuer, isRevokedSession,
  SESSION_JWT_ISSUER, SESSION_JWT_TTL_SECONDS,
} from "../auth";
import { checkRateLimit } from "../rate_limit";
import { upsertUser, isAllowlistedAdmin } from "../users";
import type { RouteContext } from "./context";
import { clientIp } from "./guards";

/** /auth/login・/auth/refresh・/auth/me。どれでもなければ null。 */
export async function handleAuth(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;

  // ----------------------------------------------------------------
  // POST /auth/login — Apple identityToken または Google idToken (Android) → 1年有効 sessionToken
  // ----------------------------------------------------------------
  if (path === "/auth/login" && request.method === "POST") {
    if (!env.SESSION_JWT_SECRET) return error("SESSION_JWT_SECRET not configured", 500);

    // IP 単位のレート制限 (未認証エンドポイントなので device/user 単位の制限は使えない)。
    // Apple/Google トークン検証の外部コスト枯渇を防ぐ一次防御。
    const authLoginRl = await checkRateLimit(env.DB, "ip:" + clientIp(request), "auth_login");
    if (!authLoginRl.allowed) {
      return rateLimitResponse(authLoginRl.used, authLoginRl.limit, authLoginRl.reset_at);
    }

    // iOS の APIClient は JSONEncoder.keyEncodingStrategy = .convertToSnakeCase で
    // 全リクエストボディを snake_case 化して送る (identityToken → identity_token,
    // displayName → display_name)。この endpoint だけ camelCase を読んでいたため
    // iOS のログインは常に 400 となり、session token が一度も発行されず、Apple
    // identityToken を直接 Bearer (10分有効) に流用するフォールバックで誤魔化されていた。
    // snake_case を正として読む (旧 camelCase クライアントも後方互換で許容)。
    // Android は Google の ID トークンを google_id_token として送る (identity_token とは別枠)。
    const body = (await request.json().catch(() => null)) as
      | {
          identity_token?: string; identityToken?: string;
          google_id_token?: string; googleIdToken?: string;
          display_name?: string; displayName?: string;
        }
      | null;
    const identityToken = body?.identity_token ?? body?.identityToken;
    const googleIdToken = body?.google_id_token ?? body?.googleIdToken;
    const displayName = body?.display_name ?? body?.displayName;

    let verified: { uid: string; email?: string; picture?: string; name?: string } | null = null;
    if (googleIdToken) {
      if (!env.GOOGLE_WEB_CLIENT_ID) return error("GOOGLE_WEB_CLIENT_ID not configured", 500);
      verified = await verifyGoogleToken(googleIdToken, env.GOOGLE_WEB_CLIENT_ID);
      if (!verified) return error("invalid googleIdToken", 401);
    } else if (identityToken) {
      verified = await verifyAppleToken(identityToken, env.APPLE_BUNDLE_ID);
      if (!verified) return error("invalid identityToken", 401);
    } else {
      return error("identityToken or googleIdToken required");
    }

    // Google は検証済みトークンの name クレームを信頼できる表示名として使う
    // (Apple はクライアント供給の displayName に頼る既存挙動を維持)。
    await upsertUser(env, verified.uid, verified.name ?? displayName, verified.picture);
    const sessionToken = await signSessionToken(verified.uid, env.SESSION_JWT_SECRET);
    // 再ログイン時 Apple は fullName を初回認可時しか返さないため、クライアントは
    // 自前で表示名を復元できない。upsert 後の正準 display_name を返し、クライアントが
    // userName を即復元できるようにする (これが無いと再ログイン直後に表示名が空になる)。
    // admin の判定も、この行の is_admin と env の許可リストで済ませる (同じ行を読み直さない)。
    const dbRow = await env.DB.prepare("SELECT display_name, is_admin FROM users WHERE id = ?")
      .bind(verified.uid)
      .first<{ display_name: string; is_admin: number }>();
    const isAdmin = isAllowlistedAdmin(env, verified.uid) || !!dbRow?.is_admin;
    return json({
      sessionToken,
      uid: verified.uid,
      email: verified.email,
      isAdmin,
      displayName: dbRow?.display_name ?? null,
      expiresIn: SESSION_JWT_TTL_SECONDS,
    });
  }

  // ----------------------------------------------------------------
  // POST /auth/refresh — 期限切れ間近/直後の sessionToken を Apple 再認証なしで再発行
  //   (sliding session)。署名が有効で猶予 (90日) 内なら新しい 1 年トークンを返す。
  // ----------------------------------------------------------------
  if (path === "/auth/refresh" && request.method === "POST") {
    if (!env.SESSION_JWT_SECRET) return error("SESSION_JWT_SECRET not configured", 500);

    // IP 単位のレート制限 (auth/login と同じ理由。refresh は外部コストは無いが下限の防御)。
    const authRefreshRl = await checkRateLimit(env.DB, "ip:" + clientIp(request), "auth_refresh");
    if (!authRefreshRl.allowed) {
      return rateLimitResponse(authRefreshRl.used, authRefreshRl.limit, authRefreshRl.reset_at);
    }

    const auth = request.headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) return error("Unauthorized", 401);
    const oldToken = auth.slice(7);
    // 自前セッショントークンのみ refresh 対象 (Apple identityToken は対象外)。
    if (peekJwtIssuer(oldToken) !== SESSION_JWT_ISSUER) return error("Unauthorized", 401);
    const verified = await verifySessionTokenForRefresh(oldToken, env.SESSION_JWT_SECRET);
    if (!verified) return error("Unauthorized", 401);
    // 退会したアカウントのトークンは再発行しない。admin の判定と同じ 1 行で見る
    // (env の許可リストの admin だけは、今まで読まなかった行を読む。refresh は 1 年に 1 回程度)。
    const row = await env.DB.prepare("SELECT is_admin, created_at FROM users WHERE id = ?")
      .bind(verified.uid)
      .first<{ is_admin: number; created_at: string }>();
    if (isRevokedSession(verified, row)) return error("Unauthorized", 401);
    const sessionToken = await signSessionToken(verified.uid, env.SESSION_JWT_SECRET);
    const isAdmin = isAllowlistedAdmin(env, verified.uid) || !!row?.is_admin;
    return json({
      sessionToken,
      uid: verified.uid,
      isAdmin,
      expiresIn: SESSION_JWT_TTL_SECONDS,
    });
  }

  // ----------------------------------------------------------------
  // GET /auth/me
  // ----------------------------------------------------------------
  if (path === "/auth/me" && request.method === "GET") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);
    // 貢献度 2 指標 (確定契約。合成しない):
    //   editCount     = users.contribution_count (編集 batch 件数。finalize で +1)
    //   goodsReceived = 自分の編集が累計で受け取った Good 数 (edit_good を editor で都度 COUNT)
    const row = await env.DB.prepare(
      `SELECT u.id, u.display_name, u.avatar_url, u.is_admin, u.is_banned, u.contribution_count, u.created_at,
              COALESCE((SELECT COUNT(*) FROM edit_good g
                        JOIN edit_batch eb ON eb.id = g.batch_id
                        WHERE eb.editor_id = u.id AND eb.source = 'app'), 0) AS goods_received
         FROM users u WHERE u.id = ?`
    )
      .bind(user.uid)
      .first<{
        id: string;
        display_name: string;
        avatar_url: string | null;
        is_admin: number;
        is_banned: number;
        contribution_count: number;
        created_at: string;
        goods_received: number;
      }>();
    // 退会で無効になったセッションは 401 (読んだ行で判定する。読み足さない)。
    if (isRevokedSession(user, row)) return error("Unauthorized", 401);
    // admin の判定は、読んだ行の is_admin と env の許可リストで済ませる (同じ行を読み直さない)。
    const isAdmin = isAllowlistedAdmin(env, user.uid) || !!row?.is_admin;
    // editCount = source='app' の編集 batch 件数。contribution_count は finalizeEditBatch で
    // source='app' のみ +1 されるため同値 (revert/seed では加算しない=現状維持。確定契約 §3)。
    const editCount = row?.contribution_count ?? 0;
    return json({
      uid: user.uid,
      displayName: row?.display_name ?? null,
      avatarUrl: row?.avatar_url ?? null,
      isAdmin,
      isBanned: !!row?.is_banned,
      editCount,
      goodsReceived: row?.goods_received ?? 0,
    });
  }

  return null;
}
