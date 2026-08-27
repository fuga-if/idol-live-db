//! 同期計画・シード判定の FFI 面。ロジックは domain::sync_planning。
//!
//! CloudKit の transport は共有しない (iOS = CloudKit.framework / Android = Web Services)。
//! ここに出ているのは「状態を渡してやるべきことを受け取る」判定だけで、CKQuery の組み立て・
//! HTTP・リトライ・DB への実書き込みは各 OS 側に残る。
//!
//! チャンクループの入力契約 (`added_since_restart` は dedup 後の新規件数 / seen は巻き戻しで
//! リセットしない / Android は `has_next_cursor = false`) は
//! [`crate::domain::sync_planning`] のモジュール doc が正。
//!
//! エポック値の単位は **秒 (f64)** で統一する (Android の `System.currentTimeMillis()` は
//! 1000 で割ってから渡す)。境界巻き戻し幅が秒で定義されているため、単位を混ぜると
//! 巻き戻しが 1000 倍ずれて境界レコードを取りこぼす。

use crate::domain::sync_planning::{
    self, SyncChunkAction, SyncCompletion, SyncCompletionState, SyncRecordPartition, SyncRunStart,
    SyncStartupPlan, SyncStartupState, SyncStep, SyncStepStart, SyncTableInfo,
};

// --- 起動時の同期モード判定 ---

/// 起動時に full / incremental のどちらで走るか、どこから取るかを決める。
#[uniffi::export]
pub fn sync_startup_plan(state: SyncStartupState) -> SyncStartupPlan {
    sync_planning::startup_plan(&state)
}

/// iOS が使う定期フル再取得の間隔 (24 時間, 秒)。Android は None を渡して無効化する。
#[uniffi::export]
pub fn sync_default_full_sync_interval_seconds() -> f64 {
    sync_planning::DEFAULT_FULL_SYNC_INTERVAL_SECONDS
}

// --- 取り込み順序 ---

/// 対応しているレコードタイプだけを FK 依存順に並べて返す。空を渡すと全ステップ。
///
/// 渡した並びは無視され、常に親テーブルが先に来る。
#[uniffi::export]
pub fn sync_steps_in_order(available_record_types: Vec<String>) -> Vec<SyncStep> {
    sync_planning::steps_for(&available_record_types)
}

// --- 実行の起点 (フル同期の途中再開) ---

/// 同期 1 回分の起点を決める (中断されたフルの再開を含む)。
#[uniffi::export]
pub fn sync_run_start_plan(
    is_full_sync: bool,
    sync_start_epoch: f64,
    pending_full_start_epoch: Option<f64>,
    persisted_done_steps: Vec<String>,
) -> SyncRunStart {
    sync_planning::run_start_plan(
        is_full_sync,
        sync_start_epoch,
        pending_full_start_epoch,
        &persisted_done_steps,
    )
}

// --- ステップの起点と孤児掃除の可否 ---

/// 1 ステップの取得起点と、そのステップで孤児掃除を許してよいかを決める。
#[uniffi::export]
pub fn sync_step_start_plan(
    record_type: String,
    is_full_sync: bool,
    done_steps: Vec<String>,
    checkpoint_epoch: Option<f64>,
    modified_since_epoch: Option<f64>,
) -> SyncStepStart {
    sync_planning::step_start_plan(
        &record_type,
        is_full_sync,
        &done_steps,
        checkpoint_epoch,
        modified_since_epoch,
    )
}

// --- チャンクループ ---

/// チャンクを 1 つ処理し終えた後の次の一手 (カーソル継続 / 境界を戻して張り直し / 完了)。
///
/// `added_since_restart` は **seen 集合で dedup した後の新規件数**。取得件数をそのまま渡すと
/// 巻き戻しで取り直した分が毎回新規に数えられ、そのステップが無限ループする。
/// Android は `CloudKitClient.query()` が continuationMarker を内部で使い切るので
/// `has_next_cursor = false` を渡すが、それでも 1 ステップにつき境界確認の 1 クエリが増える
/// (2 回目は `modifiedAt > max - 1ms` なので数件しか返らない)。
#[uniffi::export]
pub fn sync_next_chunk_action(
    has_next_cursor: bool,
    added_since_restart: u32,
    max_epoch_since_restart: Option<f64>,
) -> SyncChunkAction {
    sync_planning::next_chunk_action(
        has_next_cursor,
        added_since_restart,
        max_epoch_since_restart,
    )
}

// --- 仕分け ---

/// `deletedAt` の有無で upsert 対象と削除対象の index に分ける。
///
/// レコード本体は渡さない。呼び出し側が自国の配列を index で引き直す。
#[uniffi::export]
pub fn sync_partition_by_deleted(is_deleted: Vec<bool>) -> SyncRecordPartition {
    sync_planning::partition_by_deleted(&is_deleted)
}

// --- テーブル対応と recordName 分解 ---

/// recordType に対応するローカルテーブルと PK 列。未知のタイプは None = 同期対象外。
#[uniffi::export]
pub fn sync_table_info(record_type: String) -> Option<SyncTableInfo> {
    sync_planning::table_info(&record_type)
}

/// 複合 PK の recordName `"{table}-{v1}-{v2}"` を PK 値配列に分解する。合わなければ None。
#[uniffi::export]
pub fn sync_parse_composite_record_name(
    record_name: String,
    table: String,
    pk_count: u32,
) -> Option<Vec<String>> {
    sync_planning::parse_composite_record_name(&record_name, &table, pk_count)
}

// --- 孤児掃除 ---

/// そのレコードタイプで孤児掃除を行ってよいか (単一 PK `id` のテーブルのみ)。
#[uniffi::export]
pub fn sync_supports_orphan_cleanup(record_type: String) -> bool {
    sync_planning::supports_orphan_cleanup(&record_type)
}

/// ローカルにあってサーバに無い ID を返す。`valid_ids` が空なら常に空 (全消し防止)。
#[uniffi::export]
pub fn sync_orphan_ids(local_ids: Vec<String>, valid_ids: Vec<String>) -> Vec<String> {
    sync_planning::orphan_ids(&local_ids, &valid_ids)
}

// --- 完了時の後始末 ---

/// 同期完了時に保存する時刻・保留状態の破棄・変更通知・`last_full_sync_at` の更新を決める。
///
/// エラーで途中打ち切りになった実行でも呼ぶこと (`all_steps_completed: false`)。
/// `last_full_sync_at` の更新だけは一次実装どおり成否に関わらず走り、他は全部止まる。
/// この更新を落とすと 24 時間後から毎起動が全件フルになる。
#[uniffi::export]
pub fn sync_completion_plan(state: SyncCompletionState) -> SyncCompletion {
    sync_planning::completion_plan(&state)
}

// --- seed 取り込み (Android SeedImporter) ---

/// main と seed の両方にあるテーブルを main の順序で返す (内部テーブルは除外)。
#[uniffi::export]
pub fn seed_common_tables(main_tables: Vec<String>, seed_tables: Vec<String>) -> Vec<String> {
    sync_planning::seed_common_tables(&main_tables, &seed_tables)
}

/// main と seed の両方にある列を main の列順で返す。空ならそのテーブルは移せない。
#[uniffi::export]
pub fn seed_common_columns(main_columns: Vec<String>, seed_columns: Vec<String>) -> Vec<String> {
    sync_planning::seed_common_columns(&main_columns, &seed_columns)
}

// --- reseed (iOS bundle master.sqlite → Documents DB) ---

/// `meta.data_version` の文字列をバージョン番号に読む。欠損・非数値はすべて 0。
#[uniffi::export]
pub fn reseed_parse_data_version(value: Option<String>) -> i64 {
    sync_planning::parse_data_version(value.as_deref())
}

/// 同梱データを端末へ入れ直すべきか。
///
/// 判断の主軸は同梱データの指紋 (`meta.content_hash`)。版番号は指紋を持たない
/// 古い同梱データのための退避路。理由は `domain::sync_planning::reseed_needed` に書いた。
#[uniffi::export]
pub fn reseed_needed(
    bundle_version: i64,
    local_version: i64,
    bundle_hash: Option<String>,
    local_hash: Option<String>,
) -> bool {
    sync_planning::reseed_needed(
        bundle_version,
        local_version,
        bundle_hash.as_deref(),
        local_hash.as_deref(),
    )
}

/// reseed で触ってはいけないテーブル一覧 (ユーザデータ / 履歴 / コミュニティ投稿系)。
#[uniffi::export]
pub fn reseed_default_preserved_tables() -> Vec<String> {
    sync_planning::default_preserved_tables()
}

/// reseed 対象テーブルを bundle 側の順序で返す。
///
/// 呼び出し側はこの順序で「全テーブル DELETE → 全テーブル INSERT」の 2 段に分けること。
/// ON DELETE CASCADE は `defer_foreign_keys` の対象外なので、テーブルごとに
/// DELETE→INSERT を回すと後続の親 DELETE が入れたばかりの子を消し直す。
#[uniffi::export]
pub fn reseed_target_tables(
    bundle_tables: Vec<String>,
    local_tables: Vec<String>,
    preserved_tables: Vec<String>,
) -> Vec<String> {
    sync_planning::reseed_target_tables(&bundle_tables, &local_tables, &preserved_tables)
}

/// reseed でコピーする列を bundle 側の列順で返す。空ならそのテーブルは skip。
#[uniffi::export]
pub fn reseed_common_columns(
    bundle_columns: Vec<String>,
    main_columns: Vec<String>,
) -> Vec<String> {
    sync_planning::reseed_common_columns(&bundle_columns, &main_columns)
}

/// reseed の結果ラベル (診断 UI 用)。`v3→v4 ok=20 skipped=1` の形。
#[uniffi::export]
pub fn reseed_summary_label(
    local_version: i64,
    bundle_version: i64,
    ok: u32,
    skipped: u32,
) -> String {
    sync_planning::reseed_summary_label(local_version, bundle_version, ok, skipped)
}

// --- クレジット表記の分割 ---

/// 作詞・作曲・編曲の欄を人ごとに割る。
///
/// 括弧の外では 5 種類の区切りで割り、括弧の中では `・` と `、` だけで割る
/// (`,` `/` は社名の一部)。理由は `domain::credit_names` に書いた。
/// **アプリ側で同じ規則を書き直さないこと** — ずれると同じ人が二通りに分かれる。
#[uniffi::export]
pub fn split_credit_names(text: String) -> Vec<String> {
    crate::domain::credit_names::split_credits(&text)
}

/// 表記の揺れを落として、同じ作家を 1 つに寄せるための鍵。
///
/// 曲側の表記 (所属つき・括弧の全角半角ゆれ) から creators を引くときに使う。
/// 規則は `domain::credit_names` に書いた。
#[uniffi::export]
pub fn canonical_credit_key(name: String) -> String {
    crate::domain::credit_names::canonical_credit_key(&name)
}
