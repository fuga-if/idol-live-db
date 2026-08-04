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
import { carryOverAnnotation } from "../lyrics_calls";
import type { ClapKind, LyricCall } from "../lyrics_calls";
import type { RouteContext } from "./context";
import type { Env } from "../env";

// tools/lyrics/lyrics_json.py の MAX_LINES / MAX_LINE_CHARS と同値にしてある。
// 手元の検証を通ったものがサーバで弾かれる (またはその逆) 状態を作らないため。
const MAX_LINES = 400;
const MAX_LINE_CHARS = 200;
const MAX_SOURCE_CHARS = 200;
const MAX_SECTION_CHARS = 32;

const LINE_KINDS = new Set(["lyric", "marker", "blank"]);
const LYRIC_STATUSES = new Set(["draft", "published"]);

/** 歌詞応答は端末にもエッジにも残さない (許諾条件の「一括ダウンロード不可」の実効性)。 */
export const NO_STORE: Record<string, string> = { "Cache-Control": "no-store" };

export interface LyricLineRow {
  id: string;
  ord: number;
  kind: string;
  text: string;
  section: string | null;
  start_ms: number | null;
  /** migration 0027 が書いた行だけキーが startMs になっている (下の buildLyricsPayload 参照)。 */
  startMs?: number | null;
  // ---- コールガイド (src/lyrics_calls.ts が唯一の実装) ----
  // コールは歌詞行と同じ JSON に埋める。別テーブルにすると、歌詞 1 曲の取得を
  // D1 の行読み取り 1 回に収めるという lines_json の存在理由が壊れる。
  clap?: ClapKind | null;
  calls?: LyricCall[];
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
export function buildLyricsPayload(
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
      // migration 0027 が JSON 化した行だけキーが startMs なので両方を見る。
      startMs: l.start_ms ?? l.startMs ?? null,
      // ---- コールガイド ----
      // 保存済みの値をそのまま通す (検証は書き込み時に済ませてある)。コール未設定の曲・
      // 0027 以前から在る行では clap: null / calls: [] になる。
      clap: l.clap ?? null,
      calls: l.calls ?? [],
    })),
  };
}

/**
 * 保存された lines_json を行の配列に戻す。壊れていたら空配列。
 *
 * 行を別テーブルではなく JSON 1 列で持つのは D1 の行読み取り上限のため
 * (migration 0027 のコメント参照)。1 曲 60 行を別テーブルに持つと歌詞 1 曲の
 * 取得で 60 行読み、Worker のリクエスト上限より先に D1 が上限に当たる。
 */
export function parseLines(linesJson: string | null): LyricLineRow[] {
  if (!linesJson) return [];
  try {
    const parsed = JSON.parse(linesJson);
    return Array.isArray(parsed) ? (parsed as LyricLineRow[]) : [];
  } catch {
    // 壊れた JSON で曲詳細ごと落とさない。歌詞だけ空で返す。
    console.log("lyrics_lines_json_parse_failed");
    return [];
  }
}

/**
 * 公開済み (status='published') の歌詞を 1 曲ぶん取得する。無ければ null。
 *
 * 曲詳細バンドル (routes/song_detail.ts) 用。GET /songs/:id/lyrics は 404 を
 * レート制限より前に返す必要があるため header 取得と行取得を分けたままにしてあり、
 * この関数は使わない (どちらも parseLines / buildLyricsPayload を共有する)。
 *
 * ⚠️ 呼び出し側は「認証済みであること」と「応答に Cache-Control: no-store を付けること」を
 *    必ず守ること。歌詞は JASRAC 許諾の条件上、共有キャッシュに置いてはならない。
 */
export async function fetchPublishedLyrics(
  db: D1Database,
  songId: string,
  includeDraft = false
): Promise<(ReturnType<typeof buildLyricsPayload> & { status: string }) | null> {
  const header = await db
    .prepare(
      `SELECT source, updated_at, lines_json, status FROM song_lyrics
        WHERE song_id = ? AND (status = 'published' OR ?)`
    )
    .bind(songId, includeDraft ? 1 : 0)
    .first<{ source: string | null; updated_at: string; lines_json: string | null;
             status: string }>();
  if (!header) return null;
  // 行は同じ 1 行に JSON で入っているので、追加の読み取りは発生しない。
  return { ...buildLyricsPayload(songId, header, parseLines(header.lines_json)),
           status: header.status };
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
    const { kind, text, section, clap, calls } = line as Record<string, unknown>;
    // コールはこの経路では受け取らない。歌詞の差し替えでは既存行から自動で引き継ぐので、
    // ここで受けると「送ったのに反映されない」か「引き継ぎと二重管理」のどちらかになる。
    if (clap !== undefined || calls !== undefined) {
      return `lines[${i}]: clap/calls must be sent to PUT /songs/:song_id/calls`;
    }
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

/** 長さに依存しない比較。トークンの推測を時間差から助けない。 */
function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

/** 歌詞の書き込み権限。運用者トークン、または admin のセッション JWT。
 *  レート制限の主体に使う文字列を返す (拒否なら null)。
 *  コール保存 (routes/calls.ts) も同じ権限で通す。判定を 2 か所に増やさないこと。 */
export async function authorizeLyricsWrite(request: Request, env: Env): Promise<string | null> {
  const pushToken = request.headers.get("X-Push-Token");
  if (pushToken && env.LYRICS_PUSH_TOKEN && timingSafeEqual(pushToken, env.LYRICS_PUSH_TOKEN)) {
    // 運用者は1人なので固定の主体でよい。uid 空間と衝突しない名前にする。
    return "__lyrics_push__";
  }
  const user = await getAuthUser(request, env);
  if (!user) return null;
  return (await checkIsAdmin(env, user.uid)) ? user.uid : null;
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
    // 未公開 (draft) は admin にだけ返す。JASRAC の許諾が下りるまで一般ユーザーには
    // 配信できないが、開発中のプレビューは必要なため。
    // ⚠️ ビルド種別 (DEBUG) では判定しない。クライアントの自己申告は信用できず、
    //    Release ビルドを改変されると防げないので、サーバ側の権限で切る。
    const header = await env.DB.prepare(
      `SELECT source, updated_at, lines_json, status FROM song_lyrics WHERE song_id = ?`
    )
      .bind(songId)
      .first<{ source: string | null; updated_at: string; lines_json: string | null;
               status: string }>();
    if (!header) return error("lyrics not found", 404);
    if (header.status !== "published" && !(await checkIsAdmin(env, user.uid))) {
      // 存在自体を伏せる必要はないが、公開済みと同じ 404 に揃える。
      return error("lyrics not found", 404);
    }

    // 日次上限は置かない (rate_limit.ts のコメント参照)。IP 単位のバースト制限
    // だけを掛ける。人間が1分に30曲読むことはないので正常利用には当たらず、
    // クライアントの暴走やスクリプトによる連打だけを抑える。
    // 成功が確定してから commit する (404 等で枠を消費させない)。
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const ipRl = await dryCheckIpRateLimit(env.DB, ip);
    if (!ipRl.allowed) return rateLimitSimple();

    const lines = parseLines(header.lines_json);
    await commitIpRateLimit(env.DB, ip, ipRl.bucket);
    return json({ ...buildLyricsPayload(songId, header, lines), status: header.status },
                200, NO_STORE);
  }

  // ----------------------------------------------------------------
  // PUT /admin/lyrics/:song_id — 歌詞の投入・差し替え (モデレーターのみ)
  // ----------------------------------------------------------------
  const putMatch = path.match(/^\/admin\/lyrics\/([^/]+)$/);
  if (putMatch && request.method === "PUT") {
    // 認証は2経路。どちらかを満たせばよい。
    //   1. 運用者トークン (X-Push-Token) — 歌詞投入 CLI 用。env.LYRICS_PUSH_TOKEN。
    //   2. admin のセッション JWT — 将来アプリ側に投入 UI を作った場合用。
    // 1 を用意しているのは、投入が運用者のコマンド操作であって、そのために
    // ユーザーのセッション JWT を端末から持ち出すのが筋悪だから。
    const subject = await authorizeLyricsWrite(request, env);
    if (!subject) return error("Unauthorized", 401);

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

    const rl = await checkRateLimit(env.DB, subject, "lyrics_admin");
    if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

    const { source, status, lines } = body as {
      source?: string | null;
      status: string;
      lines: Array<{ kind?: string; text?: string | null; section?: string | null }>;
    };

    // ⚠️ 行 ID は発行後不変という契約 (将来コールがこの ID を参照する)。
    //    ord 順に既存 id を再利用し、増えた分だけ新しく採番する。
    //    既存 start_ms も同じ位置の行に引き継ぐ (本文修正でタイミングを消さない)。
    const prev = await env.DB.prepare(
      "SELECT lines_json FROM song_lyrics WHERE song_id = ?"
    )
      .bind(songId)
      .first<{ lines_json: string | null }>();
    const existing = parseLines(prev?.lines_json ?? null);

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

    const nextLines: LyricLineRow[] = lines.map((line, i) => {
      const text = line.text ?? "";
      // 行 ID と同じ規則 (ord 順で同じ位置の旧行) で clap/calls も引き継ぐ。
      // 本文が変わってアンカーがズレたコールには stale が立つ (消さない)。
      const annotation = carryOverAnnotation(existing[i], text);
      return {
        id: existing[i]?.id ?? "ll_" + crypto.randomUUID(),
        ord: i,
        kind: line.kind ?? "lyric",
        text,
        section: line.section ?? null,
        // 同じ位置に既存行があればタイミングを引き継ぐ。本文だけ直したときに消えない。
        start_ms: existing[i]?.start_ms ?? existing[i]?.startMs ?? null,
        clap: annotation.clap,
        calls: annotation.calls,
      };
    });

    statements.push(
      env.DB.prepare("UPDATE song_lyrics SET lines_json = ? WHERE song_id = ?")
        .bind(JSON.stringify(nextLines), songId)
    );

    await env.DB.batch(statements);

    const header = await env.DB.prepare(
      "SELECT source, status, updated_at, lines_json FROM song_lyrics WHERE song_id = ?"
    )
      .bind(songId)
      .first<{ source: string | null; status: string; updated_at: string;
               lines_json: string | null }>();
    const saved = parseLines(header?.lines_json ?? null);
    // GET と同じ形 + status (投入ツールが公開状態を確認できるように)。
    const payload = buildLyricsPayload(songId, header ?? { source: null, updated_at: null }, saved);
    return json({ ...payload, status: header?.status ?? status }, 200, NO_STORE);
  }

  return null;
}
