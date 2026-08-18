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

// ---- 歌詞検索 (GET /lyrics/search) の上限 ----
//
// ⚠️ 検索は「まとめ取り」に一番近い機能なので、返すものを構造で絞る:
//   - 1曲につきスニペット1本だけ。行を全部返さない。
//   - スニペットは一致箇所の前後 SNIPPET_CONTEXT 文字だけを切った窓。行全体でもない。
//   - 件数の上限は置かないが、1曲あたりに返るのは窓 1 本 (数十文字) だけ。
//   - 認証必須 + IP バースト制限 (GET /songs/:id/lyrics と同じ枠)。
// これで「1リクエストで多数の曲の本文が手に入る」形にはならない。なお同じ利用者は
// GET /songs/:id/lyrics で1曲ずつ全文を読めるので、検索が新しい取得能力を足すわけではない
// (守っているのは一括ダンプの不在であって、本文への到達不能ではない)。
// 件数の上限は置かない。一致した曲は全部返す。
//
// そのために**切り出しを SQL 側でやる**。D1 から body (歌詞全文) を取り出して JS で
// 走査する形だと、1文字検索で全曲ヒットしたとき 3〜4MB のテキストを毎回 JS で
// なめることになり、Workers 無料枠の CPU 上限 (1リクエスト 10ms) を超える。
// SQL で instr/substr まで済ませれば、JS が触るのは 1 曲あたり 100 文字程度の窓だけ。
// D1 の行読み取りは LIMIT の有無に関係なく全走査 (2,300行) なので課金は変わらない。
//
// 1文字も許す。日本語だと「桜」「夢」「星」のような1文字の検索に意味がある。
const SEARCH_MIN_CHARS = 1;
const SEARCH_MAX_CHARS = 50;
const SNIPPET_CONTEXT = 12;
const SNIPPET_MAX = 48;
/// SQL 側で切り出す窓。表示窓 (SNIPPET_MAX) より広く取っておき、JS で行に丸めてから
/// 表示窓まで詰める。広めなのは「行の切れ目がこの中に入っている」確率を上げるため。
const SQL_WINDOW = 120;
const SQL_WINDOW_BEFORE = 40;

/** LIKE のワイルドカードを無効化する (検索語の % や _ をそのままの文字として扱う)。 */
function likePattern(query: string): string {
  return "%" + query.replace(/[\\%_]/g, (c) => "\\" + c) + "%";
}

// ---- 転置インデックス (lyrics_gram_index / migrations 0029) ----
//
// body LIKE '%q%' は先頭ワイルドカードで索引が効かず、1検索で全走査 (2,291行) になる。
// gram で候補を先に絞れば、よくある検索は十数行で済む。
//
// インデックスは**近似**。2-gram の AND には偽陽性があり (「ABCD」の各 gram が
// 別々の場所にある曲)、再構築までの間は古い。だから候補は必ず body LIKE で検証する。
// ズレは「出るはずの曲が出ない」側にしか倒れない。

/** D1 の1文あたりバインド変数上限。これを超えないよう IN 句を分割する。 */
const MAX_BOUND_PARAMS = 90;
/**
 * 候補がこれを超えたら索引を捨てて全走査に倒す。
 * 「の」のような1文字は 2,282 曲に当たるので、90件ずつ IN で引くと 26 往復になり、
 * 1回の全走査より遅くて高い。候補が多い = 絞れていない、なので索引の出番ではない。
 */
const CANDIDATE_LIMIT = 300;

/** クエリを索引の gram に割る。1文字はそのまま、2文字以上は 2-gram に。 */
function queryGrams(query: string): string[] {
  const chars = Array.from(query);
  if (chars.length <= 1) return chars;
  const grams: string[] = [];
  for (let i = 0; i < chars.length - 1; i++) grams.push(chars[i] + chars[i + 1]);
  // 同じ gram が何度出ても posting は同じなので、引くのは1回でよい。
  return [...new Set(grams)].slice(0, MAX_BOUND_PARAMS);
}

/**
 * 索引から候補の song_id を引く。
 * 索引を使わない/使えない場合は null (呼び出し側は全走査に倒す)。
 */
async function candidateSongIds(env: Env, query: string): Promise<string[] | null> {
  const grams = queryGrams(query);
  if (grams.length === 0) return null;

  const placeholders = grams.map(() => "?").join(",");
  const rows = await env.DB.prepare(
    `SELECT gram, song_ids FROM lyrics_gram_index WHERE gram IN (${placeholders})`
  )
    .bind(...grams)
    .all<{ gram: string; song_ids: string }>();

  // posting は長いと part に分割されて複数行で返る (migrations 0030)。gram ごとに束ねる。
  const byGram = new Map<string, string[]>();
  for (const row of rows.results ?? []) {
    const list = byGram.get(row.gram) ?? [];
    list.push(...row.song_ids.split("\n"));
    byGram.set(row.gram, list);
  }

  // gram が1つでも索引に無い = その並びを含む曲は無い、と言い切れる…が、索引が
  // 未構築 (0件) のときも同じ形になる。区別できないので、全部欠けていたら
  // 索引を信用せず全走査に倒す。
  if (byGram.size === 0) return null;
  if (byGram.size < grams.length) return [];

  // 全 gram を含む曲だけが候補 (AND)。一番小さい posting から積むと交差が速い。
  const lists = [...byGram.values()].sort((a, b) => a.length - b.length);
  let candidates = new Set(lists[0]);
  for (const list of lists.slice(1)) {
    const next = new Set<string>();
    for (const id of list) if (candidates.has(id)) next.add(id);
    candidates = next;
    if (candidates.size === 0) break;
  }
  return candidates.size > CANDIDATE_LIMIT ? null : [...candidates];
}

/**
 * SQL が切り出した窓 (`window`) を、一致を含む 1 行ぶんに丸めて表示用に詰める。
 *
 * SQL の窓は行をまたぐ (body は歌詞行を改行で連結したもの) ので、まず改行で切って
 * 一致のある行だけを残す。読み手にとって隣の行の断片は雑音でしかない。
 *
 * `offset` は窓の先頭からの一致位置 (0 始まり)。`truncated` は SQL の窓自体が
 * 前/後ろで切れているか — 省略記号を出すかの判断に要る。
 *
 * オフセットは **Unicode スカラー単位** (JS の Array.from / Swift の unicodeScalars)。
 * コールのアンカーと同じ規約に揃えてあるので、iOS 側は同じ数え方で強調表示できる。
 * UTF-16 コードユニットで数えると絵文字や結合文字を含む行でズレる。
 */
export function buildSnippet(
  window: string,
  offset: number,
  queryLength: number,
  truncated: { head: boolean; tail: boolean }
): { snippet: string; matchStart: number; matchLength: number } | null {
  const chars = Array.from(window);
  if (offset < 0 || offset >= chars.length) return null;

  // 一致を含む行に丸める。行が見つからなければ窓の端がそのまま境界。
  let lineStart = 0;
  for (let i = offset - 1; i >= 0; i--) {
    if (chars[i] === "\n") { lineStart = i + 1; break; }
  }
  let lineEnd = chars.length;
  for (let i = offset + queryLength; i < chars.length; i++) {
    if (chars[i] === "\n") { lineEnd = i; break; }
  }
  // 行頭/行末で切れたなら、そこは行の境界なので省略記号は要らない。
  // 窓の端で切れた場合だけ、元の truncated を引き継ぐ。
  const cutHead = lineStart === 0 ? truncated.head : false;
  const cutTail = lineEnd === chars.length ? truncated.tail : false;

  const line = chars.slice(lineStart, lineEnd);
  const at = offset - lineStart;

  const to = Math.min(line.length, Math.max(0, at - SNIPPET_CONTEXT) + SNIPPET_MAX);
  // 行末で一致した時に窓が後ろへはみ出さないよう、足りない分を前に回す。
  const from = Math.max(0, Math.min(at - SNIPPET_CONTEXT, to - SNIPPET_MAX));

  const head = from > 0 || cutHead ? "…" : "";
  const tail = to < line.length || cutTail ? "…" : "";
  return {
    snippet: head + line.slice(from, to).join("") + tail,
    matchStart: head.length + (at - from),
    // 窓からはみ出す長さは返さない (iOS 側の範囲指定が壊れる)。
    matchLength: Math.max(0, Math.min(queryLength, to - at)),
  };
}

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
  const { request, env, url, path, json, error, rateLimitResponse, rateLimitSimple } = ctx;

  // ----------------------------------------------------------------
  // GET /lyrics/search?q=... — 歌詞本文の横断検索 (セッション JWT 必須)
  //   返すのは song_id と一致箇所まわりのスニペットだけ。曲名やアーティストは
  //   返さない (端末が同梱 SQLite から引ける。サーバはマスタを持っていない)。
  // ----------------------------------------------------------------
  if (path === "/lyrics/search" && request.method === "GET") {
    const user = await getAuthUser(request, env);
    // GET /songs/:id/lyrics と同じ理由で認証必須。未認証を通すと
    // edgeCacheEligible の対象になり、歌詞の断片がエッジに載りうる。
    if (!user) return error("Unauthorized", 401);

    const query = (url.searchParams.get("q") ?? "").trim();
    // 1文字だと事実上の全件走査になる (どの曲にも「あ」はある)。
    if (query.length < SEARCH_MIN_CHARS) {
      return error(`q must be at least ${SEARCH_MIN_CHARS} characters`, 400);
    }
    if (query.length > SEARCH_MAX_CHARS) return error("q too long", 400);

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const ipRl = await dryCheckIpRateLimit(env.DB, ip);
    if (!ipRl.allowed) return rateLimitSimple();

    // draft は admin にしか見せない (GET /songs/:id/lyrics と同じ規則)。
    // 検索だけ緩めると、本文は読めないのにスニペットからは読める状態になる。
    const isAdmin = await checkIsAdmin(env, user.uid);
    const statusClause = isAdmin ? "" : "AND status = 'published'";
    // まず索引で候補を絞る。絞れない (索引未構築 / 候補が多すぎる) 場合は null が返り、
    // 従来どおり全走査する。候補が空配列なら「該当なし」が確定しているので走査すらしない。
    const candidates = await candidateSongIds(env, query);
    if (candidates?.length === 0) {
      await commitIpRateLimit(env.DB, ip, ipRl.bucket);
      return json({ query, hits: [] }, 200, NO_STORE);
    }

    // ⚠️ body そのものは返させない。窓 (SQL_WINDOW 文字) だけを切って受け取る。
    //    全文を JS に渡すと 1 文字検索で全曲ヒットしたとき CPU 上限を超える。
    //    instr / substr は TEXT に対して**文字単位**で動くので、iOS と合意している
    //    Unicode スカラー単位のオフセットとそのまま噛み合う。
    //    lower() は ASCII しか畳まないため文字数が変わらず、位置がズレない。
    const windowSelect = (extraWhere: string) =>
      `WITH matched AS (
         SELECT song_id, body, instr(lower(body), lower(?1)) AS at
           FROM song_lyrics
          WHERE body LIKE ?2 ESCAPE '\\' ${statusClause} ${extraWhere}
       )
       SELECT song_id,
              substr(body, max(1, at - ?3), ?4) AS window,
              at - max(1, at - ?3) AS offset,
              max(1, at - ?3) > 1 AS cut_head,
              length(body) > max(1, at - ?3) + ?4 - 1 AS cut_tail
         FROM matched
        WHERE at > 0
        ORDER BY song_id`;

    type WindowRow = { song_id: string; window: string; offset: number;
                       cut_head: number; cut_tail: number };
    const found: WindowRow[] = [];

    if (candidates) {
      // 候補ありの経路。D1 のバインド変数上限があるので IN 句を分割して引く。
      // 4 個は固定 (query / like / before / window) なので残りを id に使う。
      const perChunk = MAX_BOUND_PARAMS - 4;
      for (let i = 0; i < candidates.length; i += perChunk) {
        const chunk = candidates.slice(i, i + perChunk);
        const rows = await env.DB.prepare(
          windowSelect(`AND song_id IN (${chunk.map(() => "?").join(",")})`)
        )
          .bind(query, likePattern(query), SQL_WINDOW_BEFORE, SQL_WINDOW, ...chunk)
          .all<WindowRow>();
        found.push(...(rows.results ?? []));
      }
      found.sort((a, b) => (a.song_id < b.song_id ? -1 : a.song_id > b.song_id ? 1 : 0));
    } else {
      const rows = await env.DB.prepare(windowSelect(""))
        .bind(query, likePattern(query), SQL_WINDOW_BEFORE, SQL_WINDOW)
        .all<WindowRow>();
      found.push(...(rows.results ?? []));
    }

    const queryLength = Array.from(query).length;
    const hits = found.flatMap((row) => {
      const snippet = buildSnippet(row.window ?? "", row.offset, queryLength, {
        head: row.cut_head === 1,
        tail: row.cut_tail === 1,
      });
      // 窓を作れないのは一致位置が窓から外れた等の端のケース。song_id だけ返しても
      // 画面に出せるものが無いので落とす。
      return snippet ? [{ songId: row.song_id, ...snippet }] : [];
    });

    await commitIpRateLimit(env.DB, ip, ipRl.bucket);
    return json({ query, hits }, 200, NO_STORE);
  }

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

    // body は検索専用の平文コピー (migrations/0028)。lines_json と必ず同時に書く。
    // 歌詞行だけを連結する: marker (イントロ/間奏) や blank は本文ではないので、
    // 「間奏」で検索して全曲ヒットするような結果にしない。
    const searchBody = nextLines
      .filter((line) => line.kind === "lyric")
      .map((line) => line.text)
      .join("\n");

    statements.push(
      env.DB.prepare("UPDATE song_lyrics SET lines_json = ?, body = ? WHERE song_id = ?")
        .bind(JSON.stringify(nextLines), searchBody, songId)
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
