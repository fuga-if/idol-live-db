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
import { updateGramIndex } from "../lyrics_index";
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

/// POST /admin/lyrics/status で 1 回に渡せる song_id の数。
///
/// ⚠️ D1 の上限は **1 クエリあたりバインド変数 100 個**。この UPDATE は ids に加えて
///    status を 3 回バインドするので、余裕を見て 90 に取ってある。
///    超えると 500 (Internal error) になり、エラー本文からは原因が分からない。
const MAX_STATUS_IDS = 90;

// ---- 掲載曲数について ----
//
// JASRAC 許諾 J260943703 の許諾書には「ご利用曲数 100曲まで」とあるが、
// 非商用配信の使用料表は**「以後10曲まで毎に加算する額」が「なし」**で、
// 曲数を増やしても額が変わらない (2026-09-03 に許諾者本人が料金表で確認)。
// したがって曲数で配信を止めない。
//
// 数えるものは残してある (GET /admin/lyrics/quota)。年次利用曲目報告の母集団が
// 「実際に掲載した曲」なので、何曲公開しているかは結局要る。

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
/// 1曲あたりに出すスニペットの本数 (= 語の数)。多すぎても読めないのでここで頭打ち。
const SNIPPET_TERMS = 3;

/** LIKE のワイルドカードを無効化する (検索語の % や _ をそのままの文字として扱う)。 */
function likePattern(query: string): string {
  return "%" + query.replace(/[\\%_]/g, (c) => "\\" + c) + "%";
}

// ---- 表記ゆれの吸収 ----
//
// ⚠️ ここに入れてよいのは **1文字 → 1文字** の変換だけ。
//    検索は body_norm 上で一致位置を求め、その位置で body から窓を切る。長さの変わる
//    変換 (半角濁点カナ ﾂﾞ → ヅ 等) を足すと位置がズレてスニペットが壊れる。
//    漢字は読みが要るのでここでは扱えない (翼 と つばさ)。それは検索側の OR で。

/** ひらがな→カタカナ・英字小文字・全角英数→半角。長さは変わらない。 */
export function normalizeForSearch(text: string): string {
  let out = "";
  for (const ch of text) {
    const code = ch.codePointAt(0)!;
    if (code >= 0x3041 && code <= 0x3096) {
      out += String.fromCodePoint(code + 0x60);       // ひらがな → カタカナ
    } else if (code >= 0xff01 && code <= 0xff5e) {
      out += String.fromCodePoint(code - 0xfee0).toLowerCase(); // 全角英数記号 → 半角
    } else {
      out += ch.toLowerCase();
    }
  }
  return out;
}

/** 検索式の木。葉が検索語で、節が AND / OR。 */
export type QueryNode =
  | { kind: "term"; text: string }
  | { kind: "and"; children: QueryNode[] }
  | { kind: "or"; children: QueryNode[] };

/**
 * 検索文字列を式の木に落とす。
 *
 *   空白 = AND … 「夢 翼」で両方を含む曲。単語1つだと「夢」で1,273曲あり
 *                絞る手段が無いので、既定を AND にしている。
 *   `|`  = OR  … 「翼|つばさ」。かなの正規化では届かない漢字の揺れ用。
 *   `()` = grouping
 *
 * `|` は空白より強く結ぶ。空白を空けずに書くので見た目どおりで、
 * 「夢 翼|つばさ」が 夢 AND (翼 OR つばさ) になる。
 * 逆向き (翼 OR (夢 AND 星)) が要るときは括弧で書く。UI 側は木を組み立てて
 * 括弧つきの文字列にして送るので、手打ちと同じ記法で表現できる。
 *
 * 文法:
 *   expr := and
 *   and  := or (WS or)*
 *   or   := atom ('|' atom)*
 *   atom := '(' expr ')' | TERM
 */
export function parseQuery(raw: string): QueryNode | null {
  // 記号を1文字トークンに、"…" は中身ごと1トークンに、それ以外の連続を語に切る。
  //
  // 引用符が要るのは、歌詞が全角スペースで区切られているため
  // (「空を描いて行くよ　ここで光るよ」)。空白 = AND なので、囲まないと
  // フレーズとして探せない。UI 側は各入力欄の中身を必ず囲って送る。
  const tokens = raw.match(/"[^"]*"|[()|｜]|[^()|｜\s　]+/g) ?? [];
  let pos = 0;

  const flatten = (kind: "and" | "or", parts: QueryNode[]): QueryNode | null => {
    const kept = parts.filter((p): p is QueryNode => p !== null);
    if (kept.length === 0) return null;
    return kept.length === 1 ? kept[0] : { kind, children: kept };
  };

  function parseAtom(): QueryNode | null {
    const token = tokens[pos];
    if (token === undefined) return null;
    if (token === "(") {
      pos++;
      const inner = parseAnd();
      if (tokens[pos] === ")") pos++;   // 閉じ忘れは黙って許す (打ちかけを弾かない)
      return inner;
    }
    if (token === ")" || token === "|" || token === "｜") return null;
    pos++;
    // 引用符つきは中身をそのまま1語にする (空白を含むフレーズ)。
    const raw = token.startsWith('"') ? token.slice(1, -1) : token;
    const text = normalizeForSearch(raw.trim());
    return text.length > 0 ? { kind: "term", text } : null;
  }

  function parseOr(): QueryNode | null {
    const parts: QueryNode[] = [];
    const first = parseAtom();
    if (first) parts.push(first);
    while (tokens[pos] === "|" || tokens[pos] === "｜") {
      pos++;
      const next = parseAtom();
      if (next) parts.push(next);
    }
    return flatten("or", parts);
  }

  function parseAnd(): QueryNode | null {
    const parts: QueryNode[] = [];
    while (pos < tokens.length && tokens[pos] !== ")") {
      const before = pos;
      const node = parseOr();
      if (node) parts.push(node);
      if (pos === before) pos++;        // 進まなかった = 余分な記号。捨てて進む
    }
    return flatten("and", parts);
  }

  return parseAnd();
}

/** 式に出てくる検索語を、書かれた順で重複なく集める。 */
export function collectTerms(node: QueryNode, out: string[] = []): string[] {
  if (node.kind === "term") {
    if (!out.includes(node.text)) out.push(node.text);
  } else {
    for (const child of node.children) collectTerms(child, out);
  }
  return out;
}

/** 式を SQL の条件に落とす。`?` の順に検索語 (LIKE パターン) を bind する。 */
export function nodeToSql(node: QueryNode, params: string[]): string {
  if (node.kind === "term") {
    params.push(likePattern(node.text));
    return `body_norm LIKE ? ESCAPE '\\'`;
  }
  const op = node.kind === "and" ? " AND " : " OR ";
  return "(" + node.children.map((c) => nodeToSql(c, params)).join(op) + ")";
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
 * 式全体の候補を索引から求める。null なら索引で絞れないので全走査に倒す。
 *
 * AND は積集合、OR は和集合。ただし OR の枝が1つでも「索引で絞れない (null)」なら、
 * 和集合も絞れない — 絞れない枝が何を含むか分からない以上、他の枝だけで答えを
 * 出すと取りこぼす。AND は逆で、絞れる枝が1つでもあればそれで足りる
 * (積集合はどの枝より大きくならない)。
 */
async function candidatesForNode(env: Env, node: QueryNode): Promise<string[] | null> {
  if (node.kind === "term") return candidateSongIds(env, node.text);

  const parts = await Promise.all(node.children.map((c) => candidatesForNode(env, c)));

  if (node.kind === "or") {
    if (parts.some((p) => p === null)) return null;
    const union = new Set<string>();
    for (const p of parts) for (const id of p!) union.add(id);
    return union.size > CANDIDATE_LIMIT ? null : [...union];
  }

  const usable = parts.filter((p): p is string[] => p !== null);
  if (usable.length === 0) return null;
  usable.sort((a, b) => a.length - b.length);
  let acc = new Set(usable[0]);
  for (const list of usable.slice(1)) {
    const next = new Set<string>();
    for (const id of list) if (acc.has(id)) next.add(id);
    acc = next;
    if (acc.size === 0) break;
  }
  return [...acc];
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

/** 歌詞**本文**の書き込み権限。運用者トークン、または admin のセッション JWT。
 *  レート制限の主体に使う文字列を返す (拒否なら null)。
 *
 *  ⚠️ コール保存 (routes/calls.ts) はこれより緩い — ログインしていれば誰でも書ける。
 *     コールはユーザーが書くもので、あの経路では歌詞本文を書き換えられないため。
 *     ここを緩めると本文まで書けるようになるので、混ぜないこと。 */
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
    if (query.length < SEARCH_MIN_CHARS) {
      return error(`q must be at least ${SEARCH_MIN_CHARS} characters`, 400);
    }
    if (query.length > SEARCH_MAX_CHARS) return error("q too long", 400);

    // 「夢 翼|つばさ」のような式を木に落とす。空白=AND / |=OR / ()=grouping。
    const expr = parseQuery(query);
    if (!expr) return error("q has no searchable term", 400);
    // 位置は「その曲で実際に一致した語」で決める。OR だと曲ごとに違う語で当たる。
    const terms = collectTerms(expr);

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const ipRl = await dryCheckIpRateLimit(env.DB, ip);
    if (!ipRl.allowed) return rateLimitSimple();

    // draft は admin にしか見せない (GET /songs/:id/lyrics と同じ規則)。
    // 検索だけ緩めると、本文は読めないのにスニペットからは読める状態になる。
    const isAdmin = await checkIsAdmin(env, user.uid);
    const statusClause = isAdmin ? "" : "AND status = 'published'";

    // まず索引で候補を絞る。絞れない (索引未構築 / 候補が多すぎる) 場合は null が返り、
    // 従来どおり全走査する。候補が空配列なら「該当なし」が確定しているので走査すらしない。
    const candidates = await candidatesForNode(env, expr);
    if (candidates?.length === 0) {
      await commitIpRateLimit(env.DB, ip, ipRl.bucket);
      return json({ query, hits: [] }, 200, NO_STORE);
    }

    // ⚠️ body そのものは返させない。窓 (SQL_WINDOW 文字) だけを切って受け取る。
    //    全文を JS に渡すと 1 文字検索で全曲ヒットしたとき CPU 上限を超える。
    //
    // 一致位置は body_norm 上で求め、窓は **body** から切る。正規化は
    // 1文字→1文字の変換だけなので位置がそのまま使える (normalizeForSearch 参照)。
    //
    // ⚠️ 番号なしの ? を混ぜないこと。SQLite の ? は「それまでの最大番号 + 1」を取るので、
    //    番号付きと混ぜると黙って衝突する (前に候補経路だけ 0 件になる不具合を出した)。
    const found: Record<string, unknown>[] = [];

    // 1曲につき語ごとに1本ずつ窓を出す。AND だと全語が当たるので、なぜ引っかかったのかが
    // 1本では分からない (「夢 翼」で夢の周辺しか見えない)。OR は曲ごとに1語しか
    // 当たらないので自然に1本になる。
    // 上限は打った語数で決まるが、多すぎても読めないので SNIPPET_TERMS 本で頭打ち。
    const shown = terms.slice(0, SNIPPET_TERMS);

    const runQuery = async (extraWhere: string, extraParams: string[]) => {
      const exprParams: string[] = [];
      const exprSql = nodeToSql(expr, exprParams);
      // ?1=before ?2=window、?3 以降が語 (位置用) → 式の LIKE → 追加条件。
      let n = 2;
      const posParams = shown.map(() => `?${++n}`);
      const cols = posParams.flatMap((p, i) => {
        const at = `instr(body_norm, ${p})`;
        return [
          `${at} AS at${i}`,
          `length(${p}) AS len${i}`,
          `substr(body, max(1, ${at} - ?1), ?2) AS win${i}`,
          `${at} - max(1, ${at} - ?1) AS off${i}`,
          `max(1, ${at} - ?1) > 1 AS head${i}`,
          `length(body) > max(1, ${at} - ?1) + ?2 - 1 AS tail${i}`,
        ];
      });

      const numbered = exprSql.replace(/\?/g, () => `?${++n}`);
      const where = extraWhere.replace(/\?/g, () => `?${++n}`);
      const rows = await env.DB.prepare(
        `SELECT song_id, ${cols.join(", ")}
           FROM song_lyrics
          WHERE ${numbered} ${statusClause} ${where}
          ORDER BY song_id`
      )
        .bind(SQL_WINDOW_BEFORE, SQL_WINDOW, ...shown, ...exprParams, ...extraParams)
        .all<Record<string, unknown>>();
      found.push(...(rows.results ?? []));
    };

    if (candidates) {
      // D1 のバインド変数上限があるので IN 句を分割して引く。
      const fixed = 2 + shown.length + terms.length;
      const perChunk = Math.max(10, MAX_BOUND_PARAMS - fixed);
      for (let i = 0; i < candidates.length; i += perChunk) {
        const chunk = candidates.slice(i, i + perChunk);
        await runQuery(`AND song_id IN (${chunk.map(() => "?").join(",")})`, chunk);
      }
      found.sort((a, b) => {
        const x = a.song_id as string, y = b.song_id as string;
        return x < y ? -1 : x > y ? 1 : 0;
      });
    } else {
      await runQuery("", []);
    }

    const hits = found.flatMap((row) => {
      const snippets = shown.flatMap((_, i) => {
        if ((row[`at${i}`] as number) <= 0) return [];   // この語は当たっていない
        const snippet = buildSnippet(
          (row[`win${i}`] as string) ?? "",
          row[`off${i}`] as number,
          row[`len${i}`] as number,
          { head: row[`head${i}`] === 1, tail: row[`tail${i}`] === 1 }
        );
        return snippet ? [snippet] : [];
      });
      // 1本も窓が作れない曲は画面に出せるものが無いので落とす。
      return snippets.length > 0 ? [{ songId: row.song_id as string, snippets }] : [];
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
  // POST /admin/lyrics/status — 公開状態だけをまとめて切り替える (モデレーターのみ)
  // ----------------------------------------------------------------
  //
  // 既に投入済みの歌詞を draft ⇄ published させるためだけの口。本文には触らない。
  //
  // ⚠️ このファイル冒頭の「1リクエスト = 高々1曲」は**読み取り**の規則で、
  //    まとめ取りで歌詞を一括ダウンロードされないためのもの。ここは書き込みで、
  //    応答に歌詞本文を一切含めない (返すのは件数だけ) ので趣旨には触れない。
  //    ⚠️ 将来ここに本文や lines を返す実装を足さないこと。足した瞬間に
  //       「まとめ取りできる口」になる。
  //
  // PUT を曲数ぶん叩くのに比べて、本文と転置インデックスを書き直さずに済む。
  if (path === "/admin/lyrics/status" && request.method === "POST") {
    const subject = await authorizeLyricsWrite(request, env);
    if (!subject) return error("Unauthorized", 401);

    const body = await request.json().catch(() => null) as
      { song_ids?: unknown; status?: unknown } | null;
    const status = body?.status;
    if (typeof status !== "string" || !LYRIC_STATUSES.has(status)) {
      return error("status must be 'draft' or 'published'", 400);
    }
    const ids = body?.song_ids;
    if (!Array.isArray(ids) || ids.length === 0) return error("song_ids required", 400);
    // 1 リクエストの上限。SQL のプレースホルダ数を現実的な範囲に留める。
    if (ids.length > MAX_STATUS_IDS) {
      return error(`song_ids must be at most ${MAX_STATUS_IDS}`, 400);
    }
    if (!ids.every((id) => typeof id === "string" && id.length > 0 && id.length <= 200)) {
      return error("song_ids must be non-empty strings", 400);
    }

    const rl = await checkRateLimit(env.DB, subject, "lyrics_admin");
    if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

    const holes = ids.map(() => "?").join(",");
    // first_published_at は PUT と同じ規則で「初回 published の時刻だけ」を残す。
    // 年次利用曲目報告の基準がここなので、published→draft→published で上書きしない。
    const res = await env.DB.prepare(
      `UPDATE song_lyrics
          SET status = ?,
              first_published_at = COALESCE(
                first_published_at,
                CASE WHEN ? = 'published' THEN datetime('now') END),
              updated_at = datetime('now')
        WHERE song_id IN (${holes}) AND status <> ?`
    )
      .bind(status, status, ...(ids as string[]), status)
      .run();

    return json({ status, requested: ids.length, updated: res.meta?.changes ?? 0 },
                200, NO_STORE);
  }

  // ----------------------------------------------------------------
  // GET /admin/lyrics/quota — 掲載曲数の集計 (モデレーターのみ)
  // ----------------------------------------------------------------
  //
  // 年次利用曲目報告の母集団は「実際に掲載した曲」なので、何曲公開しているかを
  // 数える手段が要る。上限ではなく実績の確認。
  if (path === "/admin/lyrics/quota" && request.method === "GET") {
    if (!(await authorizeLyricsWrite(request, env))) return error("Unauthorized", 401);
    const row = await env.DB.prepare(
      `SELECT
         count(*) FILTER (WHERE status = 'published') AS published,
         count(*) FILTER (WHERE status = 'draft')     AS draft
       FROM song_lyrics`
    ).first<{ published: number; draft: number }>();
    return json(
      { license: "J260943703", published: row?.published ?? 0, draft: row?.draft ?? 0 },
      200,
      NO_STORE
    );
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

    // body_norm は表記ゆれを吸収した検索用のコピー (migrations 0031)。body と必ず同時に書く。
    statements.push(
      env.DB.prepare(
        "UPDATE song_lyrics SET lines_json = ?, body = ?, body_norm = ? WHERE song_id = ?"
      ).bind(JSON.stringify(nextLines), searchBody, normalizeForSearch(searchBody), songId)
    );

    await env.DB.batch(statements);

    // 検索の転置インデックスを差分で追従させる。本文が変わっていなければ
    // 1 クエリも投げない (同じ歌詞の入れ直しは索引の書き込みゼロ)。
    //
    // 失敗しても PUT は成功として返す。索引がズレても検索側は候補を body LIKE で
    // 検証するので誤ヒットは出ず、「出るはずの曲が出ない」側にしか倒れない。
    // 歌詞そのものは既に保存済みなので、索引の都合で投入を失敗扱いにする方が害が大きい。
    const previousBody = existing
      .filter((line) => line.kind === "lyric")
      .map((line) => line.text)
      .join("\n");
    try {
      await updateGramIndex(env, songId, previousBody, searchBody);
    } catch (err) {
      console.error("lyrics_gram_index_update_failed", songId, err);
    }

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
