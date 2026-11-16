//! Sign in with ChatGPT (オープンソース向けの ChatGPT プラン利用フロー) の規則。
//!
//! 利用者の ChatGPT プラン (Plus / Pro) で Responses API を呼ぶための、OAuth の組み立てと
//! 応答の読み方。**通信・ブラウザ・保存は各 OS、判断はここ**:
//!
//! | 各 OS がやること | ここが決めること |
//! |---|---|
//! | 127.0.0.1 で callback を待つ・ブラウザを開く | 認可 URL の中身・どの client_id で入るか |
//! | フォームを POST する | フォームの中身・応答のどれを採るか |
//! | Keychain / 暗号化保存に置く | 何を保存するか (登録とトークンの形) |
//! | SSE の行を読む | 行の意味 (本文の断片 / 関数呼び出し / 失敗) と失敗の言い方 |
//!
//! 仕様の正は developers.openai.com/siwc/token-sharing-open-source の
//! sign-in / profiles-and-sessions / errors-and-recovery / models-and-inference。
//!
//! - 初回は `client_id=dynamic_agent_client` で登録し、callback で返る `oaiapp_...` を以後使う
//! - リダイレクトは `http://127.0.0.1:<port>/auth/callback` 固定 (ポートだけ可変)
//! - クライアントシークレットは無い (PKCE S256)
//!
//! ここで得た識別子 (sub / email) は画面の表示と「前回と別のアカウント」の検知にしか使わない。
//! このアプリのサーバへは送らず、アプリのアカウント (Apple / Google でサインイン) とも結ばない。

use crate::domain::sha256::sha256_digest;
use serde_json::{json, Value};

pub const ISSUER: &str = "https://auth.openai.com";
pub const AUTHORIZE_ENDPOINT: &str = "https://auth.openai.com/api/accounts/authorize";
pub const TOKEN_ENDPOINT: &str = "https://auth.openai.com/api/accounts/oauth/token";
pub const DISCOVERY_URL: &str = "https://auth.openai.com/.well-known/openid-configuration";
pub const RESOURCE: &str = "https://api.openai.com/v1";
pub const MODELS_URL: &str = "https://api.openai.com/v1/models";
pub const RESPONSES_URL: &str = "https://api.openai.com/v1/responses";
pub const CALLBACK_PATH: &str = "/auth/callback";
pub const DYNAMIC_CLIENT_ID: &str = "dynamic_agent_client";
pub const PLAN_SCOPE: &str = "chatgpt.tokens.use.direct";
const SCOPE: &str = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct";
/// 同意画面に出るアプリ名。インストールをまたいで同じ名前を使う。
const AGENT_NAME: &str = "アイドルライブDB";
/// アクセストークンの残りがこれを切ったら、使う前に更新する (秒)。
const REFRESH_MARGIN_SECONDS: i64 = 300;
/// 1 回のサインインに要る乱数のバイト数 (state 32 + nonce 32 + code_verifier 64)。
pub const ATTEMPT_RANDOM_BYTES: usize = 128;

/// 各 OS が叩く先。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChatGptEndpoints {
    pub token_url: String,
    pub discovery_url: String,
    pub models_url: String,
    pub responses_url: String,
    /// ループバックで待つパス (`/auth/callback`)。
    pub callback_path: String,
}

pub fn endpoints() -> ChatGptEndpoints {
    ChatGptEndpoints {
        token_url: TOKEN_ENDPOINT.into(),
        discovery_url: DISCOVERY_URL.into(),
        models_url: MODELS_URL.into(),
        responses_url: RESPONSES_URL.into(),
        callback_path: CALLBACK_PATH.into(),
    }
}

/// ループバックの redirect_uri。`localhost` に置き換えてはいけない (仕様)。
pub fn redirect_uri(port: u16) -> String {
    format!("http://127.0.0.1:{port}{CALLBACK_PATH}")
}

/// 端末ごとに 1 回だけ作って以後ずっと同じ値を送る識別子。`uuid` は各 OS が作った UUID。
pub fn host_id(uuid: &str) -> String {
    format!("urn:uuid:{}", uuid.trim().to_lowercase())
}

/// 保存する登録 (発行済み client_id とアカウント)。サインアウトしても残す
/// (次のサインインで同じ client_id を使い回し、連携アプリを増やさない)。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChatGptRegistration {
    pub client_id: String,
    pub subject: String,
    pub email: Option<String>,
}

/// 保存するトークン。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChatGptTokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub id_token: Option<String>,
    /// 付与された scope (並べ替え済み)。
    pub scopes: Vec<String>,
    /// アクセストークンの期限 (UNIX 秒)。
    pub expires_at: i64,
}

/// 何のためのサインインか。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ChatGptSignInIntent {
    /// 保存済みの登録があればそれで入る。無ければ新規登録。
    SignIn,
    /// 外したプラン利用の許可を、同意画面を出して取り直す。
    EnablePlan,
    /// 今の登録を使わず、別のアカウントとして新規登録する。
    NewAccount,
}

/// サインイン 1 回ぶんの控え。callback と交換のときに照らす。保存はしない。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChatGptAttempt {
    pub client_id: String,
    pub is_new_registration: bool,
    /// 保存済みの登録と同じ client_id で入り直すか (別アカウントが返ったら弾く)。
    pub is_same_registration: bool,
    pub state: String,
    pub nonce: String,
    pub code_verifier: String,
    pub redirect_uri: String,
    /// ブラウザで開く認可 URL。
    pub authorize_url: String,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum ChatGptAuthError {
    #[error("乱数が足りません")]
    NotEnoughRandom,
    #[error("ChatGPT 側で許可されませんでした{0}")]
    AccessDenied(String),
    #[error("認可エラー: {0}")]
    OAuth(String),
    #[error("別のログインの結果が返ってきました。もう一度試してください")]
    StateMismatch,
    #[error("ChatGPT から認可コードが返りませんでした")]
    MissingCode,
    #[error("ChatGPT への登録が終わりませんでした。もう一度試してください")]
    RegistrationIncomplete,
    #[error("別のアプリ向けの結果が返ってきました ({0})")]
    ClientMismatch(String),
    #[error("ChatGPT とのやりとりに失敗しました (HTTP {0})")]
    TokenEndpoint(u16),
    #[error("ChatGPT の応答を読めませんでした")]
    UnreadableResponse,
    #[error("ログインの確認に失敗しました: {0}")]
    IdToken(String),
}

/// サインインを始める。どの client_id で入るか・同意画面を出し直すか・認可 URL はここで決まる。
///
/// - `registration`: 保存済みの登録。
/// - `pending_client_id`: 前回、登録の途中で落ちて残った client_id (新規登録を重ねないため)。
/// - `id_token`: 保存済みの ID トークン (同じ登録で入り直すときのヒント)。
/// - `random`: 暗号学的に安全な乱数 [`ATTEMPT_RANDOM_BYTES`] バイト。各 OS が用意する。
pub fn begin_sign_in(
    intent: ChatGptSignInIntent,
    registration: Option<&ChatGptRegistration>,
    pending_client_id: Option<&str>,
    id_token: Option<&str>,
    host_id: &str,
    port: u16,
    random: &[u8],
) -> Result<ChatGptAttempt, ChatGptAuthError> {
    if random.len() < ATTEMPT_RANDOM_BYTES {
        return Err(ChatGptAuthError::NotEnoughRandom);
    }
    let saved_client_id: Option<&str> = match intent {
        ChatGptSignInIntent::NewAccount => None,
        ChatGptSignInIntent::SignIn | ChatGptSignInIntent::EnablePlan => {
            registration.map(|r| r.client_id.as_str()).or(pending_client_id)
        }
    };
    let is_new_registration = saved_client_id.is_none();
    let is_same_registration =
        matches!((saved_client_id, registration), (Some(id), Some(r)) if id == r.client_id);
    // 保存済み client_id の再認可は同意画面を飛ばすので、許可を足すときは出させる。
    let force_consent = intent == ChatGptSignInIntent::EnablePlan && !is_new_registration;

    let client_id = saved_client_id.unwrap_or(DYNAMIC_CLIENT_ID).to_string();
    let state = base64url_encode(&random[0..32]);
    let nonce = base64url_encode(&random[32..64]);
    let code_verifier = base64url_encode(&random[64..128]);
    let redirect_uri = redirect_uri(port);

    let mut items: Vec<(&str, String)> = vec![
        ("client_id", client_id.clone()),
        ("ext_agent_host_id", host_id.to_string()),
        ("response_type", "code".into()),
        ("redirect_uri", redirect_uri.clone()),
        ("scope", SCOPE.into()),
        ("resource", RESOURCE.into()),
        ("state", state.clone()),
        ("nonce", nonce.clone()),
        ("code_challenge_method", "S256".into()),
        ("code_challenge", base64url_encode(&sha256_digest(code_verifier.as_bytes()))),
    ];
    if is_new_registration {
        // 名前のヒントは初回登録だけ。再認可では送らない。
        items.push(("agent_name_hint", AGENT_NAME.into()));
    } else {
        if is_same_registration {
            if let Some(hint) = id_token {
                items.push(("id_token_hint", hint.to_string()));
            }
            if let Some(email) = registration.and_then(|r| r.email.as_deref()) {
                items.push(("login_hint", email.to_string()));
            }
        }
        if force_consent {
            items.push(("prompt", "consent".into()));
        }
    }
    let authorize_url = format!("{AUTHORIZE_ENDPOINT}?{}", form_body(&items));

    Ok(ChatGptAttempt {
        client_id,
        is_new_registration,
        is_same_registration,
        state,
        nonce,
        code_verifier,
        redirect_uri,
        authorize_url,
    })
}

/// ループバックに来たリクエストが、待っている callback か。
///
/// 待ち受けは端末内の誰でも叩けるので、パスと state が合うものだけを callback として受ける。
/// `target` は HTTP リクエスト行の 2 語目 (`/auth/callback?code=...`)。
pub fn is_expected_callback(target: &str, attempt: &ChatGptAttempt) -> bool {
    let (path, query) = split_target(target);
    path == CALLBACK_PATH && query_value(query, "state").as_deref() == Some(attempt.state.as_str())
}

/// callback の検証が「認可エラー」で落ちたとき、控えてあった client_id を捨てるべきか。
///
/// 登録の途中で残った client_id で入り直して認可エラーになったなら、その client はもう
/// 使えない。捨てれば次は新規登録からやり直せる (捨てないと毎回同じエラーで抜けられない)。
/// 保存済みの登録で入り直したときは捨てない (「別のアカウントでログイン」で抜けられる)。
pub fn should_forget_pending(attempt: &ChatGptAttempt, error: &ChatGptAuthError) -> bool {
    !attempt.is_new_registration && !attempt.is_same_registration && matches!(error, ChatGptAuthError::OAuth(_))
}

/// callback がエラーを運んできたか (ブラウザに出す完了ページの言い方を変える)。
pub fn callback_is_error(target: &str) -> bool {
    query_value(split_target(target).1, "error").is_some()
}

/// callback から読み取ったもの。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChatGptCallback {
    pub code: String,
    /// 以後使う client_id。初回登録ならここで発行されたもの。
    pub client_id: String,
    /// callback に付いていた scope (並べ替え済み)。無ければ空。
    pub scopes: Vec<String>,
    /// 初回登録で発行された client_id を、交換の前に控えておくべきか。
    /// (交換や検証で落ちても次の試行で使い回し、連携アプリを増やさない)
    pub remember_as_pending: bool,
    /// トークンエンドポイントへ POST するフォーム本文 (認可コードの交換)。
    pub exchange_form: String,
}

/// callback を検証する。
pub fn read_callback(target: &str, attempt: &ChatGptAttempt) -> Result<ChatGptCallback, ChatGptAuthError> {
    let query = split_target(target).1;
    // エラーでも state は先に照合する (他の試行の結果を拾わない)。
    if query_value(query, "state").as_deref() != Some(attempt.state.as_str()) {
        return Err(ChatGptAuthError::StateMismatch);
    }
    if let Some(error) = query_value(query, "error") {
        let detail = query_value(query, "error_description").filter(|d| !d.is_empty());
        if error == "access_denied" {
            return Err(ChatGptAuthError::AccessDenied(detail.map(|d| format!(" ({d})")).unwrap_or_default()));
        }
        return Err(ChatGptAuthError::OAuth(match detail {
            Some(d) => format!("{error} — {d}"),
            None => error,
        }));
    }
    let code = query_value(query, "code").filter(|c| !c.is_empty()).ok_or(ChatGptAuthError::MissingCode)?;

    let callback_client = query_value(query, "client_id").filter(|c| !c.is_empty());
    let client_id = if attempt.is_new_registration {
        match callback_client {
            Some(id) if id != DYNAMIC_CLIENT_ID => id,
            _ => return Err(ChatGptAuthError::RegistrationIncomplete),
        }
    } else {
        // 再認可では省略されうる。違う ID が来たら登録を差し替えずに弾く。
        if let Some(id) = callback_client {
            if id != attempt.client_id {
                return Err(ChatGptAuthError::ClientMismatch(id));
            }
        }
        attempt.client_id.clone()
    };

    let exchange_form = form_body(&[
        ("grant_type", "authorization_code".into()),
        ("client_id", client_id.clone()),
        ("code", code.clone()),
        ("code_verifier", attempt.code_verifier.clone()),
        ("redirect_uri", attempt.redirect_uri.clone()),
        ("resource", RESOURCE.into()),
    ]);
    Ok(ChatGptCallback {
        code,
        client_id,
        scopes: query_value(query, "scope").map(|s| split_scopes(&s)).unwrap_or_default(),
        remember_as_pending: attempt.is_new_registration,
        exchange_form,
    })
}

/// サインインの結末。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum ChatGptSignInOutcome {
    /// 通った。`registration` と `tokens` を保存する。
    Accepted {
        registration: ChatGptRegistration,
        tokens: ChatGptTokens,
        /// 別のアカウントに切り替わったので、前のアカウントのセッションは失効させる。
        revoke_previous: bool,
    },
    /// 同じ登録で入り直したのに、別のアカウントが返った。保存は書き換えず、
    /// 受け取ったばかりのセッション (`revoke_form`) を失効させる。
    DifferentAccount {
        /// 失効エンドポイントへ POST するフォーム本文。更新用トークンが無ければ None。
        revoke_form: Option<String>,
        /// 画面に出す文言。
        message: String,
    },
}

/// 認可コードの交換の応答を読み、サインインを締める。
///
/// ID トークンの署名検証は省いている。トークンエンドポイントから TLS で直接受け取った
/// ID トークンなので OIDC Core 3.1.3.7 の範囲で許容される。iss / aud / exp / nonce は照合する。
pub fn finish_sign_in(
    attempt: &ChatGptAttempt,
    callback: &ChatGptCallback,
    status: u16,
    body: &str,
    registration: Option<&ChatGptRegistration>,
    now_epoch_seconds: i64,
) -> Result<ChatGptSignInOutcome, ChatGptAuthError> {
    let tokens = read_token_response(status, body, None, &callback.scopes, now_epoch_seconds)?;
    let id_token = tokens.id_token.as_deref().ok_or_else(|| ChatGptAuthError::IdToken("ID トークンが返りませんでした".into()))?;
    let (subject, email) = validate_id_token(id_token, &callback.client_id, &attempt.nonce, now_epoch_seconds)?;

    if attempt.is_same_registration {
        if let Some(saved) = registration {
            if saved.subject != subject {
                return Ok(ChatGptSignInOutcome::DifferentAccount {
                    revoke_form: tokens.refresh_token.as_deref().map(|t| revoke_form(t, &callback.client_id)),
                    message: "前回と別の ChatGPT アカウントでログインされました。別のアカウントを使うときは「別のアカウントでログイン」から入ってください".into(),
                });
            }
        }
    }
    Ok(ChatGptSignInOutcome::Accepted {
        registration: ChatGptRegistration { client_id: callback.client_id.clone(), subject, email },
        tokens,
        revoke_previous: !attempt.is_same_registration && registration.is_some(),
    })
}

/// トークンエンドポイントの応答を、保存する形にする。
///
/// 応答に無い項目は `previous` (更新前のトークン) を引き継ぐ: 更新の応答は scope や
/// ID トークンを省くことがあり、省かれたら付与範囲は前のまま。
fn read_token_response(
    status: u16,
    body: &str,
    previous: Option<&ChatGptTokens>,
    fallback_scopes: &[String],
    now_epoch_seconds: i64,
) -> Result<ChatGptTokens, ChatGptAuthError> {
    if !(200..300).contains(&status) {
        return Err(ChatGptAuthError::TokenEndpoint(status));
    }
    let v: Value = serde_json::from_str(body).map_err(|_| ChatGptAuthError::UnreadableResponse)?;
    let text = |key: &str| v.get(key).and_then(Value::as_str).filter(|s| !s.is_empty()).map(String::from);
    let access_token = text("access_token").ok_or(ChatGptAuthError::UnreadableResponse)?;
    // 期限は 1 分〜30 日に収める (壊れた値で足し算をあふれさせない・即時の更新ループにしない)。
    let expires_in = v.get("expires_in").and_then(Value::as_f64).unwrap_or(3600.0).clamp(60.0, 2_592_000.0) as i64;
    Ok(ChatGptTokens {
        access_token,
        refresh_token: text("refresh_token").or_else(|| previous.and_then(|p| p.refresh_token.clone())),
        id_token: text("id_token").or_else(|| previous.and_then(|p| p.id_token.clone())),
        scopes: match text("scope") {
            Some(s) => split_scopes(&s),
            None => previous.map(|p| p.scopes.clone()).unwrap_or_else(|| fallback_scopes.to_vec()),
        },
        expires_at: now_epoch_seconds.saturating_add(expires_in),
    })
}

/// ID トークンを確かめて (sub, email) を返す。
fn validate_id_token(
    token: &str,
    client_id: &str,
    nonce: &str,
    now_epoch_seconds: i64,
) -> Result<(String, Option<String>), ChatGptAuthError> {
    let bad = |reason: &str| ChatGptAuthError::IdToken(reason.to_string());
    let segments: Vec<&str> = token.split('.').collect();
    if segments.len() != 3 {
        return Err(bad("JWT として読めません"));
    }
    let claims: Value = base64url_decode(segments[1])
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .filter(Value::is_object)
        .ok_or_else(|| bad("JWT として読めません"))?;

    if claims.get("iss").and_then(Value::as_str) != Some(ISSUER) {
        return Err(bad("発行元が違います"));
    }
    let audience_matches = match claims.get("aud") {
        Some(Value::String(a)) => a == client_id,
        Some(Value::Array(list)) => list.iter().any(|a| a.as_str() == Some(client_id)),
        _ => false,
    };
    if !audience_matches {
        return Err(bad("宛先が違います"));
    }
    // 期限は必須。端末の時計のずれを 60 秒まで見る。
    match claims.get("exp").and_then(Value::as_f64) {
        Some(exp) if exp as i64 >= now_epoch_seconds - 60 => {}
        Some(_) => return Err(bad("期限切れです")),
        None => return Err(bad("期限がありません")),
    }
    if claims.get("nonce").and_then(Value::as_str) != Some(nonce) {
        return Err(bad("別のログインのものです"));
    }
    let subject = claims
        .get("sub")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| bad("アカウントの識別子がありません"))?
        .to_string();
    let email = claims
        .get("email")
        .and_then(Value::as_str)
        .or_else(|| claims.get("https://api.openai.com/profile").and_then(|p| p.get("email")).and_then(Value::as_str))
        .map(String::from);
    Ok((subject, email))
}

// ---- 使うとき ----

/// このサインインで ChatGPT プランを使えるか (付与された scope にプラン利用があるか)。
pub fn can_use_plan(tokens: &ChatGptTokens) -> bool {
    tokens.scopes.iter().any(|s| s == PLAN_SCOPE)
}

/// アクセストークンを使う前に更新が要るか (期限の 5 分前を切っている)。
pub fn needs_refresh(tokens: &ChatGptTokens, now_epoch_seconds: i64) -> bool {
    tokens.expires_at - now_epoch_seconds <= REFRESH_MARGIN_SECONDS
}

/// 更新のフォーム本文。`scope` は送らない (送ると付与範囲が変わりうる)。
/// 更新用トークンが無ければ None (サインインし直してもらう)。
pub fn refresh_form(tokens: &ChatGptTokens, registration: &ChatGptRegistration) -> Option<String> {
    let refresh_token = tokens.refresh_token.as_deref()?;
    Some(form_body(&[
        ("grant_type", "refresh_token".into()),
        ("client_id", registration.client_id.clone()),
        ("refresh_token", refresh_token.to_string()),
        ("resource", RESOURCE.into()),
    ]))
}

/// 更新の結末。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum ChatGptRefreshOutcome {
    /// 新しいトークン。保存する (更新用トークンは毎回差し替わる)。
    Renewed { tokens: ChatGptTokens },
    /// 更新用トークンがもう使えない。保存したトークンを消して、ログインし直してもらう
    /// (登録は残すので、同じ client_id で入り直せる)。
    SignInAgain { message: String },
    /// 一時的な失敗。保存はそのまま。
    Failed { message: String },
}

/// 更新の応答を読む。
pub fn read_refresh(status: u16, body: &str, previous: &ChatGptTokens, now_epoch_seconds: i64) -> ChatGptRefreshOutcome {
    match read_token_response(status, body, Some(previous), &[], now_epoch_seconds) {
        Ok(tokens) => ChatGptRefreshOutcome::Renewed { tokens },
        Err(_) if is_unusable_refresh(body) => ChatGptRefreshOutcome::SignInAgain { message: sign_in_expired_message() },
        Err(e) => ChatGptRefreshOutcome::Failed { message: e.to_string() },
    }
}

/// ログインの期限切れの文言。更新用トークンが無い / もう使えないときに出す。
pub fn sign_in_expired_message() -> String {
    "ChatGPT のログインの期限が切れました。もう一度ログインしてください".into()
}

fn is_unusable_refresh(body: &str) -> bool {
    [
        "invalid_grant",
        "invalid_refresh_token",
        "token_expired",
        "refresh_token_expired",
        "refresh_token_invalidated",
        "refresh_token_reused",
    ]
    .iter()
    .any(|code| body.contains(code))
}

/// 失効 (サインアウト) のフォーム本文。
pub fn revoke_form(refresh_token: &str, client_id: &str) -> String {
    form_body(&[
        ("token", refresh_token.to_string()),
        ("token_type_hint", "refresh_token".into()),
        ("client_id", client_id.to_string()),
    ])
}

/// discovery の応答から失効エンドポイントを取り出す。https で発行元と同じホストのものだけ。
pub fn revocation_endpoint(discovery_body: &str) -> Option<String> {
    let v: Value = serde_json::from_str(discovery_body).ok()?;
    let url = v.get("revocation_endpoint")?.as_str()?;
    url.starts_with(&format!("{ISSUER}/")).then(|| url.to_string())
}

// ---- モデル ----

/// 選べるモデル 1 件。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChatGptModel {
    pub slug: String,
    /// 画面に出す名前。
    pub label: String,
}

/// モデル一覧の応答から、選ばせてよいもの (`visibility == "list"`) をサーバの並び順で返す。
pub fn read_models(body: &str) -> Vec<ChatGptModel> {
    let Ok(v) = serde_json::from_str::<Value>(body) else { return Vec::new() };
    let list = v.get("models").or_else(|| v.get("data")).and_then(Value::as_array);
    list.into_iter()
        .flatten()
        .filter(|m| m.get("visibility").and_then(Value::as_str) == Some("list"))
        .filter_map(|m| {
            let slug = m.get("slug").or_else(|| m.get("id")).and_then(Value::as_str).filter(|s| !s.is_empty())?;
            let label = m.get("display_name").and_then(Value::as_str).filter(|s| !s.is_empty()).unwrap_or(slug);
            Some(ChatGptModel { slug: slug.to_string(), label: label.to_string() })
        })
        .collect()
}

// ---- 推論 ----

/// Responses API のリクエスト本文。
///
/// この経路は `store: false` と `stream: true` が必須で、サンプリング系 (temperature 等) は送れない。
/// `input_items` / `tools_json` / `text_format_json` は JSON の文字列 (読めないものは落とす)。
pub fn responses_body(
    model: &str,
    instructions: &str,
    input_items: &[String],
    tools_json: &str,
    text_format_json: &str,
    include_encrypted_reasoning: bool,
) -> String {
    let input: Vec<Value> = input_items.iter().filter_map(|s| serde_json::from_str(s).ok()).collect();
    let mut body = json!({
        "model": model,
        "instructions": instructions,
        "input": input,
        "store": false,
        "stream": true,
    });
    // ツールを渡さない仕事 (画像の書き写し) は null で来るので、鍵ごと載せない。
    if let Some(tools) = serde_json::from_str::<Value>(tools_json).ok().filter(|t| !t.is_null()) {
        body["tools"] = tools;
    }
    if let Ok(format) = serde_json::from_str::<Value>(text_format_json) {
        body["text"] = json!({ "format": format });
    }
    if include_encrypted_reasoning {
        // store: false では推論項目が保存されないので、暗号化した中身ごと返してもらい、
        // 関数呼び出しの次の往復に積み直す。
        body["include"] = json!(["reasoning.encrypted_content"]);
    }
    body.to_string()
}

/// ストリームの 1 行の意味。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum ChatGptStreamEvent {
    /// 関係のない行。
    Ignored,
    /// 本文の断片。
    Delta { text: String },
    /// 関数呼び出しが始まった (進行表示用)。
    ToolCallStarted { name: String },
    /// 出力項目 1 件が確定した (JSON)。
    OutputItem { json: String },
    /// 正常に終わった。
    Completed,
    /// 失敗で終わった。
    Failed { failure: ChatGptFailure },
}

/// 推論の失敗。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChatGptFailure {
    /// 画面に出す文言。
    pub message: String,
    /// ChatGPT プランの利用上限に当たった (ChatGPT の設定へ案内する)。
    pub usage_limit: bool,
    /// ログインし直しが要る。
    pub sign_in_again: bool,
}

/// SSE の 1 行を読む。要るのは `data:` 行の JSON の `type` だけ。
pub fn read_stream_line(line: &str) -> ChatGptStreamEvent {
    let Some(payload) = line.strip_prefix("data:") else { return ChatGptStreamEvent::Ignored };
    let payload = payload.trim();
    if payload == "[DONE]" {
        return ChatGptStreamEvent::Ignored;
    }
    let Ok(object) = serde_json::from_str::<Value>(payload) else { return ChatGptStreamEvent::Ignored };
    let text = |v: &Value, key: &str| v.get(key).and_then(Value::as_str).map(String::from);
    match object.get("type").and_then(Value::as_str).unwrap_or("") {
        "response.output_text.delta" => match text(&object, "delta") {
            Some(delta) => ChatGptStreamEvent::Delta { text: delta },
            None => ChatGptStreamEvent::Ignored,
        },
        "response.output_item.added" => match object.get("item") {
            Some(item) if item.get("type").and_then(Value::as_str) == Some("function_call") => match text(item, "name") {
                Some(name) => ChatGptStreamEvent::ToolCallStarted { name },
                None => ChatGptStreamEvent::Ignored,
            },
            _ => ChatGptStreamEvent::Ignored,
        },
        "response.output_item.done" => match object.get("item") {
            Some(item) => ChatGptStreamEvent::OutputItem { json: item.to_string() },
            None => ChatGptStreamEvent::Ignored,
        },
        "response.completed" => ChatGptStreamEvent::Completed,
        "response.failed" => {
            let code = object.get("response").and_then(|r| r.get("error")).and_then(|e| text(e, "code"));
            ChatGptStreamEvent::Failed { failure: failure_for_code(code.as_deref()) }
        }
        "response.incomplete" => ChatGptStreamEvent::Failed {
            failure: plain_failure("応答が途中で終わりました。文を短くして試してください"),
        },
        "error" => ChatGptStreamEvent::Failed { failure: failure_for_code(text(&object, "code").as_deref()) },
        _ => ChatGptStreamEvent::Ignored,
    }
}

/// 完了の合図を受け取る前にストリームが切れたときの失敗。
pub fn stream_cut_off() -> ChatGptFailure {
    plain_failure("通信が途中で切れました。もう一度試してください")
}

/// HTTP の失敗 (2xx 以外) を説明する。
pub fn http_failure(status: u16, body: &str) -> ChatGptFailure {
    if let Some(code) = PLAN_ERROR_CODES.iter().find(|code| body.contains(*code)) {
        return failure_for_code(Some(code));
    }
    match status {
        401 => ChatGptFailure {
            message: "ChatGPT のログインを確認できませんでした。もう一度ログインしてください".into(),
            usage_limit: false,
            sign_in_again: true,
        },
        403 => plain_failure("この ChatGPT アカウントまたは地域では使えません"),
        429 => plain_failure("混み合っています。少し待ってから試してください"),
        500..=599 => plain_failure("ChatGPT 側で一時的に使えません。時間をおいて試してください"),
        _ => plain_failure("ChatGPT とのやりとりに失敗しました"),
    }
}

/// 推論のリクエストが HTTP の失敗 (2xx 以外) で返ったとき、次にどうするか。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum ChatGptHttpErrorAction {
    /// 推論の暗号化返却を受けない経路だった。それ無しで同じリクエストをやり直す
    /// (往復には数えない)。
    RetryWithoutReasoning,
    /// 組み込みツール (Web 検索・画像の生成) を受けない経路だった。それらを外した `tools` で同じリクエストをやり直す
    /// (外したものが無い仕事なら、失敗として終える)。
    RetryWithoutBuiltInTools,
    /// 失敗として終える。
    Fail { failure: ChatGptFailure },
}

/// `include_encrypted_reasoning` は、失敗したリクエストに暗号化返却を付けていたか。
/// 付けていなかったのに同じ理由で落ちたなら、やり直さず失敗にする (やり直しは 1 回だけ)。
pub fn http_error_action(status: u16, body: &str, include_encrypted_reasoning: bool) -> ChatGptHttpErrorAction {
    if include_encrypted_reasoning && status == 400 && (body.contains("include") || body.contains("encrypted")) {
        return ChatGptHttpErrorAction::RetryWithoutReasoning;
    }
    if status == 400 && (body.contains("web_search") || body.contains("image_generation")) {
        return ChatGptHttpErrorAction::RetryWithoutBuiltInTools;
    }
    ChatGptHttpErrorAction::Fail { failure: http_failure(status, body) }
}

const PLAN_ERROR_CODES: [&str; 5] = [
    "subscription_sharing_user_not_eligible",
    "subscription_sharing_usage_limit_exceeded",
    "subscription_sharing_usage_unavailable",
    "subscription_sharing_user_unavailable",
    "subscription_sharing_invalid_user",
];

/// errors-and-recovery の表のうち、利用者に伝わる言い方が要るもの。
fn failure_for_code(code: Option<&str>) -> ChatGptFailure {
    match code {
        Some("subscription_sharing_user_not_eligible") => {
            plain_failure("このアカウントでは ChatGPT プランを使えません (Plus か Pro が要ります)")
        }
        Some("subscription_sharing_usage_limit_exceeded") => ChatGptFailure {
            message: "ChatGPT プランの利用上限に達しました。ChatGPT の設定の使用状況で確認できます".into(),
            usage_limit: true,
            sign_in_again: false,
        },
        Some("subscription_sharing_usage_unavailable") | Some("subscription_sharing_user_unavailable") => {
            plain_failure("ChatGPT 側で一時的に利用状況を確認できません。時間をおいて試してください")
        }
        Some("subscription_sharing_invalid_user") => ChatGptFailure {
            message: "アカウントを確認できませんでした。もう一度ログインしてください".into(),
            usage_limit: false,
            sign_in_again: true,
        },
        _ => plain_failure("うまく探せませんでした。もう一度試してください"),
    }
}

fn plain_failure(message: &str) -> ChatGptFailure {
    ChatGptFailure { message: message.to_string(), usage_limit: false, sign_in_again: false }
}

// ---- 小物 ----

fn split_scopes(scope: &str) -> Vec<String> {
    let mut scopes: Vec<String> = scope.split_whitespace().map(String::from).collect();
    scopes.sort();
    scopes.dedup();
    scopes
}

/// `/path?query` を分ける。絶対 URL (`http://127.0.0.1:1455/auth/callback?...`) でも読む。
fn split_target(target: &str) -> (&str, &str) {
    // 絶対 URL として読むのは頭が http(s):// のときだけ。クエリの中の `://`
    // (`error_uri=https://…`) を区切りと取り違えない。
    let rest = match target.strip_prefix("http://").or_else(|| target.strip_prefix("https://")) {
        Some(after) => after.find('/').map(|j| &after[j..]).unwrap_or(""),
        None => target,
    };
    let rest = rest.split('#').next().unwrap_or("");
    match rest.split_once('?') {
        Some((path, query)) => (path, query),
        None => (rest, ""),
    }
}

/// クエリから鍵の最初の値を取り出す (percent と `+` を解く)。
fn query_value(query: &str, key: &str) -> Option<String> {
    query.split('&').find_map(|pair| {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        (form_decode(k) == key).then(|| form_decode(v))
    })
}

/// `application/x-www-form-urlencoded` の本文。英数字と `-._~` 以外は全部符号化する
/// (`+` や `@` を素通しすると受け側で空白や区切りに化ける)。
fn form_body(items: &[(&str, String)]) -> String {
    items.iter().map(|(k, v)| format!("{}={}", form_encode(k), form_encode(v))).collect::<Vec<_>>().join("&")
}

fn form_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            out.push(byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

fn form_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => match (hex_value(bytes[i + 1]), hex_value(bytes[i + 2])) {
                (Some(high), Some(low)) => {
                    out.push(high << 4 | low);
                    i += 2;
                }
                _ => out.push(b'%'),
            },
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

const B64URL: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// 詰め物なしの base64url。
fn base64url_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = (chunk[0] as u32) << 16 | (*chunk.get(1).unwrap_or(&0) as u32) << 8 | *chunk.get(2).unwrap_or(&0) as u32;
        out.push(B64URL[(n >> 18) as usize & 63] as char);
        out.push(B64URL[(n >> 12) as usize & 63] as char);
        if chunk.len() > 1 {
            out.push(B64URL[(n >> 6) as usize & 63] as char);
        }
        if chunk.len() > 2 {
            out.push(B64URL[n as usize & 63] as char);
        }
    }
    out
}

/// base64url を解く (詰め物はあっても無くてもよい。標準の `+` `/` も受ける)。
fn base64url_decode(text: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(text.len() * 3 / 4);
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for byte in text.bytes() {
        let value = match byte {
            b'A'..=b'Z' => byte - b'A',
            b'a'..=b'z' => byte - b'a' + 26,
            b'0'..=b'9' => byte - b'0' + 52,
            b'-' | b'+' => 62,
            b'_' | b'/' => 63,
            b'=' => break,
            _ => return None,
        };
        buffer = buffer << 6 | value as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
            buffer &= (1 << bits) - 1;
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_800_000_000;

    fn random() -> Vec<u8> {
        (0..ATTEMPT_RANDOM_BYTES).map(|i| (i * 7 + 3) as u8).collect()
    }

    fn registration() -> ChatGptRegistration {
        ChatGptRegistration { client_id: "oaiapp_saved".into(), subject: "user-1".into(), email: Some("p+1@example.com".into()) }
    }

    fn begin(intent: ChatGptSignInIntent, reg: Option<&ChatGptRegistration>, pending: Option<&str>) -> ChatGptAttempt {
        begin_sign_in(intent, reg, pending, Some("saved.id.token"), "urn:uuid:abc", 1455, &random()).unwrap()
    }

    fn id_token(claims: Value) -> String {
        format!("e30.{}.sig", base64url_encode(claims.to_string().as_bytes()))
    }

    fn claims(attempt: &ChatGptAttempt, client_id: &str, sub: &str) -> Value {
        json!({ "iss": ISSUER, "aud": client_id, "exp": NOW + 600, "nonce": attempt.nonce, "sub": sub, "email": "p@example.com" })
    }

    fn token_body(id_token: &str) -> String {
        json!({ "access_token": "at", "refresh_token": "rt", "id_token": id_token, "expires_in": 3600 }).to_string()
    }

    #[test]
    fn base64urlは公開の例と往復で合う() {
        assert_eq!(base64url_encode(b""), "");
        assert_eq!(base64url_encode(b"f"), "Zg");
        assert_eq!(base64url_encode(b"fo"), "Zm8");
        assert_eq!(base64url_encode(b"foobar"), "Zm9vYmFy");
        assert_eq!(base64url_encode(&[0xfb, 0xff]), "-_8");
        for n in 0..70usize {
            let bytes: Vec<u8> = (0..n).map(|i| (i * 37 + 11) as u8).collect();
            assert_eq!(base64url_decode(&base64url_encode(&bytes)).unwrap(), bytes);
        }
        assert_eq!(base64url_decode("Zg==").unwrap(), b"f");
        assert!(base64url_decode("Z g").is_none());
    }

    #[test]
    fn code_challengeはrfc7636の例と合う() {
        // RFC 7636 Appendix B。
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        assert_eq!(base64url_encode(&sha256_digest(verifier.as_bytes())), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
    }

    #[test]
    fn 初回は登録用のclient_idで名前のヒントを付ける() {
        let a = begin(ChatGptSignInIntent::SignIn, None, None);
        assert!(a.is_new_registration);
        assert!(!a.is_same_registration);
        assert_eq!(a.client_id, DYNAMIC_CLIENT_ID);
        assert_eq!(a.redirect_uri, "http://127.0.0.1:1455/auth/callback");
        assert!(a.authorize_url.starts_with("https://auth.openai.com/api/accounts/authorize?client_id=dynamic_agent_client&"));
        assert!(a.authorize_url.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback"));
        assert!(a.authorize_url.contains("scope=openid%20profile%20email%20offline_access%20resource.invoke%20chatgpt.tokens.use.direct"));
        assert!(a.authorize_url.contains("code_challenge_method=S256"));
        assert!(a.authorize_url.contains("agent_name_hint="));
        assert!(!a.authorize_url.contains("id_token_hint"));
        assert!(!a.authorize_url.contains("prompt="));
        // state / nonce / verifier は別々の乱数から作る。
        assert_ne!(a.state, a.nonce);
        assert_eq!(a.code_verifier.len(), 86);
    }

    #[test]
    fn 保存済みの登録があれば同じclient_idで入り直しヒントを付ける() {
        let reg = registration();
        let a = begin(ChatGptSignInIntent::SignIn, Some(&reg), Some("oaiapp_pending"));
        assert!(!a.is_new_registration);
        assert!(a.is_same_registration);
        assert_eq!(a.client_id, "oaiapp_saved");
        assert!(a.authorize_url.contains("id_token_hint=saved.id.token"));
        // `+` と `@` は符号化する。
        assert!(a.authorize_url.contains("login_hint=p%2B1%40example.com"));
        assert!(!a.authorize_url.contains("agent_name_hint"));
        assert!(!a.authorize_url.contains("prompt="));
    }

    #[test]
    fn 許可の取り直しは同意画面を出させる() {
        let reg = registration();
        let a = begin(ChatGptSignInIntent::EnablePlan, Some(&reg), None);
        assert!(a.authorize_url.contains("prompt=consent"));
        // 登録が無いのに許可の取り直しを頼まれたら、ただの初回登録。
        let fresh = begin(ChatGptSignInIntent::EnablePlan, None, None);
        assert!(fresh.is_new_registration);
        assert!(!fresh.authorize_url.contains("prompt="));
    }

    #[test]
    fn 途中で落ちた登録のclient_idは使い回すがヒントは付けない() {
        let a = begin(ChatGptSignInIntent::SignIn, None, Some("oaiapp_pending"));
        assert_eq!(a.client_id, "oaiapp_pending");
        assert!(!a.is_new_registration);
        assert!(!a.is_same_registration);
        assert!(!a.authorize_url.contains("id_token_hint"));
    }

    #[test]
    fn 別のアカウントは保存済みの登録を使わない() {
        let reg = registration();
        let a = begin(ChatGptSignInIntent::NewAccount, Some(&reg), Some("oaiapp_pending"));
        assert_eq!(a.client_id, DYNAMIC_CLIENT_ID);
        assert!(a.is_new_registration);
    }

    #[test]
    fn 乱数が足りなければ始めない() {
        let r = begin_sign_in(ChatGptSignInIntent::SignIn, None, None, None, "h", 1, &[0u8; 127]);
        assert_eq!(r, Err(ChatGptAuthError::NotEnoughRandom));
    }

    #[test]
    fn callbackはパスとstateが合うものだけ受ける() {
        let a = begin(ChatGptSignInIntent::SignIn, None, None);
        assert!(is_expected_callback(&format!("/auth/callback?code=c&state={}", a.state), &a));
        assert!(is_expected_callback(&format!("http://127.0.0.1:1455/auth/callback?state={}&code=c", a.state), &a));
        assert!(!is_expected_callback("/auth/callback?code=c&state=other", &a));
        assert!(!is_expected_callback(&format!("/favicon.ico?state={}", a.state), &a));
        assert!(!is_expected_callback("/auth/callback", &a));
        assert!(callback_is_error("/auth/callback?error=access_denied&state=x"));
        assert!(!callback_is_error("/auth/callback?code=c"));
    }

    #[test]
    fn 初回登録のcallbackは発行されたclient_idを採り控えさせる() {
        let a = begin(ChatGptSignInIntent::SignIn, None, None);
        let cb = read_callback(
            &format!("/auth/callback?code=the%2Bcode&state={}&client_id=oaiapp_new&scope=openid+chatgpt.tokens.use.direct", a.state),
            &a,
        )
        .unwrap();
        assert_eq!(cb.code, "the+code");
        assert_eq!(cb.client_id, "oaiapp_new");
        assert_eq!(cb.scopes, vec!["chatgpt.tokens.use.direct", "openid"]);
        assert!(cb.remember_as_pending);
        assert!(cb.exchange_form.contains("grant_type=authorization_code"));
        assert!(cb.exchange_form.contains("client_id=oaiapp_new"));
        assert!(cb.exchange_form.contains("code=the%2Bcode"));
        assert!(cb.exchange_form.contains(&format!("code_verifier={}", a.code_verifier)));

        // 発行された ID が無い / 登録用の ID のままなら、登録は終わっていない。
        for target in [
            format!("/auth/callback?code=c&state={}", a.state),
            format!("/auth/callback?code=c&state={}&client_id=dynamic_agent_client", a.state),
        ] {
            assert_eq!(read_callback(&target, &a), Err(ChatGptAuthError::RegistrationIncomplete));
        }
    }

    #[test]
    fn 再認可のcallbackは違うclient_idを弾き省略は許す() {
        let reg = registration();
        let a = begin(ChatGptSignInIntent::SignIn, Some(&reg), None);
        let ok = read_callback(&format!("/auth/callback?code=c&state={}", a.state), &a).unwrap();
        assert_eq!(ok.client_id, "oaiapp_saved");
        assert!(!ok.remember_as_pending);
        assert!(ok.scopes.is_empty());
        assert_eq!(
            read_callback(&format!("/auth/callback?code=c&state={}&client_id=oaiapp_other", a.state), &a),
            Err(ChatGptAuthError::ClientMismatch("oaiapp_other".into()))
        );
    }

    #[test]
    fn callbackのエラーはstateを先に照合してから読む() {
        let a = begin(ChatGptSignInIntent::SignIn, None, None);
        assert_eq!(read_callback("/auth/callback?error=access_denied&state=other", &a), Err(ChatGptAuthError::StateMismatch));
        assert_eq!(
            read_callback(&format!("/auth/callback?error=access_denied&state={}", a.state), &a),
            Err(ChatGptAuthError::AccessDenied(String::new()))
        );
        assert_eq!(
            read_callback(&format!("/auth/callback?error=server_error&error_description=boom&state={}", a.state), &a),
            Err(ChatGptAuthError::OAuth("server_error — boom".into()))
        );
        assert_eq!(read_callback(&format!("/auth/callback?state={}", a.state), &a), Err(ChatGptAuthError::MissingCode));
    }

    #[test]
    fn 初回のサインインは登録とトークンを返しscopeはcallbackのものを採る() {
        let a = begin(ChatGptSignInIntent::SignIn, None, None);
        let cb = read_callback(
            &format!("/auth/callback?code=c&state={}&client_id=oaiapp_new&scope=openid%20chatgpt.tokens.use.direct", a.state),
            &a,
        )
        .unwrap();
        let body = token_body(&id_token(claims(&a, "oaiapp_new", "user-1")));
        let ChatGptSignInOutcome::Accepted { registration, tokens, revoke_previous } =
            finish_sign_in(&a, &cb, 200, &body, None, NOW).unwrap()
        else {
            panic!("通るはず")
        };
        assert_eq!(registration, ChatGptRegistration { client_id: "oaiapp_new".into(), subject: "user-1".into(), email: Some("p@example.com".into()) });
        assert_eq!(tokens.access_token, "at");
        assert_eq!(tokens.refresh_token.as_deref(), Some("rt"));
        assert_eq!(tokens.expires_at, NOW + 3600);
        assert!(can_use_plan(&tokens));
        assert!(!revoke_previous);
    }

    #[test]
    fn 同じ登録で別のアカウントが返ったら保存を変えず受け取ったものを失効させる() {
        let reg = registration();
        let a = begin(ChatGptSignInIntent::SignIn, Some(&reg), None);
        let cb = read_callback(&format!("/auth/callback?code=c&state={}", a.state), &a).unwrap();
        let body = token_body(&id_token(claims(&a, "oaiapp_saved", "someone-else")));
        let ChatGptSignInOutcome::DifferentAccount { revoke_form, .. } = finish_sign_in(&a, &cb, 200, &body, Some(&reg), NOW).unwrap() else {
            panic!("別アカウントのはず")
        };
        let form = revoke_form.unwrap();
        assert!(form.contains("token=rt") && form.contains("client_id=oaiapp_saved"));
    }

    #[test]
    fn 別のアカウントへの切り替えは前のセッションを失効させる() {
        let reg = registration();
        let a = begin(ChatGptSignInIntent::NewAccount, Some(&reg), None);
        let cb = read_callback(&format!("/auth/callback?code=c&state={}&client_id=oaiapp_new", a.state), &a).unwrap();
        let body = token_body(&id_token(claims(&a, "oaiapp_new", "someone-else")));
        let ChatGptSignInOutcome::Accepted { revoke_previous, .. } = finish_sign_in(&a, &cb, 200, &body, Some(&reg), NOW).unwrap() else {
            panic!("通るはず")
        };
        assert!(revoke_previous);
    }

    #[test]
    fn idトークンは発行元と宛先と期限とnonceを照合する() {
        let a = begin(ChatGptSignInIntent::SignIn, None, None);
        let cb = read_callback(&format!("/auth/callback?code=c&state={}&client_id=oaiapp_new", a.state), &a).unwrap();
        let finish = |c: Value| finish_sign_in(&a, &cb, 200, &token_body(&id_token(c)), None, NOW);
        let good = claims(&a, "oaiapp_new", "user-1");
        assert!(finish(good.clone()).is_ok());

        let mut wrong = good.clone();
        wrong["iss"] = json!("https://evil.example");
        assert!(matches!(finish(wrong), Err(ChatGptAuthError::IdToken(_))));
        let mut wrong = good.clone();
        wrong["aud"] = json!("oaiapp_other");
        assert!(matches!(finish(wrong), Err(ChatGptAuthError::IdToken(_))));
        let mut wrong = good.clone();
        wrong["exp"] = json!(NOW - 61);
        assert!(matches!(finish(wrong), Err(ChatGptAuthError::IdToken(_))));
        let mut wrong = good.clone();
        wrong.as_object_mut().unwrap().remove("exp");
        assert!(matches!(finish(wrong), Err(ChatGptAuthError::IdToken(_))));
        let mut wrong = good.clone();
        wrong["nonce"] = json!("other");
        assert!(matches!(finish(wrong), Err(ChatGptAuthError::IdToken(_))));
        let mut wrong = good.clone();
        wrong.as_object_mut().unwrap().remove("sub");
        assert!(matches!(finish(wrong), Err(ChatGptAuthError::IdToken(_))));

        // aud は配列でもよい。email は profile の中にあってもよい。
        let mut alt = good.clone();
        alt["aud"] = json!(["x", "oaiapp_new"]);
        alt.as_object_mut().unwrap().remove("email");
        alt["https://api.openai.com/profile"] = json!({ "email": "q@example.com" });
        let ChatGptSignInOutcome::Accepted { registration, .. } = finish(alt).unwrap() else { panic!() };
        assert_eq!(registration.email.as_deref(), Some("q@example.com"));

        // ID トークンが無い / 交換が失敗 / 読めない応答。
        assert!(matches!(
            finish_sign_in(&a, &cb, 200, r#"{"access_token":"at"}"#, None, NOW),
            Err(ChatGptAuthError::IdToken(_))
        ));
        assert_eq!(finish_sign_in(&a, &cb, 400, "{}", None, NOW), Err(ChatGptAuthError::TokenEndpoint(400)));
        assert_eq!(finish_sign_in(&a, &cb, 200, "<html>", None, NOW), Err(ChatGptAuthError::UnreadableResponse));
    }

    fn saved_tokens() -> ChatGptTokens {
        ChatGptTokens {
            access_token: "old".into(),
            refresh_token: Some("rt-old".into()),
            id_token: Some("id-old".into()),
            scopes: vec![PLAN_SCOPE.into(), "openid".into()],
            expires_at: NOW + 301,
        }
    }

    #[test]
    fn 更新は期限の5分前からで省かれた項目は前のものを引き継ぐ() {
        let tokens = saved_tokens();
        assert!(!needs_refresh(&tokens, NOW));
        assert!(needs_refresh(&tokens, NOW + 1));

        let form = refresh_form(&tokens, &registration()).unwrap();
        assert!(form.contains("grant_type=refresh_token") && form.contains("refresh_token=rt-old"));
        assert!(!form.contains("scope="));
        assert!(refresh_form(&ChatGptTokens { refresh_token: None, ..tokens.clone() }, &registration()).is_none());

        let ChatGptRefreshOutcome::Renewed { tokens: renewed } =
            read_refresh(200, r#"{"access_token":"new","refresh_token":"rt-new","expires_in":100}"#, &tokens, NOW)
        else {
            panic!("更新できるはず")
        };
        assert_eq!(renewed.access_token, "new");
        assert_eq!(renewed.refresh_token.as_deref(), Some("rt-new"));
        assert_eq!(renewed.id_token.as_deref(), Some("id-old"));
        assert_eq!(renewed.scopes, tokens.scopes);
        assert_eq!(renewed.expires_at, NOW + 100);

        // 応答が scope を返したらそちらを採る (許可が外された)。
        let ChatGptRefreshOutcome::Renewed { tokens: narrowed } =
            read_refresh(200, r#"{"access_token":"new","scope":"openid"}"#, &tokens, NOW)
        else {
            panic!()
        };
        assert!(!can_use_plan(&narrowed));
        assert_eq!(narrowed.refresh_token.as_deref(), Some("rt-old"));
    }

    #[test]
    fn 使えない更新用トークンはログインし直しで一時的な失敗は保存を残す() {
        let tokens = saved_tokens();
        assert!(matches!(
            read_refresh(400, r#"{"error":"invalid_grant"}"#, &tokens, NOW),
            ChatGptRefreshOutcome::SignInAgain { .. }
        ));
        assert!(matches!(read_refresh(503, "busy", &tokens, NOW), ChatGptRefreshOutcome::Failed { .. }));
    }

    #[test]
    fn 壊れた期限でもあふれず範囲に収まる() {
        let tokens = saved_tokens();
        for (expires_in, want) in [("1e300", 2_592_000), ("-5", 60), ("0", 60)] {
            let body = format!(r#"{{"access_token":"new","expires_in":{expires_in}}}"#);
            let ChatGptRefreshOutcome::Renewed { tokens: renewed } = read_refresh(200, &body, &tokens, NOW) else { panic!() };
            assert_eq!(renewed.expires_at, NOW + want, "{expires_in}");
        }
        let ChatGptRefreshOutcome::Renewed { tokens: far } =
            read_refresh(200, r#"{"access_token":"new"}"#, &tokens, i64::MAX)
        else {
            panic!()
        };
        assert_eq!(far.expires_at, i64::MAX);
    }

    #[test]
    fn 途中で残ったclient_idは認可エラーのときだけ捨てる() {
        let oauth = ChatGptAuthError::OAuth("invalid_client".into());
        let pending = begin(ChatGptSignInIntent::SignIn, None, Some("oaiapp_pending"));
        assert!(should_forget_pending(&pending, &oauth));
        assert!(!should_forget_pending(&pending, &ChatGptAuthError::AccessDenied(String::new())));
        assert!(!should_forget_pending(&pending, &ChatGptAuthError::StateMismatch));
        let reg = registration();
        assert!(!should_forget_pending(&begin(ChatGptSignInIntent::SignIn, Some(&reg), None), &oauth));
        assert!(!should_forget_pending(&begin(ChatGptSignInIntent::SignIn, None, None), &oauth));
    }

    #[test]
    fn 失効エンドポイントは発行元のものだけ採る() {
        assert_eq!(
            revocation_endpoint(r#"{"revocation_endpoint":"https://auth.openai.com/oauth/revoke"}"#).as_deref(),
            Some("https://auth.openai.com/oauth/revoke")
        );
        assert!(revocation_endpoint(r#"{"revocation_endpoint":"https://auth.openai.com.evil.example/revoke"}"#).is_none());
        assert!(revocation_endpoint(r#"{"revocation_endpoint":"http://auth.openai.com/revoke"}"#).is_none());
        assert!(revocation_endpoint("{}").is_none());
    }

    #[test]
    fn モデルは一覧に出すものだけをサーバの順で返す() {
        let body = json!({ "models": [
            { "slug": "b", "display_name": "B", "visibility": "list" },
            { "slug": "hidden", "visibility": "hide" },
            { "slug": "a", "visibility": "list" },
        ]})
        .to_string();
        assert_eq!(
            read_models(&body),
            vec![ChatGptModel { slug: "b".into(), label: "B".into() }, ChatGptModel { slug: "a".into(), label: "a".into() }]
        );
        assert!(read_models("oops").is_empty());
    }

    #[test]
    fn リクエスト本文はstore_falseとstream_trueで読めない項目は落とす() {
        let body: Value = serde_json::from_str(&responses_body(
            "m",
            "指示",
            &[r#"{"role":"user","content":"q"}"#.to_string(), "{broken".to_string()],
            r#"[{"type":"namespace"}]"#,
            r#"{"type":"json_schema"}"#,
            true,
        ))
        .unwrap();
        assert_eq!(body["store"], false);
        assert_eq!(body["stream"], true);
        assert_eq!(body["input"].as_array().unwrap().len(), 1);
        assert_eq!(body["tools"][0]["type"], "namespace");
        assert_eq!(body["text"]["format"]["type"], "json_schema");
        assert_eq!(body["include"], json!(["reasoning.encrypted_content"]));
        assert!(body.get("temperature").is_none());

        let plain: Value = serde_json::from_str(&responses_body("m", "", &[], "", "", false)).unwrap();
        assert!(plain.get("tools").is_none() && plain.get("text").is_none() && plain.get("include").is_none());
    }

    #[test]
    fn ストリームの行を読み分ける() {
        use ChatGptStreamEvent::*;
        assert_eq!(read_stream_line("event: x"), Ignored);
        assert_eq!(read_stream_line("data: [DONE]"), Ignored);
        assert_eq!(read_stream_line("data: {broken"), Ignored);
        assert_eq!(
            read_stream_line(r#"data: {"type":"response.output_text.delta","delta":"あ"}"#),
            Delta { text: "あ".into() }
        );
        assert_eq!(
            read_stream_line(r#"data:{"type":"response.output_item.added","item":{"type":"function_call","name":"search"}}"#),
            ToolCallStarted { name: "search".into() }
        );
        assert_eq!(
            read_stream_line(r#"data: {"type":"response.output_item.added","item":{"type":"message"}}"#),
            Ignored
        );
        assert!(matches!(
            read_stream_line(r#"data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"c"}}"#),
            OutputItem { .. }
        ));
        assert_eq!(read_stream_line(r#"data: {"type":"response.completed"}"#), Completed);

        let Failed { failure } = read_stream_line(
            r#"data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#,
        ) else {
            panic!()
        };
        assert!(failure.usage_limit && !failure.sign_in_again);
        let Failed { failure } = read_stream_line(r#"data: {"type":"error","code":"subscription_sharing_invalid_user"}"#) else {
            panic!()
        };
        assert!(failure.sign_in_again);
        assert!(matches!(read_stream_line(r#"data: {"type":"response.incomplete"}"#), Failed { .. }));
    }

    #[test]
    fn httpの失敗は本文のコードを優先して説明する() {
        assert!(http_failure(429, r#"{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}"#).usage_limit);
        assert!(!http_failure(429, "slow down").usage_limit);
        assert!(http_failure(401, "").sign_in_again);
        assert!(!http_failure(503, "").sign_in_again);
        // 失敗の文言に、サーバが返した本文をそのまま載せない。
        assert!(!http_failure(500, "secret-detail").message.contains("secret-detail"));

        use ChatGptHttpErrorAction::*;
        assert_eq!(http_error_action(400, "unsupported include", true), RetryWithoutReasoning);
        assert_eq!(http_error_action(400, "Unsupported tool type: web_search", false), RetryWithoutBuiltInTools);
        assert_eq!(http_error_action(400, "Unknown tool: image_generation", false), RetryWithoutBuiltInTools);
        // やり直しは 1 回だけ。付けていないのに同じ理由で落ちたら失敗にする。
        assert!(matches!(http_error_action(400, "unsupported include", false), Fail { .. }));
        assert!(matches!(http_error_action(400, "bad model", true), Fail { .. }));
        assert!(matches!(http_error_action(500, "include", true), Fail { .. }));
    }

    #[test]
    fn 小物() {
        assert_eq!(host_id(" ABCD-12 "), "urn:uuid:abcd-12");
        assert_eq!(form_decode("a%2Bb+c%"), "a+b c%");
        assert_eq!(form_decode("%E3%81%82"), "あ");
        assert_eq!(form_decode("%zz"), "%zz");
        assert_eq!(split_target("/a/b?x=1#f"), ("/a/b", "x=1"));
        assert_eq!(split_target("http://h:1/a?x=1"), ("/a", "x=1"));
        assert_eq!(split_target("/a"), ("/a", ""));
        assert_eq!(split_target("/a?error_uri=https://x.example/y"), ("/a", "error_uri=https://x.example/y"));
        assert_eq!(split_target("http://h:1"), ("", ""));
        assert_eq!(query_value("a=1&b=2&a=3", "a").as_deref(), Some("1"));
        assert_eq!(query_value("flag", "flag").as_deref(), Some(""));
        assert_eq!(query_value("a=1", "b"), None);
    }
}
