// routes/lyrics.ts — 歌詞配信 (最小構成)。
//
// ⚠️ 歌詞本文は D1 にしか存在しない。db/master.sql / ImasLiveDB/Resources/master.sqlite /
//    CloudKit には絶対に入れない。JASRAC 許諾の条件が「ユーザが一括ダウンロードできない
//    形式での配信」であり、bundle SQLite も CloudKit 同期も一括ダウンロードそのもの。
//
// ⚠️ 1リクエスト = 高々1曲。複数 song_id をまとめて要求できる構文
//    (配列パラメータ / カンマ区切り / バッチ POST) を後から足さないこと。
//    まとめ取りができた時点で「一括ダウンロードできない形式」ではなくなる。
//
// ⚠️ このルートを index.ts の isCommunityRead に足さないこと。
//    GET が Authorization を必須にしていることで index.ts:373 の edgeCacheEligible
//    (= !request.headers.get("Authorization")) が false になり、エッジキャッシュから
//    自動的に外れる。加えて歌詞応答には Cache-Control: no-store を付ける。
//
// タイムスタンプは datetime('now') 形式 (UTC・空白区切り・ミリ秒なし) に統一する。
// 理由は migrations/0026_song_lyrics.sql の先頭コメントを参照。
// このファイルは日時文字列を JS 側で組み立てず、必ず SQL の datetime('now') で書く。

import { getAuthUser } from "../auth";
import { checkRateLimit, dryCheckIpRateLimit, commitIpRateLimit } from "../rate_limit";
import { checkIsAdmin } from "../users";
import type { RouteContext } from "./context";

// tools/lyrics/lyrics_json.py の MAX_LINES / MAX_LINE_CHARS と同値にしてある。
// 手元の検証を通ったものがサーバで弾かれる (またはその逆) 状態を作らないため。
const MAX_LINES = 400;
const MAX_LINE_CHARS = 200;
const MAX_SOURCE_CHARS = 200;
const MAX_SECTION_CHARS = 32;

const LINE_KINDS = new Set(["lyric", "marker", "blank"]);
const LYRIC_STATUSES = new Set(["draft", "published"]);

/** 歌詞応答は端末にもエッジにも残さない (許諾条件の「一括ダウンロード不可」の実効性)。 */
const NO_STORE: Record<string, string> = { "Cache-Control": "no-store" };

interface LyricLineRow {
  id: string;
  ord: number;
  kind: string;
  text: string;
  section: string | null;
  start_ms: number | null;
}

/**
 * "2026-08-05 12:00:00" (SQLite datetime('now') 形式・UTC) を epoch 秒に変換する。
 * iOS の APIClient が .secondsSince1970 でデコードするため、応答は必ず秒 epoch の数値。
 * ミリ秒や ISO 文字列にすると iOS 側のデコードが落ちる。
 */
function sqliteTimestampToEpochSeconds(ts: string | null | undefined): number {
  if (!ts) return 0;
  const ms = Date.parse(ts.replace(" ", "T") + "Z");
  return Number.isNaN(ms) ? 0 : Math.floor(ms / 1000);
}

/** iOS と合意済みの応答形状。キーは camelCase、updatedAt は秒 epoch。 */
function buildLyricsPayload(
  songId: string,
  header: { source: string | null; updated_at: string | null },
  lines: LyricLineRow[]
) {
  return {
    songId,
    source: header.source,
    updatedAt: sqliteTimestampToEpochSeconds(header.updated_at),
    lines: lines.map((l) => ({
      id: l.id,
      ord: l.ord,
      kind: l.kind,
      text: l.text,
      section: l.section,
      // start_ms は将来の再生連動用。書き込み経路が無いので現状は常に null。
      startMs: l.start_ms,
    })),
  };
}

async function fetchLines(db: D1Database, songId: string): Promise<LyricLineRow[]> {
  // ord の同値はありえない想定だが、順序を決定的にするため id を第二キーに置く。
  const { results } = await db
    .prepare(
      `SELECT id, ord, kind, text, section, start_ms
         FROM lyric_lines WHERE song_id = ? ORDER BY ord, id`
    )
    .bind(songId)
    .all<LyricLineRow>();
  return results ?? [];
}

/** PUT のボディ検証。問題があればエラーメッセージ、無ければ null。 */
function validateLyricsBody(body: unknown): string | null {
  if (!body || typeof body !== "object") return "body must be an object";
  const { source, status, lines } = body as Record<string, unknown>;

  if (source !== undefined && source !== null) {
    if (typeof source !== "string") return "source must be a string";
    if (source.length > MAX_SOURCE_CHARS) return `source too long (max ${MAX_SOURCE_CHARS})`;
  }
  if (typeof status !== "string" || !LYRIC_STATUSES.has(status)) {
    return "status must be 'draft' or 'published'";
  }
  if (!Array.isArray(lines) || lines.length === 0) return "lines must be a non-empty array";
  if (lines.length > MAX_LINES) return `too many lines (${lines.length} > ${MAX_LINES})`;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line || typeof line !== "object") return `lines[${i}] must be an object`;
    const { kind, text, section } = line as Record<string, unknown>;
    if (kind !== undefined && (typeof kind !== "string" || !LINE_KINDS.has(kind))) {
      return `lines[${i}].kind must be one of lyric/marker/blank`;
    }
    if (text !== undefined && text !== null && typeof text !== "string") {
      return `lines[${i}].text must be a string`;
    }
    const t = typeof text === "string" ? text : "";
    // 1行1要素が前提 (行 ID をコールの紐付け先にするため)。改行入りを通すと
    // 1行が事実上の複数行になり、行 ID の意味が壊れる。
    if (/[\r\n]/.test(t)) return `lines[${i}].text must not contain a newline`;
    if (t.length > MAX_LINE_CHARS) return `lines[${i}].text too long (max ${MAX_LINE_CHARS})`;
    if (section !== undefined && section !== null) {
      if (typeof section !== "string") return `lines[${i}].section must be a string`;
      if (section.length > MAX_SECTION_CHARS) return `lines[${i}].section too long`;
    }
  }
  return null;
}

export async function handleLyrics(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse, rateLimitSimple } = ctx;

  // ----------------------------------------------------------------
  // GET /songs/:song_id/lyrics — 1曲ぶんの歌詞 (セッション JWT 必須)
  //   song_id は percent-encoded ("765as_%E8%92%BC%E3%81%84%E9%B3%A5" 等)。
  // ----------------------------------------------------------------
  const getMatch = path.match(/^\/songs\/([^/]+)\/lyrics$/);
  if (getMatch && request.method === "GET") {
    const user = await getAuthUser(request, env);
    // 認証必須。未認証を通すと edgeCacheEligible の対象になり、歌詞がエッジに載りうる。
    if (!user) return error("Unauthorized", 401);

    let songId: string;
    try {
      songId = decodeURIComponent(getMatch[1]);
    } catch {
      return error("invalid song_id", 400);
    }

    // ⚠️ レート制限より先に 404 を返す。存在しない曲を叩かれても枠を減らさない
    //    ためで、POST /users/me と同じ作法。
    const header = await env.DB.prepare(
      `SELECT source, updated_at FROM song_lyrics
        WHERE song_id = ? AND status = 'published'`
    )
      .bind(songId)
      .first<{ source: string | null; updated_at: string }>();
    if (!header) return error("lyrics not found", 404);

    // 日次上限は置かない (rate_limit.ts のコメント参照)。IP 単位のバースト制限
    // だけを掛ける。人間が1分に30曲読むことはないので正常利用には当たらず、
    // クライアントの暴走やスクリプトによる連打だけを抑える。
    // 成功が確定してから commit する (404 等で枠を消費させない)。
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const ipRl = await dryCheckIpRateLimit(env.DB, ip);
    if (!ipRl.allowed) return rateLimitSimple();

    const lines = await fetchLines(env.DB, songId);
    await commitIpRateLimit(env.DB, ip, ipRl.bucket);
    return json(buildLyricsPayload(songId, header, lines), 200, NO_STORE);
  }

  // ----------------------------------------------------------------
  // PUT /admin/lyrics/:song_id — 歌詞の投入・差し替え (モデレーターのみ)
  // ----------------------------------------------------------------
  const putMatch = path.match(/^\/admin\/lyrics\/([^/]+)$/);
  if (putMatch && request.method === "PUT") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);
    if (!(await checkIsAdmin(env, user.uid))) return error("Forbidden", 403);

    let songId: string;
    try {
      songId = decodeURIComponent(putMatch[1]);
    } catch {
      return error("invalid song_id", 400);
    }
    if (!songId || songId.length > 200) return error("invalid song_id", 400);

    const body = await request.json().catch(() => null);
    // GET と同じ理由で検証を先に済ませてからレート枠を消費する。
    const invalid = validateLyricsBody(body);
    if (invalid) return error(invalid, 400);

    const rl = await checkRateLimit(env.DB, user.uid, "lyrics_admin");
    if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

    const { source, status, lines } = body as {
      source?: string | null;
      status: string;
      lines: Array<{ kind?: string; text?: string | null; section?: string | null }>;
    };

    // ⚠️ 全消し全入れにしない。行 ID は発行後不変という契約 (将来コールがこの ID を
    //    参照する) なので、ord 順に既存 id を再利用し、過不足だけ INSERT / DELETE する。
    const { results: existingRows } = await env.DB.prepare(
      "SELECT id FROM lyric_lines WHERE song_id = ? ORDER BY ord, id"
    )
      .bind(songId)
      .all<{ id: string }>();
    const existingIds = (existingRows ?? []).map((r) => r.id);

    const statements: D1PreparedStatement[] = [
      env.DB.prepare(
        `INSERT INTO song_lyrics (song_id, source, status, first_published_at, created_at, updated_at)
         VALUES (?, ?, ?, CASE WHEN ? = 'published' THEN datetime('now') ELSE NULL END,
                 datetime('now'), datetime('now'))
         ON CONFLICT(song_id) DO UPDATE SET
           source = excluded.source,
           status = excluded.status,
           -- 初回 published の時刻だけを残す。published→draft→published と往復しても
           -- 報告母集団の基準がずれないよう COALESCE で上書きを防ぐ。
           first_published_at = COALESCE(
             song_lyrics.first_published_at,
             CASE WHEN excluded.status = 'published' THEN datetime('now') ELSE NULL END),
           updated_at = datetime('now')`
      ).bind(songId, source ?? null, status, status),
    ];

    for (let i = 0; i < lines.length; i++) {
      const kind = lines[i].kind ?? "lyric";
      const text = lines[i].text ?? "";
      const section = lines[i].section ?? null;
      if (i < existingIds.length) {
        // start_ms は触らない (将来この列を埋めたとき、本文修正で消さないため)。
        statements.push(
          env.DB.prepare(
            "UPDATE lyric_lines SET ord = ?, kind = ?, text = ?, section = ? WHERE id = ?"
          ).bind(i, kind, text, section, existingIds[i])
        );
      } else {
        statements.push(
          env.DB.prepare(
            `INSERT INTO lyric_lines (id, song_id, ord, kind, text, section)
             VALUES (?, ?, ?, ?, ?, ?)`
          ).bind("ll_" + crypto.randomUUID(), songId, i, kind, text, section)
        );
      }
    }

    // 減った分だけ末尾を削る。
    const surplus = existingIds.slice(lines.length);
    if (surplus.length > 0) {
      const placeholders = surplus.map(() => "?").join(", ");
      statements.push(
        env.DB.prepare(`DELETE FROM lyric_lines WHERE id IN (${placeholders})`).bind(...surplus)
      );
    }

    await env.DB.batch(statements);

    const header = await env.DB.prepare(
      "SELECT source, status, updated_at FROM song_lyrics WHERE song_id = ?"
    )
      .bind(songId)
      .first<{ source: string | null; status: string; updated_at: string }>();
    const saved = await fetchLines(env.DB, songId);
    // GET と同じ形 + status (投入ツールが公開状態を確認できるように)。
    const payload = buildLyricsPayload(songId, header ?? { source: null, updated_at: null }, saved);
    return json({ ...payload, status: header?.status ?? status }, 200, NO_STORE);
  }

  return null;
}
