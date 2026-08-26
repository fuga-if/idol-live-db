//! 同期計画とシード判定 — 「何を取りに行き、何を取り込み、何を捨てるか」だけを決める純粋層。
//!
//! 一次実装は iOS `CloudKitSyncEngine` / `AppDatabase+Sync` / `AppDatabase.copyMasterTables` と
//! Android `CloudKitSyncEngine` / `SeedImporter`。
//!
//! ## なぜ「通信」を共有しないか
//!
//! CloudKit へのアクセス手段が OS で非対称だから。iOS は CloudKit.framework (CKQuery /
//! CKQueryOperation.Cursor / CKError のリトライ) を直接叩き、Android は CloudKit Web Services
//! に HTTP + API トークンで問い合わせる。transport を共有しようとすると、どちらか一方に
//! 存在しない概念 (cursor, CKError code, retryAfterSeconds) を型に持ち込むことになる。
//! そこで共有するのは **判定だけ** に絞った:
//!
//! - どのモード (full / incremental) で走るか、どこから取るか
//! - 取ってきたレコード列のうち何を upsert し何を削除するか
//! - フル完走時に孤児として消してよい ID はどれか
//! - seed / bundle DB から実データを移すとき、どのテーブル・どの列を対象にするか
//! - reseed が必要か (data_version 比較)
//!
//! ネットワーク呼び出し・CKQuery 組み立て・HTTP・リトライ制御・DatabaseQueue/Room への
//! 実書き込みは各 OS に残る。ここにあるのは全部「引数で状態を受け、やるべきことを返す」関数。
//!
//! ## 時刻の単位
//!
//! エポック値はすべて **秒 (f64)** で受け渡す。iOS の `Date.timeIntervalSince1970` がそのまま
//! 乗る単位で、境界巻き戻しの 1ms ([`BOUNDARY_REWIND_SECONDS`]) もこの単位で定義されている。
//! Android は `System.currentTimeMillis()` (ミリ秒) を持っているので、境界で 1000 で割ること。
//! 単位を混ぜると巻き戻し幅が 1000 倍ずれて境界レコードを取りこぼす。
//!
//! OS 時刻は取らない。「今」は必ず `now_epoch` として引数で受ける。
//!
//! ## 呼び出し側の契約 (ステップ内チャンクループ)
//!
//! [`next_chunk_action`] が返すのは「次の一手」だけで、ループの状態 (見た recordName の
//! 集合 = seen、巻き戻し区間ごとの新規件数、同区間の最大 modifiedAt) は呼び出し側が持つ。
//! 契約は 3 つ:
//!
//! 1. **`added_since_restart` は seen で dedup した後の新規件数**。取得件数をそのまま渡しては
//!    いけない。境界巻き戻し (`RestartFrom`) で取り直した同じレコードが毎回「新規」に数えられ、
//!    同じ `start_epoch` の `RestartFrom` が返り続けてそのステップが無限ループする
//!    (テスト `chunk_loop_without_dedup_never_terminates` がこれを固定している)。
//! 2. **seen は巻き戻しでリセットしない**。リセットすると重複が新規に化けて 1 と同じ結末になる。
//!    リセットするのは `added_since_restart` と `max_epoch_since_restart` の 2 つだけ。
//! 3. **cursor を読み切ってから巻き戻す**。順序を逆にすると、単一 modifiedAt がチャンク長を
//!    超えるテーブルで先頭チャンクを取り直し続け、残りが永久に落ちる。
//!
//! ### iOS
//!
//! `CKQueryOperation.Cursor` をそのまま `has_next_cursor` に写す。
//!
//! ### Android
//!
//! `CloudKitClient.query()` は continuationMarker を **内部で全ページ回してから** 返す。
//! 「cursor が無い」のではなく「呼び出し前に使い切っている」ので `has_next_cursor` は常に
//! `false`。したがって 1 ステップのループは
//!
//! 1. `query(start)` → 全件 → `added > 0` → `RestartFrom(max - 1ms)`
//! 2. `query(max - 1ms)` → 境界の数件のみ → dedup 後 `added == 0` → `Finish`
//!
//! の **2 回** になる。現行の「1 ステップ 1 クエリ」から 1 回増えるが、2 回目は
//! `modifiedAt > max - 1ms` なので境界に載った数件しか返らない。この 1 回が、同一 modifiedAt が
//! ページ境界で割れたときの取りこぼしを塞ぐ対価。**`records.size` を `added_since_restart` に
//! 渡すと 2 で止まらず無限ループする** ので、Android も `seen: MutableSet<String>` を
//! ステップ内で持ち回ること。

use std::collections::HashSet;

// ---------------------------------------------------------------------------
// 1. 起動時の同期モード判定
// ---------------------------------------------------------------------------

/// 同期モード。CloudKit へのクエリを epoch から張るか、前回同期以降に絞るか。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SyncMode {
    /// 全件取得 (iOS `modifiedSince == nil` / Android `since == 0`)。
    Full,
    /// 前回同期以降の差分のみ。
    Incremental,
}

/// そのモードになった理由。ログと診断 UI 用で、分岐そのものには使わない。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SyncModeReason {
    /// 前回のフル同期が途中で中断されて保留中 → 残りステップを再開する (フル扱い)。
    PendingFullResume,
    /// ローカル DB が空 (初回 or スキーマ更新による破棄) → 前回同期時刻を無視して全件。
    LocalDataEmpty,
    /// フル同期の実行記録が無い → 全件。
    NoFullSyncRecord,
    /// 最後のフル同期が古い (間隔超過) → 全件取り直す。
    FullSyncStale,
    /// 差分の起点となる前回同期時刻が無い → 起点が epoch になるので実質フル。
    MissingLastSync,
    /// 通常の差分同期。
    Incremental,
}

/// 起動時判定に必要な状態。呼び出し側が自分の永続化層から集めて渡す。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncStartupState {
    /// フル同期が未完了のまま保留されているか (iOS の `sync_pending_full_start` の有無)。
    /// この機能を持たない環境は false。
    pub has_pending_full_sync: bool,
    /// ローカルにマスタ行が 1 件も無いか (Android の `brandCount() == 0`)。
    /// iOS は bundle master.sqlite から起動するので実質常に false。
    pub local_data_empty: bool,
    /// 直近のフル同期完了時刻。`full_sync_interval_seconds` が None の環境では見ない。
    pub last_full_sync_epoch: Option<f64>,
    /// 直近の同期時刻 (差分の起点)。None は「起点が無い」= フルに落ちる。
    /// Android は prefs の既定値 0 を None に写像して渡すこと (`since == 0` がフルの合図)。
    pub last_sync_epoch: Option<f64>,
    /// 「今」。OS 時刻はここで受ける。
    pub now_epoch: f64,
    /// これを超えてフル同期していなければ強制的にフルへ落とす間隔。
    /// None = 定期フル再取得を行わない (Android)。iOS は 24 時間。
    pub full_sync_interval_seconds: Option<f64>,
}

/// 起動時にどう走るかの結論。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncStartupPlan {
    pub mode: SyncMode,
    /// クエリの起点。`None` = epoch から全件 (= `mode == Full` と必ず一致する)。
    pub modified_since_epoch: Option<f64>,
    pub reason: SyncModeReason,
    /// 中断されたフル同期の再開か (完了済みステップを読み出して飛ばすべきか)。
    pub resuming_pending_full: bool,
}

/// iOS が使う定期フル再取得の間隔 (24 時間)。
///
/// SongArtist (~20k 行) のように差分が大きいテーブルで incremental の取りこぼしが積もると
/// 原唱者が欠けたまま固定されてしまうため、1 日 1 回は必ず全件取り直す。
pub const DEFAULT_FULL_SYNC_INTERVAL_SECONDS: f64 = 24.0 * 3600.0;

/// 起動時の同期モードを決める。
///
/// 優先順は iOS `performStartupSync` の分岐そのまま (保留フル → フル記録 → 差分) に、
/// Android の「DB が空なら前回同期時刻を無視」を先頭寄りに足したもの。iOS では
/// `local_data_empty` が立たないので、この追加は iOS の挙動を変えない。
///
/// 最後に「差分の起点が無ければフル」を適用する。iOS は `lastSyncDate()` が nil のとき
/// `performSync(modifiedSince: nil)` = フル、Android は `since == 0` でフルなので、
/// どちらも同じ結論になる。
pub fn startup_plan(state: &SyncStartupState) -> SyncStartupPlan {
    let full = |reason: SyncModeReason, resuming: bool| SyncStartupPlan {
        mode: SyncMode::Full,
        modified_since_epoch: None,
        reason,
        resuming_pending_full: resuming,
    };

    if state.has_pending_full_sync {
        return full(SyncModeReason::PendingFullResume, true);
    }
    if state.local_data_empty {
        return full(SyncModeReason::LocalDataEmpty, false);
    }
    if let Some(interval) = state.full_sync_interval_seconds {
        match state.last_full_sync_epoch {
            None => return full(SyncModeReason::NoFullSyncRecord, false),
            // 厳密な > 。ちょうど間隔ぴったりでは falling back しない (iOS の比較と同じ)。
            Some(last) if state.now_epoch - last > interval => {
                return full(SyncModeReason::FullSyncStale, false)
            }
            Some(_) => {}
        }
    }
    match state.last_sync_epoch {
        None => full(SyncModeReason::MissingLastSync, false),
        Some(since) => SyncStartupPlan {
            mode: SyncMode::Incremental,
            modified_since_epoch: Some(since),
            reason: SyncModeReason::Incremental,
            resuming_pending_full: false,
        },
    }
}

// ---------------------------------------------------------------------------
// 2. 取り込み順序 (FK 依存)
// ---------------------------------------------------------------------------

/// 同期 1 ステップ = 1 レコードタイプ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SyncStep {
    /// CloudKit のレコードタイプ名。
    pub record_type: String,
    /// 進捗表示用のラベル (iOS/Android で同一文言)。
    pub display_name: String,
}

/// FK 依存順に並べた全ステップ。親テーブルが必ず先に来る。
///
/// 順序を崩すと、親未着の子行が FK 違反で 1 件ずつ捨てられる (iOS は savepoint で 1 行だけ
/// 捨てて続行するので、静かに欠落する)。増分 pull で親が後から来ても、その子行は次の
/// フル同期まで復活しない。
const STEPS_IN_FK_ORDER: &[(&str, &str)] = &[
    // Phase 1: 独立テーブル
    ("Brand", "ブランド"),
    // Phase 2: brands のみ依存
    ("Idol", "アイドル"),
    ("Event", "イベント"),
    ("ImasUnit", "ユニット"),
    // 会場は Show より前。Show が venue_id で参照するため。
    ("Venue", "会場"),
    ("VenueName", "会場名 (改名履歴)"),
    ("VenueHall", "会場ホール"),
    // Phase 3: 上記に依存 (CastMember/IdolCast は廃止)
    ("IdolBrand", "アイドル×ブランド"),
    ("Show", "公演"),
    ("Song", "楽曲"),
    ("UnitMember", "ユニットメンバー"),
    // Phase 4: さらに上に依存
    ("SongArtist", "楽曲アーティスト"),
    ("ShowCast", "公演キャスト"),
    ("SetlistItem", "セトリ"),
    // Phase 5: setlist_items に依存
    ("SetlistPerformer", "セトリ出演者"),
    // Phase 6: コミュニティコンテンツ (songs に依存)
    ("SongCall", "コーレス"),
    ("SongVideo", "参考動画"),
];

/// FK 依存順の全ステップ。
pub fn all_steps() -> Vec<SyncStep> {
    STEPS_IN_FK_ORDER
        .iter()
        .map(|(record_type, display_name)| SyncStep {
            record_type: (*record_type).to_string(),
            display_name: (*display_name).to_string(),
        })
        .collect()
}

/// 対応しているレコードタイプだけを FK 依存順に残す。
///
/// `available` が空なら全ステップ。Android は venue 系テーブルを持たないので、そこを
/// 除いた 14 種を渡す。順序は常にこちらの定義が正で、渡した側の並びは無視する
/// (呼び出し側で並べ替え忘れが起きても親が先に来ることを保証する)。
pub fn steps_for(available: &[String]) -> Vec<SyncStep> {
    if available.is_empty() {
        return all_steps();
    }
    let set: HashSet<&str> = available.iter().map(String::as_str).collect();
    all_steps()
        .into_iter()
        .filter(|step| set.contains(step.record_type.as_str()))
        .collect()
}

// ---------------------------------------------------------------------------
// 3. 1 回の同期実行の起点 (フル同期の途中再開)
// ---------------------------------------------------------------------------

/// 同期 1 回分の起点。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncRunStart {
    /// この実行が「開始した」とみなす時刻。フル再開時は中断前の開始時刻を引き継ぐ。
    /// 長時間同期の最中に変わったレコードを次回差分で拾えるよう、完了時にこれを
    /// last_sync として保存する。
    pub effective_start_epoch: f64,
    /// 既に完了済みで飛ばしてよいステップ (フル再開時のみ非空)。
    pub done_steps: Vec<String>,
    /// 保留状態 (開始時刻 + 空の完了ステップ) を新規に永続化すべきか。
    /// 新しくフルを開始したときだけ true。
    pub should_persist_pending_full_start: bool,
    /// 中断されたフルの再開か。
    pub resumed: bool,
}

/// フル同期の途中再開を考慮した起点を決める。
///
/// フルは中断 (バックグラウンド suspend 等) されうるので、開始時刻と完了ステップを
/// 永続化しておき、再開時は「元の開始時刻」を引き継いで残りステップだけ取る。
/// 差分同期は再開の概念を持たない (常に今から)。
pub fn run_start_plan(
    is_full_sync: bool,
    sync_start_epoch: f64,
    pending_full_start_epoch: Option<f64>,
    persisted_done_steps: &[String],
) -> SyncRunStart {
    if !is_full_sync {
        return SyncRunStart {
            effective_start_epoch: sync_start_epoch,
            done_steps: Vec::new(),
            should_persist_pending_full_start: false,
            resumed: false,
        };
    }
    match pending_full_start_epoch {
        Some(saved) => SyncRunStart {
            effective_start_epoch: saved,
            done_steps: persisted_done_steps.to_vec(),
            should_persist_pending_full_start: false,
            resumed: true,
        },
        // 保留が無い = 新規のフル。ここで初めて開始時刻と空の完了リストを書く。
        None => SyncRunStart {
            effective_start_epoch: sync_start_epoch,
            done_steps: Vec::new(),
            should_persist_pending_full_start: true,
            resumed: false,
        },
    }
}

// ---------------------------------------------------------------------------
// 4. ステップごとの起点と孤児掃除の可否
// ---------------------------------------------------------------------------

/// 1 ステップの取得起点。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncStepStart {
    /// フル再開で完了済み → このステップは丸ごと飛ばす。
    pub skip: bool,
    /// `modifiedAt > start_epoch` の start。
    pub start_epoch: f64,
    /// このステップを epoch から全件取り直しているか。
    /// **孤児掃除を許してよいのはこれが true のステップだけ**。チェックポイントからの
    /// 途中再開だと「見た ID の集合」が不完全で、見ていない既存行を孤児と誤判定して消す。
    pub started_from_epoch: bool,
}

/// ステップの起点を決める。
///
/// - `checkpoint_epoch`: そのステップの途中チェックポイント (直近に取り込んだ最大 modifiedAt)。
///   巨大ステップが中断されても全件取り直さないための保存値。
/// - `modified_since_epoch`: 実行全体の起点 (フルなら None)。
///
/// チェックポイント > 実行全体の起点 > epoch(0) の優先順。
pub fn step_start_plan(
    record_type: &str,
    is_full_sync: bool,
    done_steps: &[String],
    checkpoint_epoch: Option<f64>,
    modified_since_epoch: Option<f64>,
) -> SyncStepStart {
    let skip = is_full_sync && done_steps.iter().any(|done| done == record_type);
    SyncStepStart {
        skip,
        start_epoch: checkpoint_epoch.or(modified_since_epoch).unwrap_or(0.0),
        started_from_epoch: is_full_sync && checkpoint_epoch.is_none(),
    }
}

// ---------------------------------------------------------------------------
// 5. チャンクループの進め方
// ---------------------------------------------------------------------------

/// 同一 modifiedAt の境界を取りこぼさないためにクエリを張り直すときの巻き戻し幅 (秒)。
///
/// `modifiedAt > start` の厳密不等号なので、start ちょうどのレコードが落ちる。1ms 戻して
/// 張り直し、重複は「見た recordName」で dedup する。
pub const BOUNDARY_REWIND_SECONDS: f64 = 0.001;

/// チャンクを 1 つ処理し終えた後に取るべき行動。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq)]
pub enum SyncChunkAction {
    /// 同じクエリにまだ続きがある → 受け取ったカーソルで読み進める。
    ContinueCursor,
    /// クエリを読み切ったが新規があった → 境界を 1ms 戻して張り直す。
    RestartFrom { start_epoch: f64 },
    /// このステップは取り切った。
    Finish,
}

/// チャンク処理後の次の一手を決める。
///
/// カーソルを最後まで追ってから張り直す順序が重要。単一 modifiedAt がチャンク長を超える
/// (例: 一括投入で数千件が同一時刻) 場合、カーソルを捨てて start を張り直すと同じ先頭
/// チャンクを取り直し、新規ゼロで打ち切られて残りが永久に欠落する。
///
/// - `has_next_cursor`: 取得側が「まだ続きがある」と返したか。Android のように取得関数が
///   ページングを内部で使い切る実装では常に `false` (詳細はモジュール doc の契約 3 項)。
/// - `added_since_restart`: 今の start で張り直してから **seen 集合に新しく入った**
///   recordName の数。取得件数をそのまま渡すと巻き戻しで取り直した分が毎回新規に数えられ、
///   同じ `start_epoch` の `RestartFrom` が返り続けて無限ループする。
/// - `max_epoch_since_restart`: 同区間で見た最大 modifiedAt。None = 1 件も取れなかった。
///
/// `added_since_restart` / `max_epoch_since_restart` は `RestartFrom` のたびにリセットするが、
/// seen はリセットしない (リセットすると重複が新規に化けて同じ無限ループになる)。
pub fn next_chunk_action(
    has_next_cursor: bool,
    added_since_restart: u32,
    max_epoch_since_restart: Option<f64>,
) -> SyncChunkAction {
    if has_next_cursor {
        return SyncChunkAction::ContinueCursor;
    }
    let Some(max_epoch) = max_epoch_since_restart else {
        return SyncChunkAction::Finish; // 1 件も取れなかった = 完了
    };
    if added_since_restart == 0 {
        return SyncChunkAction::Finish; // 張り直しても新規ゼロ = 全件取得済み
    }
    SyncChunkAction::RestartFrom {
        start_epoch: max_epoch - BOUNDARY_REWIND_SECONDS,
    }
}

// ---------------------------------------------------------------------------
// 6. 取り込むレコードと捨てるレコードの仕分け
// ---------------------------------------------------------------------------

/// 生存 / 削除の仕分け結果 (入力配列への index)。
///
/// レコード本体は渡さず index で返す (FFI 境界の規約: 呼び出し側が自国の配列を引き直す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SyncRecordPartition {
    /// upsert すべきレコードの index。入力順のまま。
    pub alive_indexes: Vec<u32>,
    /// ローカルから物理削除すべきレコードの index。入力順のまま。
    pub deleted_indexes: Vec<u32>,
}

/// `deletedAt` の有無 (= soft delete フラグ) で取り込み対象と削除対象に分ける。
///
/// 削除の伝搬は soft delete 経由のみ。CloudKit から物理削除されたレコードは通知が来ないので、
/// フル完走時の孤児掃除 ([`orphan_ids`]) が最後の砦になる。
pub fn partition_by_deleted(is_deleted: &[bool]) -> SyncRecordPartition {
    let mut alive_indexes = Vec::new();
    let mut deleted_indexes = Vec::new();
    for (index, deleted) in is_deleted.iter().enumerate() {
        if *deleted {
            deleted_indexes.push(index as u32);
        } else {
            alive_indexes.push(index as u32);
        }
    }
    SyncRecordPartition {
        alive_indexes,
        deleted_indexes,
    }
}

// ---------------------------------------------------------------------------
// 7. recordType → テーブル / PK と recordName の分解
// ---------------------------------------------------------------------------

/// recordType に対応するローカルテーブルと PK 列。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SyncTableInfo {
    pub table: String,
    pub pk_columns: Vec<String>,
}

/// recordType → (テーブル名, PK 列) の対応。未知のタイプは None = 同期対象外。
///
/// 複合 PK の recordName は `"{table}-{pk1}-{pk2}"` 形式 (seed_cloudkit.py の
/// `make_record_name` と一致)。CastMember / IdolCast は廃止 (idol.voiceActors に統合) なので
/// ここに無く、届いても無視される。
pub fn table_info(record_type: &str) -> Option<SyncTableInfo> {
    let (table, pk_columns): (&str, &[&str]) = match record_type {
        "Brand" => ("brands", &["id"]),
        "Idol" => ("idols", &["id"]),
        "Event" => ("events", &["id"]),
        "ImasUnit" => ("units", &["id"]),
        "Show" => ("shows", &["id"]),
        "Venue" => ("venues", &["id"]),
        "VenueName" => ("venue_names", &["id"]),
        "VenueHall" => ("venue_halls", &["id"]),
        "Song" => ("songs", &["id"]),
        "SongCall" => ("song_calls", &["id"]),
        "SongVideo" => ("song_videos", &["id"]),
        "SetlistItem" => ("setlist_items", &["id"]),
        "IdolBrand" => ("idol_brands", &["idol_id", "brand_id"]),
        "UnitMember" => ("unit_members", &["unit_id", "idol_id"]),
        "SongArtist" => ("song_artists", &["song_id", "idol_id", "role"]),
        "ShowCast" => ("show_cast", &["show_id", "idol_id"]),
        "SetlistPerformer" => ("setlist_performers", &["setlist_item_id", "idol_id"]),
        _ => return None,
    };
    Some(SyncTableInfo {
        table: table.to_string(),
        pk_columns: pk_columns.iter().map(|c| c.to_string()).collect(),
    })
}

/// 複合 PK の recordName `"{table}-{v1}-{v2}"` を PK 値配列に分解する。
///
/// テーブル名にも `-` が入りうるので prefix を先に剥がし、残りを **前から** 最大
/// `pk_count` 個に分割する (最後の値だけ `-` を含んでよい)。個数が合わなければ None =
/// この recordName は捨てる。空要素も 1 個として数える (`"a--b"` は 3 値)。
pub fn parse_composite_record_name(
    record_name: &str,
    table: &str,
    pk_count: u32,
) -> Option<Vec<String>> {
    if pk_count == 0 {
        return None;
    }
    let prefix = format!("{table}-");
    let body = record_name.strip_prefix(&prefix)?;
    let parts: Vec<String> = body
        .splitn(pk_count as usize, '-')
        .map(str::to_string)
        .collect();
    if parts.len() != pk_count as usize {
        return None;
    }
    Some(parts)
}

// ---------------------------------------------------------------------------
// 8. 孤児掃除
// ---------------------------------------------------------------------------

/// そのレコードタイプで孤児掃除を行ってよいか。
///
/// 単一 PK (`id` 1 列) のテーブルのみ。複合 PK のテーブルには単一の `id` 列が無く、
/// `SELECT id FROM ...` が例外になる。
pub fn supports_orphan_cleanup(record_type: &str) -> bool {
    table_info(record_type).is_some_and(|info| info.pk_columns == ["id"])
}

/// ローカルにあって CloudKit に無い ID (= 孤児) を返す。順序は `local_ids` のまま。
///
/// `valid_ids` が空なら常に空を返す。取得 0 件は通信異常やスキーマ未設定でも起きるので、
/// 「サーバに 1 件も無い」と解釈してローカルを全消去するのは危険すぎる。
///
/// 呼び出せるのは「epoch から全件取り直して完走したステップ」だけ
/// ([`SyncStepStart::started_from_epoch`])。途中再開だと `valid_ids` が不完全になる。
pub fn orphan_ids(local_ids: &[String], valid_ids: &[String]) -> Vec<String> {
    if valid_ids.is_empty() {
        return Vec::new();
    }
    let valid: HashSet<&str> = valid_ids.iter().map(String::as_str).collect();
    local_ids
        .iter()
        .filter(|id| !valid.contains(id.as_str()))
        .cloned()
        .collect()
}

// ---------------------------------------------------------------------------
// 9. 同期完了時の後始末
// ---------------------------------------------------------------------------

/// 同期 1 回分を撃ち終えたときの状態。成功・失敗どちらでも同じものを渡す。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncCompletionState {
    pub is_full_sync: bool,
    /// 起動時同期 (iOS `performStartupSync`) の一環として走ったか。
    ///
    /// `last_full_sync_at` を書くのは起動フル分岐だけで、手動のフル再取得
    /// (iOS `performFullSync` = 設定画面の強制リフレッシュ) では書かない。一次実装がそうで、
    /// ここを true に倒すと手動リフレッシュが 24h の再取得タイマーを進めてしまう。
    pub is_startup_run: bool,
    /// この実行が「開始した」とみなす時刻 ([`SyncRunStart::effective_start_epoch`])。
    pub effective_start_epoch: f64,
    /// 今回の実行を開始した時刻。
    pub sync_start_epoch: f64,
    /// 撃ち終えた時刻 (「今」)。`last_full_sync_at` に書くのはこちら。
    pub completion_epoch: f64,
    pub total_fetched: u32,
    /// 全ステップを最後まで回せたか。false = 途中でエラー打ち切り。
    pub all_steps_completed: bool,
}

/// 同期完了時にやるべきこと。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncCompletion {
    /// `last_sync_at` を保存してよいか。途中で打ち切った実行では保存しない
    /// (取り込めていない範囲を「同期済み」にすると次の差分から永久に落ちる)。
    pub should_save_last_sync: bool,
    /// `last_sync_at` として保存する時刻。`should_save_last_sync` が false なら使わない。
    pub last_sync_epoch_to_save: f64,
    /// フル同期の保留状態 (開始時刻 + 完了ステップ) を消してよいか。
    pub should_clear_pending_full: bool,
    /// マスタが実際に変わったか (スナップショット再ロード等の無効化フックを撃つか)。
    pub should_notify_master_changed: bool,
    /// `last_full_sync_at` を更新すべきか。
    ///
    /// **これが [`startup_plan`] の 24h 判定 ([`SyncModeReason::FullSyncStale`]) を進める
    /// 唯一の書き込み**。落とすと `last_full_sync_epoch` が固定され、24 時間後から毎起動が
    /// フルになって 17 ステップ全件 (SongArtist ~20k 行) を取り直し続ける。
    /// `full_sync_interval_seconds = None` の Android では露見せず iOS だけが静かに劣化する。
    pub should_update_last_full_sync: bool,
    /// そこに書く時刻。`should_update_last_full_sync` が false なら None。
    ///
    /// last_sync (= 開始時刻) と違い **完了時刻** を書く。24h タイマーの起点は「いつ全件を
    /// 取り終えたか」なので、開始時刻を書くと同期にかかった時間だけ次のフルが早まる。
    pub last_full_sync_epoch_to_save: Option<f64>,
}

/// 同期完了時の後始末を決める。
///
/// フルは「開始時刻 (再開なら元の開始時刻)」を last_sync にする。同期に何時間かかっても、
/// その最中に変わったレコードを次回の差分で必ず拾い直せるようにするため。完了時刻を
/// 保存すると同期中の変更が差分範囲から抜け落ちる。
///
/// 0 件同期では変更通知を出さない。フォアグラウンド復帰のたびに走る差分同期で毎回
/// DB 全読みが起きるのを避ける。
///
/// エラーで途中打ち切りになった実行でも **呼ぶこと**。last_sync 保存・保留状態の破棄・変更通知は
/// すべて止まるが、`last_full_sync_at` の更新だけは走る。一次実装 (`performStartupSync` の
/// `try? database.updateLastFullSyncDate(Date())`) が `performSync` の成否に関わらず撃っており、
/// ここを成功時のみにすると、フルが毎回失敗する端末で起動のたびに全件取得を再試行し続ける。
pub fn completion_plan(state: &SyncCompletionState) -> SyncCompletion {
    let done = state.all_steps_completed;
    // 起動フル分岐でのみ 24h タイマーを進める。成否は問わない (一次実装の try? が無条件)。
    let update_last_full = state.is_full_sync && state.is_startup_run;
    SyncCompletion {
        should_save_last_sync: done,
        last_sync_epoch_to_save: if state.is_full_sync {
            state.effective_start_epoch
        } else {
            state.sync_start_epoch
        },
        should_clear_pending_full: state.is_full_sync && done,
        should_notify_master_changed: done && state.total_fetched > 0,
        should_update_last_full_sync: update_last_full,
        last_full_sync_epoch_to_save: update_last_full.then_some(state.completion_epoch),
    }
}

// ---------------------------------------------------------------------------
// 10. seed 取り込み (Android SeedImporter)
// ---------------------------------------------------------------------------

/// seed 取り込みの対象外テーブル。スキーマ管理用の内部テーブルで、行を移すと壊れる。
const SEED_SKIP_TABLES: &[&str] = &["room_master_table", "android_metadata", "sqlite_sequence"];

/// main と seed の両方に存在するテーブル名を **main の順序** で返す。
///
/// Room がスキーマの真実を握ったまま実データだけ移す方式なので、両方に存在するものだけが
/// 対象になる。seed 側にしか無いテーブル (song_units 等) は移す先が無いので落とし、
/// main 側にしか無いテーブル (user_marks / song_calls / song_videos) は空のまま残す
/// (ローカル投稿・CloudKit 同期で埋まる)。
pub fn seed_common_tables(main_tables: &[String], seed_tables: &[String]) -> Vec<String> {
    let seed: HashSet<&str> = seed_tables.iter().map(String::as_str).collect();
    let mut seen: HashSet<&str> = HashSet::new();
    main_tables
        .iter()
        .filter(|table| {
            seed.contains(table.as_str())
                && !SEED_SKIP_TABLES.contains(&table.as_str())
                && seen.insert(table.as_str())
        })
        .cloned()
        .collect()
}

/// main と seed の両方に存在する列名を **main の列順** で返す。
///
/// 列差分 (seed が古い / main に後から列が増えた) があっても、共通列だけを
/// `INSERT OR IGNORE ... SELECT` で移せるようにするための対象列。空なら移せる列が無いので
/// そのテーブルは飛ばす。
pub fn seed_common_columns(main_columns: &[String], seed_columns: &[String]) -> Vec<String> {
    intersect_preserving_order(main_columns, seed_columns)
}

// ---------------------------------------------------------------------------
// 11. reseed (iOS bundle master.sqlite → Documents DB)
// ---------------------------------------------------------------------------

/// reseed で触ってはいけないテーブル。
///
/// ユーザ固有データ (担当/お気に入り/メモ/attended、カスタム画像)、マイグレーション履歴、
/// meta (自前で書き換える)、コミュニティ投稿系 (CloudKit 側が正) を守る。
const DEFAULT_PRESERVED_TABLES: &[&str] = &[
    "user_marks",
    "custom_image_paths",
    "grdb_migrations",
    "meta",
    "song_calls",
    "song_videos",
    "song_tags",
    "device_song_tag",
    "device_song_penlight",
];

/// reseed の保護テーブル一覧。
pub fn default_preserved_tables() -> Vec<String> {
    DEFAULT_PRESERVED_TABLES
        .iter()
        .map(|t| t.to_string())
        .collect()
}

/// `meta.data_version` の文字列をバージョン番号に読む。欠損・非数値はすべて 0。
///
/// 0 に落とすことで「bundle > local」の比較が必ず成立し、壊れた値でも reseed が走って
/// 直る側に倒れる。
pub fn parse_data_version(value: Option<&str>) -> i64 {
    value.and_then(|v| v.parse::<i64>().ok()).unwrap_or(0)
}

/// bundle 側が新しいときだけ reseed する。等しい/古いなら何もしない。
///
/// ⚠️ 版番号だけで判断すると取りこぼす。`reseed_needed` を使うこと。
fn version_is_newer(bundle_version: i64, local_version: i64) -> bool {
    bundle_version > local_version
}

/// 同梱データを端末へ入れ直すべきか。
///
/// # なぜ版番号で判断しないか
///
/// 版番号は**内容とは別に人が管理する数字**なので、内容とズレる。実際にズレた:
/// 読み仮名を入れる前のビルドが `data_version = 70` を積んで出てしまい、端末が 70 を
/// 記録した。その後 70 のまま読み仮名入りを配っても `70 > 70` が偽になり、
/// 読み仮名が**永久に届かなくなった**。更新時刻も同じ性質で、内容と独立に動く。
///
/// 指紋 (`content_hash`) は同梱データそのものから機械的に作るので、内容が変われば必ず
/// 変わり、変わらなければ必ず同じになる。人が上げ忘れることも、上げ過ぎることもない。
///
/// 端末側が持つのは「最後に取り込んだ同梱データの指紋」であって、端末の現在の内容の
/// 指紋ではない。取り込んだ後に同期でマスタが増えても指紋は動かないので、
/// 起動のたびに入れ直したりはしない。
///
/// # 版番号を残してある理由
///
/// 指紋を持たない古い端末 (`local_hash` が `None`) と、指紋を書く前に作られた同梱データ
/// (`bundle_hash` が `None`) がある。どちらも版番号での比較に落とす。
/// 指紋を持たない端末は、同梱側に指紋があれば「違う」と判定されて一度だけ入れ直す
/// (これで上のズレも直る)。
pub fn reseed_needed(
    bundle_version: i64,
    local_version: i64,
    bundle_hash: Option<&str>,
    local_hash: Option<&str>,
) -> bool {
    match bundle_hash {
        Some(bundle) => local_hash != Some(bundle),
        // 同梱側に指紋が無い = 指紋を書く前のビルド。版番号で判断するしかない。
        None => version_is_newer(bundle_version, local_version),
    }
}

/// reseed 対象テーブルを **bundle 側の順序** で返す。
///
/// bundle にあり、ローカルにもあり、保護対象でないものだけ。`sqlite_` 前置のシステム
/// テーブルは常に除く (呼び出し側の SQL が `NOT LIKE 'sqlite_%'` を付け忘れても同じ結果に
/// なるようにここでも落とす)。
///
/// なおこの順序で DELETE → INSERT を **2 段に分ける** のは呼び出し側の責務。
/// `defer_foreign_keys` は FK 検証を COMMIT まで遅らせるが、ON DELETE CASCADE は検証では
/// なくアクションなので遅延されない。テーブルごとに DELETE→INSERT を回すと、子を入れた
/// 後に親を消した時点で CASCADE が子を消し直してしまう。
pub fn reseed_target_tables(
    bundle_tables: &[String],
    local_tables: &[String],
    preserved_tables: &[String],
) -> Vec<String> {
    let local: HashSet<&str> = local_tables.iter().map(String::as_str).collect();
    let preserved: HashSet<&str> = preserved_tables.iter().map(String::as_str).collect();
    bundle_tables
        .iter()
        .filter(|table| {
            !table.starts_with("sqlite_")
                && !preserved.contains(table.as_str())
                && local.contains(table.as_str())
        })
        .cloned()
        .collect()
}

/// reseed でコピーする列を **bundle 側の列順** で返す。
///
/// 列順が seed 取り込み ([`seed_common_columns`], main 順) と逆なのは一次実装がそうだから。
/// `INSERT (cols) SELECT (同じ cols)` と同じ並びを両側に使うので、どちらの順でも結果の
/// 行内容は変わらない。
pub fn reseed_common_columns(bundle_columns: &[String], main_columns: &[String]) -> Vec<String> {
    intersect_preserving_order(bundle_columns, main_columns)
}

/// reseed の結果ラベル (診断 UI 用)。`v3→v4 ok=20 skipped=1` の形。
pub fn reseed_summary_label(
    local_version: i64,
    bundle_version: i64,
    ok: u32,
    skipped: u32,
) -> String {
    format!("v{local_version}→v{bundle_version} ok={ok} skipped={skipped}")
}

/// `driving` の順序を保ったまま `other` にも含まれる要素だけ残す。
fn intersect_preserving_order(driving: &[String], other: &[String]) -> Vec<String> {
    let other: HashSet<&str> = other.iter().map(String::as_str).collect();
    driving
        .iter()
        .filter(|value| other.contains(value.as_str()))
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    // --- 起動時の同期モード判定 ---

    fn ios_state() -> SyncStartupState {
        SyncStartupState {
            has_pending_full_sync: false,
            local_data_empty: false,
            last_full_sync_epoch: Some(1_000_000.0),
            last_sync_epoch: Some(1_000_500.0),
            now_epoch: 1_001_000.0,
            full_sync_interval_seconds: Some(DEFAULT_FULL_SYNC_INTERVAL_SECONDS),
        }
    }

    #[test]
    fn startup_uses_incremental_when_full_sync_is_fresh() {
        let plan = startup_plan(&ios_state());
        assert_eq!(plan.mode, SyncMode::Incremental);
        assert_eq!(plan.modified_since_epoch, Some(1_000_500.0));
        assert_eq!(plan.reason, SyncModeReason::Incremental);
        assert!(!plan.resuming_pending_full);
    }

    #[test]
    fn startup_resumes_pending_full_before_anything_else() {
        let state = SyncStartupState {
            has_pending_full_sync: true,
            ..ios_state()
        };
        let plan = startup_plan(&state);
        assert_eq!(plan.mode, SyncMode::Full);
        assert_eq!(plan.modified_since_epoch, None);
        assert_eq!(plan.reason, SyncModeReason::PendingFullResume);
        assert!(plan.resuming_pending_full);
    }

    #[test]
    fn startup_falls_back_to_full_when_no_full_sync_record() {
        let state = SyncStartupState {
            last_full_sync_epoch: None,
            ..ios_state()
        };
        assert_eq!(
            startup_plan(&state).reason,
            SyncModeReason::NoFullSyncRecord
        );
    }

    #[test]
    fn startup_full_sync_staleness_uses_strict_greater_than() {
        // ちょうど 24 時間 = まだ stale ではない (iOS の `> 24*3600` と同じ)。
        let exact = SyncStartupState {
            last_full_sync_epoch: Some(0.0),
            now_epoch: DEFAULT_FULL_SYNC_INTERVAL_SECONDS,
            ..ios_state()
        };
        assert_eq!(startup_plan(&exact).mode, SyncMode::Incremental);

        let over = SyncStartupState {
            now_epoch: DEFAULT_FULL_SYNC_INTERVAL_SECONDS + 0.001,
            ..exact
        };
        assert_eq!(startup_plan(&over).reason, SyncModeReason::FullSyncStale);
    }

    #[test]
    fn startup_without_last_sync_falls_back_to_full() {
        // iOS: lastSyncDate() が nil → performSync(modifiedSince: nil) = フル。
        let state = SyncStartupState {
            last_sync_epoch: None,
            ..ios_state()
        };
        let plan = startup_plan(&state);
        assert_eq!(plan.mode, SyncMode::Full);
        assert_eq!(plan.modified_since_epoch, None);
        assert_eq!(plan.reason, SyncModeReason::MissingLastSync);
    }

    #[test]
    fn startup_android_never_forces_full_by_time() {
        // Android は定期フル再取得を持たない (interval=None)。last_full が無くても差分。
        let state = SyncStartupState {
            has_pending_full_sync: false,
            local_data_empty: false,
            last_full_sync_epoch: None,
            last_sync_epoch: Some(500.0),
            now_epoch: 999_999_999.0,
            full_sync_interval_seconds: None,
        };
        let plan = startup_plan(&state);
        assert_eq!(plan.mode, SyncMode::Incremental);
        assert_eq!(plan.modified_since_epoch, Some(500.0));
    }

    #[test]
    fn startup_android_empty_db_ignores_stored_last_sync() {
        // fallbackToDestructiveMigration で DB が消えても prefs の lastSync は残る。
        // これを無視しないと差分同期になって空のままになる。
        let state = SyncStartupState {
            has_pending_full_sync: false,
            local_data_empty: true,
            last_full_sync_epoch: None,
            last_sync_epoch: Some(500.0),
            now_epoch: 1_000.0,
            full_sync_interval_seconds: None,
        };
        let plan = startup_plan(&state);
        assert_eq!(plan.mode, SyncMode::Full);
        assert_eq!(plan.modified_since_epoch, None);
        assert_eq!(plan.reason, SyncModeReason::LocalDataEmpty);
    }

    #[test]
    fn startup_full_mode_always_means_no_since() {
        // mode == Full ⟺ modified_since_epoch == None を全分岐で固定する。
        for state in [
            SyncStartupState {
                has_pending_full_sync: true,
                ..ios_state()
            },
            SyncStartupState {
                local_data_empty: true,
                ..ios_state()
            },
            SyncStartupState {
                last_full_sync_epoch: None,
                ..ios_state()
            },
            SyncStartupState {
                now_epoch: 9_999_999.0,
                ..ios_state()
            },
            SyncStartupState {
                last_sync_epoch: None,
                ..ios_state()
            },
            ios_state(),
        ] {
            let plan = startup_plan(&state);
            assert_eq!(
                plan.mode == SyncMode::Full,
                plan.modified_since_epoch.is_none(),
                "{plan:?}"
            );
        }
    }

    // --- 取り込み順序 ---

    #[test]
    fn all_steps_keeps_parents_before_children() {
        let steps = all_steps();
        assert_eq!(steps.len(), 17);
        let index = |record_type: &str| {
            steps
                .iter()
                .position(|s| s.record_type == record_type)
                .unwrap()
        };
        assert!(index("Brand") < index("Idol"));
        assert!(index("Idol") < index("IdolBrand"));
        assert!(index("Brand") < index("IdolBrand"));
        assert!(index("Venue") < index("Show"));
        assert!(index("VenueName") < index("Show"));
        assert!(index("VenueHall") < index("Show"));
        assert!(index("ImasUnit") < index("UnitMember"));
        assert!(index("Song") < index("SongArtist"));
        assert!(index("Show") < index("ShowCast"));
        assert!(index("Show") < index("SetlistItem"));
        assert!(index("Song") < index("SetlistItem"));
        assert!(index("SetlistItem") < index("SetlistPerformer"));
        assert!(index("Song") < index("SongCall"));
        assert!(index("Song") < index("SongVideo"));
        assert_eq!(steps[0].display_name, "ブランド");
    }

    #[test]
    fn steps_for_empty_returns_everything() {
        assert_eq!(steps_for(&[]), all_steps());
    }

    #[test]
    fn steps_for_android_drops_venue_tables_and_keeps_order() {
        let android = strings(&[
            // Android 側の宣言順 (venue 系なし)。渡す順は無視され FK 順に並ぶ。
            "SongVideo",
            "Brand",
            "Idol",
            "Event",
            "ImasUnit",
            "IdolBrand",
            "Show",
            "Song",
            "UnitMember",
            "SongArtist",
            "ShowCast",
            "SetlistItem",
            "SetlistPerformer",
            "SongCall",
        ]);
        let steps: Vec<String> = steps_for(&android)
            .into_iter()
            .map(|s| s.record_type)
            .collect();
        assert_eq!(
            steps,
            strings(&[
                "Brand",
                "Idol",
                "Event",
                "ImasUnit",
                "IdolBrand",
                "Show",
                "Song",
                "UnitMember",
                "SongArtist",
                "ShowCast",
                "SetlistItem",
                "SetlistPerformer",
                "SongCall",
                "SongVideo",
            ])
        );
    }

    #[test]
    fn steps_for_ignores_unknown_record_types() {
        assert_eq!(steps_for(&strings(&["CastMember", "IdolCast"])), Vec::new());
    }

    // --- 実行の起点 ---

    #[test]
    fn run_start_new_full_persists_pending_state() {
        let plan = run_start_plan(true, 1_700.0, None, &strings(&["Brand"]));
        assert_eq!(plan.effective_start_epoch, 1_700.0);
        assert!(plan.done_steps.is_empty()); // 保留が無ければ永続化された done は読まない
        assert!(plan.should_persist_pending_full_start);
        assert!(!plan.resumed);
    }

    #[test]
    fn run_start_resumed_full_keeps_original_start() {
        let plan = run_start_plan(true, 1_700.0, Some(1_200.0), &strings(&["Brand", "Idol"]));
        assert_eq!(plan.effective_start_epoch, 1_200.0);
        assert_eq!(plan.done_steps, strings(&["Brand", "Idol"]));
        assert!(!plan.should_persist_pending_full_start);
        assert!(plan.resumed);
    }

    #[test]
    fn run_start_incremental_ignores_pending_full_state() {
        let plan = run_start_plan(false, 1_700.0, Some(1_200.0), &strings(&["Brand"]));
        assert_eq!(plan.effective_start_epoch, 1_700.0);
        assert!(plan.done_steps.is_empty());
        assert!(!plan.should_persist_pending_full_start);
        assert!(!plan.resumed);
    }

    // --- ステップの起点 ---

    #[test]
    fn step_start_full_from_epoch_allows_orphan_cleanup() {
        let plan = step_start_plan("Song", true, &[], None, None);
        assert!(!plan.skip);
        assert_eq!(plan.start_epoch, 0.0);
        assert!(plan.started_from_epoch);
    }

    #[test]
    fn step_start_checkpoint_blocks_orphan_cleanup() {
        // 途中再開は「見た ID」が不完全なので孤児掃除してはいけない。
        let plan = step_start_plan("Song", true, &[], Some(900.0), None);
        assert_eq!(plan.start_epoch, 900.0);
        assert!(!plan.started_from_epoch);
    }

    #[test]
    fn step_start_incremental_never_allows_orphan_cleanup() {
        let plan = step_start_plan("Song", false, &[], None, Some(500.0));
        assert_eq!(plan.start_epoch, 500.0);
        assert!(!plan.started_from_epoch);
    }

    #[test]
    fn step_start_checkpoint_wins_over_modified_since() {
        let plan = step_start_plan("Song", false, &[], Some(900.0), Some(500.0));
        assert_eq!(plan.start_epoch, 900.0);
    }

    #[test]
    fn step_start_skips_only_done_steps_of_a_full_run() {
        let done = strings(&["Brand", "Idol"]);
        assert!(step_start_plan("Idol", true, &done, None, None).skip);
        assert!(!step_start_plan("Song", true, &done, None, None).skip);
        // 差分同期では done を無視する (フル再開の概念が無い)。
        assert!(!step_start_plan("Idol", false, &done, None, Some(1.0)).skip);
    }

    // --- チャンクループ ---

    #[test]
    fn chunk_cursor_wins_over_restart() {
        // 同一 modifiedAt がチャンク超のとき、カーソルを捨てて張り直すと先頭を取り直して
        // 新規ゼロで打ち切られ、残りが永久に落ちる。カーソルが最優先。
        assert_eq!(
            next_chunk_action(true, 0, Some(1_000.0)),
            SyncChunkAction::ContinueCursor
        );
        assert_eq!(
            next_chunk_action(true, 5, None),
            SyncChunkAction::ContinueCursor
        );
    }

    #[test]
    fn chunk_finishes_when_nothing_fetched() {
        assert_eq!(next_chunk_action(false, 0, None), SyncChunkAction::Finish);
        assert_eq!(next_chunk_action(false, 9, None), SyncChunkAction::Finish);
    }

    #[test]
    fn chunk_finishes_when_restart_added_nothing() {
        assert_eq!(
            next_chunk_action(false, 0, Some(1_000.0)),
            SyncChunkAction::Finish
        );
    }

    #[test]
    fn chunk_restarts_one_millisecond_before_the_boundary() {
        assert_eq!(
            next_chunk_action(false, 3, Some(1_000.0)),
            SyncChunkAction::RestartFrom {
                start_epoch: 1_000.0 - 0.001
            }
        );
        assert_eq!(BOUNDARY_REWIND_SECONDS, 0.001);
    }

    // --- チャンクループ: 呼び出し側の契約 (Android の入力) ---

    /// CloudKit スタブ。`modifiedAt > start` を昇順で返し、`cap` 件で打ち切る。
    /// `cap = usize::MAX` が「continuationMarker を使い切って全件返した」状態。
    fn stub_query(records: &[(&str, f64)], start: f64, cap: usize) -> Vec<(String, f64)> {
        let mut page: Vec<(String, f64)> = records
            .iter()
            .filter(|(_, at)| *at > start)
            .map(|(name, at)| ((*name).to_string(), *at))
            .collect();
        page.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
        page.truncate(cap);
        page
    }

    /// Android の 1 ステップ分のループ。`CloudKitClient.query()` が continuationMarker を
    /// 内部で回し切るので `has_next_cursor` は常に false。
    ///
    /// `dedup = false` は「`records.size` をそのまま `added_since_restart` に渡す」誤用。
    /// 戻り値は (クエリ回数, 打ち切らずに Finish したか, 取り込んだ recordName)。
    fn run_android_step(
        records: &[(&str, f64)],
        cap: usize,
        dedup: bool,
        max_queries: u32,
    ) -> (u32, bool, Vec<String>) {
        let mut seen: HashSet<String> = HashSet::new();
        let mut imported: Vec<String> = Vec::new();
        let mut start = 0.0_f64;
        let mut queries = 0_u32;
        while queries < max_queries {
            queries += 1;
            let page = stub_query(records, start, cap);
            let mut added = 0_u32;
            let mut max_epoch: Option<f64> = None;
            for (name, at) in &page {
                if seen.insert(name.clone()) {
                    added += 1;
                    imported.push(name.clone());
                }
                max_epoch = Some(max_epoch.map_or(*at, |m: f64| m.max(*at)));
            }
            if !dedup {
                added = page.len() as u32;
            }
            match next_chunk_action(false, added, max_epoch) {
                SyncChunkAction::Finish => return (queries, true, imported),
                SyncChunkAction::RestartFrom { start_epoch } => start = start_epoch,
                SyncChunkAction::ContinueCursor => {
                    panic!("has_next_cursor=false なのに cursor 継続が返った")
                }
            }
        }
        (queries, false, imported)
    }

    #[test]
    fn android_chunk_loop_costs_exactly_one_extra_boundary_query() {
        // has_next_cursor=false を渡すだけでは「1 ステップ 1 クエリ」にはならない。
        // 1 回目で全件 → 境界 1ms 戻しで 2 回目 (境界の数件だけ) → 新規ゼロで Finish。
        let records = [("a", 100.0), ("b", 100.0), ("c", 200.0)];
        let (queries, finished, imported) = run_android_step(&records, usize::MAX, true, 8);
        assert!(finished);
        assert_eq!(queries, 2);
        assert_eq!(imported, strings(&["a", "b", "c"]));
    }

    #[test]
    fn chunk_loop_without_dedup_never_terminates() {
        // added_since_restart に取得件数をそのまま渡すと、巻き戻しで取り直した境界レコードが
        // 毎回「新規」になり、同じ start_epoch の RestartFrom が返り続ける。
        let records = [("a", 100.0), ("b", 100.0), ("c", 200.0)];
        let (queries, finished, _) = run_android_step(&records, usize::MAX, false, 8);
        assert!(!finished, "dedup 無しでも止まってしまった (契約が緩んだ)");
        assert_eq!(queries, 8); // 打ち切り上限まで回り切る = 無限ループ

        // 進まないことの直接の証拠: 同じ入力に対して常に同じ start が返る。
        let stuck = next_chunk_action(false, 1, Some(200.0));
        assert_eq!(
            stuck,
            SyncChunkAction::RestartFrom {
                start_epoch: 200.0 - BOUNDARY_REWIND_SECONDS
            }
        );
        assert_eq!(next_chunk_action(false, 1, Some(200.0)), stuck);
    }

    #[test]
    fn chunk_loop_false_cursor_is_only_sound_when_the_fetch_drained_the_query() {
        // Android が has_next_cursor=false を渡してよいのは query() が continuationMarker を
        // 使い切るから。取得側が途中で打ち切る (cap) のに false を渡すと、巻き戻しても同じ
        // 先頭ページを取り直して新規ゼロ → 残りが永久に落ちる。
        let records = [("a", 100.0), ("b", 100.0), ("c", 200.0), ("d", 300.0)];
        let (queries, finished, imported) = run_android_step(&records, 2, true, 8);
        assert!(finished);
        assert_eq!(queries, 2);
        assert_eq!(imported, strings(&["a", "b"])); // c / d が欠ける
    }

    // --- 仕分け ---

    #[test]
    fn partition_keeps_input_order_on_both_sides() {
        let partition = partition_by_deleted(&[false, true, false, true, true]);
        assert_eq!(partition.alive_indexes, vec![0, 2]);
        assert_eq!(partition.deleted_indexes, vec![1, 3, 4]);
    }

    #[test]
    fn partition_of_empty_input_is_empty() {
        let partition = partition_by_deleted(&[]);
        assert!(partition.alive_indexes.is_empty());
        assert!(partition.deleted_indexes.is_empty());
    }

    // --- テーブル対応と recordName 分解 ---

    #[test]
    fn table_info_maps_known_record_types() {
        assert_eq!(
            table_info("Brand"),
            Some(SyncTableInfo {
                table: "brands".into(),
                pk_columns: strings(&["id"]),
            })
        );
        assert_eq!(
            table_info("SongArtist"),
            Some(SyncTableInfo {
                table: "song_artists".into(),
                pk_columns: strings(&["song_id", "idol_id", "role"]),
            })
        );
        // show_cast だけ単数形テーブル名。
        assert_eq!(table_info("ShowCast").unwrap().table, "show_cast");
        assert_eq!(table_info("ImasUnit").unwrap().table, "units");
    }

    #[test]
    fn table_info_rejects_retired_record_types() {
        // CastMember / IdolCast は廃止 (idol.voiceActors に統合)。届いても捨てる。
        assert_eq!(table_info("CastMember"), None);
        assert_eq!(table_info("IdolCast"), None);
        assert_eq!(table_info(""), None);
        assert_eq!(table_info("brands"), None); // テーブル名では引けない
    }

    #[test]
    fn every_step_has_a_table_mapping() {
        for step in all_steps() {
            assert!(
                table_info(&step.record_type).is_some(),
                "{} に対応表が無い",
                step.record_type
            );
        }
    }

    #[test]
    fn parse_composite_record_name_splits_from_the_front() {
        assert_eq!(
            parse_composite_record_name("song_artists-s1-i1-original", "song_artists", 3),
            Some(strings(&["s1", "i1", "original"]))
        );
        // 最後の値だけ "-" を含んでよい (前から最大 n 個に割るため)。
        assert_eq!(
            parse_composite_record_name("idol_brands-a-b-c", "idol_brands", 2),
            Some(strings(&["a", "b-c"]))
        );
    }

    #[test]
    fn parse_composite_record_name_keeps_empty_values() {
        assert_eq!(
            parse_composite_record_name("idol_brands--b", "idol_brands", 2),
            Some(strings(&["", "b"]))
        );
    }

    #[test]
    fn parse_composite_record_name_rejects_mismatches() {
        // prefix 違い
        assert_eq!(
            parse_composite_record_name("unit_members-a-b", "idol_brands", 2),
            None
        );
        // 値が足りない
        assert_eq!(
            parse_composite_record_name("idol_brands-a", "idol_brands", 2),
            None
        );
        // 本体が空
        assert_eq!(
            parse_composite_record_name("idol_brands-", "idol_brands", 2),
            None
        );
        // ハイフンだけの prefix ("idol_brands" 単体は prefix を満たさない)
        assert_eq!(
            parse_composite_record_name("idol_brands", "idol_brands", 2),
            None
        );
        assert_eq!(
            parse_composite_record_name("idol_brands-a-b", "idol_brands", 0),
            None
        );
    }

    #[test]
    fn parse_composite_record_name_handles_hyphenated_table_name() {
        assert_eq!(
            parse_composite_record_name("a-b-x-y", "a-b", 2),
            Some(strings(&["x", "y"]))
        );
    }

    // --- 孤児掃除 ---

    #[test]
    fn orphan_cleanup_only_for_single_id_pk_tables() {
        assert!(supports_orphan_cleanup("Brand"));
        assert!(supports_orphan_cleanup("SetlistItem"));
        // 複合 PK には単一 "id" 列が無く SELECT id が落ちる。
        assert!(!supports_orphan_cleanup("SongArtist"));
        assert!(!supports_orphan_cleanup("SetlistPerformer"));
        assert!(!supports_orphan_cleanup("IdolBrand"));
        assert!(!supports_orphan_cleanup("UnitMember"));
        assert!(!supports_orphan_cleanup("ShowCast"));
        assert!(!supports_orphan_cleanup("CastMember"));
    }

    #[test]
    fn orphan_ids_returns_local_only_ids_in_local_order() {
        let local = strings(&["c", "a", "b"]);
        let valid = strings(&["b"]);
        assert_eq!(orphan_ids(&local, &valid), strings(&["c", "a"]));
    }

    #[test]
    fn orphan_ids_is_noop_when_server_returned_nothing() {
        // 取得 0 件は通信異常でも起きる。ローカル全消しは絶対に避ける。
        let local = strings(&["a", "b"]);
        assert_eq!(orphan_ids(&local, &[]), Vec::<String>::new());
    }

    #[test]
    fn orphan_ids_is_empty_when_everything_is_valid() {
        let local = strings(&["a", "b"]);
        let valid = strings(&["b", "a", "c"]);
        assert_eq!(orphan_ids(&local, &valid), Vec::<String>::new());
    }

    // --- 完了時の後始末 ---

    /// 起動フル同期を完走したときの状態。
    fn startup_full_completion() -> SyncCompletionState {
        SyncCompletionState {
            is_full_sync: true,
            is_startup_run: true,
            effective_start_epoch: 1_200.0,
            sync_start_epoch: 1_700.0,
            completion_epoch: 3_000.0,
            total_fetched: 42,
            all_steps_completed: true,
        }
    }

    #[test]
    fn completion_of_full_sync_saves_its_own_start_time() {
        // 同期中に変わったレコードを次回差分で拾えるよう、完了時刻ではなく開始時刻を保存する。
        let plan = completion_plan(&startup_full_completion());
        assert!(plan.should_save_last_sync);
        assert_eq!(plan.last_sync_epoch_to_save, 1_200.0);
        assert!(plan.should_clear_pending_full);
        assert!(plan.should_notify_master_changed);
    }

    #[test]
    fn completion_of_incremental_saves_this_run_start_time() {
        let plan = completion_plan(&SyncCompletionState {
            is_full_sync: false,
            total_fetched: 1,
            ..startup_full_completion()
        });
        assert_eq!(plan.last_sync_epoch_to_save, 1_700.0);
        assert!(!plan.should_clear_pending_full);
    }

    #[test]
    fn completion_without_fetched_records_does_not_notify() {
        let base = SyncCompletionState {
            is_full_sync: false,
            total_fetched: 0,
            ..startup_full_completion()
        };
        assert!(!completion_plan(&base).should_notify_master_changed);
        assert!(
            completion_plan(&SyncCompletionState {
                total_fetched: 1,
                ..base
            })
            .should_notify_master_changed
        );
    }

    #[test]
    fn completion_of_startup_full_writes_back_last_full_sync_at() {
        // これが startup_plan の 24h 判定を進める唯一の書き込み。落とすと 24 時間後から
        // 毎起動フルになる (Android は interval=None なので露見しない)。
        let plan = completion_plan(&startup_full_completion());
        assert!(plan.should_update_last_full_sync);
        // 開始時刻ではなく完了時刻。
        assert_eq!(plan.last_full_sync_epoch_to_save, Some(3_000.0));
    }

    #[test]
    fn completion_write_back_actually_stops_the_stale_full_sync_loop() {
        // 書き戻した値を startup_plan に食わせて、次回起動が差分に戻ることまで固定する。
        let completion = completion_plan(&startup_full_completion());
        let saved = completion.last_full_sync_epoch_to_save.unwrap();
        let next_launch = SyncStartupState {
            has_pending_full_sync: false,
            local_data_empty: false,
            last_full_sync_epoch: Some(saved),
            last_sync_epoch: Some(completion.last_sync_epoch_to_save),
            now_epoch: saved + 60.0,
            full_sync_interval_seconds: Some(DEFAULT_FULL_SYNC_INTERVAL_SECONDS),
        };
        assert_eq!(startup_plan(&next_launch).mode, SyncMode::Incremental);

        // 書き戻しを落とした世界 (last_full_sync_epoch が固定) では 24h 後から毎回フル。
        let never_written = SyncStartupState {
            last_full_sync_epoch: Some(0.0),
            now_epoch: DEFAULT_FULL_SYNC_INTERVAL_SECONDS + 1.0,
            ..next_launch
        };
        assert_eq!(
            startup_plan(&never_written).reason,
            SyncModeReason::FullSyncStale
        );
    }

    #[test]
    fn completion_does_not_touch_last_full_sync_outside_startup_full() {
        // 差分同期は 24h タイマーに触らない。
        let incremental = completion_plan(&SyncCompletionState {
            is_full_sync: false,
            ..startup_full_completion()
        });
        assert!(!incremental.should_update_last_full_sync);
        assert_eq!(incremental.last_full_sync_epoch_to_save, None);

        // 手動フル再取得 (performFullSync) も書かない。書くと強制リフレッシュのたびに
        // 定期フルの期限が先送りされ、一次実装と挙動が変わる。
        let manual_full = completion_plan(&SyncCompletionState {
            is_startup_run: false,
            ..startup_full_completion()
        });
        assert!(!manual_full.should_update_last_full_sync);
        assert_eq!(manual_full.last_full_sync_epoch_to_save, None);
    }

    #[test]
    fn completion_of_aborted_run_updates_only_last_full_sync() {
        // 一次実装は performSync がエラーで抜けても updateLastFullSyncDate を撃つ (try?)。
        // 逆に last_sync 保存・保留破棄・変更通知は成功時のみ。
        let plan = completion_plan(&SyncCompletionState {
            all_steps_completed: false,
            ..startup_full_completion()
        });
        assert!(plan.should_update_last_full_sync);
        assert_eq!(plan.last_full_sync_epoch_to_save, Some(3_000.0));
        assert!(!plan.should_save_last_sync);
        assert!(!plan.should_clear_pending_full);
        assert!(!plan.should_notify_master_changed);
    }

    // --- seed 取り込み ---

    #[test]
    fn seed_common_tables_keeps_main_order_and_drops_internal_tables() {
        let main = strings(&[
            "room_master_table",
            "brands",
            "user_marks",
            "songs",
            "android_metadata",
            "sqlite_sequence",
        ]);
        let seed = strings(&[
            "songs",
            "brands",
            "song_units",
            "room_master_table",
            "android_metadata",
            "sqlite_sequence",
        ]);
        assert_eq!(
            seed_common_tables(&main, &seed),
            strings(&["brands", "songs"])
        );
    }

    #[test]
    fn seed_common_tables_drops_one_sided_tables() {
        // seed のみ (song_units) / main のみ (user_marks) はどちらも対象外。
        let main = strings(&["user_marks", "brands"]);
        let seed = strings(&["song_units", "brands"]);
        assert_eq!(seed_common_tables(&main, &seed), strings(&["brands"]));
    }

    #[test]
    fn seed_common_columns_keeps_main_column_order() {
        let main = strings(&["id", "title", "artwork_url", "lyrics_status"]);
        let seed = strings(&["artwork_url", "title", "id", "legacy_flag"]);
        assert_eq!(
            seed_common_columns(&main, &seed),
            strings(&["id", "title", "artwork_url"])
        );
    }

    #[test]
    fn seed_common_columns_can_be_empty() {
        assert_eq!(
            seed_common_columns(&strings(&["a"]), &strings(&["b"])),
            Vec::<String>::new()
        );
    }

    // --- reseed ---

    #[test]
    fn data_version_missing_or_broken_reads_as_zero() {
        assert_eq!(parse_data_version(None), 0);
        assert_eq!(parse_data_version(Some("")), 0);
        assert_eq!(parse_data_version(Some("v4")), 0);
        assert_eq!(parse_data_version(Some("4.0")), 0);
        assert_eq!(parse_data_version(Some(" 4")), 0);
        assert_eq!(parse_data_version(Some("4")), 4);
        assert_eq!(parse_data_version(Some("-1")), -1);
    }

    #[test]
    fn reseed_runs_only_when_bundle_is_newer() {
        assert!(reseed_needed(5, 4, None, None));
        assert!(!reseed_needed(4, 4, None, None));
        assert!(!reseed_needed(3, 4, None, None));
        // 壊れた local (=0) は必ず reseed 側に倒れる。
        assert!(reseed_needed(1, parse_data_version(Some("broken")), None, None));
    }

    /// 回帰 (2026-08-27 読み仮名が届かない): 版番号は内容とズレる。
    ///
    /// 読み仮名を入れる前のビルドが 70 を積んで出てしまい、端末が 70 を記録した。
    /// 以後 70 のまま読み仮名入りを配っても `70 > 70` が偽で、永久に届かなかった。
    #[test]
    fn same_version_with_different_content_still_reseeds() {
        assert!(
            reseed_needed(70, 70, Some("読み仮名あり"), Some("読み仮名なし")),
            "版番号が同じでも内容が違えば入れ直す"
        );
    }

    /// 指紋を持たない端末は、一度だけ入れ直して指紋を持つ状態にする。
    ///
    /// これが上のズレを自動で直す経路でもある (端末は版番号しか持っていない)。
    #[test]
    fn a_device_without_a_fingerprint_is_reseeded_once() {
        assert!(reseed_needed(70, 70, Some("指紋"), None));
        // 取り込んだ後は動かない。起動のたびに入れ直したりはしない。
        assert!(!reseed_needed(70, 70, Some("指紋"), Some("指紋")));
    }

    /// 取り込んだ後に同期でマスタが増えても、入れ直しは起きない。
    ///
    /// 端末が持つのは「最後に取り込んだ同梱データの指紋」であって、
    /// 端末の現在の内容の指紋ではない。混同すると同期のたびに巻き戻る。
    #[test]
    fn syncing_new_master_data_does_not_trigger_a_reseed() {
        let bundled = Some("同梱データの指紋");
        assert!(!reseed_needed(70, 70, bundled, bundled));
    }

    /// 同梱側に指紋が無い古いビルドでは、従来どおり版番号で判断する。
    #[test]
    fn without_a_bundled_fingerprint_it_falls_back_to_the_version() {
        assert!(reseed_needed(71, 70, None, Some("端末の指紋")));
        assert!(!reseed_needed(70, 70, None, Some("端末の指紋")));
    }

    #[test]
    fn reseed_targets_keep_bundle_order_and_skip_preserved() {
        let bundle = strings(&[
            "sqlite_stat1",
            "songs",
            "user_marks",
            "brands",
            "song_units",
        ]);
        let local = strings(&["brands", "songs", "user_marks", "meta"]);
        assert_eq!(
            reseed_target_tables(&bundle, &local, &default_preserved_tables()),
            strings(&["songs", "brands"])
        );
    }

    #[test]
    fn reseed_preserves_user_and_community_tables() {
        let preserved = default_preserved_tables();
        for table in [
            "user_marks",
            "custom_image_paths",
            "grdb_migrations",
            "meta",
            "song_calls",
            "song_videos",
            "song_tags",
            "device_song_tag",
            "device_song_penlight",
        ] {
            assert!(
                preserved.iter().any(|t| t == table),
                "{table} が保護対象にない"
            );
            let tables = strings(&[table]);
            assert_eq!(
                reseed_target_tables(&tables, &tables, &preserved),
                Vec::<String>::new()
            );
        }
        assert_eq!(preserved.len(), 9);
    }

    #[test]
    fn reseed_common_columns_keep_bundle_order() {
        let bundle = strings(&["artwork_url", "id", "title", "legacy_flag"]);
        let main = strings(&["id", "title", "artwork_url", "lyrics_status"]);
        assert_eq!(
            reseed_common_columns(&bundle, &main),
            strings(&["artwork_url", "id", "title"])
        );
    }

    #[test]
    fn reseed_summary_label_is_stable() {
        assert_eq!(reseed_summary_label(3, 4, 20, 1), "v3→v4 ok=20 skipped=1");
    }
}
