//! Sign in with ChatGPT (利用者の ChatGPT プランで推論を回す) の FFI 面。判断は domain::chatgpt_plan。

use crate::domain::chatgpt_plan::{
    self as plan, ChatGptAttempt, ChatGptAuthError, ChatGptCallback, ChatGptEndpoints, ChatGptFailure,
    ChatGptHttpErrorAction, ChatGptModel,
    ChatGptRefreshOutcome, ChatGptRegistration, ChatGptSignInIntent, ChatGptSignInOutcome, ChatGptStreamEvent,
    ChatGptTokens,
};

/// 各 OS が叩く先。
#[uniffi::export]
pub fn chatgpt_endpoints() -> ChatGptEndpoints {
    plan::endpoints()
}

/// 端末ごとに 1 回だけ作る識別子。`uuid` は各 OS が作った UUID。
#[uniffi::export]
pub fn chatgpt_host_id(uuid: String) -> String {
    plan::host_id(&uuid)
}

/// サインイン 1 回に要る乱数のバイト数。
#[uniffi::export]
pub fn chatgpt_attempt_random_bytes() -> u32 {
    plan::ATTEMPT_RANDOM_BYTES as u32
}

/// サインインを始める (どの client_id で入るか・認可 URL)。`random` は安全な乱数。
#[uniffi::export]
pub fn chatgpt_begin_sign_in(
    intent: ChatGptSignInIntent,
    registration: Option<ChatGptRegistration>,
    pending_client_id: Option<String>,
    id_token: Option<String>,
    host_id: String,
    port: u16,
    random: Vec<u8>,
) -> Result<ChatGptAttempt, ChatGptAuthError> {
    plan::begin_sign_in(
        intent,
        registration.as_ref(),
        pending_client_id.as_deref(),
        id_token.as_deref(),
        &host_id,
        port,
        &random,
    )
}

/// ループバックに来たリクエストが、待っている callback か。
#[uniffi::export]
pub fn chatgpt_is_expected_callback(target: String, attempt: ChatGptAttempt) -> bool {
    plan::is_expected_callback(&target, &attempt)
}

/// callback がエラーを運んできたか。
#[uniffi::export]
pub fn chatgpt_callback_is_error(target: String) -> bool {
    plan::callback_is_error(&target)
}

/// callback を検証する。
#[uniffi::export]
pub fn chatgpt_read_callback(target: String, attempt: ChatGptAttempt) -> Result<ChatGptCallback, ChatGptAuthError> {
    plan::read_callback(&target, &attempt)
}

/// 認可コードの交換の応答を読み、サインインを締める。
#[uniffi::export]
pub fn chatgpt_finish_sign_in(
    attempt: ChatGptAttempt,
    callback: ChatGptCallback,
    status: u16,
    body: String,
    registration: Option<ChatGptRegistration>,
    now_epoch_seconds: i64,
) -> Result<ChatGptSignInOutcome, ChatGptAuthError> {
    plan::finish_sign_in(&attempt, &callback, status, &body, registration.as_ref(), now_epoch_seconds)
}

/// このサインインで ChatGPT プランを使えるか。
#[uniffi::export]
pub fn chatgpt_can_use_plan(tokens: ChatGptTokens) -> bool {
    plan::can_use_plan(&tokens)
}

/// アクセストークンを使う前に更新が要るか。
#[uniffi::export]
pub fn chatgpt_needs_refresh(tokens: ChatGptTokens, now_epoch_seconds: i64) -> bool {
    plan::needs_refresh(&tokens, now_epoch_seconds)
}

/// 更新のフォーム本文。更新用トークンが無ければ None。
#[uniffi::export]
pub fn chatgpt_refresh_form(tokens: ChatGptTokens, registration: ChatGptRegistration) -> Option<String> {
    plan::refresh_form(&tokens, &registration)
}

/// 更新の応答を読む。
#[uniffi::export]
pub fn chatgpt_read_refresh(
    status: u16,
    body: String,
    previous: ChatGptTokens,
    now_epoch_seconds: i64,
) -> ChatGptRefreshOutcome {
    plan::read_refresh(status, &body, &previous, now_epoch_seconds)
}

/// 失効 (サインアウト) のフォーム本文。更新用トークンが無ければ None。
#[uniffi::export]
pub fn chatgpt_revoke_form(tokens: ChatGptTokens, registration: ChatGptRegistration) -> Option<String> {
    tokens.refresh_token.as_deref().map(|t| plan::revoke_form(t, &registration.client_id))
}

/// discovery の応答から失効エンドポイントを取り出す。
#[uniffi::export]
pub fn chatgpt_revocation_endpoint(discovery_body: String) -> Option<String> {
    plan::revocation_endpoint(&discovery_body)
}

/// モデル一覧の応答から、選ばせてよいものをサーバの並び順で返す。
#[uniffi::export]
pub fn chatgpt_read_models(body: String) -> Vec<ChatGptModel> {
    plan::read_models(&body)
}

/// Responses API のリクエスト本文。
#[uniffi::export]
pub fn chatgpt_responses_body(
    model: String,
    instructions: String,
    input_items: Vec<String>,
    tools_json: String,
    text_format_json: String,
    include_encrypted_reasoning: bool,
) -> String {
    plan::responses_body(&model, &instructions, &input_items, &tools_json, &text_format_json, include_encrypted_reasoning)
}

/// ストリームの 1 行を読む。
#[uniffi::export]
pub fn chatgpt_read_stream_line(line: String) -> ChatGptStreamEvent {
    plan::read_stream_line(&line)
}

/// 完了の合図を受け取る前にストリームが切れたときの失敗。
#[uniffi::export]
pub fn chatgpt_stream_cut_off() -> ChatGptFailure {
    plan::stream_cut_off()
}

/// HTTP の失敗 (2xx 以外) を説明する。
#[uniffi::export]
pub fn chatgpt_http_failure(status: u16, body: String) -> ChatGptFailure {
    plan::http_failure(status, &body)
}

/// 推論のリクエストが HTTP の失敗で返ったとき、次にどうするか (やり直すか・失敗にするか)。
#[uniffi::export]
pub fn chatgpt_http_error_action(status: u16, body: String, include_encrypted_reasoning: bool) -> ChatGptHttpErrorAction {
    plan::http_error_action(status, &body, include_encrypted_reasoning)
}

/// ログインの期限切れの文言 (更新用トークンが無いとき)。
#[uniffi::export]
pub fn chatgpt_sign_in_expired_message() -> String {
    plan::sign_in_expired_message()
}

/// callback が認可エラーで落ちたとき、控えてあった client_id を捨てるべきか。
/// 認可エラーかどうかは呼ぶ側が例外の種類で見分けて渡す。
#[uniffi::export]
pub fn chatgpt_should_forget_pending(attempt: ChatGptAttempt, is_oauth_error: bool) -> bool {
    is_oauth_error && plan::should_forget_pending(&attempt, &ChatGptAuthError::OAuth(String::new()))
}
