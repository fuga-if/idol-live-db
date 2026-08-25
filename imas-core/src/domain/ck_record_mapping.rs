//! CloudKit レコード → 行 の変換規則 (Phase 8-B1)。
//!
//! **通信は共有しない**。iOS は CloudKit.framework、Android は CloudKit Web Services で
//! transport が非対称なので、共有するのは「レコード ↔ 行」の変換規則と
//! 「何を取り込み何を捨てるかの判定」だけ。CKQuery 組み立て・HTTP・カーソル・
//! チェックポイントは各 OS に残る。
//!
//! 移送元:
//! - iOS `Services/CKRecordMapper.swift` (**こちらが正**)
//! - Android `data/sync/SyncMappers.kt` + `CkRecord.kt` (iOS の後追い実装)
//!
//! ## transport 非対称の吸収
//!
//! OS 側は「フィールド名 → 値」の射影 ([`CkRecordInput`]) に潰してから渡す。
//! - iOS: `CKRecord` の各キーを `CKRecordValue` の実型で [`CkValue`] に振り分ける
//!   (`String` → Text / `Int64` → Int / `Double` → Real / `Bool` → Bool / `Date` → Timestamp)。
//! - Android: CloudKit Web Services (CKWS) の `{"value": X, "type": "STRING"|"INT64"|...}`
//!   を type で振り分ける。**この振り分けは手で書かず [`record_from_web_services_json`] /
//!   [`ingest_web_services_batch`] に生 JSON を渡す** (下の受け入れ条件 1 を参照)。
//!
//! `CKRecord` そのものや CloudKit の型は FFI に通さない。
//!
//! ## OS 側の受け入れ条件 (満たさない移植は黙って壊れる)
//!
//! 1. **CKWS の `type` を捨てない。** CKWS は TIMESTAMP / INT64 / DOUBLE を
//!    どれも JSON の数値で送るので、`fields[k] = json.getJSONObject(k).opt("value")`
//!    のように value だけ平坦化すると型が復元できなくなる。壊れ方は 2 つ:
//!    (a) `deletedAt` が [`CkValue::Int`] に潰れて [`deleted_at_millis`] が None を返し、
//!        soft delete が 1 件も伝搬しない (消えたはずの行が残り続ける)。
//!    (b) SongCall / SongVideo の `createdAt` が Date と認識されず `now_millis` に
//!        フォールバックして、投稿日時が同期のたび書き換わる。
//!    → Kotlin では HTTP と `serverErrorCode` / `continuationMarker` だけ扱い、
//!      レコードの生 JSON を [`ingest_web_services_batch`] に渡せばこの条件は自動で満たされる。
//!
//! 2. **共有コアが読まない列を upsert で NULL 上書きしない。** [`CkIdolRow`] は
//!    `voiceActors` を **意図的に読まない** (声優は idol_voice_actors が正)。
//!    行全体を置換する store (Android の Room `@Upsert` 等) にそのまま流すと
//!    ローカルの `idols.voice_actors` が同期のたび消え、CV 表示が空になる。
//!    列を温存する更新 (対象列だけの UPDATE / COALESCE) にするか、
//!    idol_voice_actors 参照へ切り替えてから差し替えること。
//!    同型の事故が `seriesGroup` の読み落としで実際に起きている ([`CkSongRow`])。
//!
//! ## 値の取り出し規則 (iOS の private helper を逐語移送)
//!
//! | helper | Text | Int | Real | Bool | Timestamp | 欠損 |
//! |---|---|---|---|---|---|---|
//! | `str` (`as? String`) | そのまま (空文字も保持) | None | None | None | None | None |
//! | `int_value` | 0 | v | 切り捨て | 1/0 | 0 | 0 |
//! | `optional_int_value` | None | v | 切り捨て | 1/0 | None | None |
//! | `double_value` | None | v as f64 | v | 1.0/0.0 | None | None |
//! | `bool_value(default)` | default | v != 0 | v != 0.0 | v | default | default |
//! | `timestamp_millis` | None | None | None | None | v | None |
//!
//! Real → Int の切り捨ては `NSNumber.intValue` (ゼロ方向切り捨て) に合わせる。
//! Bool が数値経路を通るのは、CloudKit の型に BOOL が無く INT64 で載るため
//! (ローカル生成レコードだけが真の Bool を持つ)。
//!
//! ## 不正値の扱い
//!
//! 必須キー (id / name / 外部キー) が空か非文字列なら **その 1 件だけ捨てる**
//! (iOS の `compactMap` + warning ログと同じ)。既定値で埋めて通すことはしない。
//! 任意項目は型違いなら「無かったこと」にして既定値へ倒す。

use std::collections::HashMap;

// ---- FFI 射影 (入力) ----

/// CloudKit の 1 フィールド値。OS 側が自国の表現からこの 5 種に潰して渡す。
#[derive(uniffi::Enum, Clone, Debug, PartialEq)]
pub enum CkValue {
    /// STRING。空文字も「値がある」扱い (iOS の `as? String` と同じ)。
    Text { value: String },
    /// INT64。
    Int { value: i64 },
    /// DOUBLE。
    Real { value: f64 },
    /// 真の Bool (ローカル生成レコード由来)。CloudKit 上は INT64 で来る。
    Bool { value: bool },
    /// TIMESTAMP。epoch からのミリ秒。
    Timestamp { millis: i64 },
}

/// フィールド 1 個の射影。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkField {
    pub key: String,
    pub value: CkValue,
}

/// レコード 1 件の射影。`record_name` は `CKRecord.recordID.recordName` 相当。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkRecordInput {
    pub record_name: String,
    /// キー重複は本来起きない。起きた場合は辞書の上書きに合わせて **後勝ち**。
    pub fields: Vec<CkField>,
}

// ---- CloudKit Web Services (JSON) → 射影 ----

/// CKWS の 1 フィールド `{"value": …, "type": "STRING"}` を [`CkValue`] に振り分ける。
///
/// **`type` を見ずに `value` だけ拾ってはいけない。** CKWS は TIMESTAMP / INT64 /
/// DOUBLE をどれも JSON の数値で送るので、type を落とすと日付が整数と区別できなくなり、
/// soft delete の伝搬と投稿日時が壊れる (モジュール doc の受け入れ条件 1)。
///
/// 判定できない形 (オブジェクトでない / `type` が無い / `value` の JSON 型が合わない) は
/// **そのフィールドごと捨てる**。既定値で通すと平坦化バグが黙って進むので、
/// 必須キーが落ちてレコードごと弾かれる (= すぐ露見する) 側に倒す。
///
/// CKWS に BOOL 型は無いので、ここから [`CkValue::Bool`] は出ない
/// (真の Bool を持つのは端末でローカル生成したレコードだけ)。
/// 取り込む列が無い型 (BYTES / REFERENCE / ASSETID / LOCATION / *_LIST) も欠損扱い。
pub fn ck_value_from_web_services(field: &serde_json::Value) -> Option<CkValue> {
    let ty = field.get("type")?.as_str()?;
    let value = field.get("value")?;
    match ty {
        "STRING" => Some(CkValue::Text { value: value.as_str()?.to_string() }),
        "INT64" => Some(CkValue::Int { value: json_i64(value)? }),
        "DOUBLE" => Some(CkValue::Real { value: value.as_f64()? }),
        "TIMESTAMP" => Some(CkValue::Timestamp { millis: json_i64(value)? }),
        _ => None,
    }
}

/// JSON 数値 → i64。CKWS は整数を数値で送るが、経路によっては小数表現になるので
/// `intValue` と同じゼロ方向切り捨てで受ける。数値でなければ None。
fn json_i64(value: &serde_json::Value) -> Option<i64> {
    value.as_i64().or_else(|| value.as_f64().map(truncate_to_i64))
}

/// CKWS の `fields` オブジェクト → フィールド射影。
/// 同じキーが 2 度現れたら辞書と同じく後勝ち (serde_json の Map と同じ)。
fn fields_from_web_services_object(fields: &serde_json::Value) -> Vec<CkField> {
    let Some(map) = fields.as_object() else { return Vec::new() };
    map.iter()
        .filter_map(|(key, raw)| {
            ck_value_from_web_services(raw).map(|value| CkField { key: key.clone(), value })
        })
        .collect()
}

/// CKWS のレコード 1 件 (`{"recordName": …, "fields": {…}}`) の生 JSON → 射影。
///
/// 通信は共有しないが、**ワイヤ表現から [`CkValue`] への振り分けは変換規則**なので
/// ここに置く。OS 側は HTTP と `serverErrorCode` / `continuationMarker` だけ扱えばよく、
/// 型を落とす平坦化を各 OS で書き直す必要がなくなる。
///
/// JSON が壊れていても落とさず空の射影を返す (必須キーが無い扱いになり、
/// バッチ仕分けで `invalid_record_names` に載る)。
pub fn record_from_web_services_json(record_json: &str) -> CkRecordInput {
    let parsed = serde_json::from_str::<serde_json::Value>(record_json).unwrap_or_default();
    let record_name =
        parsed.get("recordName").and_then(serde_json::Value::as_str).unwrap_or_default();
    let fields = parsed.get("fields").map(fields_from_web_services_object).unwrap_or_default();
    CkRecordInput { record_name: record_name.to_string(), fields }
}

/// `recordName` を別に持っている呼び出し側向けに、`fields` の生 JSON だけ受ける版。
pub fn record_from_web_services_fields(record_name: &str, fields_json: &str) -> CkRecordInput {
    let parsed = serde_json::from_str::<serde_json::Value>(fields_json).unwrap_or_default();
    CkRecordInput {
        record_name: record_name.to_string(),
        fields: fields_from_web_services_object(&parsed),
    }
}

/// フィールド射影を辞書に潰した読み取り面。iOS の `record["key"]` に相当する。
struct Fields<'a> {
    record_name: &'a str,
    map: HashMap<&'a str, &'a CkValue>,
}

impl<'a> Fields<'a> {
    fn new(record: &'a CkRecordInput) -> Self {
        let mut map = HashMap::with_capacity(record.fields.len());
        for f in &record.fields {
            // 後勝ち: 同じキーを 2 度 insert した辞書と同じ結果にする。
            map.insert(f.key.as_str(), &f.value);
        }
        Self { record_name: &record.record_name, map }
    }

    fn get(&self, key: &str) -> Option<&'a CkValue> {
        self.map.get(key).copied()
    }

    /// `record[key] as? String`。空文字も保持する (Android の `str()` は空文字を
    /// null に潰すが、iOS が正なのでここでは保持する)。
    fn str(&self, key: &str) -> Option<String> {
        match self.get(key) {
            Some(CkValue::Text { value }) => Some(value.clone()),
            _ => None,
        }
    }

    /// `record[key] as? String ?? ""`。
    fn str_or_empty(&self, key: &str) -> String {
        self.str(key).unwrap_or_default()
    }

    /// `record[key] as? String ?? fallback`。空文字はそのまま (fallback に倒さない)。
    fn str_or(&self, key: &str, fallback: &str) -> String {
        self.str(key).unwrap_or_else(|| fallback.to_string())
    }

    /// iOS `intValue(_:)`。欠損・型違いは 0。
    fn int_value(&self, key: &str) -> i64 {
        self.optional_int_value(key).unwrap_or(0)
    }

    /// iOS `optionalIntValue(_:)`。欠損・非数値は None。
    fn optional_int_value(&self, key: &str) -> Option<i64> {
        match self.get(key)? {
            CkValue::Int { value } => Some(*value),
            // NSNumber.intValue と同じくゼロ方向へ切り捨てる。
            CkValue::Real { value } => Some(truncate_to_i64(*value)),
            CkValue::Bool { value } => Some(i64::from(*value)),
            CkValue::Text { .. } | CkValue::Timestamp { .. } => None,
        }
    }

    /// `record[key] as? Double`。
    fn double_value(&self, key: &str) -> Option<f64> {
        match self.get(key)? {
            CkValue::Real { value } => Some(*value),
            CkValue::Int { value } => Some(*value as f64),
            CkValue::Bool { value } => Some(if *value { 1.0 } else { 0.0 }),
            CkValue::Text { .. } | CkValue::Timestamp { .. } => None,
        }
    }

    /// iOS `boolValue(_:default:)`。数値は 0 以外が true。
    fn bool_value(&self, key: &str, default: bool) -> bool {
        match self.get(key) {
            Some(CkValue::Bool { value }) => *value,
            Some(CkValue::Int { value }) => *value != 0,
            Some(CkValue::Real { value }) => *value != 0.0,
            _ => default,
        }
    }

    /// `record[key] as? Int64` 単発 (NSNumber へのフォールバック無し)。
    ///
    /// NSNumber → Int64 のブリッジは「値が Int64 で厳密に表せるか」で判定するので、
    /// 真偽値 (0/1) と整数値の Double は通り、小数を持つ Double は通らない。
    /// `intValue` (= NSNumber.intValue で切り捨て) との違いはここだけ。
    fn int64_exact(&self, key: &str) -> Option<i64> {
        match self.get(key)? {
            CkValue::Int { value } => Some(*value),
            CkValue::Bool { value } => Some(i64::from(*value)),
            CkValue::Real { value } => {
                let truncated = truncate_to_i64(*value);
                (value.fract() == 0.0 && truncated as f64 == *value).then_some(truncated)
            }
            CkValue::Text { .. } | CkValue::Timestamp { .. } => None,
        }
    }

    /// `record[key] as? Date`。Date 以外は None (数値の TIMESTAMP でも
    /// Text で来たら日付として扱わない)。
    fn timestamp_millis(&self, key: &str) -> Option<i64> {
        match self.get(key)? {
            CkValue::Timestamp { millis } => Some(*millis),
            _ => None,
        }
    }

    /// `record["id"] as? String ?? record.recordID.recordName` + 空チェック。
    ///
    /// **id フィールドが空文字なら recordName に落ちない**ことに注意
    /// (`as? String` は成功するので `??` が働かず、空チェックで捨てる)。
    /// Android は空文字を null に潰してから `?:` するため recordName に落ちる。
    fn entity_id(&self) -> Option<String> {
        let id = self.str("id").unwrap_or_else(|| self.record_name.to_string());
        non_empty(id)
    }

    /// 必須の文字列キー。欠損・型違い・空文字なら None (= レコードごと捨てる)。
    fn required(&self, key: &str) -> Option<String> {
        non_empty(self.str_or_empty(key))
    }
}

fn non_empty(value: String) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

/// `NSNumber.intValue` 相当のゼロ方向切り捨て。NaN / 範囲外は 0
/// (Objective-C の未定義域なので、落とさず 0 に倒す)。
fn truncate_to_i64(value: f64) -> i64 {
    if value.is_nan() {
        return 0;
    }
    let truncated = value.trunc();
    if truncated >= i64::MAX as f64 || truncated <= i64::MIN as f64 {
        return 0;
    }
    truncated as i64
}

// ---- 行 (出力) ----

/// brands
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkBrandRow {
    pub id: String,
    pub name: String,
    pub short_name: String,
    pub color: Option<String>,
    pub sort_order: i64,
    pub icon_url: Option<String>,
}

/// idols
///
/// `voiceActors` は **読まない**。声優は idol_voice_actors (期間つき履歴) が正で、
/// Idol からは外した。CloudKit 側のフィールドは旧アプリ向けにまだ送っているが、
/// こちらで読むと廃止した列に書き戻そうとして落ちる。
///
/// その裏返しとして、**この行を「行全体の置換」で書く store は
/// ローカルの `voice_actors` 列を消す**。Android の Room は行を丸ごと置換するので、
/// 素直に差し替えると CV 表示が同期のたび空になる (モジュール doc の受け入れ条件 2)。
/// 列を温存する更新にするか idol_voice_actors 参照へ切り替えてから移植すること。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkIdolRow {
    pub id: String,
    pub brand_id: String,
    pub name: String,
    pub name_kana: Option<String>,
    pub name_romaji: Option<String>,
    pub family_name: Option<String>,
    pub given_name: Option<String>,
    pub nickname: Option<String>,
    pub color: Option<String>,
    pub sort_order: i64,
    pub birthday: Option<String>,
    pub blood_type: Option<String>,
    pub height: Option<f64>,
    pub weight: Option<f64>,
    pub birth_place: Option<String>,
    pub age: Option<i64>,
    pub bust: Option<f64>,
    pub waist: Option<f64>,
    pub hip: Option<f64>,
    pub constellation: Option<String>,
    pub hobbies: Option<String>,
    pub talents: Option<String>,
    pub description: Option<String>,
    pub gender: Option<String>,
    pub handedness: Option<String>,
    pub debut_date: Option<String>,
    pub attribute: Option<String>,
    pub is_external: bool,
    pub aliases: Option<String>,
}

/// events
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkEventRow {
    pub id: String,
    pub brand_id: Option<String>,
    pub name: String,
    pub event_type: String,
    pub is_streaming: bool,
    pub is_solo: bool,
    pub kind: String,
    pub ticket_open_date: Option<String>,
    pub ticket_deadline: Option<String>,
    pub ticket_lottery_date: Option<String>,
    pub ticket_url: Option<String>,
    pub joint_brand_ids: Option<String>,
}

/// shows
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkShowRow {
    pub id: String,
    pub event_id: String,
    pub name: String,
    pub date: String,
    pub venue: Option<String>,
    pub venue_id: Option<String>,
    pub hall: Option<String>,
    pub stream_platform: Option<String>,
    pub venue_city: Option<String>,
    pub start_time: Option<String>,
    pub sort_order: i64,
    pub performer_type: Option<String>,
}

/// venues
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkVenueRow {
    pub id: String,
    pub name: String,
    pub name_kana: Option<String>,
    pub prefecture: Option<String>,
    pub city: Option<String>,
    pub aliases: Option<String>,
    pub capacity: Option<i64>,
    pub sort_order: i64,
}

/// venue_names
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkVenueNameRow {
    pub id: String,
    pub venue_id: String,
    pub name: String,
    pub valid_from: Option<String>,
    pub valid_to: Option<String>,
}

/// venue_halls
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkVenueHallRow {
    pub id: String,
    pub venue_id: String,
    pub name: String,
    pub capacity: Option<i64>,
}

/// songs
///
/// 列を足したらここにも足すこと。読み落とすと upsert が Song の全列を書くため、
/// 同期のたび NULL 上書きされる (series_group で実際に壊れた)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkSongRow {
    pub id: String,
    pub title: String,
    pub title_kana: Option<String>,
    pub brand_id: Option<String>,
    pub song_type: String,
    pub release_date: Option<String>,
    pub duration_sec: Option<i64>,
    pub composer: Option<String>,
    pub lyricist: Option<String>,
    pub arranger: Option<String>,
    pub cd_series: Option<String>,
    pub cd_title: Option<String>,
    pub artwork_url: Option<String>,
    pub preview_url: Option<String>,
    pub apple_music_id: Option<String>,
    pub apple_music_album_id: Option<String>,
    pub isrc: Option<String>,
    pub lyrics_url: Option<String>,
    pub parent_song_id: Option<String>,
    pub singer_label: Option<String>,
    pub unit_name: Option<String>,
    pub unit_id: Option<String>,
    pub series_group: Option<String>,
}

/// units
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkUnitRow {
    pub id: String,
    pub brand_id: String,
    pub name: String,
    pub is_permanent: bool,
    pub name_alt: Option<String>,
}

/// idol_brands
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkIdolBrandRow {
    pub idol_id: String,
    pub brand_id: String,
    pub is_primary: bool,
}

/// song_artists
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkSongArtistRow {
    pub song_id: String,
    pub idol_id: String,
    pub role: String,
}

/// unit_members
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkUnitMemberRow {
    pub unit_id: String,
    pub idol_id: String,
}

/// show_cast
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkShowCastRow {
    pub show_id: String,
    pub idol_id: String,
    /// "member" / "lead" / "guest" のいずれかに正規化済み。
    pub cast_role: String,
}

/// setlist_items
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkSetlistItemRow {
    pub id: String,
    pub show_id: String,
    pub song_id: String,
    pub position: i64,
    pub section: Option<String>,
    pub notes: Option<String>,
    pub unit_name: Option<String>,
}

/// setlist_performers
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkSetlistPerformerRow {
    pub setlist_item_id: String,
    pub idol_id: String,
}

/// song_calls
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkSongCallRow {
    pub id: String,
    pub song_id: String,
    pub call_text: String,
    pub source_url: Option<String>,
    /// ISO8601 (`yyyy-MM-dd'T'HH:mm:ss'Z'`)。
    pub created_at: String,
    pub author_display_name: Option<String>,
}

/// song_videos
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CkSongVideoRow {
    pub id: String,
    pub song_id: String,
    pub youtube_url: String,
    pub video_title: Option<String>,
    pub note: Option<String>,
    /// ISO8601 (`yyyy-MM-dd'T'HH:mm:ss'Z'`)。
    pub created_at: String,
    pub author_display_name: Option<String>,
}

/// recordType ごとの変換結果。どのテーブルへ upsert するかは変種で決まる。
#[derive(uniffi::Enum, Clone, Debug, PartialEq)]
pub enum CkRow {
    Brand { row: CkBrandRow },
    Idol { row: CkIdolRow },
    Event { row: CkEventRow },
    Show { row: CkShowRow },
    Venue { row: CkVenueRow },
    VenueName { row: CkVenueNameRow },
    VenueHall { row: CkVenueHallRow },
    Song { row: CkSongRow },
    Unit { row: CkUnitRow },
    IdolBrand { row: CkIdolBrandRow },
    SongArtist { row: CkSongArtistRow },
    UnitMember { row: CkUnitMemberRow },
    ShowCast { row: CkShowCastRow },
    SetlistItem { row: CkSetlistItemRow },
    SetlistPerformer { row: CkSetlistPerformerRow },
    SongCall { row: CkSongCallRow },
    SongVideo { row: CkSongVideoRow },
}

/// 1 recordType 分のバッチを「取り込む行 / 削除する recordName / 捨てた recordName」に
/// 仕分けた結果。iOS `CloudKitSyncEngine` の deletedAt 分割 + `compactMap` に対応する。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Default)]
pub struct CkIngestBatch {
    /// upsert すべき行 (入力順)。
    pub rows: Vec<CkRow>,
    /// soft delete (deletedAt あり) の recordName。削除伝搬はこの経路のみ。
    pub deleted_record_names: Vec<String>,
    /// 必須キー欠損で捨てた recordName (OS 側の warning ログ用)。
    /// 取り込み対象外の recordType (CastMember / IdolCast など) はここにも入らない。
    pub invalid_record_names: Vec<String>,
}

// ---- 変換規則 ----

/// HEX カラーのバリデーション。iOS `HexColor.init(rawValue:)` と同じで、
/// 前後の `#` を剥がして 6 桁か 8 桁 (アルファ付き) の hex 数字だけ通す。
/// 通らなければ **色なし** にする (元の文字列を残さない)。
pub fn validated_hex(value: Option<String>) -> Option<String> {
    let raw = value?;
    // trimmingCharacters(in: "#") は前後両方から `#` を剥がす (途中の `#` は残る)。
    let stripped = raw.trim_matches('#');
    let len = stripped.chars().count();
    if stripped.is_empty() || !(len == 6 || len == 8) {
        return None;
    }
    if !stripped.chars().all(is_hex_digit) {
        return None;
    }
    Some(stripped.to_string())
}

/// Swift `Character.isHexDigit` 相当。Unicode の Hex_Digit プロパティなので
/// ASCII だけでなく全角の 0-9 / A-F / a-f も含む。
fn is_hex_digit(c: char) -> bool {
    c.is_ascii_hexdigit()
        || matches!(c, '\u{FF10}'..='\u{FF19}' | '\u{FF21}'..='\u{FF26}' | '\u{FF41}'..='\u{FF46}')
}

/// epoch ミリ秒 → `ISO8601DateFormatter` (`.withInternetDateTime`, UTC) の文字列。
/// 秒未満は切り捨て (負の時刻でも床方向。カレンダー表示と同じ向き)。
pub fn iso8601_internet_date_time(millis: i64) -> String {
    let secs = millis.div_euclid(1000);
    match chrono::DateTime::from_timestamp(secs, 0) {
        Some(dt) => dt.format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        // 表現不能な時刻は epoch に倒す (実データでは起きない)。
        None => "1970-01-01T00:00:00Z".to_string(),
    }
}

/// `record["createdAt"] as? Date ?? Date()` を ISO8601 にした文字列。
/// OS 時刻は domain で取らないので `now_millis` で受ける。
fn created_at_string(f: &Fields, now_millis: i64) -> String {
    iso8601_internet_date_time(f.timestamp_millis("createdAt").unwrap_or(now_millis))
}

/// soft delete マーカー。`deletedAt` が Date で入っていれば削除レコード。
pub fn deleted_at_millis(record: &CkRecordInput) -> Option<i64> {
    Fields::new(record).timestamp_millis("deletedAt")
}

pub fn brand(record: &CkRecordInput) -> Option<CkBrandRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let name = f.required("name")?;
    Some(CkBrandRow {
        id,
        name,
        short_name: f.str_or_empty("shortName"),
        color: validated_hex(f.str("color")),
        sort_order: f.int_value("sortOrder"),
        icon_url: f.str("iconUrl"),
    })
}

pub fn idol(record: &CkRecordInput) -> Option<CkIdolRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let name = f.required("name")?;
    Some(CkIdolRow {
        id,
        brand_id: f.str_or_empty("brandId"),
        name,
        name_kana: f.str("nameKana"),
        name_romaji: f.str("nameRomaji"),
        family_name: f.str("familyName"),
        given_name: f.str("givenName"),
        nickname: f.str("nickname"),
        color: validated_hex(f.str("color")),
        sort_order: f.int_value("sortOrder"),
        birthday: f.str("birthday"),
        blood_type: f.str("bloodType"),
        height: f.double_value("height"),
        weight: f.double_value("weight"),
        birth_place: f.str("birthPlace"),
        age: f.optional_int_value("age"),
        bust: f.double_value("bust"),
        waist: f.double_value("waist"),
        hip: f.double_value("hip"),
        constellation: f.str("constellation"),
        hobbies: f.str("hobbies"),
        talents: f.str("talents"),
        description: f.str("description"),
        gender: f.str("gender"),
        handedness: f.str("handedness"),
        debut_date: f.str("debutDate"),
        attribute: f.str("attribute"),
        // ここだけ boolValue ヘルパーを通さず `(as? Int64 ?? 0) != 0` で書かれている。
        // 実データは INT64 なので差は出ないが、小数つき Double だけ false に倒れる。
        is_external: f.int64_exact("isExternal").unwrap_or(0) != 0,
        aliases: f.str("aliases"),
    })
}

pub fn event(record: &CkRecordInput) -> Option<CkEventRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let name = f.required("name")?;
    Some(CkEventRow {
        id,
        brand_id: f.str("brandId"),
        name,
        event_type: f.str_or("eventType", "live"),
        is_streaming: f.bool_value("isStreaming", false),
        // 単独開催が既定 (合同ライブの方が少数派)。
        is_solo: f.bool_value("isSolo", true),
        kind: f.str_or("kind", "live"),
        ticket_open_date: f.str("ticketOpenDate"),
        ticket_deadline: f.str("ticketDeadline"),
        ticket_lottery_date: f.str("ticketLotteryDate"),
        ticket_url: f.str("ticketUrl"),
        joint_brand_ids: f.str("jointBrandIds"),
    })
}

pub fn show(record: &CkRecordInput) -> Option<CkShowRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let event_id = f.required("eventId")?;
    let date = f.required("date")?;
    Some(CkShowRow {
        id,
        event_id,
        name: f.str_or_empty("name"),
        date,
        venue: f.str("venue"),
        venue_id: f.str("venueId"),
        hall: f.str("hall"),
        stream_platform: f.str("streamPlatform"),
        venue_city: f.str("venueCity"),
        start_time: f.str("startTime"),
        sort_order: f.int_value("sortOrder"),
        performer_type: f.str("performerType"),
    })
}

pub fn venue(record: &CkRecordInput) -> Option<CkVenueRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let name = f.required("name")?;
    Some(CkVenueRow {
        id,
        name,
        name_kana: f.str("nameKana"),
        prefecture: f.str("prefecture"),
        city: f.str("city"),
        aliases: f.str("aliases"),
        capacity: f.optional_int_value("capacity"),
        sort_order: f.int_value("sortOrder"),
    })
}

pub fn venue_name(record: &CkRecordInput) -> Option<CkVenueNameRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let venue_id = f.required("venueId")?;
    let name = f.required("name")?;
    Some(CkVenueNameRow {
        id,
        venue_id,
        name,
        valid_from: f.str("validFrom"),
        valid_to: f.str("validTo"),
    })
}

pub fn venue_hall(record: &CkRecordInput) -> Option<CkVenueHallRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let venue_id = f.required("venueId")?;
    let name = f.required("name")?;
    Some(CkVenueHallRow { id, venue_id, name, capacity: f.optional_int_value("capacity") })
}

pub fn song(record: &CkRecordInput) -> Option<CkSongRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let title = f.required("title")?;
    Some(CkSongRow {
        id,
        title,
        title_kana: f.str("titleKana"),
        brand_id: f.str("brandId"),
        song_type: f.str_or("songType", "solo"),
        release_date: f.str("releaseDate"),
        duration_sec: f.optional_int_value("durationSec"),
        composer: f.str("composer"),
        lyricist: f.str("lyricist"),
        arranger: f.str("arranger"),
        cd_series: f.str("cdSeries"),
        cd_title: f.str("cdTitle"),
        artwork_url: f.str("artworkUrl"),
        preview_url: f.str("previewUrl"),
        apple_music_id: f.str("appleMusicId"),
        apple_music_album_id: f.str("appleMusicAlbumId"),
        isrc: f.str("isrc"),
        lyrics_url: f.str("lyricsUrl"),
        parent_song_id: f.str("parentSongId"),
        singer_label: f.str("singerLabel"),
        unit_name: f.str("unitName"),
        unit_id: f.str("unitId"),
        series_group: f.str("seriesGroup"),
    })
}

pub fn unit(record: &CkRecordInput) -> Option<CkUnitRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let name = f.required("name")?;
    Some(CkUnitRow {
        id,
        brand_id: f.str_or_empty("brandId"),
        name,
        // 常設ユニットが既定 (期間限定の方が少数派)。
        is_permanent: f.bool_value("isPermanent", true),
        name_alt: f.str("nameAlt"),
    })
}

pub fn idol_brand(record: &CkRecordInput) -> Option<CkIdolBrandRow> {
    let f = Fields::new(record);
    let idol_id = f.required("idolId")?;
    let brand_id = f.required("brandId")?;
    Some(CkIdolBrandRow { idol_id, brand_id, is_primary: f.bool_value("isPrimary", false) })
}

pub fn song_artist(record: &CkRecordInput) -> Option<CkSongArtistRow> {
    let f = Fields::new(record);
    let song_id = f.required("songId")?;
    let idol_id = f.required("idolId")?;
    Some(CkSongArtistRow { song_id, idol_id, role: f.str_or("role", "original") })
}

pub fn unit_member(record: &CkRecordInput) -> Option<CkUnitMemberRow> {
    let f = Fields::new(record);
    let unit_id = f.required("unitId")?;
    let idol_id = f.required("idolId")?;
    Some(CkUnitMemberRow { unit_id, idol_id })
}

pub fn show_cast(record: &CkRecordInput) -> Option<CkShowCastRow> {
    let f = Fields::new(record);
    let show_id = f.required("showId")?;
    // 新スキーマは idolId フィールド。旧 CK レコードの castId は廃止 (取り込まない)。
    let idol_id = f.required("idolId")?;
    Some(CkShowCastRow { show_id, idol_id, cast_role: cast_role(f.str_or("castRole", "member")) })
}

/// `CastRole(rawValue:) ?? .member`。未知の役割は落とさず member に倒す。
fn cast_role(raw: String) -> String {
    match raw.as_str() {
        "member" | "lead" | "guest" => raw,
        _ => "member".to_string(),
    }
}

pub fn setlist_item(record: &CkRecordInput) -> Option<CkSetlistItemRow> {
    let f = Fields::new(record);
    let id = f.entity_id()?;
    let show_id = f.required("showId")?;
    let song_id = f.required("songId")?;
    Some(CkSetlistItemRow {
        id,
        show_id,
        song_id,
        position: f.int_value("position"),
        section: f.str("section"),
        notes: f.str("notes"),
        unit_name: f.str("unitName"),
    })
}

pub fn setlist_performer(record: &CkRecordInput) -> Option<CkSetlistPerformerRow> {
    let f = Fields::new(record);
    let setlist_item_id = f.required("setlistItemId")?;
    let idol_id = f.required("idolId")?;
    Some(CkSetlistPerformerRow { setlist_item_id, idol_id })
}

pub fn song_call(record: &CkRecordInput, now_millis: i64) -> Option<CkSongCallRow> {
    let f = Fields::new(record);
    let song_id = f.required("songId")?;
    let call_text = f.required("callText")?;
    Some(CkSongCallRow {
        // 投稿系は id フィールドを持たず recordName が主キー。
        id: record.record_name.clone(),
        song_id,
        call_text,
        source_url: f.str("sourceUrl"),
        created_at: created_at_string(&f, now_millis),
        author_display_name: f.str("authorDisplayName"),
    })
}

pub fn song_video(record: &CkRecordInput, now_millis: i64) -> Option<CkSongVideoRow> {
    let f = Fields::new(record);
    let song_id = f.required("songId")?;
    let youtube_url = f.required("youtubeUrl")?;
    Some(CkSongVideoRow {
        id: record.record_name.clone(),
        song_id,
        youtube_url,
        video_title: f.str("videoTitle"),
        note: f.str("note"),
        created_at: created_at_string(&f, now_millis),
        author_display_name: f.str("authorDisplayName"),
    })
}

/// recordType による振り分け。iOS `CloudKitSyncEngine.upsertRecords` の switch と同じ。
///
/// 取り込まない recordType は None:
/// - `CastMember`: Cast テーブル廃止。
/// - `IdolCast`: 声優履歴テーブルへ移行済み。
/// - 未知の recordType: 旧スキーマ由来なので黙って捨てる。
pub fn map_record(record_type: &str, record: &CkRecordInput, now_millis: i64) -> Option<CkRow> {
    match record_type {
        "Brand" => brand(record).map(|row| CkRow::Brand { row }),
        "Idol" => idol(record).map(|row| CkRow::Idol { row }),
        "Event" => event(record).map(|row| CkRow::Event { row }),
        "Show" => show(record).map(|row| CkRow::Show { row }),
        "Venue" => venue(record).map(|row| CkRow::Venue { row }),
        "VenueName" => venue_name(record).map(|row| CkRow::VenueName { row }),
        "VenueHall" => venue_hall(record).map(|row| CkRow::VenueHall { row }),
        "Song" => song(record).map(|row| CkRow::Song { row }),
        "ImasUnit" => unit(record).map(|row| CkRow::Unit { row }),
        "IdolBrand" => idol_brand(record).map(|row| CkRow::IdolBrand { row }),
        "SongArtist" => song_artist(record).map(|row| CkRow::SongArtist { row }),
        "UnitMember" => unit_member(record).map(|row| CkRow::UnitMember { row }),
        "ShowCast" => show_cast(record).map(|row| CkRow::ShowCast { row }),
        "SetlistItem" => setlist_item(record).map(|row| CkRow::SetlistItem { row }),
        "SetlistPerformer" => setlist_performer(record).map(|row| CkRow::SetlistPerformer { row }),
        "SongCall" => song_call(record, now_millis).map(|row| CkRow::SongCall { row }),
        "SongVideo" => song_video(record, now_millis).map(|row| CkRow::SongVideo { row }),
        _ => None,
    }
}

/// この recordType を取り込むか。取り込まない型では変換を試みず、
/// 「必須キー欠損で捨てた」ログにも載せない (iOS の switch の break 相当)。
pub fn is_ingested_record_type(record_type: &str) -> bool {
    matches!(
        record_type,
        "Brand"
            | "Idol"
            | "Event"
            | "Show"
            | "Venue"
            | "VenueName"
            | "VenueHall"
            | "Song"
            | "ImasUnit"
            | "IdolBrand"
            | "SongArtist"
            | "UnitMember"
            | "ShowCast"
            | "SetlistItem"
            | "SetlistPerformer"
            | "SongCall"
            | "SongVideo"
    )
}

/// 1 recordType 分のバッチ仕分け。deletedAt の有無で削除/生存に割り、
/// 生存側だけ行に変換する (iOS の分割 + compactMap と同じ順序)。
pub fn ingest_batch(
    record_type: &str,
    records: &[CkRecordInput],
    now_millis: i64,
) -> CkIngestBatch {
    let mut out = CkIngestBatch::default();
    if !is_ingested_record_type(record_type) {
        return out;
    }
    for record in records {
        if deleted_at_millis(record).is_some() {
            out.deleted_record_names.push(record.record_name.clone());
            continue;
        }
        match map_record(record_type, record, now_millis) {
            Some(row) => out.rows.push(row),
            None => out.invalid_record_names.push(record.record_name.clone()),
        }
    }
    out
}

/// CKWS の生レコード JSON をそのまま仕分ける (Android の 1 ページ = 1 呼び出し)。
///
/// [`ingest_batch`] との違いは入力だけ。Kotlin 側で `value` だけ拾って平坦化すると
/// TIMESTAMP が失われる (受け入れ条件 1) ので、**平坦化せずここへ渡す**のが正しい経路。
pub fn ingest_web_services_batch(
    record_type: &str,
    record_jsons: &[String],
    now_millis: i64,
) -> CkIngestBatch {
    // 取り込まない recordType では JSON パースすらしない (iOS の break と同じ)。
    if !is_ingested_record_type(record_type) {
        return CkIngestBatch::default();
    }
    let records: Vec<CkRecordInput> =
        record_jsons.iter().map(|json| record_from_web_services_json(json)).collect();
    ingest_batch(record_type, &records, now_millis)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(name: &str, fields: &[(&str, CkValue)]) -> CkRecordInput {
        CkRecordInput {
            record_name: name.to_string(),
            fields: fields
                .iter()
                .map(|(k, v)| CkField { key: k.to_string(), value: v.clone() })
                .collect(),
        }
    }

    fn text(s: &str) -> CkValue {
        CkValue::Text { value: s.to_string() }
    }

    fn int(v: i64) -> CkValue {
        CkValue::Int { value: v }
    }

    // ---- id 解決と必須キー ----

    #[test]
    fn id_falls_back_to_record_name_when_field_absent() {
        let r = rec("rec-1", &[("name", text("765PRO"))]);
        assert_eq!(brand(&r).unwrap().id, "rec-1");
    }

    #[test]
    fn empty_id_field_does_not_fall_back_to_record_name() {
        // `as? String` は空文字でも成功するので `??` が働かず、空チェックで捨てる。
        // Android は空文字を null に潰すため recordName に落ちる (乖離、iOS が正)。
        let r = rec("rec-1", &[("id", text("")), ("name", text("765PRO"))]);
        assert!(brand(&r).is_none());
    }

    #[test]
    fn non_string_id_falls_back_to_record_name() {
        let r = rec("rec-1", &[("id", int(7)), ("name", text("765PRO"))]);
        assert_eq!(brand(&r).unwrap().id, "rec-1");
    }

    #[test]
    fn empty_record_name_without_id_is_rejected() {
        let r = rec("", &[("name", text("765PRO"))]);
        assert!(brand(&r).is_none());
    }

    #[test]
    fn missing_or_empty_required_name_is_rejected() {
        assert!(brand(&rec("b", &[])).is_none());
        assert!(brand(&rec("b", &[("name", text(""))])).is_none());
        // 型違いも「無い」扱い。
        assert!(brand(&rec("b", &[("name", int(1))])).is_none());
    }

    #[test]
    fn duplicate_keys_take_the_last_one() {
        let r = rec("b", &[("name", text("first")), ("name", text("last"))]);
        assert_eq!(brand(&r).unwrap().name, "last");
    }

    // ---- 数値・Bool の変換 ----

    #[test]
    fn int_value_defaults_to_zero_and_truncates() {
        let base = |v: CkValue| rec("b", &[("name", text("n")), ("sortOrder", v)]);
        assert_eq!(brand(&rec("b", &[("name", text("n"))])).unwrap().sort_order, 0);
        assert_eq!(brand(&base(int(5))).unwrap().sort_order, 5);
        assert_eq!(brand(&base(CkValue::Real { value: 3.9 })).unwrap().sort_order, 3);
        assert_eq!(brand(&base(CkValue::Real { value: -3.9 })).unwrap().sort_order, -3);
        assert_eq!(brand(&base(CkValue::Bool { value: true })).unwrap().sort_order, 1);
        // 文字列・日付は数値として読めないので既定の 0。
        assert_eq!(brand(&base(text("12"))).unwrap().sort_order, 0);
        assert_eq!(brand(&base(CkValue::Timestamp { millis: 1 })).unwrap().sort_order, 0);
    }

    #[test]
    fn optional_int_value_keeps_absence_distinct_from_zero() {
        let idol_with = |v: Option<CkValue>| {
            let mut fields = vec![("name", text("春香"))];
            if let Some(v) = v {
                fields.push(("age", v));
            }
            idol(&rec("i", &fields.iter().map(|(k, v)| (*k, v.clone())).collect::<Vec<_>>()))
                .unwrap()
                .age
        };
        assert_eq!(idol_with(None), None);
        assert_eq!(idol_with(Some(int(0))), Some(0));
        assert_eq!(idol_with(Some(CkValue::Real { value: 17.9 })), Some(17));
        // 文字列は数値として読まない (0 でなく「無し」)。
        assert_eq!(idol_with(Some(text("17"))), None);
    }

    #[test]
    fn double_value_accepts_int_and_real() {
        let i = idol(&rec(
            "i",
            &[
                ("name", text("春香")),
                ("height", CkValue::Real { value: 158.5 }),
                ("weight", int(41)),
                ("bust", text("83")),
            ],
        ))
        .unwrap();
        assert_eq!(i.height, Some(158.5));
        assert_eq!(i.weight, Some(41.0));
        assert_eq!(i.bust, None);
        assert_eq!(i.waist, None);
    }

    #[test]
    fn bool_value_uses_defaults_per_field() {
        // isSolo は既定 true、isStreaming は既定 false。
        let e = event(&rec("e", &[("name", text("ライブ"))])).unwrap();
        assert!(e.is_solo);
        assert!(!e.is_streaming);

        let e = event(&rec("e", &[("name", text("ライブ")), ("isSolo", int(0))])).unwrap();
        assert!(!e.is_solo);
        // 0 以外は true。
        let e = event(&rec("e", &[("name", text("ライブ")), ("isSolo", int(2))])).unwrap();
        assert!(e.is_solo);
        // 型違いは既定へ倒す (捨てない)。
        let e = event(&rec("e", &[("name", text("ライブ")), ("isSolo", text("false"))])).unwrap();
        assert!(e.is_solo);
    }

    #[test]
    fn is_external_reads_int64_exactly() {
        // iOS は boolValue を通さず `(as? Int64 ?? 0) != 0`。
        // Int64 で厳密に表せない値 (小数つき Double・文字列) だけ false に倒れる。
        let mk = |v: Option<CkValue>| {
            let mut fields: Vec<(&str, CkValue)> = vec![("name", text("春香"))];
            if let Some(v) = v {
                fields.push(("isExternal", v));
            }
            idol(&rec("i", &fields)).unwrap().is_external
        };
        assert!(!mk(None));
        assert!(mk(Some(int(1))));
        assert!(!mk(Some(int(0))));
        assert!(mk(Some(CkValue::Bool { value: true })));
        assert!(!mk(Some(CkValue::Bool { value: false })));
        assert!(mk(Some(CkValue::Real { value: 1.0 })));
        assert!(!mk(Some(CkValue::Real { value: 1.5 })));
        assert!(!mk(Some(text("1"))));
    }

    // ---- 文字列の既定値 ----

    #[test]
    fn empty_string_is_kept_and_does_not_trigger_fallback() {
        // 任意項目の空文字は Some("") のまま (Android は null に潰す = 乖離)。
        let i = idol(&rec("i", &[("name", text("春香")), ("nameKana", text(""))])).unwrap();
        assert_eq!(i.name_kana, Some(String::new()));

        // 既定値つき項目も空文字なら空文字 ("live"/"solo"/"original" に倒さない)。
        let e = event(&rec("e", &[("name", text("ライブ")), ("kind", text(""))])).unwrap();
        assert_eq!(e.kind, "");
        assert_eq!(e.event_type, "live");

        let s = song(&rec("s", &[("title", text("GO MY WAY!!")), ("songType", text(""))])).unwrap();
        assert_eq!(s.song_type, "");

        let a = song_artist(&rec(
            "a",
            &[("songId", text("s1")), ("idolId", text("i1")), ("role", text(""))],
        ))
        .unwrap();
        assert_eq!(a.role, "");
    }

    #[test]
    fn string_defaults_apply_when_absent_or_wrong_type() {
        let e = event(&rec("e", &[("name", text("ライブ")), ("kind", int(1))])).unwrap();
        assert_eq!(e.kind, "live");
        let s = song(&rec("s", &[("title", text("t"))])).unwrap();
        assert_eq!(s.song_type, "solo");
        let a =
            song_artist(&rec("a", &[("songId", text("s1")), ("idolId", text("i1"))])).unwrap();
        assert_eq!(a.role, "original");
        let i = idol(&rec("i", &[("name", text("春香"))])).unwrap();
        assert_eq!(i.brand_id, "");
        let u = unit(&rec("u", &[("name", text("竜宮小町"))])).unwrap();
        assert_eq!(u.brand_id, "");
        assert!(u.is_permanent);
    }

    // ---- HEX カラー ----

    #[test]
    fn hex_color_is_normalised_or_dropped() {
        let hex = |s: &str| validated_hex(Some(s.to_string()));
        assert_eq!(hex("#E22B30"), Some("E22B30".to_string()));
        assert_eq!(hex("e22b30"), Some("e22b30".to_string())); // 大小はそのまま
        assert_eq!(hex("#E22B30FF"), Some("E22B30FF".to_string())); // 8 桁 (アルファ付き)
        assert_eq!(hex("##E22B30##"), Some("E22B30".to_string())); // 前後の # は全部剥がす
        assert_eq!(hex("E22B3"), None); // 5 桁
        assert_eq!(hex("E22B30F"), None); // 7 桁
        assert_eq!(hex("GGGGGG"), None); // hex でない
        assert_eq!(hex("#"), None);
        assert_eq!(hex(""), None);
        assert_eq!(hex("E2 2B30"), None);
        assert_eq!(validated_hex(None), None);
        // 不正な色は「色なし」にする (元文字列を残さない)。
        let b = brand(&rec("b", &[("name", text("765")), ("color", text("not-a-color"))])).unwrap();
        assert_eq!(b.color, None);
    }

    // ---- 日付 ----

    #[test]
    fn iso8601_matches_internet_date_time() {
        assert_eq!(iso8601_internet_date_time(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso8601_internet_date_time(1_700_000_000_000), "2023-11-14T22:13:20Z");
        // 秒未満は床方向に切り捨て (負の時刻でも 1 秒戻る)。
        assert_eq!(iso8601_internet_date_time(1_999), "1970-01-01T00:00:01Z");
        assert_eq!(iso8601_internet_date_time(-1), "1969-12-31T23:59:59Z");
    }

    #[test]
    fn created_at_falls_back_to_now_when_not_a_date() {
        let now = 1_700_000_000_000;
        let base = [("songId", text("s1")), ("callText", text("せーの"))];

        let mut fields = base.to_vec();
        fields.push(("createdAt", CkValue::Timestamp { millis: 1_600_000_000_000 }));
        let c = song_call(&rec("c1", &fields), now).unwrap();
        assert_eq!(c.created_at, "2020-09-13T12:26:40Z");

        // 欠損は now。
        let c = song_call(&rec("c1", &base), now).unwrap();
        assert_eq!(c.created_at, "2023-11-14T22:13:20Z");

        // 文字列で来ても Date ではないので now (iOS の `as? Date` と同じ)。
        let mut fields = base.to_vec();
        fields.push(("createdAt", text("2020-09-13T12:26:40Z")));
        let c = song_call(&rec("c1", &fields), now).unwrap();
        assert_eq!(c.created_at, "2023-11-14T22:13:20Z");
    }

    #[test]
    fn community_rows_use_record_name_as_id() {
        let c = song_call(
            &rec("call-uuid", &[("songId", text("s1")), ("callText", text("せーの"))]),
            0,
        )
        .unwrap();
        assert_eq!(c.id, "call-uuid");
        assert_eq!(c.source_url, None);

        let v = song_video(
            &rec("vid-uuid", &[("songId", text("s1")), ("youtubeUrl", text("https://y"))]),
            0,
        )
        .unwrap();
        assert_eq!(v.id, "vid-uuid");
        // 本文が空なら捨てる。
        assert!(song_video(
            &rec("vid", &[("songId", text("s1")), ("youtubeUrl", text(""))]),
            0
        )
        .is_none());
        assert!(song_call(&rec("c", &[("songId", text("s1")), ("callText", text(""))]), 0)
            .is_none());
    }

    #[test]
    fn deleted_at_requires_a_date() {
        assert_eq!(
            deleted_at_millis(&rec("x", &[("deletedAt", CkValue::Timestamp { millis: 42 })])),
            Some(42)
        );
        assert_eq!(deleted_at_millis(&rec("x", &[])), None);
        // 数値・文字列は削除マーカーとして扱わない (iOS の `as? Date` と同じ)。
        // Android は「非 null なら削除」なのでここが乖離する (iOS が正)。
        assert_eq!(deleted_at_millis(&rec("x", &[("deletedAt", int(42))])), None);
        assert_eq!(deleted_at_millis(&rec("x", &[("deletedAt", text("2020-01-01"))])), None);
    }

    // ---- 中間テーブル ----

    #[test]
    fn junction_rows_require_both_keys() {
        assert!(idol_brand(&rec("x", &[("idolId", text("i1"))])).is_none());
        assert!(idol_brand(&rec("x", &[("brandId", text("765as"))])).is_none());
        let ib =
            idol_brand(&rec("x", &[("idolId", text("i1")), ("brandId", text("765as"))])).unwrap();
        assert!(!ib.is_primary);

        assert!(unit_member(&rec("x", &[("unitId", text("u1"))])).is_none());
        assert!(setlist_performer(&rec("x", &[("idolId", text("i1"))])).is_none());
        assert!(song_artist(&rec("x", &[("songId", text("")), ("idolId", text("i1"))])).is_none());
    }

    #[test]
    fn show_cast_normalises_role_and_ignores_legacy_cast_id() {
        let role = |v: Option<CkValue>| {
            let mut fields: Vec<(&str, CkValue)> =
                vec![("showId", text("s1")), ("idolId", text("i1"))];
            if let Some(v) = v {
                fields.push(("castRole", v));
            }
            show_cast(&rec("x", &fields)).unwrap().cast_role
        };
        assert_eq!(role(None), "member");
        assert_eq!(role(Some(text("lead"))), "lead");
        assert_eq!(role(Some(text("guest"))), "guest");
        // 未知の役割・空文字・型違いは member に倒す (捨てない)。
        assert_eq!(role(Some(text("mc"))), "member");
        assert_eq!(role(Some(text(""))), "member");
        assert_eq!(role(Some(int(1))), "member");

        // 旧スキーマの castId しかないレコードは取り込まない。
        assert!(show_cast(&rec("x", &[("showId", text("s1")), ("castId", text("c1"))])).is_none());
    }

    #[test]
    fn setlist_item_requires_show_and_song() {
        assert!(setlist_item(&rec("x", &[("showId", text("s1"))])).is_none());
        let it = setlist_item(&rec(
            "sl1",
            &[("showId", text("s1")), ("songId", text("song1")), ("position", int(3))],
        ))
        .unwrap();
        assert_eq!((it.id.as_str(), it.position), ("sl1", 3));
        assert_eq!(it.section, None);
    }

    // ---- 会場系 (Android 未実装。iOS が正) ----

    #[test]
    fn venue_family_requires_keys() {
        let v = venue(&rec(
            "v1",
            &[("name", text("日本武道館")), ("capacity", int(14500)), ("city", text("千代田区"))],
        ))
        .unwrap();
        assert_eq!(v.capacity, Some(14500));
        assert_eq!(v.sort_order, 0);
        // 出典が無い会場はキャパ無しのまま (0 で埋めない)。
        assert_eq!(venue(&rec("v2", &[("name", text("A"))])).unwrap().capacity, None);

        assert!(venue_name(&rec("vn", &[("name", text("京王アリーナTOKYO"))])).is_none());
        assert!(venue_name(&rec("vn", &[("venueId", text("v1"))])).is_none());
        let vn = venue_name(&rec(
            "vn",
            &[("venueId", text("v1")), ("name", text("京王アリーナTOKYO"))],
        ))
        .unwrap();
        assert_eq!((vn.valid_from, vn.valid_to), (None, None));

        assert!(venue_hall(&rec("vh", &[("venueId", text("v1"))])).is_none());
        let vh =
            venue_hall(&rec("vh", &[("venueId", text("v1")), ("name", text("ホールA"))])).unwrap();
        assert_eq!(vh.capacity, None);
    }

    // ---- show / song の全項目 ----

    #[test]
    fn show_reads_venue_id_hall_and_stream_platform() {
        let s = show(&rec(
            "sh1",
            &[
                ("eventId", text("e1")),
                ("date", text("2026-08-24")),
                ("venue", text("幕張メッセ")),
                ("venueId", text("v-makuhari")),
                ("hall", text("イベントホール")),
                ("streamPlatform", text("ニコニコ")),
                ("sortOrder", int(2)),
            ],
        ))
        .unwrap();
        assert_eq!(s.venue_id, Some("v-makuhari".to_string()));
        assert_eq!(s.hall, Some("イベントホール".to_string()));
        assert_eq!(s.stream_platform, Some("ニコニコ".to_string()));
        assert_eq!(s.name, ""); // name は必須でない
        assert_eq!(s.sort_order, 2);

        // eventId / date は必須。
        assert!(show(&rec("sh", &[("date", text("2026-08-24"))])).is_none());
        assert!(show(&rec("sh", &[("eventId", text("e1"))])).is_none());
    }

    #[test]
    fn song_reads_series_group() {
        // 読み落とすと同期のたび NULL 上書きされるので固定する。
        let s = song(&rec(
            "s1",
            &[("title", text("GO MY WAY!!")), ("seriesGroup", text("MASTER ARTIST"))],
        ))
        .unwrap();
        assert_eq!(s.series_group, Some("MASTER ARTIST".to_string()));
    }

    #[test]
    fn idol_never_reads_voice_actors() {
        // voiceActors は廃止列。読むと書き戻しで落ちるので、来ても無視する。
        // 行が「voiceActors が無かったとき」と 1bit も変わらないことまで固定する
        // (CkIdolRow に voice_actors を生やして読み始めたらここで落ちる)。
        let with_cv = rec("i1", &[("name", text("春香")), ("voiceActors", text("中村繪里子"))]);
        let without_cv = rec("i1", &[("name", text("春香"))]);
        assert_eq!(idol(&with_cv).unwrap(), idol(&without_cv).unwrap());
    }

    #[test]
    fn idol_reads_every_column_it_writes() {
        // 行全体を置換する store (Android の Room) に流すので、読み落とした列は
        // 同期のたび NULL 上書きされる (seriesGroup で実際に壊れた)。
        // idols の列を足したら CkIdolRow とこのテストの両方に足すこと。
        let r = rec(
            "rec-name",
            &[
                ("id", text("i-haruka")),
                ("brandId", text("765as")),
                ("name", text("天海春香")),
                ("nameKana", text("あまみはるか")),
                ("nameRomaji", text("Amami Haruka")),
                ("familyName", text("天海")),
                ("givenName", text("春香")),
                ("nickname", text("春香さん")),
                ("color", text("#E22B30")),
                ("sortOrder", int(1)),
                ("birthday", text("04-03")),
                ("bloodType", text("O")),
                ("height", CkValue::Real { value: 158.0 }),
                ("weight", CkValue::Real { value: 41.0 }),
                ("birthPlace", text("東京都")),
                ("age", int(17)),
                ("bust", CkValue::Real { value: 83.0 }),
                ("waist", CkValue::Real { value: 56.0 }),
                ("hip", CkValue::Real { value: 82.0 }),
                ("constellation", text("牡羊座")),
                ("hobbies", text("散歩")),
                ("talents", text("model")),
                ("description", text("普通の女の子")),
                ("gender", text("female")),
                ("handedness", text("right")),
                ("debutDate", text("2005-01-01")),
                ("attribute", text("princess")),
                ("isExternal", int(1)),
                ("aliases", text("はるるん")),
                // 廃止列。読まないので行には出ない。
                ("voiceActors", text("中村繪里子")),
            ],
        );
        assert_eq!(
            idol(&r).unwrap(),
            CkIdolRow {
                id: "i-haruka".to_string(),
                brand_id: "765as".to_string(),
                name: "天海春香".to_string(),
                name_kana: Some("あまみはるか".to_string()),
                name_romaji: Some("Amami Haruka".to_string()),
                family_name: Some("天海".to_string()),
                given_name: Some("春香".to_string()),
                nickname: Some("春香さん".to_string()),
                color: Some("E22B30".to_string()),
                sort_order: 1,
                birthday: Some("04-03".to_string()),
                blood_type: Some("O".to_string()),
                height: Some(158.0),
                weight: Some(41.0),
                birth_place: Some("東京都".to_string()),
                age: Some(17),
                bust: Some(83.0),
                waist: Some(56.0),
                hip: Some(82.0),
                constellation: Some("牡羊座".to_string()),
                hobbies: Some("散歩".to_string()),
                talents: Some("model".to_string()),
                description: Some("普通の女の子".to_string()),
                gender: Some("female".to_string()),
                handedness: Some("right".to_string()),
                debut_date: Some("2005-01-01".to_string()),
                attribute: Some("princess".to_string()),
                is_external: true,
                aliases: Some("はるるん".to_string()),
            }
        );
    }

    // ---- recordType 振り分け ----

    #[test]
    fn dispatch_ignores_retired_and_unknown_types() {
        let r = rec("x", &[("name", text("n")), ("id", text("x"))]);
        assert!(map_record("CastMember", &r, 0).is_none());
        assert!(map_record("IdolCast", &r, 0).is_none());
        assert!(map_record("Whatever", &r, 0).is_none());
        assert!(!is_ingested_record_type("CastMember"));
        assert!(!is_ingested_record_type("IdolCast"));
    }

    #[test]
    fn dispatch_maps_each_known_type() {
        let cases: Vec<(&str, CkRecordInput)> = vec![
            ("Brand", rec("b", &[("name", text("765"))])),
            ("Idol", rec("i", &[("name", text("春香"))])),
            ("Event", rec("e", &[("name", text("ライブ"))])),
            ("Show", rec("sh", &[("eventId", text("e")), ("date", text("2026-01-01"))])),
            ("Venue", rec("v", &[("name", text("武道館"))])),
            ("VenueName", rec("vn", &[("venueId", text("v")), ("name", text("n"))])),
            ("VenueHall", rec("vh", &[("venueId", text("v")), ("name", text("n"))])),
            ("Song", rec("s", &[("title", text("t"))])),
            ("ImasUnit", rec("u", &[("name", text("竜宮小町"))])),
            ("IdolBrand", rec("ib", &[("idolId", text("i")), ("brandId", text("b"))])),
            ("SongArtist", rec("sa", &[("songId", text("s")), ("idolId", text("i"))])),
            ("UnitMember", rec("um", &[("unitId", text("u")), ("idolId", text("i"))])),
            ("ShowCast", rec("sc", &[("showId", text("sh")), ("idolId", text("i"))])),
            (
                "SetlistItem",
                rec("sl", &[("showId", text("sh")), ("songId", text("s"))]),
            ),
            (
                "SetlistPerformer",
                rec("sp", &[("setlistItemId", text("sl")), ("idolId", text("i"))]),
            ),
            ("SongCall", rec("c", &[("songId", text("s")), ("callText", text("せーの"))])),
            ("SongVideo", rec("v", &[("songId", text("s")), ("youtubeUrl", text("u"))])),
        ];
        for (ty, r) in &cases {
            assert!(is_ingested_record_type(ty), "{ty} は取り込み対象のはず");
            assert!(map_record(ty, r, 0).is_some(), "{ty} の変換に失敗した");
        }
    }

    // ---- バッチ仕分け ----

    #[test]
    fn ingest_batch_splits_alive_deleted_and_invalid() {
        let records = vec![
            rec("b1", &[("name", text("765プロ"))]),
            rec("b2", &[("name", text("消えたブランド")), ("deletedAt", CkValue::Timestamp { millis: 5 })]),
            rec("b3", &[]), // name 欠損 → 捨てる
            rec("b4", &[("name", text("シャニ"))]),
        ];
        let out = ingest_batch("Brand", &records, 0);
        assert_eq!(out.rows.len(), 2);
        assert_eq!(out.deleted_record_names, vec!["b2".to_string()]);
        assert_eq!(out.invalid_record_names, vec!["b3".to_string()]);
        match &out.rows[0] {
            CkRow::Brand { row } => assert_eq!(row.id, "b1"),
            other => panic!("Brand を期待した: {other:?}"),
        }
    }

    #[test]
    fn ingest_batch_skips_everything_for_retired_types() {
        // 廃止 recordType は削除伝搬もしない (iOS の break と同じ)。
        let records = vec![rec("c1", &[("deletedAt", CkValue::Timestamp { millis: 5 })])];
        assert_eq!(ingest_batch("CastMember", &records, 0), CkIngestBatch::default());
    }

    // ---- CKWS の型振り分け (受け入れ条件 1 の回帰) ----

    fn field_of(record: &CkRecordInput, key: &str) -> Option<CkValue> {
        record.fields.iter().find(|f| f.key == key).map(|f| f.value.clone())
    }

    #[test]
    fn web_services_fields_are_dispatched_by_type() {
        let r = record_from_web_services_json(
            r#"{
                "recordName": "i1",
                "recordType": "Idol",
                "fields": {
                    "name": {"value": "春香", "type": "STRING"},
                    "sortOrder": {"value": 3, "type": "INT64"},
                    "height": {"value": 158.5, "type": "DOUBLE"},
                    "deletedAt": {"value": 1700000000000, "type": "TIMESTAMP"},
                    "photo": {"value": {"fileChecksum": "x"}, "type": "ASSETID"},
                    "tags": {"value": ["a"], "type": "STRING_LIST"}
                }
            }"#,
        );
        assert_eq!(r.record_name, "i1");
        assert_eq!(field_of(&r, "name"), Some(text("春香")));
        assert_eq!(field_of(&r, "sortOrder"), Some(int(3)));
        assert_eq!(field_of(&r, "height"), Some(CkValue::Real { value: 158.5 }));
        assert_eq!(
            field_of(&r, "deletedAt"),
            Some(CkValue::Timestamp { millis: 1_700_000_000_000 })
        );
        // 取り込む列が無い型は欠損扱い (既定値で埋めない)。
        assert_eq!(field_of(&r, "photo"), None);
        assert_eq!(field_of(&r, "tags"), None);
    }

    #[test]
    fn web_services_timestamp_drives_soft_delete_and_created_at() {
        // (a) deletedAt が Date として復元される = 削除が伝搬する。
        let deleted = record_from_web_services_json(
            r#"{"recordName":"gone","fields":{"deletedAt":{"value":1700000000000,"type":"TIMESTAMP"}}}"#,
        );
        assert_eq!(deleted_at_millis(&deleted), Some(1_700_000_000_000));
        let out = ingest_batch("Song", std::slice::from_ref(&deleted), 0);
        assert_eq!(out.deleted_record_names, vec!["gone".to_string()]);
        assert!(out.invalid_record_names.is_empty());

        // (b) createdAt が now に流れない = 投稿日時が同期のたび動かない。
        let call = record_from_web_services_json(
            r#"{"recordName":"c1","fields":{
                "songId":{"value":"s1","type":"STRING"},
                "callText":{"value":"せーの","type":"STRING"},
                "createdAt":{"value":1600000000000,"type":"TIMESTAMP"}
            }}"#,
        );
        assert_eq!(song_call(&call, 1).unwrap().created_at, "2020-09-13T12:26:40Z");
        assert_eq!(
            song_call(&call, 1_800_000_000_000).unwrap().created_at,
            "2020-09-13T12:26:40Z"
        );
    }

    #[test]
    fn flattened_web_services_values_break_delete_and_created_at() {
        // `fields[k] = json.getJSONObject(k).opt("value")` と平坦化した入力が
        // どう壊れるかを固定する。ここが再現したら OS 側の移植が未完成。
        let flattened = rec("gone", &[("deletedAt", int(1_700_000_000_000))]);
        assert_eq!(deleted_at_millis(&flattened), None, "Int は削除マーカーにならない");
        let out = ingest_batch("Song", &[flattened], 0);
        assert!(out.deleted_record_names.is_empty(), "削除が 1 件も伝搬しない");
        assert_eq!(out.invalid_record_names, vec!["gone".to_string()]);

        let call = rec(
            "c1",
            &[
                ("songId", text("s1")),
                ("callText", text("せーの")),
                ("createdAt", int(1_600_000_000_000)),
            ],
        );
        assert_ne!(
            song_call(&call, 1_700_000_000_000).unwrap().created_at,
            song_call(&call, 1_800_000_000_000).unwrap().created_at,
            "createdAt が now に流れて同期のたび書き換わる"
        );
    }

    #[test]
    fn web_services_field_without_type_is_dropped() {
        // type を落とした形は「値がある」と誤解させないため丸ごと捨てる。
        // 必須キーが欠けてレコードごと弾かれるので、平坦化バグが黙って進まない。
        let r = record_from_web_services_json(
            r#"{"recordName":"b1","fields":{
                "name":{"value":"765プロ"},
                "shortName":"765",
                "sortOrder":{"value":1,"type":"INT64"}
            }}"#,
        );
        assert_eq!(field_of(&r, "name"), None);
        assert_eq!(field_of(&r, "shortName"), None);
        assert_eq!(field_of(&r, "sortOrder"), Some(int(1)));
        assert!(brand(&r).is_none());
    }

    #[test]
    fn web_services_value_of_wrong_json_type_is_dropped() {
        let r = record_from_web_services_fields(
            "x",
            r#"{
                "a":{"value":1,"type":"STRING"},
                "b":{"value":"12","type":"INT64"},
                "c":{"value":"1.5","type":"DOUBLE"},
                "d":{"value":"2020-01-01","type":"TIMESTAMP"}
            }"#,
        );
        assert!(r.fields.is_empty());
        assert_eq!(r.record_name, "x");
    }

    #[test]
    fn web_services_numbers_truncate_toward_zero() {
        // 経路によって整数が小数表現で来ることがあるので intValue と同じ向きで受ける。
        let r = record_from_web_services_fields(
            "x",
            r#"{
                "i":{"value":3.0,"type":"INT64"},
                "j":{"value":-3.9,"type":"INT64"},
                "t":{"value":1700000000000.0,"type":"TIMESTAMP"},
                "d":{"value":41,"type":"DOUBLE"}
            }"#,
        );
        assert_eq!(field_of(&r, "i"), Some(int(3)));
        assert_eq!(field_of(&r, "j"), Some(int(-3)));
        assert_eq!(field_of(&r, "t"), Some(CkValue::Timestamp { millis: 1_700_000_000_000 }));
        assert_eq!(field_of(&r, "d"), Some(CkValue::Real { value: 41.0 }));
    }

    #[test]
    fn web_services_never_produces_bool() {
        // CKWS に BOOL 型は無い。INT64 で来た真偽値は Int のまま渡し、
        // 判定は boolValue 側 (0 以外が true) に任せる。
        let r = record_from_web_services_fields(
            "e",
            r#"{"isSolo":{"value":0,"type":"INT64"},"isStreaming":{"value":1,"type":"INT64"}}"#,
        );
        assert_eq!(field_of(&r, "isSolo"), Some(int(0)));
        assert_eq!(field_of(&r, "isStreaming"), Some(int(1)));
    }

    #[test]
    fn malformed_web_services_json_yields_an_empty_projection() {
        for json in ["", "not json", "[]", "null", "{}"] {
            let r = record_from_web_services_json(json);
            assert_eq!(r.record_name, "", "{json:?}");
            assert!(r.fields.is_empty(), "{json:?}");
        }
        // recordName だけ来て fields が無い形も落ちない。
        let r = record_from_web_services_json(r#"{"recordName":"only"}"#);
        assert_eq!(r.record_name, "only");
        assert!(r.fields.is_empty());
    }

    #[test]
    fn web_services_duplicate_keys_take_the_last_one() {
        // 辞書の上書きと同じ後勝ち (CkRecordInput の規約と揃える)。
        let r = record_from_web_services_fields(
            "b",
            r#"{"name":{"value":"first","type":"STRING"},"name":{"value":"last","type":"STRING"}}"#,
        );
        assert_eq!(field_of(&r, "name"), Some(text("last")));
    }

    #[test]
    fn ingest_web_services_batch_matches_the_projected_path() {
        let jsons: Vec<String> = vec![
            r#"{"recordName":"b1","fields":{"name":{"value":"765プロ","type":"STRING"}}}"#
                .to_string(),
            r#"{"recordName":"b2","fields":{"name":{"value":"消えた","type":"STRING"},"deletedAt":{"value":5,"type":"TIMESTAMP"}}}"#
                .to_string(),
            r#"{"recordName":"b3","fields":{}}"#.to_string(),
        ];
        let out = ingest_web_services_batch("Brand", &jsons, 0);
        assert_eq!(out.deleted_record_names, vec!["b2".to_string()]);
        assert_eq!(out.invalid_record_names, vec!["b3".to_string()]);
        assert_eq!(out.rows.len(), 1);
        match &out.rows[0] {
            CkRow::Brand { row } => assert_eq!((row.id.as_str(), row.name.as_str()), ("b1", "765プロ")),
            other => panic!("Brand を期待した: {other:?}"),
        }

        // 射影経路に自分で潰した場合と同じ結果になる。
        let projected: Vec<CkRecordInput> =
            jsons.iter().map(|j| record_from_web_services_json(j)).collect();
        assert_eq!(out, ingest_batch("Brand", &projected, 0));
    }

    #[test]
    fn ingest_web_services_batch_skips_retired_types() {
        let jsons = vec![
            r#"{"recordName":"c1","fields":{"deletedAt":{"value":5,"type":"TIMESTAMP"}}}"#
                .to_string(),
        ];
        assert_eq!(ingest_web_services_batch("CastMember", &jsons, 0), CkIngestBatch::default());
    }

    #[test]
    fn deleted_record_is_not_validated() {
        // 削除レコードは必須キーが無くても recordName で消す。
        let records = vec![rec("gone", &[("deletedAt", CkValue::Timestamp { millis: 1 })])];
        let out = ingest_batch("Song", &records, 0);
        assert!(out.rows.is_empty());
        assert!(out.invalid_record_names.is_empty());
        assert_eq!(out.deleted_record_names, vec!["gone".to_string()]);
    }
}
