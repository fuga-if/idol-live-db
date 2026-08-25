//! CloudKit レコード変換の FFI 面。ロジックは domain::ck_record_mapping。
//!
//! **通信はここに無い**。CKQuery / HTTP / カーソル / チェックポイントは各 OS に残る。
//! OS 側は取得したレコードを「フィールド名 → 値」の射影 (`CkRecordInput`) に潰して渡し、
//! 返ってきた行を自国の store に upsert する。
//!
//! 呼び出し方 (1 ページ = 1 FFI 呼び出し):
//! 1. CloudKit から 1 recordType 分のページを取る。
//! 2. iOS は `CKRecord` を `CkRecordInput` に潰して `ck_ingest_batch` を 1 回呼ぶ。
//!    Android は **レコードの生 JSON をそのまま** `ck_ingest_web_services_batch` に渡す
//!    (自前で `value` だけ拾うと TIMESTAMP が失われる。domain の受け入れ条件 1 を参照)。
//! 3. `rows` を upsert、`deleted_record_names` を削除、`invalid_record_names` を warning ログ。
//!
//! upsert 側の注意: これらの行は **共有コアが読む列しか持たない**。
//! `idols.voice_actors` のようにローカルだけが持つ列を、行全体の置換で NULL に
//! 潰さないこと (domain の受け入れ条件 2)。
//!
//! `now_millis` は投稿系 (SongCall / SongVideo) の createdAt 欠損時の既定値にだけ使う。
//! domain は OS 時刻を取らないので引数で受ける。

use crate::domain::ck_record_mapping as mapping;
use crate::domain::ck_record_mapping::{CkIngestBatch, CkRecordInput, CkRow};

/// 1 recordType 分のページを「upsert する行 / 削除する recordName / 捨てた recordName」に
/// 仕分ける。取り込み対象外の recordType (CastMember / IdolCast / 未知) は空を返す。
#[uniffi::export]
pub fn ck_ingest_batch(
    record_type: String,
    records: Vec<CkRecordInput>,
    now_millis: i64,
) -> CkIngestBatch {
    mapping::ingest_batch(&record_type, &records, now_millis)
}

/// CloudKit Web Services のレコード JSON をそのまま仕分ける (Android の正規経路)。
///
/// `record_jsons` は `{"recordName": …, "fields": {…}}` の生 JSON をレコードごとに
/// 1 要素。`serverErrorCode` を持つレコードや `continuationMarker` は transport 側の
/// 責務なので、呼ぶ前に取り除いておく。
///
/// **`fields` を `value` だけに平坦化して渡してはいけない。** CKWS は TIMESTAMP /
/// INT64 / DOUBLE を全部 JSON の数値で送るので、型を落とすと soft delete が伝搬せず、
/// 投稿の createdAt が同期のたび現在時刻に書き換わる。
#[uniffi::export]
pub fn ck_ingest_web_services_batch(
    record_type: String,
    record_jsons: Vec<String>,
    now_millis: i64,
) -> CkIngestBatch {
    mapping::ingest_web_services_batch(&record_type, &record_jsons, now_millis)
}

/// CloudKit Web Services のレコード JSON 1 件 → 射影。
/// 型を判定できないフィールドは捨てるので、壊れた JSON では空の射影になる。
#[uniffi::export]
pub fn ck_record_from_web_services_json(record_json: String) -> CkRecordInput {
    mapping::record_from_web_services_json(&record_json)
}

/// レコード 1 件だけの変換。必須キー欠損・取り込み対象外の recordType では None。
/// (バッチ経路が使えない場面の補助。通常は `ck_ingest_batch` を使う)
#[uniffi::export]
pub fn ck_map_record(
    record_type: String,
    record: CkRecordInput,
    now_millis: i64,
) -> Option<CkRow> {
    mapping::map_record(&record_type, &record, now_millis)
}

/// soft delete マーカー (`deletedAt`) のミリ秒。無ければ生存レコード。
/// 削除伝搬はこの経路のみ (CloudKit の物理削除は追わない)。
#[uniffi::export]
pub fn ck_record_deleted_at_millis(record: CkRecordInput) -> Option<i64> {
    mapping::deleted_at_millis(&record)
}

/// この recordType を取り込むか。クエリ対象を組み立てる側の事前判定用。
#[uniffi::export]
pub fn ck_is_ingested_record_type(record_type: String) -> bool {
    mapping::is_ingested_record_type(&record_type)
}

/// HEX カラーのバリデーション (6/8 桁・`#` 剥がし)。通らなければ None。
/// レコード変換の内部でも使うが、手入力の色を検証する画面からも呼べるよう公開する。
#[uniffi::export]
pub fn ck_validated_hex_color(value: Option<String>) -> Option<String> {
    mapping::validated_hex(value)
}
