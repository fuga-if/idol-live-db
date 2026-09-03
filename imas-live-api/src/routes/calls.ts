// routes/calls.ts — コールガイドの保存 (PUT /songs/:song_id/calls)。
//
// 読み出し専用のエンドポイントは作らない。コールは歌詞行に埋まっているので、既存の
// GET /songs/:id/lyrics と GET /songs/:id/detail の応答にそのまま乗る
// (routes/lyrics.ts の buildLyricsPayload が clap / calls を含める)。
// コール単体の GET を足すと、歌詞と同じ「1リクエスト1曲・認証必須」の枠から外れた
// 取得経路がもう 1 本できてしまう。
//
// ⚠️ この経路で歌詞本文は書き換えられない。ボディは行 ID と clap / calls だけで、
//    本文は D1 の既存行が唯一の正 (アンカー文字列もサーバが本文から切り出す)。
//    「コール編集の権限で歌詞が書き換わる」経路を作らないための構造。
//
// ⚠️ PUT なので**曲のコール全体の全置換**。ボディに現れない行のコールは消える。
//    部分更新にしないのは、削除を表現するための特別扱いを増やさないためと、
//    1 曲あたりのコール総数上限をボディだけで正確に判定できるようにするため。
//
// 検証・正規化の実装は src/lyrics_calls.ts が唯一の正。ここは HTTP と D1 の面倒だけ見る。

import { getAuthUser } from "../auth";
import { checkRateLimit } from "../rate_limit";
import { validateCallsBody } from "../lyrics_calls";
import { authorizeLyricsWrite, buildLyricsPayload, parseLines, NO_STORE } from "./lyrics";
import type { LyricLineRow } from "./lyrics";
import type { RouteContext } from "./context";

export async function handleLyricsCalls(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;

  const match = path.match(/^\/songs\/([^/]+)\/calls$/);
  if (!match || request.method !== "PUT") return null;

  // コールは**ユーザーが書くもの**なので、ログインしていれば誰でも通す。
  // 歌詞本文の投入 (PUT /admin/lyrics/:id) とは権限が違う — この経路では本文を
  // 書き換えられない構造にしてあるので (ファイル冒頭)、開けても歌詞は守られる。
  //
  // タグ等の投稿と同じ形にそろえてある: ログイン必須 + is_banned + "edit" レート枠。
  // 荒らしの速度を落とす一次防御で、権限の細分化はしない
  // (モデレーターはフラットに全権。判定を増やすと運用が破綻する)。
  const operator = await authorizeLyricsWrite(request, env);
  let subject: string;
  if (operator) {
    subject = operator;
  } else {
    const authUser = await getAuthUser(request, env);
    if (!authUser) return error("Unauthorized", 401);
    const banned = await env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
      .bind(authUser.uid)
      .first<{ is_banned: number }>();
    if (banned?.is_banned) return error("Banned", 403);
    subject = authUser.uid;
  }

  let songId: string;
  try {
    songId = decodeURIComponent(match[1]);
  } catch {
    return error("invalid song_id", 400);
  }
  if (!songId || songId.length > 200) return error("invalid song_id", 400);

  // 歌詞が無い曲にはコールを付けられない (紐づける行 ID が存在しない)。
  const header = await env.DB.prepare(
    "SELECT source, status, updated_at, lines_json FROM song_lyrics WHERE song_id = ?"
  )
    .bind(songId)
    .first<{ source: string | null; status: string; updated_at: string;
             lines_json: string | null }>();
  if (!header) return error("lyrics not found", 404);

  const existing = parseLines(header.lines_json);
  const body = await request.json().catch(() => null);
  // 歌詞 PUT と同じ作法で、検証を済ませてからレート枠を消費する。
  const result = validateCallsBody(
    body,
    new Map(existing.map((l) => [l.id, l.text ?? ""]))
  );
  if (!result.ok) return error(result.error, 400);

  // 運用者は専用枠、一般ユーザーは編集系と共有の "edit" 枠 (タグ・マスタ編集と同じ)。
  const rl = await checkRateLimit(env.DB, subject, operator ? "lyrics_calls" : "edit");
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const byId = new Map(result.lines.map((l) => [l.id, l]));
  const nextLines: LyricLineRow[] = existing.map((line) => {
    const annotation = byId.get(line.id);
    return {
      ...line,
      // ボディに現れない行はコール無しに戻す (PUT = 全置換)。
      clap: annotation?.clap ?? null,
      calls: annotation?.calls ?? [],
    };
  });

  await env.DB.prepare(
    "UPDATE song_lyrics SET lines_json = ?, updated_at = datetime('now') WHERE song_id = ?"
  )
    .bind(JSON.stringify(nextLines), songId)
    .run();

  // 保存後の姿をそのまま返す (GET と同じ形 + status)。編集画面が再取得せずに済む。
  const saved = await env.DB.prepare(
    "SELECT source, status, updated_at, lines_json FROM song_lyrics WHERE song_id = ?"
  )
    .bind(songId)
    .first<{ source: string | null; status: string; updated_at: string;
             lines_json: string | null }>();
  const payload = buildLyricsPayload(
    songId,
    saved ?? { source: null, updated_at: null },
    parseLines(saved?.lines_json ?? null)
  );
  // 応答には歌詞本文が含まれる。歌詞と同じく no-store。
  return json({ ...payload, status: saved?.status ?? header.status }, 200, NO_STORE);
}
