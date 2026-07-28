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

/**
 * リクエスト本文の上限。**これが唯一の量的な上限**。
 *
 * 以前は op 件数の上限 (50) も別に持っていたが、
 * - セトリ編集は差分ではなく全曲・全出演者を毎回送るので簡単に超える
 *   (本番実測: セトリ登録済み 1252 公演のうち 403 件が 50 ops 超、最大 606 ops)
 * - 生データはコメントへ**バイト数で**分割するので、op が何件でもコメント数は増えない
 *   (256KB ÷ 1 チャンク 60KB ≒ 最大 5 コメント。op が極小でも同じ)
 * という理由で、件数の上限は意味を持たない二重の縛りだった。
 *
 * 送れる量も、GitHub を叩く回数も、ここだけで有界になる。
 */
const MAX_BODY = 256 * 1024;

/**
 * GitHub の issue body / comment body は 65,536 文字が上限。
 * 超えると 422 で弾かれるので、収まらないぶんはコメントに分割して投稿する。
 * 余白は Markdown の囲み (```json 等) と切れ目の注記ぶん。
 */
const GITHUB_BODY_LIMIT = 65536;
const BODY_BUDGET = 60000;

/**
 * op ごとの表を本文に載せる上限。
 * これを超える件数 (セトリ一括など) は人間が表で追える量ではないので、
 * 内訳の集計だけ出して生データはコメント側に回す。
 */
const DETAIL_OP_LIMIT = 30;

function mdEscape(s: string): string {
  return s.replace(/[|\\`]/g, (c) => "\\" + c).slice(0, 500);
}

function fmtFields(fields?: Record<string, unknown>): string {
  if (!fields || Object.keys(fields).length === 0) return "| _(なし)_ | |";
  return Object.entries(fields)
    .map(([k, v]) => `| \`${mdEscape(k)}\` | ${mdEscape(String(v))} |`)
    .join("\n");
}

/** recordType ごとの op 内訳 ("SetlistItem: 25件 (update 20 / create 5)")。 */
function opBreakdown(ops: OpInput[]): string[] {
  const byType = new Map<string, Map<string, number>>();
  for (const o of ops) {
    const type = o.recordType ?? "?";
    const kind = o.op ?? "update";
    if (!byType.has(type)) byType.set(type, new Map());
    const kinds = byType.get(type)!;
    kinds.set(kind, (kinds.get(kind) ?? 0) + 1);
  }
  return [...byType.entries()].map(([type, kinds]) => {
    const total = [...kinds.values()].reduce((a, b) => a + b, 0);
    const detail = [...kinds.entries()].map(([k, n]) => `${k} ${n}`).join(" / ");
    return `- \`${type}\`: ${total}件 (${detail})`;
  });
}

/**
 * 生データ (取り込み用 JSON) を GitHub の 1 body に収まるチャンクへ切る。
 *
 * 件数が多いと整形 JSON は簡単に 64K を超える (実測 606 ops で 136KB) ので、
 * まず圧縮 JSON にし、それでも収まらなければ ops を分割して複数チャンクにする。
 * 各チャンクは単体で JSON として読める形 ({summary, part, ops}) にしておく。
 */
function buildRawChunks(ops: OpInput[], summary: string | undefined): string[] {
  const wrap = (payload: unknown) =>
    "```json\n" + JSON.stringify(payload) + "\n```";

  const whole = wrap({ summary, ops });
  if (whole.length <= BODY_BUDGET) return [whole];

  // 1 op あたりの実測サイズから、1 チャンクに詰められる件数を見積もって分割する。
  const perOp = Math.max(1, Math.ceil(JSON.stringify(ops).length / ops.length));
  const perChunk = Math.max(1, Math.floor((BODY_BUDGET - 500) / perOp));
  const chunks: string[] = [];
  const total = Math.ceil(ops.length / perChunk);
  for (let i = 0; i < ops.length; i += perChunk) {
    const part = Math.floor(i / perChunk) + 1;
    chunks.push(
      `**raw ${part}/${total}** (取り込み用)\n\n` +
        wrap({ summary, part, parts: total, ops: ops.slice(i, i + perChunk) })
    );
  }
  return chunks;
}

/**
 * issue の本文と、本文に収まらなかった生データのコメントを組み立てる。
 *
 * @returns body は必ず GitHub の上限内。comments は作成後に順に投稿する。
 */
function buildIssue(ops: OpInput[], summary: string | undefined, uid: string) {
  const title = `[修正リクエスト] ${summary || ops[0]?.recordType || "master"}`.slice(0, 120);
  const lines: string[] = [];
  lines.push("> アプリから自動投稿されたマスタ修正リクエストです。内容を確認し data/fixes に取り込んでください。");
  if (summary) lines.push(`\n**概要**: ${mdEscape(summary)}`);
  lines.push(`\n**投稿者**: \`${uid.slice(0, 8)}…\``);
  lines.push(`\n**op 数**: ${ops.length}`);
  lines.push("");
  lines.push(...opBreakdown(ops));
  lines.push("");

  // 少数の編集は今までどおり field 単位の表を出す。セトリ一括のような大量 op は
  // 表にしても追えないので内訳だけにして、中身は生データ側で見てもらう。
  if (ops.length <= DETAIL_OP_LIMIT) {
    ops.forEach((o, i) => {
      const where = o.recordName ? ` (\`${o.recordName}\`)` : " (新規)";
      lines.push(`### ${i + 1}. ${o.op ?? "update"} ${o.recordType ?? "?"}${where}`);
      lines.push("");
      lines.push("| field | 希望値 |");
      lines.push("|---|---|");
      lines.push(fmtFields(o.fields));
      lines.push("");
    });
  } else {
    lines.push(`_op が ${ops.length} 件あるため個別の表は省略しています。内容は raw を参照してください。_`);
    lines.push("");
  }

  const chunks = buildRawChunks(ops, summary);
  const header = lines.join("\n");
  const comments: string[] = [];

  // 生データが 1 チャンクで、かつ本文に収まるなら従来どおり折りたたみで同梱する。
  const inline = `<details><summary>raw (取り込み用)</summary>\n\n${chunks[0]}\n</details>`;
  let body: string;
  if (chunks.length === 1 && header.length + inline.length <= BODY_BUDGET) {
    body = `${header}\n${inline}`;
  } else {
    body = `${header}\n_生データは以下のコメントに ${chunks.length} 分割で投稿しています。_`;
    comments.push(...chunks);
  }

  // 最後の砦。ここまでで超えることは無い想定だが、超えたまま投げると 422 になる。
  if (body.length > GITHUB_BODY_LIMIT) {
    body = body.slice(0, GITHUB_BODY_LIMIT - 100) + "\n\n_(本文が長すぎるため切り詰めました)_";
  }
  return { title, body, comments };
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
  const { title, body: issueBody, comments } = buildIssue(ops, body?.summary, user.uid);

  const gh = (path: string, payload: unknown) =>
    fetch(`https://api.github.com/repos/${repo}${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github+json",
        "User-Agent": "imas-live-api",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

  const res = await gh("/issues", { title, body: issueBody });

  if (!res.ok) {
    const t = await res.text();
    console.error(`[edit-requests] github ${res.status}: ${t.slice(0, 300)}`);
    return error(`failed to create request (github ${res.status})`, 502);
  }
  const issue = (await res.json()) as { number: number; html_url: string };

  // 本文に入りきらなかった生データをコメントとして続けて投稿する。
  // ここで失敗すると issue はあるのに取り込み用データが欠けた状態になるため、
  // 黙って 201 を返さず、どこまで投稿できたかを添えてエラーにする。
  for (let i = 0; i < comments.length; i++) {
    const c = await gh(`/issues/${issue.number}/comments`, { body: comments[i] });
    if (!c.ok) {
      const t = await c.text();
      console.error(`[edit-requests] github comment ${c.status}: ${t.slice(0, 300)}`);
      return error(
        `request created (${issue.html_url}) but raw data is incomplete: ` +
          `posted ${i}/${comments.length} parts (github ${c.status})`,
        502
      );
    }
  }

  return json({ ok: true, issueNumber: issue.number, issueUrl: issue.html_url }, 201);
}
