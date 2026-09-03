//! バックアップ (引き継ぎコード / ファイルエクスポート) の**組み立て規則と整合判定**。
//!
//! 対象は「担当・お気に入り・メモ・参加 (user_marks)」「マイタグ (personal_tags)」
//! 「投票履歴 (poll votes)」の 3 つ。いずれも**クラウドにもサーバにも無い端末唯一データ**で、
//! 取り込み規則を 1bit でも間違えるとユーザーの担当/お気に入りが壊れる。
//! そのため「どのバイト列を作るか」「何を弾き何を取り込むか」「重複をどう解決するか」を
//! ここに集約し、境界 (空・未知バージョン・重複 id・不正 JSON) をテストで固定する。
//!
//! # 責務の線引き (docs/SHARED_CORE_STUDY.md §4-B1 と同じ流儀)
//!
//! ファイル IO・iCloud KVS (`UserMarkBackup`)・SharedPreferences・SQLite への書き込みは
//! 各 OS に残す。ここが扱うのは **文字列 ↔ 値** の純粋な変換と判定だけ:
//!
//! - 書き出し: 射影 ([`BackupExportInput`]) → payload JSON + checksum + envelope JSON
//! - 読み込み: envelope JSON → 検証済みの「入れるべき行」([`BackupImportPlan`])
//!
//! 現在時刻・端末 ID・アプリバージョンは引数で受け取る (OS 時刻を直接取らない規約)。
//!
//! # なぜ checksum まで Rust で計算するか
//!
//! checksum は **envelope に埋め込まれた payload 文字列そのもの**に対する SHA-256 で、
//! 「どうシリアライズしたか」と「何をハッシュしたか」が 1bit でもズレると自分が書いた
//! ファイルを自分で読めなくなる。両者を同じ関数の中で作れば、そのズレが原理的に起きない。
//! 外部 crate を足さずに済ませるため SHA-256 は本ファイル内に持つ (FIPS 180-4 の
//! テストベクタで固定してある)。
//!
//! # JSON のバイト規則
//!
//! payload はキー昇順 (Swift `JSONEncoder` の `.sortedKeys` と同じ並び)・区切り空白なし。
//! 文字列のエスケープは [`crate::domain::image_template_json::json_string_literal`] を
//! 再利用する (Darwin の `JSONSerialization` 流儀 = `/` を `\/` にする等)。
//! envelope は同じくキー昇順で、Darwin の `.prettyPrinted` に合わせた 2 スペース字下げ・
//! `" : "` 区切り。envelope 自体は checksum の対象外なので、この体裁が変わっても
//! 過去のファイルの検証結果には影響しない。
//!
//! # 意図的な原本との差分 (divergence)
//!
//! `userMarks` / `pollVotes` / `personalTags` の配列に**オブジェクトでない要素**が
//! 混ざっていたときの扱いだけ、iOS 原本と一致しない。iOS は
//! `topLevel["userMarks"] as? [[String: Any]]` で受けるので、1 要素でもオブジェクトで
//! なければ**配列ごと nil** になり、その項目は 0 件・skipped 0 のまま静かに素通りする
//! (Swift 6.3 実測)。ここは Android の org.json 実装 (`getJSONObject` が throw →
//! `skippedMarks++`) と同じく**要素ごとに**読み、健全な要素は取り込んで壊れた要素だけ
//! skipped に積む (上の例なら added 1 / skipped 1)。
//!
//! 両原本が食い違っている以上どちらかを選ぶしかなく、Android 側に寄せた理由は 3 つ:
//! (1) 取り込みが増える方向なので既存データを消さない (非破壊マージという本モジュールの
//! 大前提と同じ向き)、(2) 自前の書き出し器は非オブジェクト要素を作らないうえ、手で壊された
//! ファイルは checksum 検証で先に弾かれるので、この差が出る入力は実質存在しない、
//! (3) 「壊れた要素があった」ことを skipped として画面に出せる (iOS 原本は無言で 0 件)。
//! 挙動は `mixed_arrays_are_read_element_wise_unlike_ios` で固定してある。

use crate::domain::image_template_json::json_string_literal;
use crate::domain::sha256::sha256_hex;
use std::collections::{HashMap, HashSet};

/// このコアが書き出す payload の schemaVersion。
/// iOS `BackupExportImportService.currentSchemaVersion` / Android `CURRENT_SCHEMA_VERSION` と同値。
pub const BACKUP_SCHEMA_VERSION: i64 = 1;

/// envelope の版。両 OS とも読み取り時に値を検査していないので、書き出し専用の定数。
pub const BACKUP_ENVELOPE_VERSION: i64 = 1;

// MARK: - 射影 (FFI 境界を渡る値)

/// バックアップ 1 行分の user_mark。
///
/// `kind` の表記は [`BackupKindDialect`] で指定した方言。Rust の内部処理と JSON は
/// 常に canonical (iOS 表記) に正規化される。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BackupUserMarkRecord {
    pub entity_type: String,
    pub entity_id: String,
    pub kind: String,
    pub bool_value: bool,
    /// メモ本文。`None` のときは JSON からキーごと落とす (両 OS の既存挙動)。
    pub text_value: Option<String>,
    pub updated_at: String,
}

/// 1 お題ぶんの投票履歴。`entity_ids` は「そのお題で自分が選んだ entity」の集合。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BackupPollVoteRecord {
    pub poll_id: String,
    pub entity_ids: Vec<String>,
}

/// マイタグ 1 行分 (端末ローカル専用・サーバー非送信)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BackupPersonalTagRecord {
    pub entity_type: String,
    pub entity_id: String,
    pub tag_name: String,
    pub created_at: String,
}

/// `kind` 列の表記ゆれ。
///
/// iOS は `UserMarkKind.rawValue` (`myPick` / `note` / `favorite` / `attended` / …) を
/// そのまま DB にも JSON にも書く。Android は DB 側が `pick` / `memo` なので、
/// JSON との境界で読み替える必要がある。呼び出し側に読み替えを任せると
/// 「ローカルの既存キー」と「バックアップの kind」で表記が食い違って重複判定が壊れるので、
/// 方言をここに渡してもらい、正規化も逆変換もこのモジュールの中で閉じる。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum BackupKindDialect {
    /// iOS 表記。JSON の canonical 表記でもある。
    Canonical,
    /// Android の `user_marks.kind` 表記。
    Android,
}

/// 書き出しの入力。時刻・端末 ID・アプリ版は OS から受け取る。
#[derive(uniffi::Record, Clone, Debug)]
pub struct BackupExportInput {
    /// ISO8601 文字列。iOS は `ISO8601DateFormatter`、Android は `Instant.now().toString()`。
    pub exported_at: String,
    /// `"ios"` / `"android"`。
    pub platform: String,
    pub app_version: String,
    pub device_id: String,
    pub user_marks: Vec<BackupUserMarkRecord>,
    pub poll_votes: Vec<BackupPollVoteRecord>,
    pub personal_tags: Vec<BackupPersonalTagRecord>,
}

/// 書き出し結果。`envelope_json` をそのままファイル/引き継ぎコードにすればよい。
///
/// `payload_json` と `checksum` も返すのは、サーバー経由の引き継ぎコードのように
/// envelope を組み直す経路が checksum を計算し直さずに済むようにするため。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BackupEnvelopeDocument {
    pub payload_json: String,
    /// `"sha256:" + 小文字16進` 形式。
    pub checksum: String,
    pub envelope_json: String,
}

/// ローカルに既にある user_mark の同一性キー。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BackupMarkKey {
    pub entity_type: String,
    pub entity_id: String,
    /// [`BackupKindDialect`] で指定した方言のまま渡してよい。
    pub kind: String,
}

/// ローカルに既にあるマイタグの同一性キー。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BackupTagKey {
    pub entity_type: String,
    pub entity_id: String,
    pub tag_name: String,
}

/// 取り込み先の現状 (射影)。ここに無いものだけが「追加すべき行」になる。
#[derive(uniffi::Record, Clone, Debug, Default)]
pub struct BackupLocalState {
    pub mark_keys: Vec<BackupMarkKey>,
    pub tag_keys: Vec<BackupTagKey>,
    pub poll_votes: Vec<BackupPollVoteRecord>,
}

/// envelope を検証して取り出したメタ情報 (取り込み前のプレビュー用)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BackupEnvelopeInfo {
    /// envelope に載っていなければ `None` (両 OS とも値を使っていないので拒否理由にしない)。
    pub envelope_version: Option<i64>,
    pub schema_version: i64,
    pub exported_at: String,
    pub platform: String,
    pub app_version: String,
    /// 空文字なら端末 ID の復元はできない。
    pub device_id: String,
    pub mark_count: i64,
    pub vote_count: i64,
    pub personal_tag_count: i64,
    /// 形式不正で捨てた要素数 (marks / votes / personalTags の合計)。
    /// `backup_import_summary` の `skipped_marks` に渡す値。
    pub skipped_entries: i64,
}

/// 取り込み計画。実際の書き込み (SQLite / SharedPreferences / UserDefaults) は OS 側。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BackupImportPlan {
    pub info: BackupEnvelopeInfo,
    /// ローカルに無いので挿入すべき user_mark (kind は要求された方言)。
    pub marks_to_insert: Vec<BackupUserMarkRecord>,
    /// お題ごとの「まだ持っていない entity_id」だけ。空になったお題は落とす。
    pub poll_votes_to_add: Vec<BackupPollVoteRecord>,
    pub personal_tags_to_insert: Vec<BackupPersonalTagRecord>,
    pub added_marks: i64,
    pub added_votes: i64,
    pub added_personal_tags: i64,
    /// 端末 ID を復元してよいか (要求されていて、かつ payload の deviceId が非空)。
    pub restore_device_id: bool,
}

/// 取り込みを中断する理由。要素単位の不正はここに来ず `skipped_entries` に積まれる。
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum BackupImportError {
    #[error("ファイルの形式が正しくありません")]
    MalformedFile,
    #[error("データが破損しています")]
    ChecksumMismatch,
    #[error("対応していないバックアップ形式です (schemaVersion: {found})")]
    UnsupportedSchemaVersion { found: i64 },
}

// MARK: - kind の方言変換

/// canonical (iOS 表記) → Android の `user_marks.kind`。
///
/// Android が知らない kind (`collected` / `seat` / `owned` 等) は素通しする。
/// `user_marks.kind` に CHECK 制約は無く、既存クエリは kind を明示指定して絞るので
/// 未知の行が混ざっても無害。素通しさせておけば次に iOS へ書き戻すときそのまま戻る
/// (静かなデータ消失を防ぐ)。
pub fn backup_kind_to_android(canonical: &str) -> String {
    match canonical {
        "myPick" => "pick".to_string(),
        "note" => "memo".to_string(),
        other => other.to_string(),
    }
}

/// Android の `user_marks.kind` → canonical (iOS 表記)。
pub fn backup_kind_to_canonical(android: &str) -> String {
    match android {
        "pick" => "myPick".to_string(),
        "memo" => "note".to_string(),
        other => other.to_string(),
    }
}

/// 方言 → canonical。
fn to_canonical(kind: &str, dialect: BackupKindDialect) -> String {
    match dialect {
        BackupKindDialect::Canonical => kind.to_string(),
        BackupKindDialect::Android => backup_kind_to_canonical(kind),
    }
}

/// canonical → 方言。
fn from_canonical(kind: &str, dialect: BackupKindDialect) -> String {
    match dialect {
        BackupKindDialect::Canonical => kind.to_string(),
        BackupKindDialect::Android => backup_kind_to_android(kind),
    }
}

// MARK: - 書き出し

/// payload / checksum / envelope を一括で組み立てる。
///
/// - `poll_votes` は poll_id 昇順、`entity_ids` も昇順に並べ替える。iOS は Dictionary を
///   そのまま並べていて実行ごとに順が変わっていた (= 同じデータから違うバイト列が出ていた)。
///   checksum は自分で計算した文字列に対して付くので互換性には影響せず、決定性だけが増える。
/// - `user_marks` / `personal_tags` は渡された順を保つ (両 OS とも `SELECT *` の行順)。
pub fn build_backup_envelope(
    input: &BackupExportInput,
    dialect: BackupKindDialect,
) -> BackupEnvelopeDocument {
    let payload_json = build_payload_json(input, dialect);
    let checksum = format!("sha256:{}", sha256_hex(&payload_json));
    let envelope_json = format!(
        "{{\n  \"checksum\" : {},\n  \"envelopeVersion\" : {},\n  \"payload\" : {}\n}}",
        json_string_literal(&checksum),
        BACKUP_ENVELOPE_VERSION,
        json_string_literal(&payload_json),
    );
    BackupEnvelopeDocument { payload_json, checksum, envelope_json }
}

/// payload だけを組み立てる (キー昇順・空白なし)。
fn build_payload_json(input: &BackupExportInput, dialect: BackupKindDialect) -> String {
    let mut votes = input.poll_votes.clone();
    for vote in &mut votes {
        vote.entity_ids.sort();
    }
    votes.sort_by(|a, b| a.poll_id.cmp(&b.poll_id));

    let marks = input
        .user_marks
        .iter()
        .map(|mark| {
            // textValue は None のときキーごと落とす (Swift の synthesized Codable が
            // encodeIfPresent を使うのと、Android が非 null のときだけ put するのに合わせる)。
            let text = match &mark.text_value {
                Some(value) => format!(",\"textValue\":{}", json_string_literal(value)),
                None => String::new(),
            };
            format!(
                "{{\"boolValue\":{},\"entityId\":{},\"entityType\":{},\"kind\":{}{},\"updatedAt\":{}}}",
                mark.bool_value,
                json_string_literal(&mark.entity_id),
                json_string_literal(&mark.entity_type),
                json_string_literal(&to_canonical(&mark.kind, dialect)),
                text,
                json_string_literal(&mark.updated_at),
            )
        })
        .collect::<Vec<_>>()
        .join(",");

    let vote_items = votes
        .iter()
        .map(|vote| {
            let ids = vote
                .entity_ids
                .iter()
                .map(|id| json_string_literal(id))
                .collect::<Vec<_>>()
                .join(",");
            format!("{{\"entityIds\":[{}],\"pollId\":{}}}", ids, json_string_literal(&vote.poll_id))
        })
        .collect::<Vec<_>>()
        .join(",");

    let tags = input
        .personal_tags
        .iter()
        .map(|tag| {
            format!(
                "{{\"createdAt\":{},\"entityId\":{},\"entityType\":{},\"tagName\":{}}}",
                json_string_literal(&tag.created_at),
                json_string_literal(&tag.entity_id),
                json_string_literal(&tag.entity_type),
                json_string_literal(&tag.tag_name),
            )
        })
        .collect::<Vec<_>>()
        .join(",");

    format!(
        "{{\"appVersion\":{},\"deviceId\":{},\"exportedAt\":{},\"personalTags\":[{}],\"platform\":{},\"pollVotes\":[{}],\"schemaVersion\":{},\"userMarks\":[{}]}}",
        json_string_literal(&input.app_version),
        json_string_literal(&input.device_id),
        json_string_literal(&input.exported_at),
        tags,
        json_string_literal(&input.platform),
        vote_items,
        BACKUP_SCHEMA_VERSION,
        marks,
    )
}

// MARK: - 読み込み (整合判定)

/// 中断理由を判定して payload の中身まで取り出した結果。
struct ParsedBackup {
    info: BackupEnvelopeInfo,
    marks: Vec<BackupUserMarkRecord>,
    votes: Vec<BackupPollVoteRecord>,
    tags: Vec<BackupPersonalTagRecord>,
}

/// envelope を検証し、中身の件数とメタ情報だけを返す (書き込み前のプレビュー用)。
pub fn inspect_backup_envelope(envelope_json: &str) -> Result<BackupEnvelopeInfo, BackupImportError> {
    Ok(parse_backup(envelope_json)?.info)
}

/// envelope を検証し、ローカルの現状と突き合わせて「入れるべき行」を決める。
///
/// 非破壊マージ: ローカルにあるものは一切上書き・削除しない。
/// 同じキーがバックアップの中に 2 回出てきた場合も 1 回しか数えない (iOS が
/// 1 件ごとに存在確認しながら挿入するのと同じ。Android は既存キーを最初に
/// スナップショットしてしまうので二重に数えていた ≒ 件数の水増しバグ)。
pub fn plan_backup_import(
    envelope_json: &str,
    local: &BackupLocalState,
    restore_device_id: bool,
    dialect: BackupKindDialect,
) -> Result<BackupImportPlan, BackupImportError> {
    let parsed = parse_backup(envelope_json)?;

    // 既存キーは方言のまま来るので canonical に揃えてから比較する。
    let mut seen_marks: HashSet<(String, String, String)> = local
        .mark_keys
        .iter()
        .map(|k| {
            (k.entity_type.clone(), k.entity_id.clone(), to_canonical(&k.kind, dialect))
        })
        .collect();
    let mut marks_to_insert = Vec::new();
    for mark in parsed.marks {
        let key = (mark.entity_type.clone(), mark.entity_id.clone(), mark.kind.clone());
        // insert が true = 既存にも計画済みにも無い。
        if seen_marks.insert(key) {
            let kind = from_canonical(&mark.kind, dialect);
            marks_to_insert.push(BackupUserMarkRecord { kind, ..mark });
        }
    }

    let mut seen_tags: HashSet<(String, String, String)> = local
        .tag_keys
        .iter()
        .map(|k| (k.entity_type.clone(), k.entity_id.clone(), k.tag_name.clone()))
        .collect();
    let mut personal_tags_to_insert = Vec::new();
    for tag in parsed.tags {
        let key = (tag.entity_type.clone(), tag.entity_id.clone(), tag.tag_name.clone());
        if seen_tags.insert(key) {
            personal_tags_to_insert.push(tag);
        }
    }

    let mut owned: HashMap<String, HashSet<String>> = HashMap::new();
    for vote in &local.poll_votes {
        owned
            .entry(vote.poll_id.clone())
            .or_default()
            .extend(vote.entity_ids.iter().cloned());
    }
    // 同じ poll_id が複数エントリに分かれていても 1 つにまとめる (初出順を保つ)。
    let mut order: Vec<String> = Vec::new();
    let mut delta: HashMap<String, Vec<String>> = HashMap::new();
    for vote in &parsed.votes {
        let current = owned.entry(vote.poll_id.clone()).or_default();
        let missing: Vec<String> =
            vote.entity_ids.iter().filter(|id| current.insert((*id).clone())).cloned().collect();
        if missing.is_empty() {
            continue;
        }
        match delta.get_mut(&vote.poll_id) {
            Some(existing) => existing.extend(missing),
            None => {
                order.push(vote.poll_id.clone());
                delta.insert(vote.poll_id.clone(), missing);
            }
        }
    }
    let poll_votes_to_add: Vec<BackupPollVoteRecord> = order
        .into_iter()
        .map(|poll_id| {
            let entity_ids = delta.remove(&poll_id).unwrap_or_default();
            BackupPollVoteRecord { poll_id, entity_ids }
        })
        .collect();

    let added_marks = marks_to_insert.len() as i64;
    let added_personal_tags = personal_tags_to_insert.len() as i64;
    let added_votes: i64 = poll_votes_to_add.iter().map(|v| v.entity_ids.len() as i64).sum();
    let restore_device_id = restore_device_id && !parsed.info.device_id.is_empty();

    Ok(BackupImportPlan {
        info: parsed.info,
        marks_to_insert,
        poll_votes_to_add,
        personal_tags_to_insert,
        added_marks,
        added_votes,
        added_personal_tags,
        restore_device_id,
    })
}

/// envelope → checksum 検証 → payload → 要素ごとの型チェック。
fn parse_backup(envelope_json: &str) -> Result<ParsedBackup, BackupImportError> {
    let envelope: serde_json::Value =
        serde_json::from_str(envelope_json).map_err(|_| BackupImportError::MalformedFile)?;
    let envelope = envelope.as_object().ok_or(BackupImportError::MalformedFile)?;

    let payload_text = non_empty_string(envelope.get("payload")).ok_or(BackupImportError::MalformedFile)?;
    let checksum = non_empty_string(envelope.get("checksum")).ok_or(BackupImportError::MalformedFile)?;
    // envelopeVersion は両 OS とも値を見ていない。無い/型違いを中断理由にすると
    // 検証できるはずのファイルを弾くだけなので、読めたときだけ持ち回る。
    let envelope_version = envelope.get("envelopeVersion").and_then(integral_number);

    if checksum != format!("sha256:{}", sha256_hex(payload_text)) {
        return Err(BackupImportError::ChecksumMismatch);
    }

    let payload: serde_json::Value =
        serde_json::from_str(payload_text).map_err(|_| BackupImportError::MalformedFile)?;
    let payload = payload.as_object().ok_or(BackupImportError::MalformedFile)?;

    let schema_version = payload
        .get("schemaVersion")
        .and_then(integral_number)
        .ok_or(BackupImportError::MalformedFile)?;
    // 「未来の版で作られたファイル」だけを弾く。古い版 (= 項目が少ない) は読める。
    if schema_version > BACKUP_SCHEMA_VERSION {
        return Err(BackupImportError::UnsupportedSchemaVersion { found: schema_version });
    }

    let mut skipped: i64 = 0;
    let marks = parse_array(payload.get("userMarks"), &mut skipped, parse_mark);
    let votes = parse_array(payload.get("pollVotes"), &mut skipped, parse_vote);
    // personalTags は schemaVersion 1 の途中で足した項目なので、無いときは空扱い。
    let tags = parse_array(payload.get("personalTags"), &mut skipped, parse_tag);

    Ok(ParsedBackup {
        info: BackupEnvelopeInfo {
            envelope_version,
            schema_version,
            exported_at: optional_string(payload.get("exportedAt")),
            platform: optional_string(payload.get("platform")),
            app_version: optional_string(payload.get("appVersion")),
            device_id: optional_string(payload.get("deviceId")),
            mark_count: marks.len() as i64,
            vote_count: votes.len() as i64,
            personal_tag_count: tags.len() as i64,
            skipped_entries: skipped,
        },
        marks,
        votes,
        tags,
    })
}

/// 配列を要素ごとに読む。配列でなければ空 (件数も数えない = 数えようがない)。
/// 要素が読めなければその 1 件だけ捨てて数える (残りは取り込む)。
///
/// 非オブジェクト要素が混ざったときに「配列ごと捨てる」iOS 原本ではなく
/// 「要素ごとに捨てる」Android 原本に寄せてある。理由はモジュール冒頭の
/// 「意図的な原本との差分」を参照。
fn parse_array<T>(
    value: Option<&serde_json::Value>,
    skipped: &mut i64,
    parse: fn(&serde_json::Value) -> Option<T>,
) -> Vec<T> {
    let Some(items) = value.and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    let mut out = Vec::with_capacity(items.len());
    for item in items {
        match parse(item) {
            Some(parsed) => out.push(parsed),
            None => *skipped += 1,
        }
    }
    out
}

fn parse_mark(value: &serde_json::Value) -> Option<BackupUserMarkRecord> {
    let object = value.as_object()?;
    let text_value = match object.get("textValue") {
        None | Some(serde_json::Value::Null) => None,
        Some(serde_json::Value::String(text)) => Some(text.clone()),
        // 型違いは iOS の JSONDecoder が落とすので、行ごと捨てる側に倒す。
        Some(_) => return None,
    };
    Some(BackupUserMarkRecord {
        entity_type: string_field(object, "entityType")?,
        entity_id: string_field(object, "entityId")?,
        kind: string_field(object, "kind")?,
        bool_value: object.get("boolValue")?.as_bool()?,
        text_value,
        updated_at: string_field(object, "updatedAt")?,
    })
}

fn parse_vote(value: &serde_json::Value) -> Option<BackupPollVoteRecord> {
    let object = value.as_object()?;
    let poll_id = string_field(object, "pollId")?;
    let mut entity_ids = Vec::new();
    for item in object.get("entityIds")?.as_array()? {
        entity_ids.push(item.as_str()?.to_string());
    }
    Some(BackupPollVoteRecord { poll_id, entity_ids })
}

fn parse_tag(value: &serde_json::Value) -> Option<BackupPersonalTagRecord> {
    let object = value.as_object()?;
    Some(BackupPersonalTagRecord {
        entity_type: string_field(object, "entityType")?,
        entity_id: string_field(object, "entityId")?,
        tag_name: string_field(object, "tagName")?,
        created_at: string_field(object, "createdAt")?,
    })
}

fn string_field(object: &serde_json::Map<String, serde_json::Value>, key: &str) -> Option<String> {
    object.get(key)?.as_str().map(|s| s.to_string())
}

/// メタ情報用。文字列でなければ空文字 (deviceId が空 = 復元しない、に自然に落ちる)。
fn optional_string(value: Option<&serde_json::Value>) -> String {
    value.and_then(|v| v.as_str()).unwrap_or("").to_string()
}

fn non_empty_string(value: Option<&serde_json::Value>) -> Option<&str> {
    match value?.as_str()? {
        "" => None,
        text => Some(text),
    }
}

/// 整数として読める数値だけを受ける。
/// `1.0` を通すのは iOS の `NSNumber as? Int` が通していたため。文字列は通さない
/// (Android の `getInt` は `"1"` も通すが、書き出し側が数値しか作らないので合わせない)。
fn integral_number(value: &serde_json::Value) -> Option<i64> {
    if let Some(int) = value.as_i64() {
        return Some(int);
    }
    let float = value.as_f64()?;
    if float.fract() == 0.0 && float >= i64::MIN as f64 && float <= i64::MAX as f64 {
        Some(float as i64)
    } else {
        None
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    fn mark(entity_id: &str, kind: &str) -> BackupUserMarkRecord {
        BackupUserMarkRecord {
            entity_type: "idol".to_string(),
            entity_id: entity_id.to_string(),
            kind: kind.to_string(),
            bool_value: true,
            text_value: None,
            updated_at: "2026-01-02T03:04:05Z".to_string(),
        }
    }

    fn tag(entity_id: &str, name: &str) -> BackupPersonalTagRecord {
        BackupPersonalTagRecord {
            entity_type: "song".to_string(),
            entity_id: entity_id.to_string(),
            tag_name: name.to_string(),
            created_at: "2026-01-02T03:04:05Z".to_string(),
        }
    }

    fn vote(poll_id: &str, ids: &[&str]) -> BackupPollVoteRecord {
        BackupPollVoteRecord {
            poll_id: poll_id.to_string(),
            entity_ids: ids.iter().map(|s| s.to_string()).collect(),
        }
    }

    fn export_input() -> BackupExportInput {
        BackupExportInput {
            exported_at: "2026-08-25T00:00:00Z".to_string(),
            platform: "ios".to_string(),
            app_version: "1.7.0".to_string(),
            device_id: "device-1".to_string(),
            user_marks: vec![mark("idol_1", "myPick")],
            poll_votes: vec![vote("poll_1", &["b", "a"])],
            personal_tags: vec![tag("song_1", "神曲")],
        }
    }

    /// envelope を組んで自分で読み直せる (checksum も schemaVersion も通る)。
    #[test]
    fn round_trips_own_envelope() {
        let doc = build_backup_envelope(&export_input(), BackupKindDialect::Canonical);
        let plan = plan_backup_import(
            &doc.envelope_json,
            &BackupLocalState::default(),
            true,
            BackupKindDialect::Canonical,
        )
        .expect("自分で書いた envelope は必ず読める");
        assert_eq!(plan.added_marks, 1);
        assert_eq!(plan.added_votes, 2);
        assert_eq!(plan.added_personal_tags, 1);
        assert!(plan.restore_device_id);
        assert_eq!(plan.info.device_id, "device-1");
        assert_eq!(plan.info.platform, "ios");
        assert_eq!(plan.info.schema_version, 1);
        assert_eq!(plan.info.envelope_version, Some(1));
        assert_eq!(plan.info.skipped_entries, 0);
    }

    // MARK: 書き出しのバイト規則

    /// payload はキー昇順・空白なし。textValue が None ならキーごと落ちる。
    #[test]
    fn payload_keys_are_sorted_and_compact() {
        let doc = build_backup_envelope(&export_input(), BackupKindDialect::Canonical);
        assert_eq!(
            doc.payload_json,
            concat!(
                r#"{"appVersion":"1.7.0","deviceId":"device-1","exportedAt":"2026-08-25T00:00:00Z","#,
                r#""personalTags":[{"createdAt":"2026-01-02T03:04:05Z","entityId":"song_1","entityType":"song","tagName":"神曲"}],"#,
                r#""platform":"ios","pollVotes":[{"entityIds":["a","b"],"pollId":"poll_1"}],"schemaVersion":1,"#,
                r#""userMarks":[{"boolValue":true,"entityId":"idol_1","entityType":"idol","kind":"myPick","updatedAt":"2026-01-02T03:04:05Z"}]}"#
            )
        );
    }

    /// checksum を外部の SHA-256 実装 (`shasum -a 256`) で計算した値に固定する。
    /// 自前ハッシュと payload バイト列の両方が同時にズレていないことを 1 本で押さえる。
    #[test]
    fn checksum_is_pinned_to_an_external_sha256() {
        let doc = build_backup_envelope(&export_input(), BackupKindDialect::Canonical);
        assert_eq!(
            doc.checksum,
            "sha256:cf2e1aa392de9184b59bf2514a9307fd16288be47e5fc0f0a4b8f84a59dd99f0"
        );
    }

    /// textValue があるときだけ kind と updatedAt の間 (昇順の位置) に入る。
    #[test]
    fn text_value_appears_in_sorted_position() {
        let mut input = export_input();
        input.user_marks = vec![BackupUserMarkRecord {
            text_value: Some("最高\n だった".to_string()),
            ..mark("event_1", "note")
        }];
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);
        assert!(doc.payload_json.contains(
            r#"{"boolValue":true,"entityId":"event_1","entityType":"idol","kind":"note","textValue":"最高\n だった","updatedAt":"2026-01-02T03:04:05Z"}"#
        ));
    }

    /// エクスポートは決定的: poll は poll_id 昇順、entity_ids も昇順に整列される。
    #[test]
    fn export_sorts_poll_votes_deterministically() {
        let mut input = export_input();
        input.poll_votes = vec![vote("z", &["c", "a"]), vote("a", &["b"])];
        let first = build_backup_envelope(&input, BackupKindDialect::Canonical);
        input.poll_votes = vec![vote("a", &["b"]), vote("z", &["a", "c"])];
        let second = build_backup_envelope(&input, BackupKindDialect::Canonical);
        assert_eq!(first.envelope_json, second.envelope_json);
        assert!(first
            .payload_json
            .contains(r#""pollVotes":[{"entityIds":["b"],"pollId":"a"},{"entityIds":["a","c"],"pollId":"z"}]"#));
    }

    /// 空バックアップ: 配列は 3 つとも空で出て、そのまま読み戻せる。
    #[test]
    fn empty_backup_round_trips() {
        let input = BackupExportInput {
            user_marks: vec![],
            poll_votes: vec![],
            personal_tags: vec![],
            ..export_input()
        };
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);
        assert!(doc.payload_json.contains(r#""personalTags":[]"#));
        assert!(doc.payload_json.contains(r#""pollVotes":[]"#));
        assert!(doc.payload_json.contains(r#""userMarks":[]"#));
        let plan = plan_backup_import(
            &doc.envelope_json,
            &BackupLocalState::default(),
            false,
            BackupKindDialect::Canonical,
        )
        .expect("空でも読める");
        assert_eq!((plan.added_marks, plan.added_votes, plan.added_personal_tags), (0, 0, 0));
    }

    /// envelope はキー昇順・2 スペース字下げ・`" : "` 区切り (Darwin の prettyPrinted 流儀)。
    #[test]
    fn envelope_layout_is_stable() {
        let doc = build_backup_envelope(&export_input(), BackupKindDialect::Canonical);
        let lines: Vec<&str> = doc.envelope_json.lines().collect();
        assert_eq!(lines[0], "{");
        assert!(lines[1].starts_with("  \"checksum\" : \"sha256:"));
        assert_eq!(lines[2], "  \"envelopeVersion\" : 1,");
        assert!(lines[3].starts_with("  \"payload\" : \"{"));
        assert_eq!(lines[4], "}");
    }

    /// `/` は `\/` にエスケープする (Darwin の JSONSerialization 流儀を踏襲)。
    #[test]
    fn escapes_forward_slash_like_darwin() {
        let mut input = export_input();
        input.app_version = "1.0/beta".to_string();
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);
        assert!(doc.payload_json.contains(r#""appVersion":"1.0\/beta""#));
        // エスケープしても読み戻しは通る (checksum は書いた文字列に対して付くため)。
        assert!(plan_backup_import(
            &doc.envelope_json,
            &BackupLocalState::default(),
            false,
            BackupKindDialect::Canonical
        )
        .is_ok());
    }

    // MARK: kind の方言

    #[test]
    fn android_kinds_map_to_canonical_on_export() {
        let mut input = export_input();
        input.user_marks = vec![mark("i1", "pick"), mark("i2", "memo"), mark("i3", "favorite")];
        let doc = build_backup_envelope(&input, BackupKindDialect::Android);
        assert!(doc.payload_json.contains(r#""kind":"myPick""#));
        assert!(doc.payload_json.contains(r#""kind":"note""#));
        assert!(doc.payload_json.contains(r#""kind":"favorite""#));
    }

    /// Android が知らない kind は素通しする (次に iOS へ戻したとき復元できる)。
    #[test]
    fn unknown_kinds_pass_through_both_ways() {
        for kind in ["collected", "seat", "owned", "attended"] {
            assert_eq!(backup_kind_to_android(kind), kind);
            assert_eq!(backup_kind_to_canonical(kind), kind);
        }
        assert_eq!(backup_kind_to_android("myPick"), "pick");
        assert_eq!(backup_kind_to_canonical("pick"), "myPick");
        assert_eq!(backup_kind_to_android("note"), "memo");
        assert_eq!(backup_kind_to_canonical("memo"), "note");
    }

    /// Android 方言で取り込むと、既存キーも取り込み結果も Android 表記で揃う。
    #[test]
    fn android_dialect_normalizes_both_sides() {
        let mut input = export_input();
        input.user_marks = vec![mark("i1", "myPick"), mark("i2", "note")];
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);

        let local = BackupLocalState {
            // ローカルは Android 表記。canonical の myPick と同じものとして弾かれる。
            mark_keys: vec![BackupMarkKey {
                entity_type: "idol".to_string(),
                entity_id: "i1".to_string(),
                kind: "pick".to_string(),
            }],
            ..Default::default()
        };
        let plan =
            plan_backup_import(&doc.envelope_json, &local, false, BackupKindDialect::Android)
                .expect("読める");
        assert_eq!(plan.added_marks, 1);
        assert_eq!(plan.marks_to_insert[0].entity_id, "i2");
        assert_eq!(plan.marks_to_insert[0].kind, "memo");
    }

    // MARK: 整合判定 (中断する条件)

    #[test]
    fn rejects_non_json() {
        assert_eq!(
            plan_backup_import("これはJSONではない", &BackupLocalState::default(), false, BackupKindDialect::Canonical),
            Err(BackupImportError::MalformedFile)
        );
    }

    #[test]
    fn rejects_envelope_without_payload_or_checksum() {
        for json in [
            r#"{"envelopeVersion":1,"checksum":"sha256:x"}"#,
            r#"{"envelopeVersion":1,"payload":"{}"}"#,
            r#"{"envelopeVersion":1,"checksum":"","payload":"{}"}"#,
            r#"{"envelopeVersion":1,"checksum":"sha256:x","payload":""}"#,
            r#"{"envelopeVersion":1,"checksum":123,"payload":"{}"}"#,
            "[]",
        ] {
            assert_eq!(
                inspect_backup_envelope(json),
                Err(BackupImportError::MalformedFile),
                "{json} は弾かれるべき"
            );
        }
    }

    /// envelopeVersion は無くても中断しない (両 OS とも値を使っていない)。
    #[test]
    fn missing_envelope_version_is_tolerated() {
        let doc = build_backup_envelope(&export_input(), BackupKindDialect::Canonical);
        let stripped = format!(
            "{{\"checksum\":{},\"payload\":{}}}",
            json_string_literal(&doc.checksum),
            json_string_literal(&doc.payload_json)
        );
        let info = inspect_backup_envelope(&stripped).expect("envelopeVersion 無しでも読める");
        assert_eq!(info.envelope_version, None);
        assert_eq!(info.mark_count, 1);
    }

    /// payload を 1 文字でも書き換えたら checksum 不一致で中断する。
    #[test]
    fn detects_tampered_payload() {
        let doc = build_backup_envelope(&export_input(), BackupKindDialect::Canonical);
        let tampered = doc.payload_json.replace("device-1", "device-2");
        let json = format!(
            "{{\"checksum\":{},\"envelopeVersion\":1,\"payload\":{}}}",
            json_string_literal(&doc.checksum),
            json_string_literal(&tampered)
        );
        assert_eq!(inspect_backup_envelope(&json), Err(BackupImportError::ChecksumMismatch));
    }

    /// checksum が合っていても payload が JSON でなければ形式エラー。
    #[test]
    fn rejects_payload_that_is_not_json_object() {
        for payload in ["not json", "[]", "\"text\"", "{}"] {
            let json = format!(
                "{{\"checksum\":\"sha256:{}\",\"envelopeVersion\":1,\"payload\":{}}}",
                sha256_hex(payload),
                json_string_literal(payload)
            );
            assert_eq!(
                inspect_backup_envelope(&json),
                Err(BackupImportError::MalformedFile),
                "payload={payload} は弾かれるべき"
            );
        }
    }

    /// schemaVersion が現行より新しければ中断 (値をそのままユーザーに見せる)。
    #[test]
    fn rejects_future_schema_version() {
        let json = envelope_of(r#"{"schemaVersion":2}"#);
        assert_eq!(
            inspect_backup_envelope(&json),
            Err(BackupImportError::UnsupportedSchemaVersion { found: 2 })
        );
        let json = envelope_of(r#"{"schemaVersion":99}"#);
        assert_eq!(
            inspect_backup_envelope(&json),
            Err(BackupImportError::UnsupportedSchemaVersion { found: 99 })
        );
    }

    /// 現行以下の schemaVersion は読む (0 や負も含む。古い版を弾く理由がない)。
    #[test]
    fn accepts_current_and_older_schema_versions() {
        for version in [-1, 0, 1] {
            let json = envelope_of(&format!(r#"{{"schemaVersion":{version}}}"#));
            let info = inspect_backup_envelope(&json).expect("現行以下は読める");
            assert_eq!(info.schema_version, version);
            // 項目が丸ごと無い古い payload は空扱い (personalTags 追加前のファイル)。
            assert_eq!((info.mark_count, info.vote_count, info.personal_tag_count), (0, 0, 0));
        }
    }

    /// 整数値の 1.0 は通す (iOS の NSNumber as? Int 相当)。文字列や小数は形式エラー。
    #[test]
    fn schema_version_must_be_an_integral_number() {
        assert_eq!(inspect_backup_envelope(&envelope_of(r#"{"schemaVersion":1.0}"#)).unwrap().schema_version, 1);
        for payload in [r#"{"schemaVersion":"1"}"#, r#"{"schemaVersion":1.5}"#, r#"{"schemaVersion":null}"#, "{}"] {
            assert_eq!(
                inspect_backup_envelope(&envelope_of(payload)),
                Err(BackupImportError::MalformedFile),
                "{payload} は弾かれるべき"
            );
        }
    }

    // MARK: 要素単位のスキップ

    /// 壊れた要素だけを捨てて、健全な要素は取り込む。件数は 3 種の合計。
    #[test]
    fn skips_only_broken_entries() {
        let payload = concat!(
            r#"{"schemaVersion":1,"userMarks":["#,
            r#"{"entityType":"idol","entityId":"ok","kind":"myPick","boolValue":true,"updatedAt":"t"},"#,
            r#"{"entityType":"idol","entityId":"no_kind","boolValue":true,"updatedAt":"t"},"#,
            r#"{"entityType":"idol","entityId":"bool_as_number","kind":"myPick","boolValue":1,"updatedAt":"t"},"#,
            r#""文字列要素""#,
            r#"],"pollVotes":[{"pollId":"p","entityIds":["a"]},{"pollId":"p2","entityIds":[1]},{"entityIds":["x"]}],"#,
            r#""personalTags":[{"entityType":"song","entityId":"s","tagName":"n","createdAt":"c"},{"entityType":"song"}]}"#
        );
        let plan = plan_backup_import(
            &envelope_of(payload),
            &BackupLocalState::default(),
            false,
            BackupKindDialect::Canonical,
        )
        .expect("全体は中断しない");
        assert_eq!(plan.added_marks, 1);
        assert_eq!(plan.marks_to_insert[0].entity_id, "ok");
        assert_eq!(plan.added_votes, 1);
        assert_eq!(plan.added_personal_tags, 1);
        // marks 3 + votes 2 + tags 1
        assert_eq!(plan.info.skipped_entries, 6);
    }

    /// textValue は null / 未指定なら None、文字列ならそのまま、型違いなら行ごとスキップ。
    #[test]
    fn text_value_typing_matches_ios_decoder() {
        let payload = concat!(
            r#"{"schemaVersion":1,"userMarks":["#,
            r#"{"entityType":"e","entityId":"null","kind":"note","boolValue":false,"textValue":null,"updatedAt":"t"},"#,
            r#"{"entityType":"e","entityId":"text","kind":"note","boolValue":false,"textValue":"メモ","updatedAt":"t"},"#,
            r#"{"entityType":"e","entityId":"number","kind":"note","boolValue":false,"textValue":5,"updatedAt":"t"}"#,
            "]}"
        );
        let plan = plan_backup_import(
            &envelope_of(payload),
            &BackupLocalState::default(),
            false,
            BackupKindDialect::Canonical,
        )
        .unwrap();
        assert_eq!(plan.added_marks, 2);
        assert_eq!(plan.marks_to_insert[0].text_value, None);
        assert_eq!(plan.marks_to_insert[1].text_value, Some("メモ".to_string()));
        assert_eq!(plan.info.skipped_entries, 1);
    }

    /// 非オブジェクト要素が混ざっても、健全な要素は取り込み、壊れた要素だけ数える。
    /// iOS 原本は `as? [[String: Any]]` が配列ごと nil になり 0 件・skipped 0 で素通りする。
    /// ここは Android (org.json) 側に寄せた意図的な差分なので、その差分ごとピン留めする。
    #[test]
    fn mixed_arrays_are_read_element_wise_unlike_ios() {
        let payload = concat!(
            r#"{"schemaVersion":1,"userMarks":["#,
            r#"{"entityType":"idol","entityId":"ok","kind":"myPick","boolValue":true,"updatedAt":"t"},"#,
            r#"42"#,
            r#"],"pollVotes":[{"pollId":"p","entityIds":["a"]},null],"#,
            r#""personalTags":[{"entityType":"song","entityId":"s","tagName":"n","createdAt":"c"},["x"]]}"#
        );
        let plan = plan_backup_import(
            &envelope_of(payload),
            &BackupLocalState::default(),
            false,
            BackupKindDialect::Canonical,
        )
        .expect("壊れた要素があっても全体は中断しない");
        // iOS 原本ならこの 3 項目はすべて 0 件になっていた。
        assert_eq!((plan.added_marks, plan.added_votes, plan.added_personal_tags), (1, 1, 1));
        assert_eq!(plan.marks_to_insert[0].entity_id, "ok");
        assert_eq!(plan.personal_tags_to_insert[0].tag_name, "n");
        assert_eq!(plan.poll_votes_to_add[0].entity_ids, vec!["a".to_string()]);
        // 3 項目それぞれ 1 要素ずつ壊れている (iOS 原本は 0)。
        assert_eq!(plan.info.skipped_entries, 3);
        // 下見の件数も「読めた分」を返す。
        assert_eq!(
            (plan.info.mark_count, plan.info.vote_count, plan.info.personal_tag_count),
            (1, 1, 1)
        );
    }

    /// 配列であるべき所が配列でなければ、その項目は空扱い (数えようがないので skip も 0)。
    #[test]
    fn non_array_sections_are_treated_as_empty() {
        let payload = r#"{"schemaVersion":1,"userMarks":{},"pollVotes":"x","personalTags":3}"#;
        let info = inspect_backup_envelope(&envelope_of(payload)).unwrap();
        assert_eq!((info.mark_count, info.vote_count, info.personal_tag_count), (0, 0, 0));
        assert_eq!(info.skipped_entries, 0);
    }

    // MARK: 重複・衝突の解決

    /// ローカルに同じ (entityType, entityId, kind) があれば足さない (非破壊マージ)。
    #[test]
    fn existing_marks_are_never_overwritten() {
        let mut input = export_input();
        input.user_marks = vec![mark("i1", "myPick"), mark("i2", "favorite")];
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);
        let local = BackupLocalState {
            mark_keys: vec![BackupMarkKey {
                entity_type: "idol".to_string(),
                entity_id: "i1".to_string(),
                kind: "myPick".to_string(),
            }],
            ..Default::default()
        };
        let plan =
            plan_backup_import(&doc.envelope_json, &local, false, BackupKindDialect::Canonical).unwrap();
        assert_eq!(plan.added_marks, 1);
        assert_eq!(plan.marks_to_insert[0].entity_id, "i2");
    }

    /// kind が違えば別行 (担当とお気に入りは共存する)。
    #[test]
    fn same_entity_with_different_kind_is_a_separate_row() {
        let mut input = export_input();
        input.user_marks = vec![mark("i1", "myPick"), mark("i1", "favorite")];
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);
        let plan = plan_backup_import(
            &doc.envelope_json,
            &BackupLocalState::default(),
            false,
            BackupKindDialect::Canonical,
        )
        .unwrap();
        assert_eq!(plan.added_marks, 2);
    }

    /// バックアップの中に同じキーが 2 回あっても 1 件しか数えない (件数の水増しを防ぐ)。
    #[test]
    fn duplicate_keys_inside_backup_count_once() {
        let mut input = export_input();
        input.user_marks = vec![
            mark("i1", "myPick"),
            BackupUserMarkRecord { updated_at: "9999".to_string(), ..mark("i1", "myPick") },
        ];
        input.personal_tags = vec![tag("s1", "神曲"), tag("s1", "神曲")];
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);
        let plan = plan_backup_import(
            &doc.envelope_json,
            &BackupLocalState::default(),
            false,
            BackupKindDialect::Canonical,
        )
        .unwrap();
        assert_eq!(plan.added_marks, 1);
        // 先勝ち: 後から来た同キーの行は捨てる。
        assert_eq!(plan.marks_to_insert[0].updated_at, "2026-01-02T03:04:05Z");
        assert_eq!(plan.added_personal_tags, 1);
    }

    /// マイタグは (entityType, entityId, tagName) が一致したら足さない。
    #[test]
    fn existing_personal_tags_are_skipped() {
        let mut input = export_input();
        input.personal_tags = vec![tag("s1", "神曲"), tag("s1", "泣ける"), tag("s2", "神曲")];
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);
        let local = BackupLocalState {
            tag_keys: vec![BackupTagKey {
                entity_type: "song".to_string(),
                entity_id: "s1".to_string(),
                tag_name: "神曲".to_string(),
            }],
            ..Default::default()
        };
        let plan =
            plan_backup_import(&doc.envelope_json, &local, false, BackupKindDialect::Canonical).unwrap();
        assert_eq!(plan.added_personal_tags, 2);
    }

    /// 投票履歴はお題ごとの集合の差分だけ返す。全部持っていればそのお題は消える。
    #[test]
    fn poll_votes_merge_as_set_difference() {
        let mut input = export_input();
        input.poll_votes = vec![vote("p1", &["a", "b", "c"]), vote("p2", &["x"])];
        let doc = build_backup_envelope(&input, BackupKindDialect::Canonical);
        let local = BackupLocalState {
            poll_votes: vec![vote("p1", &["a"]), vote("p2", &["x"])],
            ..Default::default()
        };
        let plan =
            plan_backup_import(&doc.envelope_json, &local, false, BackupKindDialect::Canonical).unwrap();
        assert_eq!(plan.added_votes, 2);
        assert_eq!(plan.poll_votes_to_add, vec![vote("p1", &["b", "c"])]);
    }

    /// 同じ poll_id が複数エントリに割れていても 1 つにまとめ、重複は 1 回しか数えない。
    #[test]
    fn duplicate_poll_ids_are_unioned() {
        let payload = concat!(
            r#"{"schemaVersion":1,"pollVotes":["#,
            r#"{"pollId":"p","entityIds":["a","b"]},"#,
            r#"{"pollId":"p","entityIds":["b","c"]}"#,
            "]}"
        );
        let plan = plan_backup_import(
            &envelope_of(payload),
            &BackupLocalState::default(),
            false,
            BackupKindDialect::Canonical,
        )
        .unwrap();
        assert_eq!(plan.added_votes, 3);
        assert_eq!(plan.poll_votes_to_add, vec![vote("p", &["a", "b", "c"])]);
    }

    // MARK: 端末 ID

    /// deviceId が空・非文字列なら、要求されていても復元しない。
    #[test]
    fn device_id_is_restored_only_when_present_and_requested() {
        let with_id = envelope_of(r#"{"schemaVersion":1,"deviceId":"abc"}"#);
        let empty_id = envelope_of(r#"{"schemaVersion":1,"deviceId":""}"#);
        let no_id = envelope_of(r#"{"schemaVersion":1}"#);
        let numeric_id = envelope_of(r#"{"schemaVersion":1,"deviceId":42}"#);
        let plan = |json: &str, restore: bool| {
            plan_backup_import(json, &BackupLocalState::default(), restore, BackupKindDialect::Canonical)
                .unwrap()
                .restore_device_id
        };
        assert!(plan(&with_id, true));
        assert!(!plan(&with_id, false));
        assert!(!plan(&empty_id, true));
        assert!(!plan(&no_id, true));
        assert!(!plan(&numeric_id, true));
    }

    // MARK: SHA-256

    /// FIPS 180-4 / NIST の既知テストベクタ。
    #[test]
    fn sha256_matches_known_vectors() {
        assert_eq!(
            sha256_hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
        // 2 ブロック超え + 長さフィールドの繰り上がり。
        assert_eq!(
            sha256_hex(
                "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
            ),
            "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
        );
        // 非 ASCII は UTF-8 バイト列としてハッシュする (日本語メモが入るため重要)。
        assert_eq!(
            sha256_hex("日本語"),
            "77710aedc74ecfa33685e33a6c7df5cc83004da1bdcef7fb280f5c2b2e97e0a5"
        );
    }

    /// 55 / 56 / 64 バイト境界 (パディングが 1 ブロック増える所) で崩れない。
    #[test]
    fn sha256_handles_padding_boundaries() {
        assert_eq!(
            sha256_hex(&"a".repeat(55)),
            "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"
        );
        assert_eq!(
            sha256_hex(&"a".repeat(56)),
            "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"
        );
        assert_eq!(
            sha256_hex(&"a".repeat(64)),
            "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"
        );
    }

    /// テスト用: 任意の payload 文字列を正しい checksum つき envelope に包む。
    fn envelope_of(payload: &str) -> String {
        format!(
            "{{\"checksum\":\"sha256:{}\",\"envelopeVersion\":1,\"payload\":{}}}",
            sha256_hex(payload),
            json_string_literal(payload)
        )
    }
}
