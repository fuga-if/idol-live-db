// routes/lyric_submissions.ts — 歌詞の投稿 (POST /songs/:song_id/lyric-submissions)。
//
// 利用者が CD の歌詞カードなどの一次ソースを見て入力した歌詞を預かる。
// 投稿はその場で song_lyrics に公開する (運営はあとから確認する。2026-10-06 オーナー判断)。
// 既に歌詞のある曲への直しもすぐ公開する (2026-10-07 オーナー判断)。上書き前の版は
// song_lyrics_versions に残し、モデレーターが POST /admin/lyrics/:song_id/restore で戻せる。
// 歌詞を出せない曲 (lyric_unlicensed_songs) と、歌詞の形に合わないものは預かるだけで公開しない。
// lyric_submissions の status は運営の確認の状態 (pending = 未確認)。公開したかは published_at。
//
// ボディは { agreed_to_guideline, text } (アプリの JSON は snake_case)。
// ⚠️ 投稿ガイドラインへの同意 (agreed_to_guideline: true) が必須。入力元は書かせない
//    (どこから写したかは確かめようがないので規約で縛る。ガイドラインはコアが持つ)。
// ⚠️ 本文の整え方と上限は imas-core domain/lyric_submission.rs と同じ (改行を揃え、行末の空白と
//    前後の空行を落とし、空行の連続を 1 つに。文字数は UTF-16 = .length)。字そのものは変えない。
// ⚠️ 応答に本文を返さない (預かった id と状態だけ)。

import { getAuthUser } from "../auth";
import { postChannelMessage } from "../discord";
import { md } from "../discord_digest";
import { checkRateLimit } from "../rate_limit";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody, requireActiveUser } from "./guards";
import { NO_STORE, parseLines, storeLyrics, validateLyricsBody, type LyricsBody } from "./lyrics";

/** 投稿から公開した歌詞の出典の表記 (曲の歌詞の下に「出典: …」と出る)。 */
export const SUBMISSION_SOURCE = "みんなの投稿";

/** 整えた本文を歌詞の行にする。空行は blank、それ以外は lyric。 */
export function submissionLines(body: string): Array<{ kind: string; text: string }> {
  return body.split("\n").map((text) => (text ? { kind: "lyric", text } : { kind: "blank", text: "" }));
}

export const SUBMISSION_MAX_CHARS = 8000;
export const SUBMISSION_MAX_LINES = 400;

export function normalizeLyricText(text: string): string {
  const out: string[] = [];
  for (const raw of text.replace(/\r\n?/g, "\n").split("\n")) {
    const line = raw.replace(/\s+$/u, "");
    if (!line && (out.length === 0 || out[out.length - 1] === "")) continue;
    out.push(line);
  }
  while (out.length && out[out.length - 1] === "") out.pop();
  return out.join("\n");
}

export type SubmissionResult =
  | { ok: true; body: string; lineCount: number }
  | { ok: false; error: string };

export function validateSubmission(body: Readonly<Record<string, unknown>>): SubmissionResult {
  const { agreed_to_guideline: agreed, text } = body;
  if (agreed !== true) return { ok: false, error: "agreed_to_guideline must be true" };
  if (typeof text !== "string") return { ok: false, error: "text must be a string" };
  const normalized = normalizeLyricText(text);
  if (!normalized) return { ok: false, error: "text is empty" };
  // 半角カナ (U+FF61〜U+FF9F) は表記どおりではないので受け付けない (コアの HalfwidthKana と同じ)。
  if (/[\uFF61-\uFF9F]/u.test(normalized)) return { ok: false, error: "text must not contain halfwidth kana" };
  if (normalized.length > SUBMISSION_MAX_CHARS) return { ok: false, error: `text must be up to ${SUBMISSION_MAX_CHARS}` };
  const lineCount = normalized.split("\n").length;
  if (lineCount > SUBMISSION_MAX_LINES) return { ok: false, error: `text must be up to ${SUBMISSION_MAX_LINES} lines` };
  return { ok: true, body: normalized, lineCount };
}

/** 歌詞の報告の理由 (アプリの選択肢と同じ鍵)。 */
export const LYRICS_REPORT_REASONS: Readonly<Record<string, string>> = {
  copied: "歌詞サイト・他サービスからの転載",
  wrong: "歌詞の誤り",
  rights: "権利者からの削除の求め",
  other: "その他",
};
const LYRICS_REPORT_NOTE_MAX = 300;

/**
 * POST /songs/:song_id/lyrics-report — 歌詞の報告 (転載・誤り・削除の求め)。GitHub の issue にする。
 * 非公開の #運営 (DISCORD_MOD_CHANNEL_ID) にもすぐ知らせる (即公開なので荒らしに早く気づくため)。
 * ⚠️ issue は公開リポジトリに立つので、歌詞の本文は載せない (曲 id・理由・短い補足だけ)。
 *    補足に本文を貼られても長く載らないよう 300 字で切る。
 */
async function handleLyricsReport(ctx: RouteContext, songIdRaw: string): Promise<Response> {
  const { request, env, json, error, rateLimitResponse } = ctx;
  const user = await getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);
  const songId = decodePathParam(ctx, songIdRaw, "song_id");
  if (songId instanceof Response) return songId;
  if (!songId || songId.length > 200) return error("invalid song_id", 400);
  const body = await readJsonBody(ctx);
  if (body instanceof Response) return body;
  const reason = typeof body.reason === "string" ? LYRICS_REPORT_REASONS[body.reason] : undefined;
  if (!reason) return error("invalid reason", 400);
  const note = typeof body.note === "string" ? body.note.trim().slice(0, LYRICS_REPORT_NOTE_MAX) : "";

  const [inactive, rl] = await Promise.all([
    requireActiveUser(ctx, user),
    checkRateLimit(env.DB, user.uid, "edit_request"),
  ]);
  if (inactive) return inactive;
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);
  if (!env.GITHUB_TOKEN) return error("reports are not configured (GITHUB_TOKEN missing)", 503);

  const repo = env.GITHUB_REPO || "fuga-if/idol-live-db";
  const issueBody = [
    `**曲**: \`${songId.replace(/`/g, "")}\``,
    `**理由**: ${reason}`,
    note ? `**補足**:\n\n> ${note.replace(/\n/g, "\n> ")}` : "",
    "",
    "非公開にする: `POST /admin/lyrics/status` (song_ids, status=draft) / 前の版に戻す: `POST /admin/lyrics/:song_id/restore`",
  ].filter((l) => l !== "").join("\n");
  const res = await fetch(`https://api.github.com/repos/${repo}/issues`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "User-Agent": "imas-live-api",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ title: `[歌詞の報告] ${songId} — ${reason}`, body: issueBody, labels: ["lyrics-report"] }),
  });
  if (!res.ok) {
    console.error(`[lyrics-report] github ${res.status}: ${(await res.text()).slice(0, 300)}`);
    return error(`failed to report (github ${res.status})`, 502);
  }
  const issue = (await res.json().catch(() => ({}))) as { html_url?: string };
  const notify = notifyModerators(env, songId, reason, issue.html_url);
  if (ctx.waitUntil) ctx.waitUntil(notify);
  else await notify;
  return json({ ok: true }, 201, NO_STORE);
}

/** 歌詞の報告を #運営 に出す。届かなくても報告そのものは成立しているので投げない。 */
async function notifyModerators(env: RouteContext["env"], songId: string, reason: string, issueUrl?: string): Promise<void> {
  if (!env.DISCORD_BOT_TOKEN || !env.DISCORD_MOD_CHANNEL_ID) return;
  const page = `https://idollivedb.fugaapp.site/songs/${encodeURIComponent(songId)}/`;
  const lines = [
    `🚩 **歌詞の報告** ${md(songId)}（${reason}）`,
    `曲ページ: <${page}>`,
    issueUrl ? `issue: <${issueUrl}>` : "",
  ].filter(Boolean);
  try {
    const ok = await postChannelMessage(env, env.DISCORD_MOD_CHANNEL_ID, {
      content: lines.join("\n"),
      allowed_mentions: { parse: [] },
    });
    if (!ok) console.error("[lyrics-report] discord post failed");
  } catch (e) {
    console.error(`[lyrics-report] discord post failed: ${e}`);
  }
}

export async function handleLyricSubmissions(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;
  const report = path.match(/^\/songs\/([^/]+)\/lyrics-report$/);
  if (report && request.method === "POST") return handleLyricsReport(ctx, report[1]);
  const lineEdit = path.match(/^\/songs\/([^/]+)\/lyric-lines\/([^/]+)$/);
  if (lineEdit && request.method === "PUT") return handleLineEdit(ctx, lineEdit[1], lineEdit[2]);
  const match = path.match(/^\/songs\/([^/]+)\/lyric-submissions$/);
  if (!match || request.method !== "POST") return null;

  const authUser = await getAuthUser(request, env);
  if (!authUser) return error("Unauthorized", 401);
  const inactive = await requireActiveUser(ctx, authUser);
  if (inactive) return inactive;

  const songId = decodePathParam(ctx, match[1], "song_id");
  if (songId instanceof Response) return songId;
  if (!songId || songId.length > 200) return error("invalid song_id", 400);

  const body = await readJsonBody(ctx);
  if (body instanceof Response) return body;
  const result = validateSubmission(body);
  if (!result.ok) return error(result.error, 400);

  const rl = await checkRateLimit(env.DB, authUser.uid, "lyric_submission");
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const id = `lsub_${crypto.randomUUID()}`;
  await env.DB.prepare(
    `INSERT INTO lyric_submissions (id, song_id, user_id, body, line_count) VALUES (?, ?, ?, ?, ?)`
  ).bind(id, songId, authUser.uid, result.body, result.lineCount).run();
  const published = await publishSubmission(ctx, songId, submissionLines(result.body), id);
  return json({ id, song_id: songId, status: "pending", published }, 201, NO_STORE);
}

/**
 * PUT /songs/:song_id/lyric-lines/:line_id — 公開中の歌詞の 1 行だけを直す。
 *
 * 誤字の直しのたびに全文を打ち直させないための口。ボディは投稿と同じ { agreed_to_guideline, text }
 * で、text は 1 行。行の数は変わらないので、行 id・タイミング・歌割・コールはその行に残る
 * (本文が変わってずれたコールには stale が立つ)。扱いは投稿と同じ: その場で公開し、前の版を残し、
 * lyric_submissions に直した後の全文を記録する (確認・BAN 時の一括非公開・奥付が引く)。
 * ⚠️ 応答に本文を返さない。
 */
async function handleLineEdit(ctx: RouteContext, songIdRaw: string, lineIdRaw: string): Promise<Response> {
  const { request, env, json, error, rateLimitResponse } = ctx;
  const authUser = await getAuthUser(request, env);
  if (!authUser) return error("Unauthorized", 401);
  const inactive = await requireActiveUser(ctx, authUser);
  if (inactive) return inactive;
  const songId = decodePathParam(ctx, songIdRaw, "song_id");
  if (songId instanceof Response) return songId;
  const lineId = decodePathParam(ctx, lineIdRaw, "line_id");
  if (lineId instanceof Response) return lineId;
  if (!songId || songId.length > 200 || !lineId || lineId.length > 200) return error("invalid id", 400);

  const body = await readJsonBody(ctx);
  if (body instanceof Response) return body;
  const result = validateSubmission(body);
  if (!result.ok) return error(result.error, 400);
  if (result.lineCount !== 1) return error("text must be a single line", 400);

  const header = await env.DB.prepare("SELECT status, lines_json FROM song_lyrics WHERE song_id = ?")
    .bind(songId).first<{ status: string; lines_json: string | null }>();
  const current = parseLines(header?.status === "published" ? header.lines_json : null);
  const index = current.findIndex((l) => l.id === lineId && l.kind === "lyric");
  if (index < 0) return error("line not found", 404);
  if (current[index]!.text === result.body) return json({ id: null, song_id: songId, line_id: lineId, published: false }, 200, NO_STORE);

  const rl = await checkRateLimit(env.DB, authUser.uid, "edit");
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const lines = current.map((l, i) => ({ kind: l.kind, text: i === index ? result.body : l.text, section: l.section ?? null }));
  const fullText = lines.map((l) => (l.kind === "lyric" ? l.text : "")).join("\n");
  const id = `lsub_${crypto.randomUUID()}`;
  await env.DB.prepare(
    `INSERT INTO lyric_submissions (id, song_id, user_id, body, line_count) VALUES (?, ?, ?, ?, ?)`
  ).bind(id, songId, authUser.uid, fullText, lines.length).run();
  const published = await publishSubmission(ctx, songId, lines, id);
  return json({ id, song_id: songId, line_id: lineId, published }, 200, NO_STORE);
}

/**
 * 投稿を公開する。前の版があれば残してから上書きする。公開したら true。
 * 誰の投稿で公開されたか (published_at) も残す (手応え・歌詞の奥付・BAN 時の一括非公開が引く)。
 */
async function publishSubmission(
  ctx: RouteContext, songId: string, lines: LyricsBody["lines"], submissionId: string
): Promise<boolean> {
  const { env } = ctx;
  const unlicensed = await env.DB.prepare("SELECT 1 AS x FROM lyric_unlicensed_songs WHERE song_id = ?")
    .bind(songId).first();
  if (unlicensed) return false;
  const lyrics = { source: SUBMISSION_SOURCE, status: "published", lines };
  // 1 行が長すぎるなど、歌詞の形に合わないものは公開せず確認待ちに残す。
  if (validateLyricsBody(lyrics)) return false;
  const prev = await env.DB.prepare("SELECT source, status, lines_json FROM song_lyrics WHERE song_id = ?")
    .bind(songId).first<{ source: string | null; status: string; lines_json: string | null }>();
  if (prev?.lines_json) {
    await env.DB.prepare(
      `INSERT INTO song_lyrics_versions (song_id, source, status, lines_json, replaced_by) VALUES (?, ?, ?, ?, ?)`
    ).bind(songId, prev.source, prev.status, prev.lines_json, submissionId).run();
  }
  await storeLyrics(env, songId, lyrics);
  await env.DB.prepare("UPDATE lyric_submissions SET published_at = datetime('now') WHERE id = ?")
    .bind(submissionId).run();
  return true;
}
