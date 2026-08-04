// lyrics_calls.ts — コールガイド (clap / calls) のドメインロジック。
//
// 置き場所について: コールは歌詞行 (song_lyrics.lines_json) の一部として保存する。
// 別テーブルにはしない。migration 0027 のコメントのとおり、歌詞 1 曲の取得を
// D1 の行読み取り 1 回に収めるのが lines_json の存在理由であり、コールを別テーブルに
// 分けた瞬間にその前提が壊れる (1曲取得で「歌詞1行 + コール n 行」を読むことになる)。
//
// このファイルはルート非依存の純粋関数だけを置く (D1 も Request も触らない)。
// - routes/lyrics.ts   … 歌詞差し替え時のコール引き継ぎ (carryOverAnnotation) で使う
// - routes/calls.ts    … PUT /songs/:song_id/calls のボディ検証で使う
// 逆向き (このファイルから routes を import) は作らないこと。循環参照になる。

/** 行全体のクラップ指定。実物のコール本の記号に対応する。
 *  ★=裏拍 back_beat / ■=4つ打ち four_on_floor / ♠=PPPH ppph / ♥=コールなし none。
 *  「未指定」は null で表す ("none" は「ここは叩かない」という積極的な指定なので別物)。 */
export type ClapKind = "back_beat" | "four_on_floor" | "ppph" | "none";

/** normal=通常(青) / optional=おこのみで(緑) / performer_request=演者要望(赤)。 */
export type CallEmphasis = "normal" | "optional" | "performer_request";

export const CLAP_KINDS: ReadonlySet<string> = new Set([
  "back_beat",
  "four_on_floor",
  "ppph",
  "none",
]);

export const CALL_EMPHASES: ReadonlySet<string> = new Set([
  "normal",
  "optional",
  "performer_request",
]);

export interface LyricCall {
  /** 'cl_<uuid>' 相当。クライアントが採番した ID があればそれを尊重する。 */
  id: string;
  /** 行内の開始位置 (Unicode スカラー単位・0 始まり)。scalarSlice のコメントを必ず読むこと。 */
  start: number;
  /** 行内の終了位置 (Unicode スカラー単位・排他的)。start === end は「本文に紐づかないコール」。 */
  end: number;
  /**
   * [start, end) の文字列。**ズレ検出専用で、検索キーではない。**
   * 保存時は必ずサーバが line.text から切り出した値を入れる (クライアントの申告値は検証にのみ使う)。
   * 歌詞を差し替えた後にここと切り出し結果が食い違ったら stale を立てる。
   */
  anchorText: string;
  /** 叫ぶ文言。自由テキスト。繰り返しも文言に含める ("(Hi!) × 26" / "(Fuwa × 4)")。 */
  text: string;
  emphasis: CallEmphasis;
  /** 歌詞編集でアンカーがズレた印。編集画面で「要再設定」を出すため。false のときは省略する。 */
  stale?: boolean;
}

/** 1 行ぶんのコール注釈。lines_json の各行に直接埋め込まれる。 */
export interface CallAnnotation {
  clap: ClapKind | null;
  calls: LyricCall[];
}

/** 1 行あたりのコール数上限。1 行に 20 個並ぶコール本は実在しないので十分な余裕。 */
export const MAX_CALLS_PER_LINE = 20;
/** 1 曲あたりのコール総数上限。lines_json 1 行の肥大 (= D1 の 1 行読みが重くなる) を抑える。 */
export const MAX_CALLS_PER_SONG = 600;
/** コール文言の長さ上限 (Unicode スカラー数)。 */
export const MAX_CALL_TEXT_CHARS = 200;
/** クライアント採番の call id に許す長さ。 */
export const MAX_CALL_ID_CHARS = 64;

// ---------------------------------------------------------------------------
// 文字位置の数え方 (iOS と共有する契約。ここが唯一の定義)
// ---------------------------------------------------------------------------
//
// **start / end は Unicode スカラー値 (= コードポイント) 単位で数える。**
//
//   - JS の String.length / String.prototype.slice は UTF-16 コードユニット単位なので使わない。
//     絵文字 (U+1F3B5 等) が 2 と数えられ、Swift の String.UnicodeScalarView と 1 ずれる。
//   - Swift 側は `text.unicodeScalars` の index で切ること。
//     `Array(text)` (Character = 書記素クラスタ) では "か"+"゙" (結合文字) や 家族絵文字 (ZWJ 連結) が
//     1 と数えられ、こちらとずれる。**書記素クラスタでは数えない。**
//   - JS で コードポイント単位のイテレータになるのは Array.from(text) / [...text] なので、
//     このファイルの toScalars() を唯一の実装とし、他所で text.length を使わないこと。
//
// スカラーを選んだ理由: 書記素クラスタは Unicode のバージョン (ICU の版) で境界が変わりうるため、
// サーバとクライアントで実装/更新時期が違うと同じ文字列でも数え方が食い違う。スカラーは
// 文字列のコードポイント列そのものなので、両者で必ず一致する。

/** 文字列をコードポイント (Unicode スカラー) の配列に分解する。 */
export function toScalars(text: string): string[] {
  return Array.from(text);
}

/** Unicode スカラー単位の文字数。 */
export function scalarLength(text: string): number {
  return toScalars(text).length;
}

/** Unicode スカラー単位の [start, end) 切り出し。範囲外は自動で丸められる。 */
export function scalarSlice(text: string, start: number, end: number): string {
  return toScalars(text).slice(start, end).join("");
}

// ---------------------------------------------------------------------------
// 検証 (PUT /songs/:song_id/calls のボディ)
// ---------------------------------------------------------------------------

/** 検証を通した 1 行ぶんの指定。id は既存行の ID であることが保証されている。 */
export interface ValidatedCallLine extends CallAnnotation {
  id: string;
}

export type ValidateResult =
  | { ok: true; lines: ValidatedCallLine[] }
  | { ok: false; error: string };

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

/** 0 以上の整数か。 */
function isIndex(v: unknown): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= 0;
}

/**
 * コール保存ボディを検証し、保存できる形に正規化する。
 *
 * @param body        リクエストボディ (未検証)
 * @param lineTextById 既存行の id → 本文。**歌詞本文はこちらが正**で、
 *                     ボディ側から本文を受け取らない (この経路で歌詞を書き換えられないようにするため)。
 */
export function validateCallsBody(
  body: unknown,
  lineTextById: ReadonlyMap<string, string>
): ValidateResult {
  if (!isPlainObject(body)) return { ok: false, error: "body must be an object" };
  const { lines } = body;
  // 空配列は「この曲のコールを全消し」を意味する (PUT なので全置換)。
  if (!Array.isArray(lines)) return { ok: false, error: "lines must be an array" };
  if (lines.length > lineTextById.size) {
    return { ok: false, error: `too many lines (${lines.length} > ${lineTextById.size})` };
  }

  const out: ValidatedCallLine[] = [];
  const seen = new Set<string>();
  let total = 0;

  for (let i = 0; i < lines.length; i++) {
    const where = `lines[${i}]`;
    const line = lines[i];
    if (!isPlainObject(line)) return { ok: false, error: `${where} must be an object` };

    const { id, clap, calls } = line;
    if (typeof id !== "string" || !id) return { ok: false, error: `${where}.id must be a string` };
    const lineText = lineTextById.get(id);
    // 知らない行 ID は 400。歌詞側の行が消えた後の古い編集画面から飛んできた場合に、
    // 宙に浮いたコールを黙って作らないため。
    if (lineText === undefined) return { ok: false, error: `${where}.id is not a line of this song` };
    if (seen.has(id)) return { ok: false, error: `${where}.id is duplicated` };
    seen.add(id);

    if (clap !== undefined && clap !== null && (typeof clap !== "string" || !CLAP_KINDS.has(clap))) {
      return {
        ok: false,
        error: `${where}.clap must be null or one of back_beat/four_on_floor/ppph/none`,
      };
    }

    if (calls !== undefined && calls !== null && !Array.isArray(calls)) {
      return { ok: false, error: `${where}.calls must be an array` };
    }
    const rawCalls: unknown[] = Array.isArray(calls) ? calls : [];
    if (rawCalls.length > MAX_CALLS_PER_LINE) {
      return {
        ok: false,
        error: `${where}.calls too many (${rawCalls.length} > ${MAX_CALLS_PER_LINE})`,
      };
    }
    total += rawCalls.length;
    if (total > MAX_CALLS_PER_SONG) {
      return { ok: false, error: `too many calls in this song (max ${MAX_CALLS_PER_SONG})` };
    }

    const lineLength = scalarLength(lineText);
    const normalized: LyricCall[] = [];
    for (let j = 0; j < rawCalls.length; j++) {
      const at = `${where}.calls[${j}]`;
      const call = rawCalls[j];
      if (!isPlainObject(call)) return { ok: false, error: `${at} must be an object` };

      const { id: callId, start, end, text, emphasis } = call;
      // iOS の APIClient は keyEncodingStrategy = .convertToSnakeCase なので、
      // anchorText は実際には anchor_text で飛んでくる。ここで両方を受ける。
      // (保存値・応答は camelCase の anchorText 一本。iOS 側のデコーダは
      //  convertFromSnakeCase で camelCase キーをそのまま camelCase に落とすので通る。)
      // 他のキー (id/start/end/text/emphasis/clap/calls) は 1 語なので変換の影響を受けない。
      const anchorText = call.anchorText ?? call.anchor_text;

      if (callId !== undefined && callId !== null) {
        if (typeof callId !== "string" || !callId || callId.length > MAX_CALL_ID_CHARS) {
          return { ok: false, error: `${at}.id must be a string (1-${MAX_CALL_ID_CHARS} chars)` };
        }
      }

      if (!isIndex(start) || !isIndex(end)) {
        return { ok: false, error: `${at}.start / ${at}.end must be non-negative integers` };
      }
      if (start > end) return { ok: false, error: `${at}.start must be <= ${at}.end` };
      // 行の文字数を超える位置は受け取らない。受けてしまうと GET で返した後に
      // クライアント側の切り出しが落ちる (行のない位置を指すコールを保存させない)。
      if (end > lineLength) {
        return { ok: false, error: `${at}.end out of range (line has ${lineLength} chars)` };
      }

      // anchorText は保存値をサーバが本文から切り出して作る。クライアントの申告値は
      // 「位置の数え方が一致しているか」の検算にだけ使い、食い違ったら 400 で落とす
      // (黙って別の位置を保存すると、ズレ検出の基準そのものが壊れるため)。
      const sliced = scalarSlice(lineText, start, end);
      if (anchorText !== undefined && anchorText !== null) {
        if (typeof anchorText !== "string") {
          return { ok: false, error: `${at}.anchorText must be a string` };
        }
        if (anchorText !== sliced) {
          return {
            ok: false,
            error: `${at}.anchorText does not match line text at [${start},${end}) ` +
              `(expected ${JSON.stringify(sliced)}); ` +
              `positions are counted in Unicode scalars`,
          };
        }
      }

      if (typeof text !== "string" || !text) {
        return { ok: false, error: `${at}.text must be a non-empty string` };
      }
      if (/[\r\n]/.test(text)) return { ok: false, error: `${at}.text must not contain a newline` };
      if (scalarLength(text) > MAX_CALL_TEXT_CHARS) {
        return { ok: false, error: `${at}.text too long (max ${MAX_CALL_TEXT_CHARS})` };
      }

      if (
        emphasis !== undefined &&
        emphasis !== null &&
        (typeof emphasis !== "string" || !CALL_EMPHASES.has(emphasis))
      ) {
        return {
          ok: false,
          error: `${at}.emphasis must be one of normal/optional/performer_request`,
        };
      }

      normalized.push({
        id: typeof callId === "string" && callId ? callId : "cl_" + crypto.randomUUID(),
        start,
        end,
        anchorText: sliced,
        text,
        emphasis: (emphasis as CallEmphasis) ?? "normal",
        // 今まさに本文と突き合わせた直後なのでズレは無い。stale は立てない。
      });
      // 同一アンカーに複数のコールを許す (重複チェックはしない)。配列順が表示順。
    }

    out.push({ id, clap: (clap as ClapKind) ?? null, calls: normalized });
  }

  return { ok: true, lines: out };
}

// ---------------------------------------------------------------------------
// 歌詞差し替え時の引き継ぎ
// ---------------------------------------------------------------------------

/** 未知の値が保存されていても落ちないように clap を正規化する。 */
function normalizeClap(clap: unknown): ClapKind | null {
  return typeof clap === "string" && CLAP_KINDS.has(clap) ? (clap as ClapKind) : null;
}

/**
 * 歌詞を差し替えたとき、同じ位置の旧行から clap / calls を引き継ぐ。
 *
 * PUT /admin/lyrics/:song_id は ord 順に既存の行 ID を引き継ぐ契約なので、コールも
 * 同じ規則 (同じ位置の行から) で引き継ぐ。**本文だけ直したときにコールが消えないこと**が
 * このデータモデルの要。
 *
 * 本文が変わってアンカーが指す文字列が変わったコールには stale: true を立てる
 * (消さない。位置の再設定はコールを覚えている人にしかできないので、消すと情報が失われる)。
 * 併せて start/end を新しい本文の長さに丸める。stale なコールでも GET の応答をそのまま
 * 切り出せる状態に保つため。
 */
export function carryOverAnnotation(
  prev: { clap?: unknown; calls?: unknown } | undefined,
  nextText: string
): CallAnnotation {
  const clap = normalizeClap(prev?.clap);
  const prevCalls = Array.isArray(prev?.calls) ? (prev!.calls as unknown[]) : [];
  const length = scalarLength(nextText);

  const calls: LyricCall[] = [];
  for (const raw of prevCalls) {
    if (!isPlainObject(raw)) continue;
    const anchorText = typeof raw.anchorText === "string" ? raw.anchorText : "";
    const text = typeof raw.text === "string" ? raw.text : "";
    if (!text) continue;

    const start = Math.min(isIndex(raw.start) ? raw.start : 0, length);
    const end = Math.min(Math.max(isIndex(raw.end) ? raw.end : start, start), length);
    const stale = scalarSlice(nextText, start, end) !== anchorText;

    calls.push({
      id: typeof raw.id === "string" && raw.id ? raw.id : "cl_" + crypto.randomUUID(),
      start,
      end,
      anchorText,
      text,
      emphasis:
        typeof raw.emphasis === "string" && CALL_EMPHASES.has(raw.emphasis)
          ? (raw.emphasis as CallEmphasis)
          : "normal",
      // stale は false のとき省略する (歌詞を直して元に戻したら印も消える)。
      ...(stale ? { stale: true } : {}),
    });
  }

  return { clap, calls };
}
