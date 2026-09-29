//! 認証・admin 権限判定の FFI 面。ロジックは domain::auth_rules。
//!
//! いずれも「1 ユーザー操作 = 1 呼び出し」で完結する粒度にしてある
//! (起動時の復元 / ログイン応答の採用 / 再発行の可否 / admin 能力の解決)。
//! 判定材料はすべて引数で渡す — コアは時計も保存領域も通信も持たない。

use crate::domain::auth_rules::{
    self, AdminCapabilities, AppleCredentialState, CredentialCheckAction, MeResponse,
    ProfileRefresh, RestoredAuthState, RetryDecision, SessionAdoption, SessionResponse,
    StoredAuthState, TokenExchangeOutcome,
};

/// 起動時: 保存済みの認証状態を復元する (トークンの採否・再発行要否・削除要否を一括で返す)。
#[uniffi::export]
pub fn auth_restore_stored_state(
    stored: StoredAuthState,
    now_epoch_seconds: i64,
) -> RestoredAuthState {
    auth_rules::restore_stored_state(stored, now_epoch_seconds)
}

/// sessionToken の claim 検証 (alg/iss/aud/期限)。
#[uniffi::export]
pub fn auth_is_valid_session_token(token: String, now_epoch_seconds: i64) -> bool {
    auth_rules::is_valid_session_token(&token, now_epoch_seconds)
}

/// Authorization ヘッダに載せるトークン (sessionToken 優先、無ければ identityToken)。
///
/// ⚠️ 有効性は見ない。送信前に期限を判定して止めると 401 → 自動リフレッシュ → 再送が死ぬ。
#[uniffi::export]
pub fn auth_bearer_token(
    session_token: Option<String>,
    identity_token: Option<String>,
) -> Option<String> {
    auth_rules::bearer_token(session_token, identity_token)
}

/// `/auth/refresh` に載せるトークン。None ならリクエストごと送らない。
#[uniffi::export]
pub fn auth_session_refresh_candidate(
    in_memory_token: Option<String>,
    stored_token: Option<String>,
) -> Option<String> {
    auth_rules::session_refresh_candidate(in_memory_token, stored_token)
}

/// `/auth/login` `/auth/refresh` が返したセッションを採用してよいか (と、何を書き換えるか)。
///
/// 両エンドポイントで同じ型を通す。採用時は `is_signed_in = Some(true)` も返るので、
/// 401 で落としたサインイン状態はこれで戻す (無視するとログイン導線が出たままになる)。
#[uniffi::export]
pub fn auth_adopt_session_response(
    response: SessionResponse,
    now_epoch_seconds: i64,
) -> SessionAdoption {
    auth_rules::adopt_session_response(response, now_epoch_seconds)
}

/// `GET /auth/me` の反映内容 (admin/BAN は上書き、表示名は変化時のみ)。
#[uniffi::export]
pub fn auth_apply_me_response(
    me: MeResponse,
    current_display_name: Option<String>,
) -> ProfileRefresh {
    auth_rules::apply_me_response(me, current_display_name.as_deref())
}

/// identityToken → sessionToken の交換を続けるか (`attempt` は 0 始まり)。
#[uniffi::export]
pub fn auth_token_exchange_retry(attempt: u32, outcome: TokenExchangeOutcome) -> RetryDecision {
    auth_rules::token_exchange_retry(attempt, outcome)
}

/// bool フラグの保存表現 ("1"/"0")。Keychain は文字列しか持てない。
#[uniffi::export]
pub fn auth_stored_flag_value(flag: bool) -> String {
    auth_rules::stored_flag_value(flag)
}

/// Apple が返した姓名から表示名を組み立てる (空なら None = 既存の表示名を保つ)。
#[uniffi::export]
pub fn auth_display_name_from_apple_name(
    family_name: Option<String>,
    given_name: Option<String>,
) -> Option<String> {
    auth_rules::display_name_from_apple_name(family_name, given_name)
}

/// Apple ID 資格情報の状態から次の一手を決める
/// (`is_recheck` = revoked を受けて問い合わせ直した 2 回目か)。
#[uniffi::export]
pub fn auth_credential_check_action(
    state: AppleCredentialState,
    is_recheck: bool,
) -> CredentialCheckAction {
    auth_rules::credential_check_action(state, is_recheck)
}

/// admin フラグから開く操作をまとめて解決する。
#[uniffi::export]
pub fn auth_admin_capabilities(is_admin: bool) -> AdminCapabilities {
    auth_rules::admin_capabilities(is_admin)
}
