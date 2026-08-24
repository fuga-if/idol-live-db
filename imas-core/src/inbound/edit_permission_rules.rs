//! オープン編集権限判定の FFI 面。ロジックは domain::edit_permission_rules。
//!
//! `EditPermissionRules` は認証状態の 2 bool だけの射影 Record。UI の各判定
//! (ボタン表示可否・押下時の分岐など) がそれぞれ 1 回の FFI 呼び出しで完結する。

use crate::domain::edit_permission_rules::{EditPermissionRules, EditTapOutcome};

/// 編集 UI を実際に出してよいか (ログイン済み かつ 未 BAN)。
#[uniffi::export]
pub fn edit_permission_can_edit(rules: EditPermissionRules) -> bool {
    rules.can_edit()
}

/// 未ログインで編集導線を押した時にログイン誘導を出すべきか。
#[uniffi::export]
pub fn edit_permission_should_prompt_login(rules: EditPermissionRules) -> bool {
    rules.should_prompt_login()
}

/// 編集 / 新規作成ボタン自体を表示してよいか (BAN 済みのみ隠す)。
#[uniffi::export]
pub fn edit_permission_show_edit_affordance(rules: EditPermissionRules) -> bool {
    rules.show_edit_affordance()
}

/// 編集導線を押した時の分岐 (present / prompt_login / ignore)。
#[uniffi::export]
pub fn edit_permission_outcome_on_edit_tap(rules: EditPermissionRules) -> EditTapOutcome {
    rules.outcome_on_edit_tap()
}
