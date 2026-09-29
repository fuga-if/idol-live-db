// routes/discord.ts — Discord のロール受け取り。
//
//   POST /discord/link          アプリ (ログイン済み) から。Discord の認可 URL を返す
//   GET  /discord/callback      Discord から戻る先。サーバーに参加させ、条件を満たせば「データ協力」を付ける
//   POST /discord/interactions  Discord のスラッシュコマンド (/申請) の受け口
//   GET  /github/callback       /申請 コントリビューター から。GitHub で本人確認し「コントリビューター」を付ける
//
// ロールの条件:
//   データ協力       … アプリでの編集が DATA_ROLE_MIN_EDITS 件以上 (badges.ts の bronze と同じ件数)。
//                      ただしバッジと違い、差し戻された編集は数えない (雑な編集でロールを取りにいけないように)
//   コントリビューター … GITHUB_REPO にマージ済みの PR がある
// どちらも付けるだけで外さない (条件を満たさなくなっても、後から外す処理は持たない)。
//
// state はワンタイム (DELETE ... RETURNING で取り出す)・10 分で失効。
// 戻り先 (redirect_uri) はこの Worker 自身のオリジンから組むので、Discord / GitHub の
// 管理画面には https://<この Worker>/discord/callback と /github/callback を登録しておく。

import { getAuthUser } from "../auth";
import {
  addGuildMember,
  addGuildMemberRole,
  countMergedPullRequests,
  exchangeDiscordCode,
  exchangeGithubCode,
  fetchDiscordUserId,
  fetchGithubLogin,
  isDiscordLinkConfigured,
  isGithubLinkConfigured,
  randomState,
  renderResultPage,
  verifyDiscordSignature,
} from "../discord";
import { checkRateLimit } from "../rate_limit";
import type { RouteContext } from "./context";
import { requireActiveUser } from "./guards";

/** 「データ協力」の条件 (編集件数)。badges.ts の bronze と揃える。 */
export const DATA_ROLE_MIN_EDITS = 10;
const STATE_TTL_MS = 10 * 60 * 1000;

/**
 * ロールの条件に使う編集件数。badges.ts の editCount と同じ数え方から、差し戻された batch
 * (reverted_at IS NOT NULL) を除く。バッジは「通算の活動量」なので残すが、ロールは「今も残っている貢献」で見る。
 */
async function countKeptEdits(db: D1Database, userId: string): Promise<number> {
  const row = await db
    .prepare(
      "SELECT COUNT(*) AS cnt FROM edit_batch WHERE editor_id = ? AND cloudkit_ok = 1 AND source = 'app' AND reverted_at IS NULL"
    )
    .bind(userId)
    .first<{ cnt: number }>();
  return Number(row?.cnt) || 0;
}

export async function handleDiscord(ctx: RouteContext): Promise<Response | null> {
  const { request, path } = ctx;
  if (path === "/discord/link" && request.method === "POST") return startDiscordLink(ctx);
  if (path === "/discord/callback" && request.method === "GET") return discordCallback(ctx);
  if (path === "/discord/interactions" && request.method === "POST") return discordInteractions(ctx);
  if (path === "/github/callback" && request.method === "GET") return githubCallback(ctx);
  return null;
}

function guildUrl(ctx: RouteContext): string {
  return `https://discord.com/channels/${ctx.env.DISCORD_GUILD_ID}`;
}

async function insertState(
  ctx: RouteContext,
  kind: "discord" | "github",
  ids: { userId?: string; discordUserId?: string }
): Promise<string> {
  const state = randomState();
  const now = Date.now();
  await ctx.env.DB.prepare(
    `INSERT INTO discord_oauth_states (state, kind, user_id, discord_user_id, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`
  )
    .bind(
      state,
      kind,
      ids.userId ?? null,
      ids.discordUserId ?? null,
      new Date(now).toISOString(),
      new Date(now + STATE_TTL_MS).toISOString()
    )
    .run();
  return state;
}

/** state を 1 回だけ取り出す。無い・期限切れ・種類違いは null。 */
async function consumeState(
  ctx: RouteContext,
  kind: "discord" | "github",
  state: string | null
): Promise<{ user_id: string | null; discord_user_id: string | null } | null> {
  if (!state) return null;
  const row = await ctx.env.DB.prepare(
    "DELETE FROM discord_oauth_states WHERE state = ? RETURNING kind, user_id, discord_user_id, expires_at"
  )
    .bind(state)
    .first<{ kind: string; user_id: string | null; discord_user_id: string | null; expires_at: string }>();
  if (!row || row.kind !== kind || new Date(row.expires_at).getTime() < Date.now()) return null;
  return row;
}

const EXPIRED_PAGE = {
  heading: "リンクの期限が切れました",
  message: "お手数ですが、はじめからもう一度お試しください。",
  status: 400,
};

// ---------------------------------------------------------------------------
// POST /discord/link
// ---------------------------------------------------------------------------

async function startDiscordLink(ctx: RouteContext): Promise<Response> {
  const { request, env, json, error, rateLimitResponse, url } = ctx;

  const user = await getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);
  if (!isDiscordLinkConfigured(env)) return error("discord_not_configured", 503);

  const [inactive, rl] = await Promise.all([
    requireActiveUser(ctx, user),
    checkRateLimit(env.DB, user.uid, "discord_link"),
  ]);
  if (inactive) return inactive;
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const state = await insertState(ctx, "discord", { userId: user.uid });
  const authorize = new URL("https://discord.com/oauth2/authorize");
  authorize.search = new URLSearchParams({
    client_id: env.DISCORD_APPLICATION_ID!,
    response_type: "code",
    redirect_uri: `${url.origin}/discord/callback`,
    scope: "identify guilds.join",
    state,
    prompt: "none",
  }).toString();
  return json({ url: authorize.toString() });
}

// ---------------------------------------------------------------------------
// GET /discord/callback
// ---------------------------------------------------------------------------

async function discordCallback(ctx: RouteContext): Promise<Response> {
  const { env, url } = ctx;
  if (!isDiscordLinkConfigured(env)) {
    return renderResultPage({ heading: "いまは受け付けていません", message: "時間をおいてお試しください。", status: 503 });
  }
  const row = await consumeState(ctx, "discord", url.searchParams.get("state"));
  if (!row?.user_id) return renderResultPage(EXPIRED_PAGE);

  const code = url.searchParams.get("code");
  if (!code) {
    // 認可画面で「キャンセル」を押したとき (error=access_denied)。
    return renderResultPage({
      heading: "キャンセルしました",
      message: "ロールを受け取るときは、アプリからもう一度お試しください。",
    });
  }

  const accessToken = await exchangeDiscordCode(env, code, `${url.origin}/discord/callback`);
  const discordUserId = accessToken ? await fetchDiscordUserId(accessToken) : null;
  if (!accessToken || !discordUserId) {
    return renderResultPage({
      heading: "Discord と連携できませんでした",
      message: "時間をおいて、アプリからもう一度お試しください。",
      status: 502,
    });
  }

  const joined = await addGuildMember(env, discordUserId, accessToken);
  await env.DB.prepare(
    `INSERT INTO discord_links (user_id, discord_user_id, linked_at) VALUES (?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET discord_user_id = excluded.discord_user_id, linked_at = excluded.linked_at`
  )
    .bind(row.user_id, discordUserId, new Date().toISOString())
    .run();
  if (!joined) {
    return renderResultPage({
      heading: "サーバーに参加できませんでした",
      message: "サーバーに参加してから、アプリでもう一度ボタンを押してください。",
      button: { label: "Discord を開く", href: guildUrl(ctx) },
      status: 502,
    });
  }

  const editCount = await countKeptEdits(env.DB, row.user_id);
  if (editCount < DATA_ROLE_MIN_EDITS) {
    return renderResultPage({
      heading: "サーバーに参加しました",
      message: `あと ${DATA_ROLE_MIN_EDITS - editCount} 件編集すると「データ協力」ロールが付きます。条件を満たしたら、アプリでもう一度ボタンを押してください。`,
      button: { label: "Discord を開く", href: guildUrl(ctx) },
    });
  }
  const granted = await addGuildMemberRole(env, discordUserId, env.DISCORD_DATA_ROLE_ID!);
  if (!granted) {
    return renderResultPage({
      heading: "ロールを付けられませんでした",
      message: "時間をおいて、アプリからもう一度お試しください。",
      button: { label: "Discord を開く", href: guildUrl(ctx) },
      status: 502,
    });
  }
  return renderResultPage({
    heading: "「データ協力」ロールを付けました",
    message: "いつもデータを入れてくださってありがとうございます。",
    button: { label: "Discord を開く", href: guildUrl(ctx) },
  });
}

// ---------------------------------------------------------------------------
// POST /discord/interactions
// ---------------------------------------------------------------------------

const EPHEMERAL = 64;

interface Interaction {
  type: number;
  data?: { name?: string; options?: Array<{ name: string; value: unknown }> };
  member?: { user?: { id?: string } };
  user?: { id?: string };
}

async function discordInteractions(ctx: RouteContext): Promise<Response> {
  const { request, env, json, error, url } = ctx;
  if (!env.DISCORD_PUBLIC_KEY) return error("discord_not_configured", 503);

  const body = await request.text();
  const ok = await verifyDiscordSignature(
    env.DISCORD_PUBLIC_KEY,
    request.headers.get("X-Signature-Ed25519") ?? "",
    request.headers.get("X-Signature-Timestamp") ?? "",
    body
  );
  if (!ok) return error("invalid request signature", 401);

  let interaction: Interaction;
  try {
    interaction = JSON.parse(body) as Interaction;
  } catch {
    return error("invalid_json", 400);
  }

  // PING (Interactions Endpoint URL を登録するときの疎通確認)。
  if (interaction.type === 1) return json({ type: 1 });

  const reply = (content: string, components?: unknown[]) =>
    json({ type: 4, data: { content, flags: EPHEMERAL, ...(components ? { components } : {}) } });

  if (interaction.type !== 2 || interaction.data?.name !== "申請") {
    return reply("このコマンドには対応していません。");
  }
  const role = interaction.data.options?.find((o) => o.name === "ロール")?.value;

  if (role === "data") {
    return reply(
      `「データ協力」ロールはアプリから受け取れます。マイページの「Discordでロールを受け取る」を押してください（アプリで${DATA_ROLE_MIN_EDITS}件以上編集すると付きます）。`
    );
  }
  if (role === "contributor") {
    const discordUserId = interaction.member?.user?.id ?? interaction.user?.id;
    if (!discordUserId || !isGithubLinkConfigured(env)) {
      return reply("いまはコントリビューターの申請を受け付けていません。");
    }
    const state = await insertState(ctx, "github", { discordUserId });
    const authorize = new URL("https://github.com/login/oauth/authorize");
    authorize.search = new URLSearchParams({
      client_id: env.GITHUB_OAUTH_CLIENT_ID!,
      redirect_uri: `${url.origin}/github/callback`,
      state,
      allow_signup: "false",
    }).toString();
    return reply(
      "GitHub でログインすると、マージされた PR があるか確かめて「コントリビューター」ロールを付けます（リンクは10分有効です）。",
      [{ type: 1, components: [{ type: 2, style: 5, label: "GitHub で確認する", url: authorize.toString() }] }]
    );
  }
  return reply("ロールを選んでください。");
}

// ---------------------------------------------------------------------------
// GET /github/callback
// ---------------------------------------------------------------------------

async function githubCallback(ctx: RouteContext): Promise<Response> {
  const { env, url } = ctx;
  if (!isGithubLinkConfigured(env)) {
    return renderResultPage({ heading: "いまは受け付けていません", message: "時間をおいてお試しください。", status: 503 });
  }
  const row = await consumeState(ctx, "github", url.searchParams.get("state"));
  if (!row?.discord_user_id) return renderResultPage(EXPIRED_PAGE);

  const code = url.searchParams.get("code");
  if (!code) {
    return renderResultPage({
      heading: "キャンセルしました",
      message: "申請するときは、Discord でもう一度 /申請 を使ってください。",
    });
  }
  const accessToken = await exchangeGithubCode(env, code, `${url.origin}/github/callback`);
  const login = accessToken ? await fetchGithubLogin(accessToken) : null;
  const merged = accessToken && login ? await countMergedPullRequests(env, accessToken, login) : null;
  if (!login || merged === null) {
    // どこで止まったかを小さく出す (Workers Logs を見なくても切り分けられるように)。
    const step = !accessToken ? "token" : !login ? "user" : "search";
    return renderResultPage({
      heading: "GitHub で確認できませんでした",
      message: `時間をおいて、Discord でもう一度 /申請 を使ってください。(${step})`,
      status: 502,
    });
  }
  if (merged === 0) {
    return renderResultPage({
      heading: "マージされた PR が見つかりませんでした",
      message: `${login} さんの PR がマージされたら、もう一度 /申請 を使ってください。`,
      button: { label: "Discord を開く", href: guildUrl(ctx) },
    });
  }
  const granted = await addGuildMemberRole(env, row.discord_user_id, env.DISCORD_CONTRIBUTOR_ROLE_ID!);
  if (!granted) {
    return renderResultPage({
      heading: "ロールを付けられませんでした",
      message: "サーバーに参加しているか確かめて、もう一度 /申請 を使ってください。",
      button: { label: "Discord を開く", href: guildUrl(ctx) },
      status: 502,
    });
  }
  return renderResultPage({
    heading: "「コントリビューター」ロールを付けました",
    message: `${login} さん、コードでの貢献ありがとうございます。`,
    button: { label: "Discord を開く", href: guildUrl(ctx) },
  });
}
