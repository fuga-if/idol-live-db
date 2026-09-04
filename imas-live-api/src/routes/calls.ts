// routes/calls.ts — コールガイドの保存 (PUT /songs/:song_id/calls) と
//                    整備状況の一覧 (GET /calls/dashboard)。
//
// **コール本文の読み出し口は作らない。** コールは歌詞行に埋まっているので、既存の
// GET /songs/:id/lyrics と GET /songs/:id/detail の応答にそのまま乗る
// (routes/lyrics.ts の buildLyricsPayload が clap / calls を含める)。
// コール単体の GET を足すと、歌詞と同じ「1リクエスト1曲・認証必須」の枠から外れた
// 取得経路がもう 1 本できてしまう。
//
// 読み口はこのファイルに 1 本だけある: **GET /calls/dashboard**。
// 返すのは song_id と件数・日時・編集者の表示名だけで、コール本文もアンカー文字列も
// 歌詞本文も一切含まない。歌詞と同じ枠を作った理由は「歌詞と、歌詞の断片が一括で
// 取れる経路を作らない」ことなので、断片を含まないメタデータの一覧はその枠の外にある。
//
// ⚠️ **この応答に text / anchorText を足さないこと。** 足した瞬間に、エッジキャッシュ
//    (public, max-age) に歌詞の断片が載る。この 1 行がこのファイルで最も重要な制約。
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
import { maskDisplayName } from "../feed";
import {
  appendCallEditHistory,
  callStatsUpsertStatement,
  countCallAnnotations,
  isCallAnnotationUnchanged,
  buildCallEditSummary,
} from "../call_stats";
import {
  authorizeLyricsWrite,
  buildLyricsPayload,
  parseLines,
  sqliteTimestampToEpochSeconds,
  NO_STORE,
} from "./lyrics";
import type { LyricLineRow } from "./lyrics";
import type { RouteContext } from "./context";

/** 運用者トークン (X-Push-Token) の主体名。authorizeLyricsWrite が返す固定値。 */
const OPERATOR_SUBJECT = "__lyrics_push__";

/** GET /calls/dashboard のエッジキャッシュキー (PUT 後の破棄に使う)。
 *  index.ts のキー生成 (URL のみ・GET) と必ず同じ形にすること。 */
export function callsDashboardCacheKey(origin: string): Request {
  return new Request(`${origin}/calls/dashboard`, { method: "GET" });
}

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

  // 整備量は保存する形から数えるだけなので、D1 の追加読み取りは 0 回。
  const before = countCallAnnotations(existing);
  const after = countCallAnnotations(nextLines);
  const unchanged =
    JSON.stringify(nextLines) === header.lines_json ||
    isCallAnnotationUnchanged(existing, nextLines);
  // 運用者トークンでの一括投入は「みんなの編集」ではないので編集者として記録しない
  // (admin のセッション JWT はその人の編集なので記録する)。
  const editorUid = subject === OPERATOR_SUBJECT ? null : subject;

  // 歌詞行と統計を 1 トランザクションで書く。batch なので「歌詞側だけ書けて統計が
  // 古いまま」は起きない。無変更の保存では統計に触らない (updated_at を動かすと
  // 「最近整備された順」の並びが中身の無い保存で乱れる)。
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      "UPDATE song_lyrics SET lines_json = ?, updated_at = datetime('now') WHERE song_id = ?"
    ).bind(JSON.stringify(nextLines), songId),
  ];
  if (!unchanged) {
    statements.push(callStatsUpsertStatement(env.DB, songId, after, editorUid));
  }
  await env.DB.batch(statements);

  // 履歴は副次データ。書けなくても保存は成功として返す (routes/lyrics.ts の索引更新と
  // 同じ方針: 副次データの都合でユーザーの保存を失敗にしない)。
  if (!unchanged && editorUid) {
    try {
      await appendCallEditHistory(env.DB, songId, editorUid, before, after);
    } catch (err) {
      console.error("call_edit_history_append_failed", songId, err);
    }
  }

  // 自分の編集がすぐ一覧に出ないと「保存できていない」と誤解される。Cache API の delete は
  // 自コロのみで、他コロは max-age で自然に切れる (最大 30 分)。それでよい種類のズレ。
  if (!unchanged && ctx.waitUntil) {
    ctx.waitUntil(
      caches.default
        .delete(callsDashboardCacheKey(ctx.url.origin))
        .catch((err) => console.error("calls_dashboard_cache_purge_failed", err))
    );
  }

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

// ---------------------------------------------------------------------------
// GET /calls/dashboard — コールガイドの整備状況 (1 画面 1 リクエスト)
// ---------------------------------------------------------------------------
//
// 3 つの問いに 1 本で答える:
//   ① コールガイドがある曲はどれか (最近整備された順)
//   ② 最近だれが何を書いたか
//   ③ 「コール曲」タグが付いているのにコールガイドが無い曲はどれか (書く人の導線)
//
// 曲名は返さない。D1 に曲マスタは無く (0019 で drop)、名前は端末の master.sqlite が
// 解決する。GET /tags/activity と同じ役割分担。

// 濫用対策の内訳:
//   読みの物量        エッジキャッシュ (max-age=1800) + パラメータ無し = キーは 1 つ。
//                     ミスは 1 コロ 30 分に 1 回。
//   クローンただ乗り  isCommunityRead に登録 (X-App-Token or ログイン)。
//                     ⚠️ この判定はキャッシュ**ミス時のみ**走る — index.ts はエッジ
//                     キャッシュ命中を App Attest ゲートより前で返すため。
//                     「未検証クライアントは 1 回も読めない」保証にはならない。
//   応答サイズ        200 / 30 / 100 のサーバ定数上限。上限に達しても ~35KB。
//   書きの連打        既存の "edit" 枠 (100/日)。運用者は "lyrics_calls" 枠。
//   履歴の肥大        30 分まとめ + cron で 180 日切り (apply.ts)。
//   情報露出          曲 id / 件数 / 日時 / マスク済み表示名のみ。
//                     uid・歌詞・コール本文・アンカーは一切含まない。

/** 一覧の上限。クエリパラメータは受け付けない (キャッシュキーを 1 つに保つため、
 *  可変にするとパラメータ違いでキャッシュを空撃ちさせられる)。 */
const DASHBOARD_SONGS_LIMIT = 200;
const DASHBOARD_EDITS_LIMIT = 30;
const DASHBOARD_TODO_LIMIT = 100;
/** ③ の母集合 (タグが付いた曲) を数えるときの安全上限。曲数 (~2,100) より十分大きい。 */
const DASHBOARD_TAGGED_SCAN_LIMIT = 5000;

/** 「コール曲」タグ。id ではなく名前で引く — slug 規則の変更やタグの作り直しに耐えるため。 */
const CALL_TAG_NAME = "コール曲";

/** コールが増えるのは人が保存したときだけ。書いた本人には PUT 側のキャッシュ破棄で
 *  すぐ見える (自コロのみ・best effort)。他コロは最大 30 分遅れる。 */
const DASHBOARD_CACHE_HEADERS: Record<string, string> = {
  "Cache-Control": "public, max-age=1800",
};

interface CallStatsRow {
  song_id: string;
  call_lines: number;
  call_count: number;
  updated_at: string | null;
  updated_by_name: string | null;
}

interface CallHistoryRow {
  id: number;
  song_id: string;
  at: string | null;
  call_lines_before: number;
  call_lines_after: number;
  call_count_before: number;
  call_count_after: number;
  by_name: string | null;
}

interface TaggedRow {
  song_id: string;
  has_lyrics: number;
  has_calls: number;
}

export async function handleCallsDashboard(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json } = ctx;
  if (path !== "/calls/dashboard" || request.method !== "GET") return null;

  // タグは名前で引く。無い/削除済みなら ③ を空にして 200 を返す (500 にしない —
  // ①② は独立して意味があり、タグの有無で画面全体を落とす理由が無い)。
  const tag = await env.DB.prepare(
    "SELECT id, name FROM tags WHERE name = ? AND status != 'removed'"
  )
    .bind(CALL_TAG_NAME)
    .first<{ id: string; name: string }>();

  const [statsRows, historyRows, taggedRows] = await Promise.all([
    // ① コールガイドのある曲。表示名は users を LEFT JOIN してマスクする (生 uid は返さない)。
    env.DB.prepare(
      `SELECT s.song_id, s.call_lines, s.call_count, s.updated_at,
              u.display_name AS updated_by_name
         FROM song_call_stats s
         LEFT JOIN users u ON u.id = s.updated_by_uid
        WHERE s.call_lines > 0
        ORDER BY s.updated_at DESC
        LIMIT ?`
    )
      .bind(DASHBOARD_SONGS_LIMIT)
      .all<CallStatsRow>(),

    // ② 最近の編集。30 分まとめで at が動くので id 順ではなく at 順。
    env.DB.prepare(
      `SELECT h.id, h.song_id, h.at, h.call_lines_before, h.call_lines_after,
              h.call_count_before, h.call_count_after, u.display_name AS by_name
         FROM call_edit_history h
         LEFT JOIN users u ON u.id = h.user_id
        ORDER BY h.at DESC, h.id DESC
        LIMIT ?`
    )
      .bind(DASHBOARD_EDITS_LIMIT)
      .all<CallHistoryRow>(),

    // ③ + 内訳。song_tags の走査は 1 回だけにする (一覧と内訳で 2 回舐めない)。
    //   票数の多い順 = みんなが「コール曲」だと思っている順。
    tag
      ? env.DB.prepare(
          `SELECT st.song_id,
                  CASE WHEN sl.song_id IS NULL THEN 0 ELSE 1 END AS has_lyrics,
                  CASE WHEN COALESCE(cs.call_lines, 0) > 0 THEN 1 ELSE 0 END AS has_calls
             FROM song_tags st
             LEFT JOIN song_lyrics sl ON sl.song_id = st.song_id AND sl.status = 'published'
             LEFT JOIN song_call_stats cs ON cs.song_id = st.song_id
            WHERE st.tag_id = ?
            ORDER BY st.vote_count DESC, st.song_id
            LIMIT ?`
        )
          .bind(tag.id, DASHBOARD_TAGGED_SCAN_LIMIT)
          .all<TaggedRow>()
      : Promise.resolve({ results: [] as TaggedRow[] }),
  ]);

  const tagged = taggedRows.results ?? [];
  // 歌詞が未登録の曲は「書く」導線に並べない。PUT /songs/:id/calls が 404 になるので、
  // 並べると行き止まりを作ることになる。外した数は callTag.withoutLyrics で素直に見せる。
  const todo = tagged
    .filter((r) => r.has_lyrics === 1 && r.has_calls === 0)
    .slice(0, DASHBOARD_TODO_LIMIT)
    .map((r) => r.song_id);

  return json(
    {
      generatedAt: Math.floor(Date.now() / 1000),
      songsWithCalls: (statsRows.results ?? [])
        .slice(0, DASHBOARD_SONGS_LIMIT)
        .map((r) => ({
          songId: r.song_id,
          callLines: r.call_lines,
          callCount: r.call_count,
          updatedAt: sqliteTimestampToEpochSeconds(r.updated_at),
          // 記録が無ければ "匿名"。iOS 側の Optional 分岐を増やさないため必ず文字列。
          updatedBy: maskDisplayName(r.updated_by_name),
        })),
      recentEdits: (historyRows.results ?? [])
        .slice(0, DASHBOARD_EDITS_LIMIT)
        .map((r) => ({
          id: r.id,
          songId: r.song_id,
          at: sqliteTimestampToEpochSeconds(r.at),
          by: maskDisplayName(r.by_name),
          callLinesBefore: r.call_lines_before,
          callLinesAfter: r.call_lines_after,
          callCountBefore: r.call_count_before,
          callCountAfter: r.call_count_after,
          // 監査用の機械文字列。表示文言はクライアントが 4 つの数から組み立てる。
          summary: buildCallEditSummary(
            { callLines: r.call_lines_before, callCount: r.call_count_before },
            { callLines: r.call_lines_after, callCount: r.call_count_after }
          ),
        })),
      taggedWithoutCalls: todo,
      callTag: tag
        ? {
            tagId: tag.id,
            tagName: tag.name,
            tagged: tagged.length,
            withCalls: tagged.filter((r) => r.has_calls === 1).length,
            withoutLyrics: tagged.filter((r) => r.has_lyrics === 0).length,
          }
        : null,
    },
    200,
    DASHBOARD_CACHE_HEADERS
  );
}
