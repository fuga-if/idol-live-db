// master_validators.ts — /edits 用のマスタ編集検証。
//
// recordType allowlist (ck_schema) + フィールド allowlist + 型 + 制約を一元管理する。
// ログイン全開放で無検証の forceUpdate を許すと任意ユーザーがマスタを破壊できるため、
// オープン編集型は「許可フィールドのみ・型・長さ・URL/HEX/enum」を厳格に検証する。
// admin はフィールド allowlist を免除 (構造マスタの保守のため)。

import {
  isKnownRecordType,
  ADMIN_ONLY_TYPES,
  NO_CREATE_TYPES,
  NO_DELETE_TYPES,
  type CKFieldType,
} from "./ck_schema";

export type EditOp = "create" | "update" | "delete";

const HEX_RE = /^#[0-9a-fA-F]{6}$/i;
const HTTP_URL_RE = /^https?:\/\/[^\s]+$/;
const APPLE_MUSIC_URL_RE = /^https:\/\/music\.apple\.com\//;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
// ticket_sales の日時列。日付だけ (YYYY-MM-DD) か、日付+時刻 (YYYY-MM-DD HH:MM) を許す
// (imas-core の解釈と合わせる。時刻無しは domain 側で日の始まり/終わりに正規化する)。
const TICKET_MOMENT_RE = /^\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?$/;
// ticket_sales.show_ids はカンマ区切りの id (NULL = 全公演)。1 個でも成立する。
// id には @ や日本語 (第2弾 等) を含むものが実在する (JS の \w は ASCII だけなので
// [\w.-] だと 65/1219 件の show id が弾かれ、iOS/Android が毎回 showIds を送る更新が
// 常に 400 になっていた)。区切りのカンマと空白さえ含まなければ通す。
const ID_CSV_RE = /^[^,\s]+(?:,[^,\s]+)*$/;
const APPLE_MUSIC_ID_RE = /^\d{1,20}$/; // appleMusicId は数値 ID
// YouTube 動画 URL (watch / youtu.be / shorts / embed)。SongVideo.youtubeUrl 用 (確定契約 §4)。
const YOUTUBE_URL_RE =
  /^https:\/\/(?:(?:www\.|m\.)?youtube\.com\/(?:watch\?[^\s]*\bv=|shorts\/|embed\/|live\/)[\w-]+|youtu\.be\/[\w-]+)(?:[?&#][^\s]*)?$/;
const MAX_STR_DEFAULT = 500;
const MAX_STR_LONG = 2000;

interface FieldRule {
  type: CKFieldType;
  required?: boolean; // create 時に必須
  maxLen?: number;
  pattern?: RegExp;
  enum?: string[];
  url?: "apple_music" | "http" | "youtube";
  hex?: boolean;
  appleMusicId?: boolean;
  min?: number;
  max?: number;
  // TICKET_MOMENT_RE の形式に加え、実在する日時か (2026-02-30 や 24:00 等を弾く) も見る。
  ticketMoment?: boolean;
}

/**
 * ticket_sales の日時が実在するか。TICKET_MOMENT_RE (形式) を先に通した値を渡すこと。
 * 正規表現は桁数しか見ないので、2026-02-30 や 24:00 / 23:60 のような架空の日時も通ってしまう
 * (apply_data.py / imas-core と同じ穴。ここでは datetime 相当の範囲検査で弾く)。
 */
function isRealTicketMoment(value: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}))?$/.exec(value);
  if (!m) return false;
  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  if (month < 1 || month > 12) return false;
  const daysInMonth = new Date(year, month, 0).getDate(); // month は 1-indexed のまま渡してよい
  if (day < 1 || day > daysInMonth) return false;
  if (m[4] !== undefined) {
    const hour = Number(m[4]);
    const minute = Number(m[5]);
    if (hour > 23 || minute > 59) return false;
  }
  return true;
}

/** 日付だけの値を比較用に境界時刻へ正規化する (時刻つきならそのまま)。apply_data.py と同じ規則。 */
function ticketMomentBound(value: string, pad: string): string {
  return value.length > 10 ? value : `${value} ${pad}`;
}

// 各オープン編集型の編集可能フィールド (ここに無いフィールドは一般ユーザーは送れない)。
const FIELD_RULES: Record<string, Record<string, FieldRule>> = {
  Event: {
    name: { type: "STRING", required: true, maxLen: 300 },
    brandId: { type: "STRING", maxLen: 100 },
    kind: { type: "STRING", maxLen: 50 },
    eventType: { type: "STRING", maxLen: 100 },
    isSolo: { type: "INT64", min: 0, max: 1 },
    isStreaming: { type: "INT64", min: 0, max: 1 },
    // 受付開始・締切・当落は 3 つで 1 組。`ticketOpenDate` だけ規則が無く、
    // 一般ユーザーが受付開始を入れるとイベント編集が丸ごと 400 になっていた
    // (CloudKit にも DB にも列はあり、iOS/Android どちらも送っている)。
    // 旧版互換: この 3 列は ticket_sales (TicketSale レコード) に置き換わったが、
    // 旧版のアプリ (App Store 審査中・強制アップデート前) がまだこの 3 列を送ってくる。
    // 消すと旧版のイベント編集が丸ごと 400 になるので、規則ごと残す。
    ticketOpenDate: { type: "STRING", maxLen: 100 },
    ticketDeadline: { type: "STRING", maxLen: 100 },
    ticketLotteryDate: { type: "STRING", maxLen: 100 },
    ticketUrl: { type: "STRING", url: "http", maxLen: MAX_STR_DEFAULT },
    jointBrandIds: { type: "STRING", maxLen: MAX_STR_DEFAULT },
  },
  Show: {
    name: { type: "STRING", maxLen: 300 },
    eventId: { type: "STRING", required: true, maxLen: 200 },
    date: { type: "STRING", pattern: ISO_DATE_RE },
    venue: { type: "STRING", maxLen: 200 },
    // venueId は会場マスタへの参照。表示名は Venue/VenueName 側から解決するので、
    // venue (生文字列) は会場が特定できない公演のフォールバックとして残している。
    venueId: { type: "STRING", maxLen: 200 },
    hall: { type: "STRING", maxLen: 200 },
    streamPlatform: { type: "STRING", maxLen: 200 },
    venueCity: { type: "STRING", maxLen: 100 },
    startTime: { type: "STRING", maxLen: 20 },
    performerType: { type: "STRING", maxLen: 50 },
    // 会場の形態 (NULL = 観客のいる会場 / online = 会場の舞台なし / closed = 無観客)。
    venueMode: { type: "STRING", maxLen: 20 },
    sortOrder: { type: "INT64", min: 0 },
  },
  Idol: {
    // create 不可 (NO_CREATE_TYPES)。既存アイドルの誤字・属性修正用。
    name: { type: "STRING", required: true, maxLen: 100 },
    nameKana: { type: "STRING", maxLen: 100 },
    nameRomaji: { type: "STRING", maxLen: 100 },
    brandId: { type: "STRING", maxLen: 100 },
    color: { type: "STRING", hex: true },
    birthday: { type: "STRING", maxLen: 50 },
    bloodType: { type: "STRING", maxLen: 10 },
    birthPlace: { type: "STRING", maxLen: 100 },
    attribute: { type: "STRING", maxLen: 50 },
    aliases: { type: "STRING", maxLen: MAX_STR_DEFAULT },
    debutDate: { type: "STRING", maxLen: 50 },
    nickname: { type: "STRING", maxLen: 100 },
    constellation: { type: "STRING", maxLen: 50 },
    height: { type: "DOUBLE", min: 0, max: 300 },
    weight: { type: "DOUBLE", min: 0, max: 300 },
    bust: { type: "DOUBLE", min: 0, max: 300 },
    waist: { type: "DOUBLE", min: 0, max: 300 },
    hip: { type: "DOUBLE", min: 0, max: 300 },
    age: { type: "INT64", min: 0, max: 200 },
    sortOrder: { type: "INT64", min: 0 },
  },
  Song: {
    title: { type: "STRING", required: true, maxLen: 300 },
    titleKana: { type: "STRING", maxLen: 300 },
    brandId: { type: "STRING", maxLen: 100 },
    appleMusicId: { type: "STRING", appleMusicId: true, maxLen: 30 },
    appleMusicAlbumId: { type: "STRING", appleMusicId: true, maxLen: 30 },
    artworkUrl: { type: "STRING", url: "http", maxLen: MAX_STR_LONG },
    previewUrl: { type: "STRING", url: "http", maxLen: MAX_STR_LONG },
    lyricsUrl: { type: "STRING", url: "http", maxLen: MAX_STR_DEFAULT },
    cdSeries: { type: "STRING", maxLen: 200 },
    cdTitle: { type: "STRING", maxLen: 200 },
    unitName: { type: "STRING", maxLen: 200 },
    songType: { type: "STRING", maxLen: 50 },
    durationSec: { type: "INT64", min: 0, max: 100000 },
    // 制作情報 (iOS SongEditView「制作情報」セクション)。フォームに無いフィールドが
    // 編集経路から欠落してデータ消失を招いたバグの再発防止として、Song モデルの
    // 編集対象フィールドを網羅する (parentSongId/unitId は ID 参照のためスコープ外)。
    lyricist: { type: "STRING", maxLen: 200 },
    composer: { type: "STRING", maxLen: 200 },
    arranger: { type: "STRING", maxLen: 200 },
    // releaseDate は初出 (ゲーム・MV・放送を含む)。配信開始日と CD 発売日は別に持つ。
    releaseDate: { type: "STRING", pattern: ISO_DATE_RE },
    streamingDate: { type: "STRING", pattern: ISO_DATE_RE },
    cdReleaseDate: { type: "STRING", pattern: ISO_DATE_RE },
    singerLabel: { type: "STRING", maxLen: 300 },
    isrc: { type: "STRING", maxLen: 20 },
    // 曲の補足 (「ミリシタ 1 周年記念楽曲」など)。曲詳細の曲名の下に 1 文で出す自由文。
    // 利用者からの投稿が主な入口なので、長文にならないよう短めに切る。
    note: { type: "STRING", maxLen: 200 },
  },
  SetlistItem: {
    showId: { type: "STRING", required: true, maxLen: 200 },
    songId: { type: "STRING", required: true, maxLen: 200 },
    position: { type: "INT64", required: true, min: 0, max: 1000 },
    section: { type: "STRING", maxLen: 100 },
    notes: { type: "STRING", maxLen: 1000 },
    unitName: { type: "STRING", maxLen: 200 },
  },
  SetlistPerformer: {
    setlistItemId: { type: "STRING", required: true, maxLen: 200 },
    idolId: { type: "STRING", required: true, maxLen: 200 },
    castId: { type: "STRING", maxLen: 200 },
  },
  SongArtist: {
    songId: { type: "STRING", required: true, maxLen: 200 },
    idolId: { type: "STRING", required: true, maxLen: 200 },
    role: { type: "STRING", enum: ["original", "cover", "featuring", "remix"], maxLen: 30 },
  },
  ShowCast: {
    showId: { type: "STRING", required: true, maxLen: 200 },
    idolId: { type: "STRING", required: true, maxLen: 200 },
    castId: { type: "STRING", maxLen: 200 },
  },
  // 参考動画 (確定契約 §4)。フィールド名は CKRecordMapper.songVideo に厳密一致。
  // createdAt(TIMESTAMP)/authorDisplayName は allowlist 外 = ユーザーは送れない (createdAt はサーバ注入)。
  // コーレス (SongCall) は 2026-09-06 に廃止 (歌詞行につけるコールガイドに置き換わった)。
  SongVideo: {
    songId: { type: "STRING", required: true, maxLen: 200 },
    youtubeUrl: { type: "STRING", required: true, url: "youtube", maxLen: MAX_STR_DEFAULT },
    videoTitle: { type: "STRING", maxLen: 300 },
    note: { type: "STRING", maxLen: 1000 },
  },
  // チケット受付 (旧 Event.ticketOpenDate/ticketDeadline/ticketLotteryDate の後継)。
  // 1 イベントに複数の受付 (抽選/先着/リセール/当日券) を持てるようにした独立レコード。
  // 開始 ≤ 締切 ≤ 当落・日時の形式・showIds の実在は imas-core (validate_ticket_sale_draft) 側の検査で、
  // ここはオープン編集の入口としてのフィールド allowlist・型・大まかな形式だけを見る。
  TicketSale: {
    eventId: { type: "STRING", required: true, maxLen: 200 },
    // カンマ区切りの show id。空/未指定 = 対象イベントの全公演。
    showIds: { type: "STRING", pattern: ID_CSV_RE, maxLen: MAX_STR_DEFAULT },
    kind: {
      type: "STRING", required: true,
      enum: ["lottery", "first_come", "resale", "same_day"],
      maxLen: 30,
    },
    name: { type: "STRING", required: true, maxLen: 200 },
    startsAt: { type: "STRING", pattern: TICKET_MOMENT_RE, ticketMoment: true, maxLen: 20 },
    endsAt: { type: "STRING", pattern: TICKET_MOMENT_RE, ticketMoment: true, maxLen: 20 },
    resultAt: { type: "STRING", pattern: TICKET_MOMENT_RE, ticketMoment: true, maxLen: 20 },
    url: { type: "STRING", url: "http", maxLen: MAX_STR_DEFAULT },
    note: { type: "STRING", maxLen: 1000 },
    sourceUrl: { type: "STRING", required: true, url: "http", maxLen: MAX_STR_DEFAULT },
    sortOrder: { type: "INT64", min: 0 },
  },
};

function validateField(field: string, value: unknown, rule: FieldRule): string | null {
  if (rule.type === "INT64" || rule.type === "DOUBLE") {
    if (typeof value !== "number" || Number.isNaN(value)) return `${field} must be a number`;
    if (rule.type === "INT64" && !Number.isInteger(value)) return `${field} must be an integer`;
    if (rule.min !== undefined && value < rule.min) return `${field} must be >= ${rule.min}`;
    if (rule.max !== undefined && value > rule.max) return `${field} must be <= ${rule.max}`;
    return null;
  }
  // STRING
  if (typeof value !== "string") return `${field} must be a string`;
  if (value === "") return null; // 空文字は「クリア」として許可
  if (rule.maxLen && value.length > rule.maxLen) return `${field} exceeds ${rule.maxLen} chars`;
  if (rule.pattern && !rule.pattern.test(value)) return `${field} has invalid format`;
  if (rule.ticketMoment && !isRealTicketMoment(value)) return `${field} is not a real date/time`;
  if (rule.enum && !rule.enum.includes(value)) return `${field} must be one of: ${rule.enum.join(", ")}`;
  if (rule.hex && !HEX_RE.test(value)) return `${field} must be #RRGGBB`;
  if (rule.appleMusicId && !APPLE_MUSIC_ID_RE.test(value)) return `${field} must be a numeric Apple Music ID`;
  if (rule.url === "apple_music" && !APPLE_MUSIC_URL_RE.test(value)) return `${field} must be an Apple Music URL`;
  if (rule.url === "http" && !HTTP_URL_RE.test(value)) return `${field} must be an http(s) URL`;
  if (rule.url === "youtube" && !YOUTUBE_URL_RE.test(value)) return `${field} must be a YouTube URL`;
  return null;
}

export interface MasterEditInput {
  recordType: string;
  op: EditOp;
  recordName?: string;
  fields?: Record<string, unknown>;
}

/**
 * 1 件のマスタ編集を検証する。問題があればエラーメッセージ、無ければ null。
 * isAdmin の場合はフィールド allowlist と create/delete 制限を免除する。
 */
export function validateMasterEdit(input: MasterEditInput, isAdmin: boolean): string | null {
  const { recordType, op } = input;
  if (!isKnownRecordType(recordType)) return `unknown recordType: ${recordType}`;
  if (ADMIN_ONLY_TYPES.has(recordType) && !isAdmin) return `recordType ${recordType} is admin-only`;

  if (op !== "create" && op !== "update" && op !== "delete") return `invalid op: ${op}`;
  if (!input.recordName && op !== "create") return "recordName is required for update/delete";

  if (op === "create" && NO_CREATE_TYPES.has(recordType) && !isAdmin)
    return `creating ${recordType} is not allowed`;
  if (op === "delete" && NO_DELETE_TYPES.has(recordType) && !isAdmin)
    return `deleting ${recordType} is not allowed`;

  if (op === "delete") return null; // delete は recordName のみで成立

  const fields = input.fields ?? {};
  const rules = FIELD_RULES[recordType];

  // オープン編集型はフィールド allowlist が必須。admin は raw 編集可。
  if (!rules) {
    if (isAdmin) return null;
    return `no field rules defined for ${recordType}`;
  }

  for (const [k, v] of Object.entries(fields)) {
    if (k === "modifiedAt" || k === "deletedAt") continue; // サーバ管理
    const rule = rules[k];
    if (!rule) {
      if (isAdmin) continue;
      return `field ${k} is not editable on ${recordType}`;
    }
    if (v === null || v === undefined) continue; // クリア/未変更は許可
    const err = validateField(k, v, rule);
    if (err) return err;
  }

  if (op === "create") {
    for (const [k, rule] of Object.entries(rules)) {
      if (!rule.required) continue;
      const v = fields[k];
      if (v === undefined || v === null || v === "") return `field ${k} is required to create ${recordType}`;
    }
  }

  // startsAt ≤ endsAt ≤ resultAt。日付だけの値は開始側 00:00・締切/当落側 23:59 で比べる
  // (imas-core / apply_data.py と同じ規則)。1 回の編集に複数フィールドが同時に来たときだけ
  // 見られる (update で片方だけ送る編集は imas-core 側の draft 検査が最終防波堤)。
  if (recordType === "TicketSale") {
    const starts = fields.startsAt;
    const ends = fields.endsAt;
    const result = fields.resultAt;
    if (typeof starts === "string" && starts && typeof ends === "string" && ends) {
      if (ticketMomentBound(starts, "00:00") > ticketMomentBound(ends, "23:59")) {
        return "startsAt is after endsAt";
      }
    }
    if (typeof ends === "string" && ends && typeof result === "string" && result) {
      if (ticketMomentBound(ends, "23:59") > ticketMomentBound(result, "23:59")) {
        return "endsAt is after resultAt";
      }
    }
  }

  return null;
}
