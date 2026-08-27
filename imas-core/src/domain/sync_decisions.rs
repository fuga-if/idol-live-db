//! 同期エンジンに残っていた判断 — 「失敗をどう扱うか」「どこまで進んだと記録するか」。
//!
//! 一次実装は iOS `Services/CloudKitSyncEngine.swift` と Android
//! `data/sync/CloudKitSyncEngine.kt` / `CloudKitClient.kt`。
//! [`crate::domain::sync_planning`] が「どこから何を取るか」を決めるのに対し、こちらは
//! **取りに行った結果をどう解釈するか** を決める:
//!
//! - 返ってきたエラーは再試行してよいのか、このステップだけ飛ばすのか、実行ごと止めるのか
//! - 何秒待ってから再試行するのか
//! - チャンクを 1 つ取り込んだ後、チェックポイントに何を書くのか
//! - ステップを終えたとき、チェックポイントを消してよいのか / 完了ステップに加えてよいのか
//! - そのステップで孤児掃除を撃ってよいのか
//! - そもそも同期を開始してよいのか
//!
//! 通信そのもの (CKQueryOperation / HTTP)、`Task.sleep`、DB への実書き込み、
//! UserDefaults / SharedPreferences への実保存は各 OS に残る。ここにあるのは全部
//! 「状態を引数で受け、やるべきことを返す」純粋関数。
//!
//! ## エラーを共有するための形
//!
//! CloudKit へのアクセス手段が OS で非対称なので (iOS = CloudKit.framework の `CKError`、
//! Android = CloudKit Web Services の HTTP + `serverErrorCode`)、エラー**そのもの**は
//! 共有できない。共有するのは [`SyncErrorSignal`] という「判定に必要な事実だけを抜いた
//! 射影」で、各 OS が自分の例外からこれを組み立てて渡す。片方にしか無いフィールドは
//! `None` を渡す (`sync_planning` が `has_pending_full_sync = false` を渡すのと同じ流儀)。
//!
//! ## 時刻の単位
//!
//! [`crate::domain::sync_planning`] と同じく **秒 (f64)**。Android は
//! `System.currentTimeMillis()` を 1000 で割ってから渡すこと。

use crate::domain::sync_planning::{steps_for, supports_orphan_cleanup};

// ---------------------------------------------------------------------------
// 1. エラーの射影と分類
// ---------------------------------------------------------------------------

/// iOS `CKError.Code` の生値。
///
/// Swift の enum をそのまま FFI 型に写すと「iOS だけが知る 36 個の値」がコアの公開型に
/// 漏れるので、生値 (`ckError.code.rawValue`) で受けてここで名前を付ける。
/// **判定に使う値だけ**を置く (使わないコードを並べても増える一方で腐る)。
mod ck_error_code {
    pub const NETWORK_UNAVAILABLE: i32 = 3;
    pub const NETWORK_FAILURE: i32 = 4;
    pub const SERVICE_UNAVAILABLE: i32 = 6;
    pub const REQUEST_RATE_LIMITED: i32 = 7;
    /// レコードタイプ / レコードがコンテナに無い。
    pub const UNKNOWN_ITEM: i32 = 11;
    /// クエリの引数が不正。`modifiedAt` の QUERYABLE/SORTABLE 未設定もここに来る。
    pub const INVALID_ARGUMENTS: i32 = 12;
    pub const ZONE_BUSY: i32 = 23;
}

/// 一時的な失敗として再試行してよい `CKError.Code`。
///
/// 一次実装 `fetchChunkWithRetry` の `case .networkUnavailable, .networkFailure,
/// .serviceUnavailable, .zoneBusy, .requestRateLimited:` をそのまま写したもの。
/// **広げないこと**: ここに入れたコードは 3 回まで黙って再試行されるので、恒久的な失敗
/// (権限・スキーマ・課金) を入れると 14 秒待たされた末に同じエラーで落ちるだけになる。
const RETRYABLE_CK_ERROR_CODES: &[i32] = &[
    ck_error_code::NETWORK_UNAVAILABLE,
    ck_error_code::NETWORK_FAILURE,
    ck_error_code::SERVICE_UNAVAILABLE,
    ck_error_code::REQUEST_RATE_LIMITED,
    ck_error_code::ZONE_BUSY,
];

/// CKWS の `reason` が「そのレコードタイプは無い」と言っているときの言い回し。
///
/// Android `CloudKitQueryException.MISSING_WORDS` と同一。
const MISSING_WORDS: &[&str] = &[
    "unknown",
    "not found",
    "does not exist",
    "not defined",
    "no such",
];

/// `modifiedAt` にインデックスが張られていないことを示す文面。
///
/// 一次実装 `msg.contains("not queryable") || msg.contains("not sortable")` の
/// **リテラルそのまま**。CloudKit の実際の文面は "Field 'modifiedAt' is not marked
/// queryable" で、この部分文字列とは一致しない可能性が高い。それでも広げないのは、
/// 広げた瞬間に「今まで一般エラーとして中断していたものが専用メッセージに変わる」という
/// 挙動変更になるから。文面判定を直すなら移送とは別の判断として行う。
const SCHEMA_INDEX_MARKERS: &[&str] = &["not queryable", "not sortable"];

/// エラーから「判定に必要な事実」だけを抜いた射影。各 OS が自分の例外から組み立てる。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncErrorSignal {
    /// CloudKit 自身が返したエラーか。
    ///
    /// iOS は `error is CKError`、Android は `CloudKitQueryException` かどうか。
    /// false = 通信断・JSON パース失敗・ローカル DB 書き込み失敗など、CloudKit の外で
    /// 起きた失敗。一次実装が分析イベント `sync_error` を撃つのはこちらだけ。
    pub is_cloudkit_error: bool,
    /// iOS `CKError.Code` の生値 (`ckError.code.rawValue`)。Android は None。
    pub ck_error_code: Option<i32>,
    /// Android `records/query` の HTTP ステータス。iOS は None。
    pub http_status: Option<i32>,
    /// Android CKWS 応答本文の `serverErrorCode`。iOS は None。
    pub server_error_code: Option<String>,
    /// **判定に使う**本文。iOS は `localizedDescription`、Android は CKWS の `reason`。
    pub reason: Option<String>,
    /// **表示に使う**本文。iOS は `localizedDescription`、Android は例外の `message`。
    ///
    /// iOS では `reason` と同じ文字列になる。Android は分けている: `reason` は
    /// サーバの言い分そのもので、`message` は HTTP ステータスを含む診断用の文。
    pub message: String,
    /// サーバが指定した再試行間隔 (iOS `CKError.retryAfterSeconds`)。
    /// 指定があれば指数バックオフより優先する。
    pub retry_after_seconds: Option<f64>,
}

/// エラーの正体。取得層 (再試行) とステップ層 (飛ばす/止める) の両方がこれを見る。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SyncErrorKind {
    /// このコンテナ環境にまだそのレコードタイプが無い。
    ///
    /// 新しいレコードタイプは development へ import してから production へ deploy するので、
    /// その間 production だけが未作成になる。実行ごと止めると、FK 依存順で前の方にある
    /// レコードタイプ 1 つで後続すべてが取り込まれなくなるため、このステップだけ飛ばす。
    UnknownRecordType,
    /// `modifiedAt` が QUERYABLE / SORTABLE になっていない。
    /// 設定しない限り何度やっても同じなので、対処方法を出して止める。
    SchemaNotQueryable,
    /// ネットワーク断・レート制限など、待てば直りうる失敗。
    Retryable,
    /// それ以外。再試行しても飛ばしても直らないので実行ごと止める。
    Fatal,
}

/// エラーの正体を見分ける。
///
/// 判定順は「飛ばしてよいもの → 専用の対処があるもの → 待てば直るもの → それ以外」。
/// 先に [`SyncErrorKind::UnknownRecordType`] を見るのは、iOS の `CKError.unknownItem` も
/// Android の 404/NOT_FOUND も他の条件と競合しないため。
pub fn classify_error(signal: &SyncErrorSignal) -> SyncErrorKind {
    if is_unknown_record_type(signal) {
        return SyncErrorKind::UnknownRecordType;
    }
    if is_schema_not_queryable(signal) {
        return SyncErrorKind::SchemaNotQueryable;
    }
    if signal
        .ck_error_code
        .is_some_and(|code| RETRYABLE_CK_ERROR_CODES.contains(&code))
    {
        return SyncErrorKind::Retryable;
    }
    SyncErrorKind::Fatal
}

/// レコードタイプ未作成か。iOS は `CKError` のコード、Android は HTTP + 本文で見る。
///
/// Android 側の判定を**狭く**取るのは一次実装の意図どおり。取りこぼしても同期が止まるだけ
/// (= 従来どおり) だが、本物の失敗をこれと誤認すると last_sync だけ進み、そのレコード
/// タイプの変更が次のフル同期まで永久に落ちる。
fn is_unknown_record_type(signal: &SyncErrorSignal) -> bool {
    if signal.ck_error_code == Some(ck_error_code::UNKNOWN_ITEM) {
        return true;
    }
    // ここから先は Android (CKWS) の経路。CK コードを持つ iOS は上で決着済み。
    if !matches!(signal.http_status, Some(400) | Some(404)) {
        return false;
    }
    if signal.server_error_code.as_deref() == Some("NOT_FOUND") {
        return true;
    }
    let Some(reason) = signal.reason.as_deref() else {
        return false;
    };
    let text = reason.to_lowercase();
    // **レコードタイプ**を名指ししているものだけ。フィールド側のスキーマ不備
    // ("Field 'modifiedAt' is not marked queryable" 等) は本物の設定漏れで、
    // 飛ばすとそのテーブルが静かに欠落したまま気づけない。
    text.contains("unknown type")
        || (text.contains("record type") && MISSING_WORDS.iter().any(|w| text.contains(w)))
}

/// `modifiedAt` のインデックス未設定か。
///
/// 一次実装が `CKError.invalidArguments` に限って本文を見ているので、その条件ごと写す。
/// Android は `ck_error_code` を持たないため現状ここへは来ない (= 一般エラーとして中断)。
fn is_schema_not_queryable(signal: &SyncErrorSignal) -> bool {
    if signal.ck_error_code != Some(ck_error_code::INVALID_ARGUMENTS) {
        return false;
    }
    let Some(reason) = signal.reason.as_deref() else {
        return false;
    };
    // 一次実装は `localizedDescription` を大文字小文字そのままで `contains` している。
    // 正規化を足すと一致する範囲が広がってしまうので、あえて素の部分一致にする。
    SCHEMA_INDEX_MARKERS.iter().any(|m| reason.contains(m))
}

// ---------------------------------------------------------------------------
// 2. 取得の再試行
// ---------------------------------------------------------------------------

/// 1 チャンクの取得を試みる最大回数 (一次実装 `CloudKitSyncEngine.maxRetries`)。
pub const DEFAULT_MAX_FETCH_RETRIES: u32 = 3;

/// 取得が失敗したときの次の一手。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq)]
pub enum SyncRetryAction {
    /// 再試行しない。待たずにそのままエラーを上へ投げる。
    FailNow,
    /// `delay_seconds` 待ってから同じチャンクを取り直す。
    RetryAfter { delay_seconds: f64 },
    /// 再試行対象だが試行回数を使い切った。**待ってから**失敗する。
    ///
    /// 待つのは一次実装の `for attempt in 0..<maxRetries` が最終試行でも sleep してから
    /// ループを抜け `throw lastError!` するため。ここで待たない設計にすると最終失敗が
    /// 8 秒早まる = 挙動が変わる。
    FailAfterDelay { delay_seconds: f64 },
}

/// 取得失敗後に再試行するか、するなら何秒待つかを決める。
///
/// - `attempt`: 0 始まりの試行番号 (0 = 1 回目の失敗)。
/// - `max_retries`: 最大試行回数。[`DEFAULT_MAX_FETCH_RETRIES`] を渡す。
///
/// 待ち時間はサーバ指定 (`retry_after_seconds`) を最優先し、無ければ 2, 4, 8 秒の指数
/// バックオフ (一次実装の `Double(2 << attempt)`)。サーバ指定は値をそのまま使う
/// (0 や負でも一次実装は素通しなので、ここでも丸めない)。
pub fn retry_action(attempt: u32, max_retries: u32, signal: &SyncErrorSignal) -> SyncRetryAction {
    if classify_error(signal) != SyncErrorKind::Retryable {
        return SyncRetryAction::FailNow;
    }
    let delay_seconds = signal
        .retry_after_seconds
        .unwrap_or_else(|| exponential_backoff_seconds(attempt));
    // attempt は 0 始まりなので、attempt + 1 回試したことになる。
    if attempt + 1 < max_retries {
        SyncRetryAction::RetryAfter { delay_seconds }
    } else {
        SyncRetryAction::FailAfterDelay { delay_seconds }
    }
}

/// `2 << attempt` = 2^(attempt+1) 秒。attempt 0/1/2 → 2/4/8 秒。
///
/// シフト幅は 62 で頭打ちにする。一次実装の `Int` シフトは 64 回目でオーバーフロー
/// トラップになるが、コアを落とすより飽和させる方が安全 (max_retries が 3 である限り
/// どちらの経路にも入らない)。
fn exponential_backoff_seconds(attempt: u32) -> f64 {
    (1u64 << (attempt.min(62) + 1)) as f64
}

// ---------------------------------------------------------------------------
// 3. ステップが失敗したときの扱い
// ---------------------------------------------------------------------------

/// 失敗したステップをどうするか。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SyncStepFailureAction {
    /// このステップだけ飛ばして次のレコードタイプへ進む。
    SkipStep,
    /// 実行ごと中断する。
    Abort,
}

/// ステップ失敗時にやるべきこと。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncStepFailure {
    pub action: SyncStepFailureAction,
    /// ユーザーに出す文言。[`SyncStepFailureAction::SkipStep`] では None
    /// (一次実装はスキップを画面に出さない — 出すと deploy 待ちのレコードタイプが
    /// あるだけで毎回エラー表示になる)。
    pub message: Option<String>,
    /// CloudKit Dashboard 側の設定が要るか。true のときの `message` は操作手順で、
    /// 「通信に失敗した」系の再試行導線を出してはいけない。
    pub requires_schema_setup: bool,
    /// 分析イベント `sync_error` を撃つか。
    ///
    /// CloudKit が返したエラーでは撃たない。一次実装が撃つのは最後の `catch`
    /// (= CKError 以外) だけで、電波の悪い端末の CKError で埋め尽くされないようにしている。
    pub should_report_analytics: bool,
}

/// 失敗したステップを飛ばすか、実行ごと止めるかを決める。
///
/// `record_type` はスキーマ設定の案内文に、`display_name` は一般エラーの文言に使う
/// (一次実装がそう組み立てている: 案内文はダッシュボードで探す名前なので生の
/// レコードタイプ名、一般エラーは画面に出るので日本語ラベル)。
pub fn step_failure_plan(
    record_type: &str,
    display_name: &str,
    signal: &SyncErrorSignal,
) -> SyncStepFailure {
    match classify_error(signal) {
        SyncErrorKind::UnknownRecordType => SyncStepFailure {
            action: SyncStepFailureAction::SkipStep,
            message: None,
            requires_schema_setup: false,
            should_report_analytics: false,
        },
        SyncErrorKind::SchemaNotQueryable => SyncStepFailure {
            action: SyncStepFailureAction::Abort,
            message: Some(format!(
                "スキーマ設定が必要です: CloudKit Dashboard で {record_type} の modifiedAt を QUERYABLE + SORTABLE に設定してください"
            )),
            requires_schema_setup: true,
            should_report_analytics: false,
        },
        // Retryable がここへ来るのは再試行を使い切った後。もう一度待つ理由は無いので中断。
        SyncErrorKind::Retryable | SyncErrorKind::Fatal => SyncStepFailure {
            action: SyncStepFailureAction::Abort,
            message: Some(format!("{display_name}の同期に失敗: {}", signal.message)),
            requires_schema_setup: false,
            should_report_analytics: !signal.is_cloudkit_error,
        },
    }
}

// ---------------------------------------------------------------------------
// 4. チェックポイントの更新
// ---------------------------------------------------------------------------

/// チャンクを 1 つ取り込んだ後の進捗。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq)]
pub struct SyncChunkProgress {
    /// 巻き戻し区間で見た最大 modifiedAt。そのまま
    /// [`crate::domain::sync_planning::next_chunk_action`] の
    /// `max_epoch_since_restart` に渡す。
    pub max_epoch_since_restart: Option<f64>,
    /// チェックポイントとして保存すべき値。None = 更新しない。
    ///
    /// **区間の最大ではなくこのチャンクの最大**を書く (一次実装がそう)。チャンクは
    /// modifiedAt 昇順で返るので通常は同じ値になるが、境界巻き戻しの直後だけ区間最大の
    /// 方が大きくなりうる。小さい方を書くのは安全側 (次回そこから取り直す = 取りこぼさない)。
    pub checkpoint_epoch_to_save: Option<f64>,
}

/// チャンクを 1 つ取り込んだ後のチェックポイントと区間最大を計算する。
///
/// `chunk_modified_epochs` は **そのチャンクのレコードが持つ modifiedAt だけ** を並べたもの
/// (一次実装の `records.compactMap { $0["modifiedAt"] as? Date }`)。modifiedAt を持たない
/// レコードは含めない。空 = チャンクが空、または誰も modifiedAt を持たなかった場合で、
/// どちらもチェックポイントを動かさない。
///
/// modifiedAt の無いレコードでチェックポイントを進めないのは重要で、進めてしまうと
/// 「取り込めていない範囲を取り込んだ」ことにして次回の起点を前へ動かしてしまう。
pub fn chunk_progress(
    previous_max_since_restart: Option<f64>,
    chunk_modified_epochs: &[f64],
) -> SyncChunkProgress {
    let chunk_max = chunk_modified_epochs
        .iter()
        .copied()
        .fold(None, |acc: Option<f64>, epoch| {
            Some(acc.map_or(epoch, |a: f64| a.max(epoch)))
        });
    match chunk_max {
        None => SyncChunkProgress {
            max_epoch_since_restart: previous_max_since_restart,
            checkpoint_epoch_to_save: None,
        },
        Some(chunk_max) => SyncChunkProgress {
            max_epoch_since_restart: Some(
                previous_max_since_restart.map_or(chunk_max, |prev| prev.max(chunk_max)),
            ),
            checkpoint_epoch_to_save: Some(chunk_max),
        },
    }
}

/// ステップを抜けるときの後始末。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SyncStepFinish {
    /// ステップ内チェックポイントを消してよいか。
    ///
    /// 消してよいのは取り切ったときだけ。飛ばしたステップで消すと、次のフル同期が
    /// そのステップを epoch から取り直すことになり (`started_from_epoch` が真になる)、
    /// 途中まで取り込んだ分を無駄に取り直す。
    pub should_clear_checkpoint: bool,
    /// 「完了ステップ」として保存し直す一覧。None = 保存しない。
    ///
    /// 中断されたフルの再開で飛ばす対象になるので、フル同期を取り切ったときだけ Some。
    /// 差分同期は再開の概念を持たないので常に None。
    pub done_steps_to_persist: Option<Vec<String>>,
}

/// ステップを抜けるときにチェックポイントを消すか、完了ステップに加えるかを決める。
///
/// `completed` は「そのステップを最後まで取り切ったか」。レコードタイプ未作成で飛ばした
/// 場合は false を渡すこと (一次実装は `continue` / `return@forEachIndexed` で後始末を
/// 素通りする)。ここを true にすると、まだ deploy されていないレコードタイプが
/// 「完了済み」として記録され、deploy 後の最初のフル同期でそのテーブルだけ丸ごと
/// 飛ばされる。
pub fn step_finish_plan(
    record_type: &str,
    is_full_sync: bool,
    completed: bool,
    done_steps: &[String],
) -> SyncStepFinish {
    if !completed {
        return SyncStepFinish {
            should_clear_checkpoint: false,
            done_steps_to_persist: None,
        };
    }
    let done_steps_to_persist = is_full_sync.then(|| {
        let mut next = done_steps.to_vec();
        // 一次実装は Set に insert してから配列化する。ここでは順序を保って追加する
        // (集合としては同じで、保存値が実行ごとに並び替わらない分だけ差分が読みやすい)。
        if !next.iter().any(|done| done == record_type) {
            next.push(record_type.to_string());
        }
        next
    });
    SyncStepFinish {
        should_clear_checkpoint: true,
        done_steps_to_persist,
    }
}

// ---------------------------------------------------------------------------
// 5. 孤児掃除を撃ってよいか
// ---------------------------------------------------------------------------

/// そのステップで孤児掃除を実行してよいか。
///
/// 2 つの条件の連言:
/// - `started_from_epoch` … epoch から全件取り直したステップだけ
///   ([`crate::domain::sync_planning::SyncStepStart::started_from_epoch`])。
///   途中再開だと「サーバで見た ID」が不完全で、見ていない既存行を孤児と誤判定して消す。
/// - 単一 PK (`id`) のテーブルだけ
///   ([`crate::domain::sync_planning::supports_orphan_cleanup`])。
///
/// iOS はこの後者を DB 層 (`deleteOrphans` が単一 PK 以外で no-op) に任せているので、
/// ここで先に落としても結果は変わらない。
pub fn should_delete_orphans(record_type: &str, started_from_epoch: bool) -> bool {
    started_from_epoch && supports_orphan_cleanup(record_type)
}

// ---------------------------------------------------------------------------
// 6. 同期を開始してよいか
// ---------------------------------------------------------------------------

/// 同期の前提となるアカウント状態。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum SyncAccountStatus {
    /// iCloud が使える (iOS `CKAccountStatus.available`)。
    Available,
    /// 未サインイン・制限中・不明。いずれも public DB を読めない。
    Unavailable,
    /// 状態の確認そのものに失敗した。`message` は表示に使う。
    CheckFailed { message: String },
    /// アカウントの概念が無い経路。Android は API トークンで public DB を読むので常にこれ。
    NotApplicable,
}

/// 同期を始める前の結論。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum SyncPreflight {
    /// 同期してよい。
    Proceed,
    /// 何も表示せず同期だけ諦める。
    ///
    /// 資格情報が無いのは設定漏れであってユーザーの落ち度ではなく、seed / 既存 DB の
    /// 実データで画面は成立する。エラーを出すと「壊れている」ように見えるだけ。
    SkipQuietly,
    /// 同期できない旨を出して終わる。
    Fail { message: String },
}

/// 同期を開始してよいかを決める。
///
/// - `credentials_configured`: 資格情報が揃っているか (Android の API トークン)。
///   iOS は CloudKit.framework がエンタイトルメントで解決するので常に true を渡す。
/// - `account`: iOS の iCloud アカウント状態。Android は
///   [`SyncAccountStatus::NotApplicable`]。
///
/// 資格情報を先に見るのは、無ければアカウント状態を問い合わせる相手すらいないから。
/// どちらの OS も相手側のフィールドには退化した値を渡すので、順序は実挙動に影響しない。
pub fn preflight(credentials_configured: bool, account: &SyncAccountStatus) -> SyncPreflight {
    if !credentials_configured {
        return SyncPreflight::SkipQuietly;
    }
    match account {
        SyncAccountStatus::Available | SyncAccountStatus::NotApplicable => SyncPreflight::Proceed,
        SyncAccountStatus::Unavailable => SyncPreflight::Fail {
            message: "iCloudアカウントが利用できません".to_string(),
        },
        SyncAccountStatus::CheckFailed { message } => SyncPreflight::Fail {
            message: format!("iCloud状態の確認に失敗: {message}"),
        },
    }
}

// ---------------------------------------------------------------------------
// 7. 進捗率
// ---------------------------------------------------------------------------

/// 「今 `display_name` のステップを走っている」から進捗率 (0..1] を出す。
///
/// 一次実装 iOS `syncProgress` と同じく、**表示中のラベルからステップ列を引き直す**。
/// 進捗の分母はステップ列の長さなので、ステップの増減に合わせて呼び出し側を直す必要が
/// 無くなる。ラベルが列に無ければ None (= 同期中でない / 未知のステップ)。
///
/// `available_record_types` は [`crate::domain::sync_planning::steps_for`] にそのまま渡す。
/// 空なら全ステップ (iOS はこれ)。
pub fn progress_fraction(display_name: &str, available_record_types: &[String]) -> Option<f64> {
    let steps = steps_for(available_record_types);
    let index = steps
        .iter()
        .position(|step| step.display_name == display_name)?;
    Some((index + 1) as f64 / steps.len() as f64)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::prng::SplitMix64;
    use crate::domain::sync_planning::{next_chunk_action, SyncChunkAction};
    use std::collections::HashSet;

    // -----------------------------------------------------------------------
    // テスト用ヘルパ: 各 OS の例外を射影した SyncErrorSignal
    // -----------------------------------------------------------------------

    /// iOS: `CKError` から組み立てた射影。
    fn ck(code: i32, description: &str) -> SyncErrorSignal {
        SyncErrorSignal {
            is_cloudkit_error: true,
            ck_error_code: Some(code),
            http_status: None,
            server_error_code: None,
            // iOS は判定にも表示にも localizedDescription を使う。
            reason: Some(description.to_string()),
            message: description.to_string(),
            retry_after_seconds: None,
        }
    }

    /// iOS: CKError 以外 (通信断・DB 書き込み失敗など)。
    fn non_ck(description: &str) -> SyncErrorSignal {
        SyncErrorSignal {
            is_cloudkit_error: false,
            ck_error_code: None,
            http_status: None,
            server_error_code: None,
            reason: Some(description.to_string()),
            message: description.to_string(),
            retry_after_seconds: None,
        }
    }

    /// Android: `CloudKitQueryException` から組み立てた射影。
    fn ckws(http: i32, server_error_code: Option<&str>, reason: Option<&str>) -> SyncErrorSignal {
        SyncErrorSignal {
            is_cloudkit_error: true,
            ck_error_code: None,
            http_status: Some(http),
            server_error_code: server_error_code.map(str::to_string),
            reason: reason.map(str::to_string),
            message: format!("CloudKit query HTTP {http}: {}", reason.unwrap_or("")),
            retry_after_seconds: None,
        }
    }

    // -----------------------------------------------------------------------
    // 1. 分類 — iOS の switch を全 CKError コードで写し取る
    // -----------------------------------------------------------------------

    /// 一次実装 `fetchChunkWithRetry` の retryable な case と 1 対 1 で一致すること。
    /// CKError.Code は 1..=36 なので全部通して、抜けも増えもしないことを固定する。
    #[test]
    fn ios_retryable_codes_match_primary_implementation() {
        // networkUnavailable=3, networkFailure=4, serviceUnavailable=6,
        // requestRateLimited=7, zoneBusy=23
        let expected: HashSet<i32> = [3, 4, 6, 7, 23].into_iter().collect();
        for code in 1..=36 {
            let retryable = classify_error(&ck(code, "boom")) == SyncErrorKind::Retryable;
            assert_eq!(
                retryable,
                expected.contains(&code),
                "CKError code {code} の再試行可否が一次実装とずれている"
            );
        }
    }

    /// `unknownItem` (11) だけがステップスキップになること。
    #[test]
    fn ios_only_unknown_item_skips_the_step() {
        for code in 1..=36 {
            let kind = classify_error(&ck(code, "boom"));
            assert_eq!(
                kind == SyncErrorKind::UnknownRecordType,
                code == 11,
                "CKError code {code} のスキップ可否が一次実装とずれている"
            );
        }
    }

    /// `invalidArguments` + 一次実装のリテラルでだけスキーマ案内に落ちること。
    #[test]
    fn ios_schema_marker_requires_invalid_arguments_code() {
        assert_eq!(
            classify_error(&ck(12, "Field 'modifiedAt' is not queryable")),
            SyncErrorKind::SchemaNotQueryable
        );
        assert_eq!(
            classify_error(&ck(12, "Field 'modifiedAt' is not sortable")),
            SyncErrorKind::SchemaNotQueryable
        );
        // 同じ文面でも invalidArguments 以外なら一般エラー (一次実装が code で絞っている)。
        assert_eq!(
            classify_error(&ck(15, "Field 'modifiedAt' is not queryable")),
            SyncErrorKind::Fatal
        );
    }

    /// CloudKit の実際の文面 ("is not marked queryable") は一次実装のリテラルに一致せず
    /// 一般エラーへ落ちる。**現状の挙動**であり、直すなら移送とは別の判断。
    #[test]
    fn ios_marked_queryable_wording_does_not_match_and_stays_fatal() {
        assert_eq!(
            classify_error(&ck(12, "Field 'modifiedAt' is not marked queryable")),
            SyncErrorKind::Fatal
        );
    }

    /// Android `CloudKitQueryException.isUnknownRecordType` の判定表をそのまま固定する。
    #[test]
    fn android_unknown_record_type_matches_primary_implementation() {
        // serverErrorCode が NOT_FOUND なら本文を見ない。
        assert_eq!(
            classify_error(&ckws(404, Some("NOT_FOUND"), None)),
            SyncErrorKind::UnknownRecordType
        );
        assert_eq!(
            classify_error(&ckws(400, Some("NOT_FOUND"), None)),
            SyncErrorKind::UnknownRecordType
        );
        // "unknown type" は単独で成立する。
        assert_eq!(
            classify_error(&ckws(
                400,
                Some("BAD_REQUEST"),
                Some("unknown type 'SongVideo'")
            )),
            SyncErrorKind::UnknownRecordType
        );
        // "record type" + 不在語の組み合わせ。大文字小文字は無視される。
        for missing in [
            "unknown",
            "not found",
            "does not exist",
            "not defined",
            "no such",
        ] {
            let reason = format!("Record Type 'SongCall' {missing}");
            assert_eq!(
                classify_error(&ckws(400, Some("BAD_REQUEST"), Some(&reason))),
                SyncErrorKind::UnknownRecordType,
                "reason={reason}"
            );
        }
        // 不在語が無ければ成立しない。
        assert_eq!(
            classify_error(&ckws(
                400,
                Some("BAD_REQUEST"),
                Some("record type is invalid")
            )),
            SyncErrorKind::Fatal
        );
        // フィールド側のスキーマ不備は**飛ばさない** (静かな欠落を作らないため)。
        assert_eq!(
            classify_error(&ckws(
                400,
                Some("BAD_REQUEST"),
                Some("Field 'modifiedAt' is not marked queryable")
            )),
            SyncErrorKind::Fatal
        );
        // 400/404 以外は本文が何であれ対象外。
        assert_eq!(
            classify_error(&ckws(500, Some("NOT_FOUND"), Some("unknown type 'Song'"))),
            SyncErrorKind::Fatal
        );
        // reason が無ければ本文判定は成立しない。
        assert_eq!(
            classify_error(&ckws(400, Some("BAD_REQUEST"), None)),
            SyncErrorKind::Fatal
        );
    }

    /// Android は HTTP しか持たないので、通信系のエラーでも Retryable にはならない
    /// (一次実装に再試行が無い)。ここが Retryable に化けると Android の挙動が変わる。
    #[test]
    fn android_signals_never_classify_as_retryable() {
        for http in [400, 404, 429, 500, 503] {
            assert_ne!(
                classify_error(&ckws(http, Some("SERVICE_UNAVAILABLE"), Some("try later"))),
                SyncErrorKind::Retryable,
                "http={http}"
            );
        }
    }

    // -----------------------------------------------------------------------
    // 2. 再試行 — 一次実装のループを 1 手ずつ写し取る
    // -----------------------------------------------------------------------

    /// `for attempt in 0..<3` の各周回で何が起きるか。2 秒 → 4 秒 → (8 秒待って失敗)。
    #[test]
    fn retry_follows_primary_backoff_schedule() {
        let signal = ck(4, "network failure");
        assert_eq!(
            retry_action(0, DEFAULT_MAX_FETCH_RETRIES, &signal),
            SyncRetryAction::RetryAfter { delay_seconds: 2.0 }
        );
        assert_eq!(
            retry_action(1, DEFAULT_MAX_FETCH_RETRIES, &signal),
            SyncRetryAction::RetryAfter { delay_seconds: 4.0 }
        );
        // 最終試行でも sleep してから throw する (一次実装のループがそう抜ける)。
        assert_eq!(
            retry_action(2, DEFAULT_MAX_FETCH_RETRIES, &signal),
            SyncRetryAction::FailAfterDelay { delay_seconds: 8.0 }
        );
    }

    /// サーバ指定があれば指数バックオフより優先する (`retryAfterSeconds ?? 2 << attempt`)。
    #[test]
    fn retry_prefers_server_specified_delay() {
        let mut signal = ck(7, "rate limited");
        signal.retry_after_seconds = Some(30.0);
        assert_eq!(
            retry_action(0, DEFAULT_MAX_FETCH_RETRIES, &signal),
            SyncRetryAction::RetryAfter {
                delay_seconds: 30.0
            }
        );
        assert_eq!(
            retry_action(2, DEFAULT_MAX_FETCH_RETRIES, &signal),
            SyncRetryAction::FailAfterDelay {
                delay_seconds: 30.0
            }
        );
    }

    /// 再試行対象外は待たずに即失敗 (一次実装の `default: throw ckError`)。
    #[test]
    fn retry_refuses_non_retryable_errors_without_waiting() {
        for signal in [ck(11, "unknown item"), ck(12, "bad args"), non_ck("boom")] {
            assert_eq!(
                retry_action(0, DEFAULT_MAX_FETCH_RETRIES, &signal),
                SyncRetryAction::FailNow
            );
        }
    }

    /// 3 回の試行が「2 回の再試行 + 1 回の打ち切り」になること。
    #[test]
    fn retry_allows_exactly_two_reattempts() {
        let signal = ck(23, "zone busy");
        let reattempts = (0..DEFAULT_MAX_FETCH_RETRIES)
            .filter(|a| {
                matches!(
                    retry_action(*a, DEFAULT_MAX_FETCH_RETRIES, &signal),
                    SyncRetryAction::RetryAfter { .. }
                )
            })
            .count();
        assert_eq!(reattempts, 2);
    }

    // -----------------------------------------------------------------------
    // 3. ステップ失敗時の扱い
    // -----------------------------------------------------------------------

    #[test]
    fn unknown_record_type_skips_the_step_silently() {
        let plan = step_failure_plan("SongVideo", "参考動画", &ck(11, "unknown item"));
        assert_eq!(plan.action, SyncStepFailureAction::SkipStep);
        assert_eq!(plan.message, None);
        assert!(!plan.requires_schema_setup);
        assert!(!plan.should_report_analytics);
    }

    /// 案内文は一次実装の文面と 1 文字も違わないこと (ダッシュボードでの操作手順なので、
    /// レコードタイプ名は表示ラベルではなく生の名前が入る)。
    #[test]
    fn schema_failure_message_matches_primary_implementation() {
        let plan = step_failure_plan(
            "SongArtist",
            "楽曲アーティスト",
            &ck(12, "Field 'modifiedAt' is not queryable"),
        );
        assert_eq!(plan.action, SyncStepFailureAction::Abort);
        assert_eq!(
            plan.message.as_deref(),
            Some("スキーマ設定が必要です: CloudKit Dashboard で SongArtist の modifiedAt を QUERYABLE + SORTABLE に設定してください")
        );
        assert!(plan.requires_schema_setup);
        assert!(!plan.should_report_analytics);
    }

    /// 一般エラーは表示ラベル + 本文。
    #[test]
    fn generic_failure_message_matches_primary_implementation() {
        let plan = step_failure_plan("Show", "公演", &ck(15, "Server rejected request"));
        assert_eq!(plan.action, SyncStepFailureAction::Abort);
        assert_eq!(
            plan.message.as_deref(),
            Some("公演の同期に失敗: Server rejected request")
        );
        assert!(!plan.should_report_analytics);
    }

    /// 分析イベントは CKError 以外でだけ撃つ (一次実装は最後の catch にしか置いていない)。
    #[test]
    fn analytics_fires_only_outside_cloudkit_errors() {
        assert!(step_failure_plan("Song", "楽曲", &non_ck("disk full")).should_report_analytics);
        assert!(!step_failure_plan("Song", "楽曲", &ck(1, "internal")).should_report_analytics);
        // 再試行を使い切った通信エラーも CKError なので撃たない。
        assert!(!step_failure_plan("Song", "楽曲", &ck(4, "offline")).should_report_analytics);
    }

    /// 再試行を使い切ったエラーは飛ばさず中断する (飛ばすと last_sync だけ進んで欠落する)。
    #[test]
    fn exhausted_retryable_error_aborts_the_run() {
        let plan = step_failure_plan("SetlistItem", "セトリ", &ck(3, "offline"));
        assert_eq!(plan.action, SyncStepFailureAction::Abort);
    }

    /// Android のレコードタイプ未作成も同じ扱い (iOS の unknownItem → continue に揃う)。
    #[test]
    fn android_unknown_record_type_skips_the_step() {
        let plan = step_failure_plan("SongCall", "コーレス", &ckws(404, Some("NOT_FOUND"), None));
        assert_eq!(plan.action, SyncStepFailureAction::SkipStep);
    }

    // -----------------------------------------------------------------------
    // 4. チェックポイント
    // -----------------------------------------------------------------------

    #[test]
    fn chunk_progress_saves_this_chunks_max() {
        let progress = chunk_progress(None, &[100.0, 130.0, 120.0]);
        assert_eq!(progress.checkpoint_epoch_to_save, Some(130.0));
        assert_eq!(progress.max_epoch_since_restart, Some(130.0));
    }

    #[test]
    fn chunk_progress_keeps_running_max_across_chunks() {
        let progress = chunk_progress(Some(200.0), &[150.0, 180.0]);
        // 区間最大は下がらない。
        assert_eq!(progress.max_epoch_since_restart, Some(200.0));
        // チェックポイントはこのチャンクの最大 (一次実装は区間最大を書かない)。
        assert_eq!(progress.checkpoint_epoch_to_save, Some(180.0));
    }

    /// 空チャンク / modifiedAt を持たないチャンクではチェックポイントを動かさない。
    #[test]
    fn chunk_progress_without_timestamps_leaves_checkpoint_untouched() {
        let progress = chunk_progress(Some(90.0), &[]);
        assert_eq!(progress.checkpoint_epoch_to_save, None);
        assert_eq!(progress.max_epoch_since_restart, Some(90.0));

        let first = chunk_progress(None, &[]);
        assert_eq!(first.checkpoint_epoch_to_save, None);
        assert_eq!(first.max_epoch_since_restart, None);
    }

    #[test]
    fn completed_full_step_is_recorded_and_checkpoint_cleared() {
        let finish = step_finish_plan("Song", true, true, &["Brand".to_string()]);
        assert!(finish.should_clear_checkpoint);
        assert_eq!(
            finish.done_steps_to_persist,
            Some(vec!["Brand".to_string(), "Song".to_string()])
        );
    }

    /// 再開で二重に積まないこと (一次実装は Set なので重複しない)。
    #[test]
    fn already_recorded_step_is_not_duplicated() {
        let finish = step_finish_plan("Song", true, true, &["Song".to_string()]);
        assert_eq!(finish.done_steps_to_persist, Some(vec!["Song".to_string()]));
    }

    /// 差分同期は完了ステップを持たない (再開の概念が無い)。
    #[test]
    fn incremental_step_records_no_done_steps() {
        let finish = step_finish_plan("Song", false, true, &[]);
        assert!(finish.should_clear_checkpoint);
        assert_eq!(finish.done_steps_to_persist, None);
    }

    /// 飛ばしたステップは完了扱いにしないし、チェックポイントも残す。
    /// ここを緩めると deploy 前に飛ばしたレコードタイプが永久に取り込まれない。
    #[test]
    fn skipped_step_is_not_recorded_as_done() {
        let finish = step_finish_plan("SongVideo", true, false, &["Brand".to_string()]);
        assert!(!finish.should_clear_checkpoint);
        assert_eq!(finish.done_steps_to_persist, None);
    }

    // -----------------------------------------------------------------------
    // 5. 孤児掃除の可否
    // -----------------------------------------------------------------------

    #[test]
    fn orphan_cleanup_needs_both_full_pass_and_single_pk() {
        // 単一 PK + epoch から全件 → 掃除してよい。
        assert!(should_delete_orphans("Song", true));
        // 途中再開 → だめ (見ていない行を孤児と誤判定する)。
        assert!(!should_delete_orphans("Song", false));
        // 複合 PK のテーブルには id 列が無い。
        assert!(!should_delete_orphans("SongArtist", true));
        assert!(!should_delete_orphans("UnitMember", true));
        assert!(!should_delete_orphans("ShowCast", true));
        assert!(!should_delete_orphans("SetlistPerformer", true));
        assert!(!should_delete_orphans("IdolBrand", true));
        // 同期対象外のレコードタイプ。
        assert!(!should_delete_orphans("CastMember", true));
    }

    // -----------------------------------------------------------------------
    // 6. 前提条件
    // -----------------------------------------------------------------------

    #[test]
    fn ios_preflight_matches_account_status_branch() {
        assert_eq!(
            preflight(true, &SyncAccountStatus::Available),
            SyncPreflight::Proceed
        );
        assert_eq!(
            preflight(true, &SyncAccountStatus::Unavailable),
            SyncPreflight::Fail {
                message: "iCloudアカウントが利用できません".to_string()
            }
        );
        assert_eq!(
            preflight(
                true,
                &SyncAccountStatus::CheckFailed {
                    message: "timed out".to_string()
                }
            ),
            SyncPreflight::Fail {
                message: "iCloud状態の確認に失敗: timed out".to_string()
            }
        );
    }

    /// Android: トークン未設定は静かに諦める (seed / 既存 DB で画面は成立する)。
    #[test]
    fn android_preflight_skips_quietly_without_token() {
        assert_eq!(
            preflight(false, &SyncAccountStatus::NotApplicable),
            SyncPreflight::SkipQuietly
        );
        assert_eq!(
            preflight(true, &SyncAccountStatus::NotApplicable),
            SyncPreflight::Proceed
        );
    }

    // -----------------------------------------------------------------------
    // 7. 進捗率
    // -----------------------------------------------------------------------

    #[test]
    fn progress_fraction_matches_ios_step_position() {
        // iOS は全 19 ステップを分母にする。
        assert_eq!(progress_fraction("ブランド", &[]), Some(1.0 / 19.0));
        assert_eq!(progress_fraction("参考動画", &[]), Some(1.0));
        assert_eq!(progress_fraction("公演", &[]), Some(10.0 / 19.0));
        // 未知のラベル (同期中でない) は None。
        assert_eq!(progress_fraction("存在しない", &[]), None);
    }

    #[test]
    fn progress_fraction_uses_available_steps_as_denominator() {
        let available = vec!["Brand".to_string(), "Idol".to_string()];
        assert_eq!(progress_fraction("ブランド", &available), Some(0.5));
        assert_eq!(progress_fraction("アイドル", &available), Some(1.0));
        // 対象外のステップは分母にも入らない。
        assert_eq!(progress_fraction("公演", &available), None);
    }

    // -----------------------------------------------------------------------
    // 8. 一次実装との一致 — チャンクループを丸ごと突き合わせる
    // -----------------------------------------------------------------------

    /// 疑似 CloudKit レコード。判定に効くのは recordName と modifiedAt だけ。
    #[derive(Clone, Debug)]
    struct FakeRecord {
        name: String,
        modified_epoch: Option<f64>,
    }

    /// `modifiedAt > after` を昇順で返し、`page_size` ごとにカーソルを返す疑似サーバ。
    /// CKQuery + CKQueryOperation.Cursor / CKWS の continuationMarker と同じ振る舞い。
    struct FakeServer {
        records: Vec<FakeRecord>,
        page_size: usize,
    }

    impl FakeServer {
        /// modifiedAt 昇順 (同値は投入順) に並べ替えて持つ。CloudKit の sortBy と同じ。
        fn new(mut records: Vec<FakeRecord>, page_size: usize) -> Self {
            records.sort_by(|a, b| {
                a.modified_epoch
                    .unwrap_or(f64::NEG_INFINITY)
                    .partial_cmp(&b.modified_epoch.unwrap_or(f64::NEG_INFINITY))
                    .expect("modifiedAt に NaN は入らない")
            });
            Self { records, page_size }
        }

        /// `cursor` は「同じクエリの何件目から返すか」。None なら先頭から。
        ///
        /// 昇順に持っているので該当範囲は末尾の連続区間になる。二分探索で切り出すのは
        /// 実データ規模 (song_artists 21,665 行 × 218 クエリ) を毎回走査すると
        /// テストが実用的な時間で終わらないため。
        fn fetch(&self, after: f64, cursor: Option<usize>) -> (Vec<FakeRecord>, Option<usize>) {
            // 「該当しない」= modifiedAt <= after。NaN は入れない前提なので単純な比較でよい。
            let first = self
                .records
                .partition_point(|r| r.modified_epoch.unwrap_or(f64::NEG_INFINITY) <= after);
            let matched = &self.records[first..];
            let offset = cursor.unwrap_or(0).min(matched.len());
            let end = (offset + self.page_size).min(matched.len());
            let page = matched[offset..end].to_vec();
            let next = (end < matched.len()).then_some(end);
            (page, next)
        }
    }

    /// 1 ステップ分のループの結果。両実装でこれが完全一致することを見る。
    #[derive(Debug, PartialEq)]
    struct LoopOutcome {
        /// 取り込んだ延べ件数 (重複を含む — 一次実装の `totalFetched` と同じ数え方)。
        total_fetched: usize,
        /// 見た recordName (取りこぼしの検出用)。
        seen: Vec<String>,
        /// チェックポイントに書いた値の列。
        checkpoints: Vec<f64>,
        /// サーバへ投げたクエリ回数。
        queries: usize,
    }

    /// **一次実装 (Swift) をそのまま Rust に書き写したループ**。コアを一切呼ばない。
    ///
    /// `CloudKitSyncEngine.performSyncBody` のステップ内 while ループを 1 行ずつ対応させて
    /// あり、これが「正」の側。下の [`core_driven_loop`] と結果が一致することで、コアの
    /// [`chunk_progress`] と [`next_chunk_action`] の組が元の制御フローを保っていることを示す。
    fn transcribed_swift_loop(server: &FakeServer, initial_start: f64) -> LoopOutcome {
        let mut start = initial_start;
        let mut seen: Vec<String> = Vec::new();
        let mut seen_set: HashSet<String> = HashSet::new();
        let mut cursor: Option<usize> = None;
        let mut added_since_restart: usize = 0;
        let mut max_since_restart: Option<f64> = None;
        let mut total_fetched = 0usize;
        let mut checkpoints: Vec<f64> = Vec::new();
        let mut queries = 0usize;

        loop {
            let (records, next_cursor) = server.fetch(start, cursor);
            queries += 1;

            // let before = seen.count / for r in records { seen.insert(...) }
            let before = seen_set.len();
            for r in &records {
                if seen_set.insert(r.name.clone()) {
                    seen.push(r.name.clone());
                }
            }
            added_since_restart += seen_set.len() - before;

            if !records.is_empty() {
                total_fetched += records.len();
                // records.compactMap { $0["modifiedAt"] as? Date }.max()
                let chunk_max = records
                    .iter()
                    .filter_map(|r| r.modified_epoch)
                    .fold(None, |acc: Option<f64>, e| {
                        Some(acc.map_or(e, |a| a.max(e)))
                    });
                if let Some(max_date) = chunk_max {
                    max_since_restart =
                        Some(max_since_restart.map_or(max_date, |prev: f64| prev.max(max_date)));
                    checkpoints.push(max_date);
                }
            }

            if let Some(next) = next_cursor {
                cursor = Some(next);
                continue;
            }
            let Some(max_date) = max_since_restart else {
                break;
            };
            if added_since_restart == 0 {
                break;
            }
            cursor = None;
            start = max_date - 0.001;
            added_since_restart = 0;
            max_since_restart = None;
        }

        LoopOutcome {
            total_fetched,
            seen,
            checkpoints,
            queries,
        }
    }

    /// 同じループを **コアの判定関数だけ**で回したもの。
    fn core_driven_loop(server: &FakeServer, initial_start: f64) -> LoopOutcome {
        let mut start = initial_start;
        let mut seen: Vec<String> = Vec::new();
        let mut seen_set: HashSet<String> = HashSet::new();
        let mut cursor: Option<usize> = None;
        let mut added_since_restart: u32 = 0;
        let mut max_since_restart: Option<f64> = None;
        let mut total_fetched = 0usize;
        let mut checkpoints: Vec<f64> = Vec::new();
        let mut queries = 0usize;

        loop {
            let (records, next_cursor) = server.fetch(start, cursor);
            queries += 1;

            let before = seen_set.len();
            for r in &records {
                if seen_set.insert(r.name.clone()) {
                    seen.push(r.name.clone());
                }
            }
            // 契約: added_since_restart は dedup 後の新規件数。
            added_since_restart += (seen_set.len() - before) as u32;
            total_fetched += records.len();

            let epochs: Vec<f64> = records.iter().filter_map(|r| r.modified_epoch).collect();
            let progress = chunk_progress(max_since_restart, &epochs);
            max_since_restart = progress.max_epoch_since_restart;
            if let Some(checkpoint) = progress.checkpoint_epoch_to_save {
                checkpoints.push(checkpoint);
            }

            match next_chunk_action(
                next_cursor.is_some(),
                added_since_restart,
                max_since_restart,
            ) {
                SyncChunkAction::ContinueCursor => cursor = next_cursor,
                SyncChunkAction::Finish => break,
                SyncChunkAction::RestartFrom { start_epoch } => {
                    cursor = None;
                    start = start_epoch;
                    added_since_restart = 0;
                    max_since_restart = None;
                }
            }
        }

        LoopOutcome {
            total_fetched,
            seen,
            checkpoints,
            queries,
        }
    }

    /// 全レコードを取りこぼさず、両実装が同じ道筋を辿ることを確認する共通アサーション。
    fn assert_parity(server: &FakeServer, initial_start: f64) -> LoopOutcome {
        let reference = transcribed_swift_loop(server, initial_start);
        let core = core_driven_loop(server, initial_start);
        assert_eq!(core, reference, "コア駆動のループが一次実装と一致しない");

        let expected: HashSet<&str> = server
            .records
            .iter()
            .filter(|r| r.modified_epoch.is_some_and(|m| m > initial_start))
            .map(|r| r.name.as_str())
            .collect();
        let got: HashSet<&str> = reference.seen.iter().map(String::as_str).collect();
        assert_eq!(got, expected, "取りこぼし / 余計な取得がある");
        reference
    }

    fn bulk(prefix: &str, count: usize, epoch: f64) -> Vec<FakeRecord> {
        (0..count)
            .map(|i| FakeRecord {
                name: format!("{prefix}_{i}"),
                modified_epoch: Some(epoch),
            })
            .collect()
    }

    /// 実データ規模の再現: song_artists 21,665 行が一括投入で **同一 modifiedAt** を持つ。
    /// ページ (200 件) を大きく超える同値なので、カーソルを読み切る前に起点を張り直すと
    /// 先頭ページを取り直し続けて残りが永久に落ちる — その退行が起きないことを見る。
    #[test]
    fn parity_song_artists_single_timestamp_bulk_seed() {
        let server = FakeServer::new(bulk("sa", 21_665, 1_700_000_000.0), 200);
        let outcome = assert_parity(&server, 0.0);
        // 109 ページ読み切り → 1ms 戻して張り直し → 同じ 109 ページを重複として読み直す。
        assert_eq!(outcome.queries, 109 * 2);
        assert_eq!(outcome.total_fetched, 21_665 * 2);
        assert_eq!(outcome.seen.len(), 21_665);
    }

    /// 実データ規模の再現: setlist_performers 60,383 行が 3 回の一括投入に分かれている。
    #[test]
    fn parity_setlist_performers_three_bulk_batches() {
        let mut records = bulk("sp_a", 20_000, 1_700_000_000.0);
        records.extend(bulk("sp_b", 20_000, 1_700_000_060.0));
        records.extend(bulk("sp_c", 20_383, 1_700_000_120.0));
        let server = FakeServer::new(records, 200);
        let outcome = assert_parity(&server, 0.0);
        assert_eq!(outcome.seen.len(), 60_383);
    }

    /// 同一 modifiedAt がページ境界でちょうど割れるケース。
    /// `modifiedAt > start` の厳密不等号のせいで、巻き戻さないと境界の行が落ちる。
    #[test]
    fn parity_timestamp_split_exactly_across_page_boundary() {
        let mut records = bulk("head", 199, 1_000.0);
        records.extend(bulk("edge", 2, 2_000.0)); // 200 件目と 201 件目に跨る
        records.extend(bulk("tail", 5, 3_000.0));
        let server = FakeServer::new(records, 200);
        let outcome = assert_parity(&server, 0.0);
        assert_eq!(outcome.seen.len(), 206);
    }

    /// 1 件も無いステップ (未使用のレコードタイプ) は 1 クエリで終わり、
    /// チェックポイントを書かない。
    #[test]
    fn parity_empty_step_finishes_without_checkpoint() {
        let server = FakeServer::new(Vec::new(), 200);
        let outcome = assert_parity(&server, 0.0);
        assert_eq!(outcome.queries, 1);
        assert!(outcome.checkpoints.is_empty());
    }

    /// modifiedAt を持たないレコードが混ざっても、チェックポイントは持っている行の
    /// 最大でしか動かない (持たない行はサーバのフィルタにも掛からず返らない)。
    #[test]
    fn parity_records_without_timestamp_do_not_move_checkpoint() {
        let mut records = bulk("ok", 3, 500.0);
        records.push(FakeRecord {
            name: "broken".to_string(),
            modified_epoch: None,
        });
        let server = FakeServer::new(records, 200);
        let outcome = assert_parity(&server, 0.0);
        // 1 回目で 3 件 → 巻き戻して 2 回目に同じ 3 件 (重複) → 新規ゼロで完了。
        // どちらの周回も書く値は「持っている行の最大」だけで、None の行には動かされない。
        assert_eq!(outcome.checkpoints, vec![500.0, 500.0]);
        assert!(!outcome.seen.iter().any(|name| name == "broken"));
    }

    /// 差分同期の起点が既に最新のとき (0 件差分)。フォアグラウンド復帰のたびに走る経路。
    #[test]
    fn parity_incremental_with_no_changes() {
        let server = FakeServer::new(bulk("s", 10, 1_000.0), 200);
        let outcome = assert_parity(&server, 1_000.0);
        assert_eq!(outcome.total_fetched, 0);
        assert_eq!(outcome.queries, 1);
    }

    /// ランダムな modifiedAt 分布 200 通りで一致すること。
    /// 乱数は OS から取らずシード注入 (規約どおり SplitMix64)。
    #[test]
    fn parity_over_randomized_timestamp_distributions() {
        let mut rng = SplitMix64(0x5171A5_DEC1D3);
        for case in 0..200u64 {
            let count = 1 + rng.next_below(400) as usize;
            // 同値が固まりやすいように、少数の候補値から選ぶ (一括投入の再現)。
            let distinct = 1 + rng.next_below(6) as usize;
            let page_size = 1 + rng.next_below(64) as usize;
            let records: Vec<FakeRecord> = (0..count)
                .map(|i| FakeRecord {
                    name: format!("r{case}_{i}"),
                    modified_epoch: Some(
                        1_000.0 + (rng.next_below(distinct as u64) as f64) * 0.001,
                    ),
                })
                .collect();
            let server = FakeServer::new(records, page_size);
            assert_parity(&server, 0.0);
        }
    }

    /// 巻き戻し幅より細かい間隔 (0.0005 秒) で並ぶと、張り直しが 1 件も減らせず
    /// 重複だけが増える。それでも **停止する** ことを固定する (無限ループ回帰の砦)。
    #[test]
    fn parity_terminates_when_timestamps_are_finer_than_rewind() {
        let records: Vec<FakeRecord> = (0..50)
            .map(|i| FakeRecord {
                name: format!("fine_{i}"),
                modified_epoch: Some(1_000.0 + i as f64 * 0.0005),
            })
            .collect();
        let server = FakeServer::new(records, 8);
        let outcome = assert_parity(&server, 0.0);
        assert_eq!(outcome.seen.len(), 50);
    }
}
