// edit_requests.ts — マスタ修正リクエストを GitHub issue 化する。
//
// 一般ユーザーの「修正をリクエスト」を受け、CloudKit には一切書かず GitHub issue を作る。
// 運営が issue を見て data/fixes に落とし込み apply_data.py で本DBへ反映する
// (= マスタ変更を git 経路に一本化し、二重書き込みによる乖離/巻き戻しを防ぐ)。
//
// コミュニティ投稿 (コーレス/参考動画) は従来どおり /edits で全員オープン。ここはマスタ専用。

export interface EditRequestEnv {
  DB: D1Database;
  GITHUB_TOKEN?: string;
  GITHUB_REPO?: string; // "owner/repo"
}

interface OpInput {
  op?: string;
  recordType?: string;
  recordName?: string;
  fields?: Record<string, unknown>;
}

export interface EditRequestDeps<E extends EditRequestEnv> {
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

const MAX_BODY = 256 * 1024;
const MAX_OPS = 50;

function mdEscape(s: string): string {
  return s.replace(/[|\\`]/g, (c) => "\\" + c).slice(0, 500);
}

function fmtFields(fields?: Record<string, unknown>): string {
  if (!fields || Object.keys(fields).length === 0) return "| _(なし)_ | |";
  return Object.entries(fields)
    .map(([k, v]) => `| \`${mdEscape(k)}\` | ${mdEscape(String(v))} |`)
    .join("\n");
}

function buildIssue(ops: OpInput[], summary: string | undefined, uid: string) {
  const title = `[修正リクエスト] ${summary || ops[0]?.recordType || "master"}`.slice(0, 120);
  const lines: string[] = [];
  lines.push("> アプリから自動投稿されたマスタ修正リクエストです。内容を確認し data/fixes に取り込んでください。");
  if (summary) lines.push(`\n**概要**: ${mdEscape(summary)}`);
  lines.push(`\n**投稿者**: \`${uid.slice(0, 8)}…\``);
  lines.push("");
  ops.forEach((o, i) => {
    const where = o.recordName ? ` (\`${o.recordName}\`)` : " (新規)";
    lines.push(`### ${i + 1}. ${o.op ?? "update"} ${o.recordType ?? "?"}${where}`);
    lines.push("");
    lines.push("| field | 希望値 |");
    lines.push("|---|---|");
    lines.push(fmtFields(o.fields));
    lines.push("");
  });
  lines.push("<details><summary>raw (取り込み用)</summary>\n");
  lines.push("```json");
  lines.push(JSON.stringify({ summary, ops }, null, 2));
  lines.push("```");
  lines.push("</details>");
  return { title, body: lines.join("\n") };
}

export async function handlePostEditRequests<E extends EditRequestEnv>(
  request: Request,
  env: E,
  deps: EditRequestDeps<E>
): Promise<Response> {
  const { json, error, rateLimitResponse } = deps;

  const user = await deps.getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const raw = await request.text();
  if (raw.length > MAX_BODY) return error("body too large", 413);
  let body: { ops?: OpInput[]; summary?: string } | null;
  try {
    body = JSON.parse(raw) as { ops?: OpInput[]; summary?: string };
  } catch {
    return error("invalid json body");
  }
  const ops = body?.ops ?? [];
  if (!Array.isArray(ops) || ops.length === 0) return error("ops is required (non-empty array)");
  if (ops.length > MAX_OPS) return error(`too many ops (max ${MAX_OPS})`, 413);

  const [dbUser, rl] = await Promise.all([
    env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
      .bind(user.uid)
      .first<{ is_banned: number }>(),
    deps.checkRateLimit(env.DB, user.uid, "edit_request"),
  ]);
  if (dbUser?.is_banned) return error("Banned", 403);
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  if (!env.GITHUB_TOKEN) {
    return error("correction requests are not configured (GITHUB_TOKEN missing)", 503);
  }
  const repo = env.GITHUB_REPO || "fuga-if/idol-live-db";
  const { title, body: issueBody } = buildIssue(ops, body?.summary, user.uid);

  const res = await fetch(`https://api.github.com/repos/${repo}/issues`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "User-Agent": "imas-live-api",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ title, body: issueBody }),
  });

  if (!res.ok) {
    const t = await res.text();
    console.error(`[edit-requests] github ${res.status}: ${t.slice(0, 300)}`);
    return error(`failed to create request (github ${res.status})`, 502);
  }
  const issue = (await res.json()) as { number: number; html_url: string };
  return json({ ok: true, issueNumber: issue.number, issueUrl: issue.html_url }, 201);
}
