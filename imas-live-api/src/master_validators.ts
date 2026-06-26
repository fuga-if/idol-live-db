// master_validators.ts — /edits 用のマスタ編集検証。
//
// recordType allowlist (ck_schema) + フィールド allowlist + 型 + 制約を一元管理する。
// ログイン全開放で無検証の forceUpdate を許すと任意ユーザーがマスタを破壊できるため、
// オープン編集型は「許可フィールドのみ・型・長さ・URL/HEX/enum」を厳格に検証する。
// admin はフィールド allowlist を免除 (構造マスタの保守のため)。

import {
  ckFieldType,
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
const APPLE_MUSIC_ID_RE = /^\d{1,20}$/; // appleMusicId は数値 ID
// YouTube 動画 URL (watch / youtu.be / shorts / embed)。SongVideo.youtubeUrl 用 (確定契約 §4)。
const YOUTUBE_URL_RE =
  /^https:\/\/(?:(?:www\.|m\.)?youtube\.com\/(?:watch\?[^\s]*\bv=|shorts\/|embed\/|live\/)[\w-]+|youtu\.be\/[\w-]+)(?:[?&#][^\s]*)?$/;
const MAX_STR_DEFAULT = 500;
const MAX_STR_LONG = 2000;
const MAX_STR_CALL = 5000; // SongCall.callText (コーレスは長文になりうる)

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
    venueCity: { type: "STRING", maxLen: 100 },
    startTime: { type: "STRING", maxLen: 20 },
    performerType: { type: "STRING", maxLen: 50 },
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
    releaseDate: { type: "STRING", pattern: ISO_DATE_RE },
    singerLabel: { type: "STRING", maxLen: 300 },
    isrc: { type: "STRING", maxLen: 20 },
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
  // コーレス (確定契約 §4)。フィールド名は CKRecordMapper.songCall に厳密一致。
  // createdAt(TIMESTAMP)/authorDisplayName は allowlist 外 = ユーザーは送れない (createdAt はサーバ注入)。
  SongCall: {
    songId: { type: "STRING", required: true, maxLen: 200 },
    callText: { type: "STRING", required: true, maxLen: MAX_STR_CALL },
    sourceUrl: { type: "STRING", url: "http", maxLen: MAX_STR_DEFAULT },
  },
  // 参考動画 (確定契約 §4)。フィールド名は CKRecordMapper.songVideo に厳密一致。
  SongVideo: {
    songId: { type: "STRING", required: true, maxLen: 200 },
    youtubeUrl: { type: "STRING", required: true, url: "youtube", maxLen: MAX_STR_DEFAULT },
    videoTitle: { type: "STRING", maxLen: 300 },
    note: { type: "STRING", maxLen: 1000 },
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
  return null;
}
