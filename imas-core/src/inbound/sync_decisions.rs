//! 同期エンジンに残っていた判断の FFI 面。ロジックは [`crate::domain::sync_decisions`]。
//!
//! [`crate::inbound::sync_planning`] が「どこから何を取るか」を返すのに対し、こちらは
//! **取りに行った結果をどう解釈するか** を返す (失敗の扱い・待ち時間・チェックポイント・
//! 孤児掃除の可否・開始可否・進捗率)。
//!
//! 通信そのもの・`Task.sleep` / `delay` の実行・UserDefaults / SharedPreferences への
//! 実保存・DB への実書き込みは各 OS に残る。ここに出ているのは全部「状態を渡して
//! やるべきことを受け取る」だけ。
//!
//! エラーは OS で型が非対称 (iOS = `CKError` / Android = CKWS の HTTP + `serverErrorCode`)
//! なので、共有するのは [`SyncErrorSignal`] という射影だけ。各 OS が自分の例外から
//! 組み立て、相手側にしか無いフィールドには `None` を渡す。
//!
//! エポック値の単位は [`crate::inbound::sync_planning`] と同じく **秒 (f64)**。

use crate::domain::sync_decisions::{
    self, SyncAccountStatus, SyncChunkProgress, SyncErrorKind, SyncErrorSignal, SyncPreflight,
    SyncRetryAction, SyncStepFailure, SyncStepFinish,
};

// --- エラーの分類 ---

/// エラーの正体 (レコードタイプ未作成 / スキーマ未設定 / 一時的 / 恒久的) を見分ける。
///
/// 各 OS は自分の例外を [`SyncErrorSignal`] に射影して渡す。iOS は `ck_error_code` に
/// `ckError.code.rawValue` を、Android は `http_status` / `server_error_code` / `reason` を
/// 埋め、持たない側は None にする。
#[uniffi::export]
pub fn sync_classify_error(signal: SyncErrorSignal) -> SyncErrorKind {
    sync_decisions::classify_error(&signal)
}

// --- 取得の再試行 ---

/// 1 チャンクの取得を試みる最大回数 (3)。
#[uniffi::export]
pub fn sync_default_max_fetch_retries() -> u32 {
    sync_decisions::DEFAULT_MAX_FETCH_RETRIES
}

/// 取得が失敗したとき、再試行するか・何秒待つかを決める。
///
/// `attempt` は 0 始まり。返り値が `FailAfterDelay` のときも **待ってから** 失敗させること
/// (一次実装の再試行ループが最終試行でも待ってから投げるため、待たないと失敗が早まる)。
#[uniffi::export]
pub fn sync_retry_action(
    attempt: u32,
    max_retries: u32,
    signal: SyncErrorSignal,
) -> SyncRetryAction {
    sync_decisions::retry_action(attempt, max_retries, &signal)
}

// --- ステップ失敗時の扱い ---

/// 失敗したステップを飛ばすか実行ごと止めるか、何を表示するかを決める。
///
/// レコードタイプ未作成は飛ばす (deploy 待ちのレコードタイプ 1 つで、FK 依存順の後続が
/// 丸ごと取り込まれなくなるのを防ぐ)。それ以外は止める。
#[uniffi::export]
pub fn sync_step_failure_plan(
    record_type: String,
    display_name: String,
    signal: SyncErrorSignal,
) -> SyncStepFailure {
    sync_decisions::step_failure_plan(&record_type, &display_name, &signal)
}

// --- チェックポイント ---

/// チャンクを 1 つ取り込んだ後のチェックポイント値と、区間の最大 modifiedAt を返す。
///
/// `chunk_modified_epochs` には **そのチャンクのレコードが持つ modifiedAt だけ** を並べる
/// (持たないレコードは入れない)。返した `max_epoch_since_restart` はそのまま
/// [`crate::inbound::sync_planning::sync_next_chunk_action`] に渡す。
#[uniffi::export]
pub fn sync_chunk_progress(
    previous_max_since_restart: Option<f64>,
    chunk_modified_epochs: Vec<f64>,
) -> SyncChunkProgress {
    sync_decisions::chunk_progress(previous_max_since_restart, &chunk_modified_epochs)
}

/// ステップを抜けるときにチェックポイントを消すか、完了ステップに加えるかを決める。
///
/// `completed` にはレコードタイプ未作成で飛ばした場合 false を渡すこと。true にすると
/// deploy 前に飛ばしたレコードタイプが完了済みとして記録され、deploy 後の最初のフル
/// 同期でそのテーブルだけ丸ごと飛ばされる。
#[uniffi::export]
pub fn sync_step_finish_plan(
    record_type: String,
    is_full_sync: bool,
    completed: bool,
    done_steps: Vec<String>,
) -> SyncStepFinish {
    sync_decisions::step_finish_plan(&record_type, is_full_sync, completed, &done_steps)
}

// --- 孤児掃除の可否 ---

/// そのステップで孤児掃除を撃ってよいか (epoch から全件取り直した単一 PK のステップのみ)。
///
/// `started_from_epoch` は
/// [`crate::inbound::sync_planning::sync_step_start_plan`] の返り値をそのまま渡す。
#[uniffi::export]
pub fn sync_should_delete_orphans(record_type: String, started_from_epoch: bool) -> bool {
    sync_decisions::should_delete_orphans(&record_type, started_from_epoch)
}

// --- 開始可否 ---

/// 同期を始めてよいか (進める / 静かに諦める / 理由を出して止める) を決める。
///
/// iOS は `credentials_configured = true` と iCloud のアカウント状態を、Android は
/// API トークンの有無と [`SyncAccountStatus::NotApplicable`] を渡す。
#[uniffi::export]
pub fn sync_preflight(credentials_configured: bool, account: SyncAccountStatus) -> SyncPreflight {
    sync_decisions::preflight(credentials_configured, &account)
}

// --- 進捗率 ---

/// 表示中のステップ名から進捗率 (0..1] を出す。未知のラベルなら None。
///
/// `available_record_types` は空なら全ステップ (分母 17)。
#[uniffi::export]
pub fn sync_progress_fraction(
    display_name: String,
    available_record_types: Vec<String>,
) -> Option<f64> {
    sync_decisions::progress_fraction(&display_name, &available_record_types)
}

#[cfg(test)]
mod tests {
    use super::*;
    // 委譲の突き合わせだけに要る型 (FFI 面には出てこないので上の use には無い)。
    use crate::domain::sync_decisions::SyncStepFailureAction;

    // -----------------------------------------------------------------------
    // FFI 面の自足的な固定
    //
    // 回帰: この 9 本は tests/ffi_surface.rs の一覧に登録されないまま「テスト緑」と
    // 報告された。あの一覧は **書いた関数しか守らない** ので、書き忘れた関数は改名しても
    // 削除しても緑のまま通り、Swift / Kotlin ラッパのリンク時まで発覚しない。
    // 共有の一覧 (更新権限が別にある) に依存せず、このモジュール分はここで守り切る。
    // -----------------------------------------------------------------------

    /// UniFFI は各エクスポートに `uniffi_imas_core_checksum_func_<name>` という引数なしの
    /// checksum 関数を no_mangle で生やす。それを extern 宣言して呼ぶと、関数が消えた /
    /// 改名された / エクスポート属性が外れたときに **リンクエラー** になる。
    macro_rules! checked_ffi_exports {
        ($($symbol:ident),+ $(,)?) => {
            extern "C" {
                $(fn $symbol() -> u16;)+
            }

            /// 属性の実数と突き合わせるための分母。
            const CHECKED_EXPORTS: usize = [$(stringify!($symbol)),+].len();

            /// 消えた / 改名されたエクスポートを捕まえる。
            #[test]
            fn exported_functions_keep_their_ffi_symbols() {
                // 呼べること自体がリンク成功の証明。checksum の値は署名変更で正当に変わるため固定しない。
                let checksums = [$(unsafe { $symbol() }),+];
                assert_eq!(checksums.len(), CHECKED_EXPORTS);
            }
        };
    }

    checked_ffi_exports! {
        uniffi_imas_core_checksum_func_sync_chunk_progress,
        uniffi_imas_core_checksum_func_sync_classify_error,
        uniffi_imas_core_checksum_func_sync_default_max_fetch_retries,
        uniffi_imas_core_checksum_func_sync_preflight,
        uniffi_imas_core_checksum_func_sync_progress_fraction,
        uniffi_imas_core_checksum_func_sync_retry_action,
        uniffi_imas_core_checksum_func_sync_should_delete_orphans,
        uniffi_imas_core_checksum_func_sync_step_failure_plan,
        uniffi_imas_core_checksum_func_sync_step_finish_plan,
    }

    /// 増えた分を捕まえる。上のリンク検査は「消えた」しか見ないので、エクスポートを足して
    /// 一覧に足し忘れると素通りしてしまう (その取りこぼしがこの指摘そのもの)。
    /// このファイルの属性数と突き合わせて塞ぐ。
    #[test]
    fn export_count_matches_the_checked_symbol_list() {
        // このソースを読み込んで数えるので、リテラルをそのまま書くと自分自身を数えてしまう。
        // 分割して組み立てるのは tests/ffi_surface.rs と同じ理由。
        let attribute = concat!("#[uniffi", "::export]");
        let found = include_str!("sync_decisions.rs")
            .lines()
            .filter(|line| line.trim_start().starts_with(attribute))
            .count();
        assert_eq!(
            found, CHECKED_EXPORTS,
            "このモジュールの #[uniffi..export] 関数 {found} 本に対し、リンク検査は {CHECKED_EXPORTS} 本しか見ていない。\n\
             エクスポートを増減したら checked_ffi_exports! の一覧と tests/ffi_surface.rs の両方を更新すること。"
        );
    }

    // -----------------------------------------------------------------------
    // 委譲の疎通 — 引数の取り違えは型が同じだと素通りするので、全 9 本を 1 回ずつ通す
    // (判定の正しさそのものは domain::sync_decisions のテストが持つ)。
    // -----------------------------------------------------------------------

    /// iOS の `CKError` を射影した信号。
    fn ck(code: i32, description: &str) -> SyncErrorSignal {
        SyncErrorSignal {
            is_cloudkit_error: true,
            ck_error_code: Some(code),
            http_status: None,
            server_error_code: None,
            reason: Some(description.to_string()),
            message: description.to_string(),
            retry_after_seconds: None,
        }
    }

    #[test]
    fn classify_error_delegates() {
        assert_eq!(
            sync_classify_error(ck(11, "unknown item")),
            SyncErrorKind::UnknownRecordType
        );
        assert_eq!(sync_classify_error(ck(4, "offline")), SyncErrorKind::Retryable);
    }

    #[test]
    fn default_max_fetch_retries_delegates() {
        assert_eq!(
            sync_default_max_fetch_retries(),
            sync_decisions::DEFAULT_MAX_FETCH_RETRIES
        );
    }

    /// `attempt` と `max_retries` を取り違えると 1 回目から打ち切りになる。
    #[test]
    fn retry_action_keeps_attempt_and_max_in_order() {
        let signal = ck(4, "network failure");
        assert_eq!(
            sync_retry_action(0, 3, signal.clone()),
            SyncRetryAction::RetryAfter { delay_seconds: 2.0 }
        );
        assert_eq!(
            sync_retry_action(2, 3, signal),
            SyncRetryAction::FailAfterDelay { delay_seconds: 8.0 }
        );
    }

    /// `record_type` と `display_name` はどちらも String なので、入れ替えても型検査を通る。
    /// 案内文にはレコードタイプ名 (ダッシュボードで探す名前) が入る側であることを固定する。
    #[test]
    fn step_failure_plan_keeps_record_type_and_display_name_apart() {
        let schema = sync_step_failure_plan(
            "SongArtist".into(),
            "楽曲アーティスト".into(),
            ck(12, "Field 'modifiedAt' is not queryable"),
        );
        assert_eq!(schema.action, SyncStepFailureAction::Abort);
        assert!(schema.requires_schema_setup);
        assert_eq!(
            schema.message.as_deref(),
            Some("スキーマ設定が必要です: CloudKit Dashboard で SongArtist の modifiedAt を QUERYABLE + SORTABLE に設定してください")
        );

        // 一般エラーは逆に表示ラベルの側を使う。
        let generic = sync_step_failure_plan("Show".into(), "公演".into(), ck(15, "rejected"));
        assert_eq!(generic.message.as_deref(), Some("公演の同期に失敗: rejected"));
    }

    #[test]
    fn chunk_progress_delegates() {
        let progress = sync_chunk_progress(Some(200.0), vec![150.0, 180.0]);
        assert_eq!(progress.max_epoch_since_restart, Some(200.0));
        assert_eq!(progress.checkpoint_epoch_to_save, Some(180.0));
    }

    /// `is_full_sync` と `completed` はどちらも bool。入れ替えると差分同期が完了ステップを
    /// 書き始める / 飛ばしたステップが完了扱いになる。
    #[test]
    fn step_finish_plan_keeps_full_sync_and_completed_apart() {
        let full = sync_step_finish_plan("Song".into(), true, true, vec!["Brand".to_string()]);
        assert!(full.should_clear_checkpoint);
        assert_eq!(
            full.done_steps_to_persist,
            Some(vec!["Brand".to_string(), "Song".to_string()])
        );

        // 差分同期 (完了) は完了ステップを書かない。
        let incremental = sync_step_finish_plan("Song".into(), false, true, vec![]);
        assert!(incremental.should_clear_checkpoint);
        assert_eq!(incremental.done_steps_to_persist, None);

        // フル同期でも飛ばした (未完了) なら何も書かず、チェックポイントも残す。
        let skipped = sync_step_finish_plan("SongVideo".into(), true, false, vec![]);
        assert!(!skipped.should_clear_checkpoint);
        assert_eq!(skipped.done_steps_to_persist, None);
    }

    #[test]
    fn should_delete_orphans_delegates() {
        assert!(sync_should_delete_orphans("Song".into(), true));
        assert!(!sync_should_delete_orphans("Song".into(), false));
        // 複合 PK は epoch から取り直していても対象外。
        assert!(!sync_should_delete_orphans("SongArtist".into(), true));
    }

    #[test]
    fn preflight_delegates() {
        assert_eq!(
            sync_preflight(true, SyncAccountStatus::Available),
            SyncPreflight::Proceed
        );
        assert_eq!(
            sync_preflight(false, SyncAccountStatus::NotApplicable),
            SyncPreflight::SkipQuietly
        );
        assert_eq!(
            sync_preflight(true, SyncAccountStatus::Unavailable),
            SyncPreflight::Fail {
                message: "iCloudアカウントが利用できません".to_string()
            }
        );
    }

    #[test]
    fn progress_fraction_delegates() {
        assert_eq!(sync_progress_fraction("ブランド".into(), vec![]), Some(1.0 / 19.0));
        assert_eq!(sync_progress_fraction("参考動画".into(), vec![]), Some(1.0));
        assert_eq!(sync_progress_fraction("存在しない".into(), vec![]), None);
        // available_record_types を渡すと分母がそちらに縮む。
        assert_eq!(
            sync_progress_fraction("ブランド".into(), vec!["Brand".to_string(), "Idol".to_string()]),
            Some(0.5)
        );
    }
}
