// ck_schema.ts — CloudKit Public DB スキーマの型情報の単一ソース。
//
// Scripts/cloudkit_schema.ckdb から導出。buildForceUpdate の型付けと
// master_validators の検証はこの 1 ファイルを正とする。
// CloudKit には BOOL 型が無く、真偽値フィールド (isSolo 等) は INT64(0/1)。

export type CKFieldType = "STRING" | "INT64" | "DOUBLE" | "TIMESTAMP";

// STRING 以外のフィールドだけ明示列挙する (未掲載フィールド = STRING)。
// modifiedAt / deletedAt は全 recordType 共通の TIMESTAMP として別途扱う。
const NON_STRING_FIELDS: Record<string, Record<string, CKFieldType>> = {
  Brand: { sortOrder: "INT64" },
  Event: { isSolo: "INT64", isStreaming: "INT64" },
  Idol: {
    age: "INT64", isExternal: "INT64", sortOrder: "INT64",
    bust: "DOUBLE", height: "DOUBLE", hip: "DOUBLE", waist: "DOUBLE", weight: "DOUBLE",
  },
  IdolBrand: { isPrimary: "INT64" },
  IdolCast: { isCurrent: "INT64" },
  ImasUnit: { isPermanent: "INT64" },
  Show: { sortOrder: "INT64" },
  Song: { durationSec: "INT64" },
  SetlistItem: { position: "INT64" },
  // SongCall/SongVideo の createdAt は CKRecordMapper が Date で読むため TIMESTAMP
  // (authorDisplayName は STRING なので未掲載で既定の STRING になる)。
  SongCall: { createdAt: "TIMESTAMP" },
  SongVideo: { createdAt: "TIMESTAMP" },
};

const COMMON_TIMESTAMP_FIELDS = new Set(["modifiedAt", "deletedAt"]);

/** recordType.field の CloudKit 型を返す (未知フィールドは STRING)。 */
export function ckFieldType(recordType: string, field: string): CKFieldType {
  if (COMMON_TIMESTAMP_FIELDS.has(field)) return "TIMESTAMP";
  return NON_STRING_FIELDS[recordType]?.[field] ?? "STRING";
}

/** ログイン済みユーザーが update できる型。 */
export const OPEN_EDIT_TYPES = new Set([
  "Event", "Show", "Idol", "Song",
  "SetlistItem", "SetlistPerformer", "SongArtist", "ShowCast",
  // コーレス (SongCall) / 参考動画 (SongVideo) もオープン編集 (確定契約 §4)。
  "SongCall", "SongVideo",
]);

/** admin 限定の構造マスタ。一般ユーザーは編集不可。 */
export const ADMIN_ONLY_TYPES = new Set([
  "Brand", "IdolBrand", "IdolCast", "ImasUnit", "UnitMember", "CastMember", "MetaData", "Users",
]);

/** 一般ユーザーが create できない型 (既存編集のみ)。Idol は新規作成スコープ外。 */
export const NO_CREATE_TYPES = new Set(["Idol"]);

/** 一般ユーザーが delete できない型。 */
export const NO_DELETE_TYPES = new Set(["Idol"]);

/** スキーマに定義された既知の recordType か。 */
export function isKnownRecordType(t: string): boolean {
  return OPEN_EDIT_TYPES.has(t) || ADMIN_ONLY_TYPES.has(t);
}
