// routes/lyric_submissions.ts — 歌詞の投稿 (POST /songs/:song_id/lyric-submissions)。
//
// 利用者が CD の歌詞カードなどの一次ソースを見て入力した歌詞を、確認待ち (pending) として預かる。
// 公開はモデレーターの確認後 (公開の手順は別。ここは song_lyrics に書かない)。
//
// ボディは { source_kind, source_note?, attested_no_copy, text } (アプリの JSON は snake_case)。
// ⚠️ 入力元 (source_kind) と「歌詞サイトから転載していない」の確認 (attested_no_copy: true) が必須。
// ⚠️ 本文の整え方と上限は imas-core domain/lyric_submission.rs と同じ (改行を揃え、行末の空白と
//    前後の空行を落とし、空行の連続を 1 つに。文字数は UTF-16 = .length)。字そのものは変えない。
// ⚠️ 応答に本文を返さない (預かった id と状態だけ)。

import { getAuthUser } from "../auth";
import { checkRateLimit } from "../rate_limit";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody, requireActiveUser } from "./guards";
import { NO_STORE } from "./lyrics";

export const SUBMISSION_MAX_CHARS = 8000;
export const SUBMISSION_MAX_LINES = 400;
export const SOURCE_NOTE_MAX = 200;
export const LYRIC_SOURCE_KINDS = ["booklet", "official", "listening"] as const;
export type LyricSourceKind = (typeof LYRIC_SOURCE_KINDS)[number];

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
  | { ok: true; sourceKind: LyricSourceKind; sourceNote: string | null; body: string; lineCount: number }
  | { ok: false; error: string };

export function validateSubmission(body: Readonly<Record<string, unknown>>): SubmissionResult {
  const { source_kind: sourceKind, source_note: sourceNote, attested_no_copy: attestedNoCopy, text } = body;
  if (typeof sourceKind !== "string" || !(LYRIC_SOURCE_KINDS as readonly string[]).includes(sourceKind)) {
    return { ok: false, error: "source_kind must be booklet, official or listening" };
  }
  if (attestedNoCopy !== true) return { ok: false, error: "attested_no_copy must be true" };
  if (typeof text !== "string") return { ok: false, error: "text must be a string" };
  let note: string | null = null;
  if (sourceNote !== undefined && sourceNote !== null) {
    if (typeof sourceNote !== "string" || sourceNote.length > SOURCE_NOTE_MAX) {
      return { ok: false, error: `source_note must be a string up to ${SOURCE_NOTE_MAX}` };
    }
    note = sourceNote.trim() || null;
  }
  const normalized = normalizeLyricText(text);
  if (!normalized) return { ok: false, error: "text is empty" };
  if (normalized.length > SUBMISSION_MAX_CHARS) return { ok: false, error: `text must be up to ${SUBMISSION_MAX_CHARS}` };
  const lineCount = normalized.split("\n").length;
  if (lineCount > SUBMISSION_MAX_LINES) return { ok: false, error: `text must be up to ${SUBMISSION_MAX_LINES} lines` };
  return { ok: true, sourceKind: sourceKind as LyricSourceKind, sourceNote: note, body: normalized, lineCount };
}

export async function handleLyricSubmissions(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;
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
    `INSERT INTO lyric_submissions (id, song_id, user_id, source_kind, source_note, body, line_count)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).bind(id, songId, authUser.uid, result.sourceKind, result.sourceNote, result.body, result.lineCount).run();
  return json({ id, song_id: songId, status: "pending" }, 201, NO_STORE);
}
