//! 認証セッションと admin 権限の判定。純粋ロジック (通信・保存は呼び出し側)。
//!
//! iOS `Services/AuthService.swift` が持っていた判断だけを移したもの。移送対象は
//! 「保存済みトークンをどう扱うか」「サーバが返したトークンを採用してよいか」
//! 「/auth/refresh を投げるか」「ログイン交換をリトライするか」
//! 「Apple 資格情報が失効した時にサインアウトするか」「admin で何ができるか」。
//! HTTP 通信・Keychain/EncryptedSharedPreferences・UI 更新は移していない。
//!
//! ## iOS が正
//! Android (`data/auth/AuthService.kt`) は同じ役目をより浅く実装していて、
//! セッションの claim 検証も再発行も持っていない。規則としては iOS を採り、
//! Android がここに繋がる時に挙動が変わるのは以下:
//!
//! - サインイン済みの判定: iOS は userId の有無、Android は sessionToken の有無。
//!   ここでは userId を見る ([`restore_stored_state`])。
//! - `/auth/me` が空文字の表示名を返した時: iOS は値として採用し表示名が空になる。
//!   Android は空を「無し」として既存名を残していた。ここでは iOS 側を採る
//!   ([`apply_me_response`])。
//! - `/auth/login` が表示名を空/欠落で返した時は、どちらも既存名を保つ
//!   ([`adopt_session_response`])。Android は保存に null を書いていたが、
//!   ここでは「変更しない」に統一する。
//! - 保存フラグ: iOS は文字列 "1"/"0"、Android は真偽値。ここでは iOS の表現
//!   ([`stored_flag_value`] / [`decode_stored_flag`]) を正とする。
//!
//! ## ログイン/BAN による編集可否はここではない
//! 「ログイン済みか」「BAN されているか」だけで決まるオープン編集の可否は
//! [`crate::domain::edit_permission_rules`] が正 (Phase 1 で移送済み)。
//! こちらは **セッション寿命** と **admin 権限** だけを扱う。二重定義しないこと。
//!
//! ## 時刻
//! OS 時計は触らない。期限判定はすべて `now_epoch_seconds` 引数で受ける
//! (Swift の `Date().timeIntervalSince1970` 相当を呼び出し側が渡す)。
//!
//! ## `/auth/login` と `/auth/refresh` は同じ型を通る
//! [`SessionResponse`] / [`SessionAdoption`] は両方のエンドポイントで使い回す。
//! 反映する状態が微妙に違うので、差は [`SessionAdoption`] のフィールドで表す
//! (`None` = 変更しない)。呼び出し側が login/refresh を見分ける必要は無い。
//!
//! ## 意図的な原本との差分 (divergence)
//!
//! JWT の claim を取り出す経路は原本 (`Data(base64Encoded:)` + `JSONSerialization`) を
//! 再現してあるが、**2 点だけ意図的に厳しくしてある**。どちらも Foundation 側の
//! 不具合と見てよい挙動で、真似すると Android にまで移植することになる。
//! どちらも「Rust が受け付けない」向きなので、緩い側に倒れる危険は無い。
//!
//! 1. **JSON 文字列の中の単独バイト `0xA9`**。原本はこれだけを U+FFFD に置き換えて
//!    解析を通す (0x80〜0xFF の他の 127 バイトはすべて nil。切り詰めた多バイト列・
//!    overlong・CESU-8 のサロゲートも nil)。1 バイトだけ通るのは筋が通らないので
//!    再現しない — ここでは不正な UTF-8 は一律 nil 相当にする。
//! 2. **閉じ括弧直前の余分なカンマ** (`{"exp":1,}` `[1,2,]`)。原本は 1 個だけ許す
//!    (先頭カンマ・二重カンマ・引用符なしキー・コメント・NaN 等は他と同じく nil)。
//!    serde_json は JSON の文法どおり拒否する。ここを合わせるには JSON パーサ自体を
//!    差し替える必要があり、得るものに対して代償が大きい。
//!
//! 到達経路: 自前 Worker (`imas-live-api/src/auth.ts`) は UTF-8 の compact JWT しか
//! 出さないので正規経路では踏まない。踏むのは保存領域を書き換えられた端末か、
//! 汚染されたサーバ応答だけ。上記いずれも Rust 側が「捨てる」に倒れる。
//!
//! これ以外の入力クラス (UTF-16/32・BOM・重複キー・数値の精度・base64 の厳密さ・
//! 空セグメント) は原本と一致することをテストで押さえてある。
//!
//! ## ⚠️ 送信前チェックを増やさないこと
//! 「トークンが期限切れっぽいから送らない」という事前判定は **作ってはいけない**。
//! 過去に投票系で送信前に bearerToken を検査した結果、401 → 自動リフレッシュ →
//! 再送 の経路が死んで無言で失敗する事故が起きた。失効の検知はサーバの 401 が正で、
//! ここにあるのは「起動時の復元」「サーバ応答の採用可否」「refresh を投げる価値があるか」
//! であって、リクエスト送信のゲートではない。

use serde::de::{Deserializer, MapAccess, Visitor};
use serde::Deserialize;
use serde_json::Value as JsonValue;
use std::borrow::Cow;

// ── サーバ (Worker) と揃える定数 ─────────────────────────────

/// sessionToken (Worker 発行 HS256) の期待 claim。Worker 側
/// SESSION_JWT_ISSUER / SESSION_JWT_AUDIENCE / 署名アルゴリズムと一致させる。
const SESSION_TOKEN_ISSUER: &str = "imas-live-db";
const SESSION_TOKEN_AUDIENCE: &str = "imas-live-db-ios";
const SESSION_TOKEN_ALG: &str = "HS256";

/// 期限判定の余裕 (秒)。残り 60 秒以下のトークンは「もう使えない」とみなす。
/// 送信中に切れて 401 になるのを避けるためのマージン。
const EXPIRY_MARGIN_SECONDS: f64 = 60.0;

/// 「期限が近い」の既定しきい値 = 7 日。起動時の先回り更新に使う。
const NEAR_EXPIRY_SECONDS: f64 = 60.0 * 60.0 * 24.0 * 7.0;

/// identityToken を sessionToken に交換する試行回数。identityToken 自体が
/// 10 分で切れるので、粘っても無駄になる前に諦める。
const TOKEN_EXCHANGE_MAX_ATTEMPTS: u32 = 3;

/// 交換失敗時の待ち時間 (ミリ秒)。
const TOKEN_EXCHANGE_RETRY_DELAY_MILLIS: u64 = 1_500;

/// Apple ID 資格情報が revoked に見えた時、確定させる前に置く間隔 (ミリ秒)。
/// 端末が一時的に revoked を返すことがあり、即サインアウトすると誤爆する。
const CREDENTIAL_RECHECK_DELAY_MILLIS: u64 = 2_000;

/// Keychain は文字列しか持てないので bool は "1"/"0" で保存する。
const STORED_FLAG_TRUE: &str = "1";
const STORED_FLAG_FALSE: &str = "0";

// ── 型 ───────────────────────────────────────────────────

/// 保存済み sessionToken の扱い。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SessionTokenDisposition {
    /// そもそも保存されていない。
    Absent,
    /// claims 妥当・期限に余裕あり → そのまま使う。
    Use,
    /// 使えるが期限が近い → 使いつつ、先回りで再発行を投げる。
    UseAndRefresh,
    /// 期限切れだが形・iss/aud は妥当 → 保存は残したまま再発行を試す
    /// (署名が生きていればサーバが猶予内と判断して再発行してくれる = Apple 再認証が要らない)。
    RefreshOnly,
    /// claims が不正で再発行も望めない → 保存から消す。
    Discard,
}

/// 起動時に保存領域から読み出した認証状態 (iOS は Keychain)。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct StoredAuthState {
    /// 認証プロバイダのユーザー ID。**これが無い時は何も復元しない** (iOS の `if let savedId`)。
    pub user_id: Option<String>,
    /// Apple identityToken (10 分で失効)。
    pub identity_token: Option<String>,
    /// Worker 発行 sessionToken。
    pub session_token: Option<String>,
    /// admin フラグの保存値 ("1"/"0")。
    pub is_admin_flag: Option<String>,
    /// BAN フラグの保存値 ("1"/"0")。
    pub is_banned_flag: Option<String>,
}

/// 起動時復元の結果。呼び出し側はこの通りに状態を組み立てるだけでよい。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct RestoredAuthState {
    pub is_signed_in: bool,
    /// 保持してよい identityToken (期限切れは落とす)。
    pub identity_token: Option<String>,
    /// そのまま使ってよい sessionToken。再発行待ちの間は None。
    pub session_token: Option<String>,
    pub session_disposition: SessionTokenDisposition,
    /// `/auth/refresh` を投げるべきか。
    pub should_refresh_session: bool,
    /// 保存済み sessionToken を消すべきか。
    pub should_delete_stored_session_token: bool,
    pub is_admin: bool,
    pub is_banned: bool,
}

/// `/auth/login` と `/auth/refresh` の応答のうち、クライアント状態に反映する部分。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SessionResponse {
    pub session_token: String,
    pub is_admin: bool,
    /// サーバが持つ正準表示名。再ログイン時 Apple は fullName を返さないので、
    /// これが無いとサインアウト → 再ログインで表示名が空になる。
    /// `/auth/refresh` の応答には無いので None を渡す。
    pub display_name: Option<String>,
}

/// サーバ応答の採用結果。`Option` のフィールドは **None = 変更しない**。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SessionAdoption {
    /// false = claims が想定外なので丸ごと捨てる (保存も状態更新もしない)。
    pub accepted: bool,
    pub session_token: Option<String>,
    pub is_admin: Option<bool>,
    pub display_name: Option<String>,
    /// サインイン状態。採用時は `Some(true)` = **サインイン済みに戻す**。
    ///
    /// これが要るのは 401 経路。`handleSessionExpired` が `isSignedIn` を false に
    /// してから `/auth/refresh` が成功した時、iOS はここで true に戻す
    /// (`AuthService.performSessionRefresh`)。落とすとログイン済みなのにログイン導線が
    /// 出続ける (`LoginToEditSheet` が自動 dismiss しない)。
    ///
    /// `/auth/login` 側では採用時点で既に true なので、同じ `Some(true)` を書いても
    /// 何も変わらない — だから login/refresh を区別せず 1 つの規則で足りる。
    pub is_signed_in: Option<bool>,
}

/// `GET /auth/me` の応答 (契約: 素の camelCase)。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MeResponse {
    pub is_admin: bool,
    pub is_banned: bool,
    pub display_name: Option<String>,
}

/// `/auth/me` の反映内容。`display_name` は **None = 変更しない**。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ProfileRefresh {
    pub is_admin: bool,
    pub is_banned: bool,
    pub display_name: Option<String>,
}

/// トークン交換 1 回分の結果。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum TokenExchangeOutcome {
    /// 発行に成功した。
    Succeeded,
    /// 401。identityToken 自体が無効なのでリトライしても無駄。
    Unauthorized,
    /// 通信エラー等。時間を空ければ通るかもしれない。
    Failed,
}

/// 次の一手。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum RetryDecision {
    /// もう試さない。
    Stop,
    /// この時間だけ待って再試行する。
    RetryAfter { delay_millis: u64 },
}

/// Apple ID 資格情報の状態 (`ASAuthorizationAppleIDProvider.credentialState`)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AppleCredentialState {
    Authorized,
    Revoked,
    NotFound,
    Transferred,
    /// 将来 OS が増やした値 (Swift の `@unknown default`)。
    Unknown,
}

/// 資格情報チェックの結果として何をするか。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CredentialCheckAction {
    /// サインイン状態を維持する。
    KeepSession,
    /// 少し待ってもう一度問い合わせる。
    RecheckAfter { delay_millis: u64 },
    /// サインアウトする。
    SignOut,
}

/// admin (= モデレーター) に開く操作。
///
/// モデレーター権限は細分化せずフラット (信頼ベースで付与するので分ける意味がない)。
/// 今はすべて同じ値になるが、呼び出し側が `isAdmin` を直に読むのをやめさせるために
/// 能力ごとに名前を分けてある。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct AdminCapabilities {
    /// ユーザーモデレーション画面 (BAN/解除) に入れるか。
    pub can_moderate_users: bool,
    /// マスタ編集をリクエスト (issue) に回さず直接反映してよいか。
    pub can_apply_master_edit_directly: bool,
    /// 歌詞の編集導線を出すか (歌詞 draft はそもそも admin にしかサーバが返さない)。
    pub can_edit_lyrics: bool,
}

// ── JWT の claim 取り出し ────────────────────────────────
//
// 署名は検証しない (鍵はサーバにしかない)。サーバ側で検証済みの前提で、
// 想定外のトークンをそのまま保持しないための defense-in-depth。
//
// iOS の実装は Foundation の `Data(base64Encoded:)` + `JSONSerialization` に
// 乗っており、その細かい挙動 (下記) までが「現行仕様」。ここはそれを再現している。
// 期待値は Foundation 上で元の Swift を実行して生成した (tests の ORACLE)。
//
// 再現しない 2 点 (不正 UTF-8 の 1 バイトと閉じ括弧前の余分なカンマ) は
// モジュール doc の「意図的な原本との差分」を見ること。

/// JSON オブジェクトをキー出現順のまま持つ。
///
/// `JSONSerialization` は重複キーで **先に現れた方** を採用する (実測)。serde_json の
/// Map は後勝ちなので、順序を保って自前で先勝ちを引く。攻撃者が
/// `{"exp":1,"exp":<遠い未来>}` のようなトークンを持ち込んだ時に iOS と判定がズレないようにする。
struct FirstWinsObject(Vec<(String, JsonValue)>);

impl<'de> Deserialize<'de> for FirstWinsObject {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct ObjectVisitor;

        impl<'de> Visitor<'de> for ObjectVisitor {
            type Value = FirstWinsObject;

            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("a JSON object")
            }

            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let mut entries = Vec::new();
                while let Some(entry) = map.next_entry::<String, JsonValue>()? {
                    entries.push(entry);
                }
                Ok(FirstWinsObject(entries))
            }
        }

        // オブジェクト以外 (配列・数値・文字列) は Swift の `as? [String: Any]` と同じく失敗させる。
        deserializer.deserialize_map(ObjectVisitor)
    }
}

impl FirstWinsObject {
    fn first(&self, key: &str) -> Option<&JsonValue> {
        self.0.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    /// Swift の `payload[key] as? String`。文字列以外は nil 相当。
    fn string(&self, key: &str) -> Option<&str> {
        self.first(key).and_then(JsonValue::as_str)
    }

    /// Swift の `payload[key] as? TimeInterval` (= `as? Double`)。
    ///
    /// NSNumber → Double の条件付きキャストは **値が Double で厳密に表せる時だけ成功する**。
    /// 例: 2^53 は成功、2^53+1 と Int64.max と UInt64.max は nil (実測)。
    /// JSON の true/false も NSNumber なのでキャストは成功し 1.0 / 0.0 になる (実測)。
    fn time_interval(&self, key: &str) -> Option<f64> {
        match self.first(key)? {
            JsonValue::Number(n) => {
                if n.is_f64() {
                    // 小数点・指数付きリテラルは Foundation でも Double NSNumber。
                    n.as_f64()
                } else if let Some(i) = n.as_i64() {
                    exact_f64_from_i128(i as i128)
                } else {
                    exact_f64_from_i128(n.as_u64()? as i128)
                }
            }
            // JSON の真偽値は NSNumber になるので Double キャストが通ってしまう。
            JsonValue::Bool(b) => Some(if *b { 1.0 } else { 0.0 }),
            _ => None,
        }
    }
}

/// 整数が f64 で厳密に表せる時だけ返す (`Double(exactly:)` 相当)。
fn exact_f64_from_i128(value: i128) -> Option<f64> {
    let converted = value as f64;
    if converted.is_finite() && converted as i128 == value {
        Some(converted)
    } else {
        None
    }
}

/// Foundation の `Data(base64Encoded:)` (オプション無し) と同じ厳密さで base64 を解く。
///
/// 空白・改行・アルファベット外の文字・途中の `=`・3 個以上の `=` はすべて拒否する
/// (`.ignoreUnknownCharacters` を付けていないため)。
fn base64_decode_strict(input: &str) -> Option<Vec<u8>> {
    let bytes = input.as_bytes();
    if !bytes.len().is_multiple_of(4) {
        return None;
    }
    // 長さが 4 の倍数であることは上で確認済みなので端数ブロックは出ない。
    let (chunks, _) = bytes.as_chunks::<4>();
    let mut out = Vec::with_capacity(chunks.len() * 3);
    let chunk_count = chunks.len();
    for (index, chunk) in chunks.iter().enumerate() {
        let pad = chunk.iter().filter(|&&c| c == b'=').count();
        // `=` は最終ブロックの末尾 1〜2 個だけ。"ab=c" も "A===" も不正。
        let is_last = index + 1 == chunk_count;
        if pad > 0 && (!is_last || pad > 2 || chunk[4 - pad..].iter().any(|&c| c != b'=')) {
            return None;
        }
        let mut acc: u32 = 0;
        for &c in &chunk[..4 - pad] {
            acc = (acc << 6) | u32::from(base64_symbol_value(c)?);
        }
        // pad 分の 6bit を 0 で埋めて 24bit に揃える。
        acc <<= 6 * pad;
        let decoded = [(acc >> 16) as u8, (acc >> 8) as u8, acc as u8];
        out.extend_from_slice(&decoded[..3 - pad]);
    }
    Some(out)
}

fn base64_symbol_value(symbol: u8) -> Option<u8> {
    match symbol {
        b'A'..=b'Z' => Some(symbol - b'A'),
        b'a'..=b'z' => Some(symbol - b'a' + 26),
        b'0'..=b'9' => Some(symbol - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
}

/// `JSONSerialization` が受け付けるテキストエンコーディング。
///
/// JSON の仕様 (RFC 4627 §3) が挙げる 5 種で、Apple の公式仕様どおり
/// `JSONSerialization` はこれらを自動判別する。serde_json は UTF-8 しか読まないので、
/// ここで判別して UTF-8 に直してから渡す。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum JsonTextEncoding {
    Utf8,
    Utf16Le,
    Utf16Be,
    Utf32Le,
    Utf32Be,
}

/// エンコーディングと本文の開始位置 (BOM を読み飛ばす分) を決める。
///
/// 規則は Darwin 上の `JSONSerialization` を実測して起こしたもので、
/// swift-corelibs-foundation の同名処理とは 1 箇所ちがう (下記 `FF FE`)。
fn detect_json_encoding(bytes: &[u8]) -> (JsonTextEncoding, usize) {
    use JsonTextEncoding::{Utf16Be, Utf16Le, Utf32Be, Utf32Le, Utf8};

    // BOM は **1 個だけ** 剥がす。2 個目は U+FEFF という普通の文字として残り、
    // JSON の頭に文字がある扱いで解析が落ちる (実測)。
    if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        return (Utf8, 3);
    }
    if bytes.starts_with(&[0x00, 0x00, 0xFE, 0xFF]) {
        return (Utf32Be, 4);
    }
    // ⚠️ `FF FE 00 00` を UTF-32LE の BOM と読む実装もある (swift-corelibs) が、
    // Darwin は `FF FE` を無条件に UTF-16LE と読む (実測)。結果 UTF-32LE + BOM の
    // JSON は「先頭が U+0000」となって解析に失敗する — BOM 無しの UTF-32LE は通るのに。
    // 直感に反するが原本がそうなので合わせる。
    if bytes.starts_with(&[0xFF, 0xFE]) {
        return (Utf16Le, 2);
    }
    if bytes.starts_with(&[0xFE, 0xFF]) {
        return (Utf16Be, 2);
    }
    // BOM 無しは先頭 4 バイトの NUL の並びで見分ける (RFC 4627 §3)。
    // JSON の先頭 2 文字は必ず ASCII なので、この 4 バイトで判別がつく。
    //
    // 4 バイトちょうどの入力では判別が効かず UTF-8 扱いになる (実測: UTF-16 の
    // `{}` = 4 バイトは nil)。5 バイトなら効く — 末尾の半端な 1 バイトは捨てられる
    // ので、UTF-16 の `{}` + 1 バイトは通る。境界はここ (`> 4`) で確定している。
    if bytes.len() > 4 {
        let detected = match (bytes[0], bytes[1], bytes[2], bytes[3]) {
            (0, 0, 0, _) => Utf32Be,
            (_, 0, 0, 0) => Utf32Le,
            (0, _, 0, _) => Utf16Be,
            (_, 0, _, 0) => Utf16Le,
            _ => Utf8,
        };
        return (detected, 0);
    }
    (Utf8, 0)
}

/// JSON テキストを UTF-8 バイト列に揃える。デコードできない時は None
/// (= `JSONSerialization` が nil を返す場合と一致させる)。
///
/// 対にならないサロゲートとスカラ値の範囲外は原本も nil を返す (実測)。
///
/// 末尾の**半端なバイト**は原本が黙って捨てる (実測: UTF-16 の JSON に 1 バイト
/// 足しても通り、1 バイト削ると `}` が欠けて落ちる)。ここでも同じく捨てる —
/// 「長さが揃っていないから不正」にすると、原本が受けるトークンを弾いてしまう。
fn json_text_as_utf8(bytes: &[u8]) -> Option<Cow<'_, [u8]>> {
    let (encoding, body_start) = detect_json_encoding(bytes);
    let body = &bytes[body_start..];
    match encoding {
        JsonTextEncoding::Utf8 => Some(Cow::Borrowed(body)),
        JsonTextEncoding::Utf16Le | JsonTextEncoding::Utf16Be => {
            // 余り (最大 1 バイト) は捨てる。
            let (pairs, _) = body.as_chunks::<2>();
            let little = encoding == JsonTextEncoding::Utf16Le;
            let units: Vec<u16> = pairs
                .iter()
                .map(|&pair| {
                    if little {
                        u16::from_le_bytes(pair)
                    } else {
                        u16::from_be_bytes(pair)
                    }
                })
                .collect();
            // 対にならないサロゲートは Err (原本も nil)。U+FFFF 等の非文字は通る。
            String::from_utf16(&units)
                .ok()
                .map(|text| Cow::Owned(text.into_bytes()))
        }
        JsonTextEncoding::Utf32Le | JsonTextEncoding::Utf32Be => {
            // 余り (最大 3 バイト) は捨てる。
            let (quads, _) = body.as_chunks::<4>();
            let little = encoding == JsonTextEncoding::Utf32Le;
            let mut text = String::with_capacity(quads.len());
            for &quad in quads {
                let scalar = if little {
                    u32::from_le_bytes(quad)
                } else {
                    u32::from_be_bytes(quad)
                };
                // サロゲート値・0x10FFFF 超は None (原本も nil)。
                text.push(char::from_u32(scalar)?);
            }
            Some(Cow::Owned(text.into_bytes()))
        }
    }
}

/// base64url セグメント → JSON オブジェクト。
///
/// Swift 側は `-`/`_` を標準 base64 に戻し、長さが 4 の倍数になるまで `=` を足してから解く。
/// パディング量を Swift は Character 数、ここはバイト数で数えるが、差が出るのは
/// 非 ASCII を含む場合だけで、その時はどちらにせよアルファベット外として弾かれる。
fn decode_base64url_json(segment: &str) -> Option<FirstWinsObject> {
    let mut normalized = segment.replace('-', "+").replace('_', "/");
    while !normalized.len().is_multiple_of(4) {
        normalized.push('=');
    }
    let data = base64_decode_strict(&normalized)?;
    // `JSONSerialization` は UTF-8 だけでなく UTF-16/32 (BOM 有無どちらも) を
    // 自動判別する。serde_json は UTF-8 専用なので、ここで揃えてから渡す。
    // これをやらないと、UTF-16 の payload を持つトークンで iOS と判定が反転する。
    let utf8 = json_text_as_utf8(&data)?;
    // 前後の空白は JSONSerialization も許す (実測)。数値のオーバーフロー (1e400) は
    // どちらも「JSON 全体の解析失敗」になる。
    serde_json::from_slice::<FirstWinsObject>(&utf8).ok()
}

/// JWT (header.payload.signature) の 0=header / 1=payload を取り出す。
///
/// Swift の `split(separator:)` は既定で **空セグメントを落とす** ので、
/// `"h..sig"` は 2 個扱いで不正、`"h.p.sig."` や `".h.p.sig"` は 3 個扱いで通る。
/// この癖まで含めて現行仕様。
fn decode_jwt_segment(token: &str, index: usize) -> Option<FirstWinsObject> {
    let parts: Vec<&str> = token.split('.').filter(|p| !p.is_empty()).collect();
    if parts.len() != 3 {
        return None;
    }
    decode_base64url_json(parts[index])
}

fn decode_jwt_header(token: &str) -> Option<FirstWinsObject> {
    decode_jwt_segment(token, 0)
}

fn decode_jwt_payload(token: &str) -> Option<FirstWinsObject> {
    decode_jwt_segment(token, 1)
}

/// `Date(timeIntervalSince1970: exp).timeIntervalSinceNow` と同じ「残り秒数」。
fn seconds_until(exp: f64, now_epoch_seconds: i64) -> f64 {
    exp - now_epoch_seconds as f64
}

// ── セッショントークンの判定 ──────────────────────────────

/// 自分たちのサーバが出した形をしているトークンの exp。
/// alg/iss/aud のどれかが違う、あるいは exp が読めなければ None。
///
/// 署名は検証しない (鍵はサーバにしかない)。ここは「別サービスのトークンや
/// 壊れた値を保持し続けない」ための照合で、正当性の判断はサーバが行う。
fn session_token_expiry(token: &str) -> Option<f64> {
    let header = decode_jwt_header(token)?;
    if header.string("alg") != Some(SESSION_TOKEN_ALG) {
        return None;
    }
    let payload = decode_jwt_payload(token)?;
    if payload.string("iss") != Some(SESSION_TOKEN_ISSUER)
        || payload.string("aud") != Some(SESSION_TOKEN_AUDIENCE)
    {
        return None;
    }
    payload.time_interval("exp")
}

/// sessionToken の claim 検証 (defense-in-depth)。
/// 期待: alg=HS256 / iss=imas-live-db / aud=imas-live-db-ios / 残り 60 秒超。
pub fn is_valid_session_token(token: &str, now_epoch_seconds: i64) -> bool {
    session_token_expiry(token)
        .is_some_and(|exp| seconds_until(exp, now_epoch_seconds) > EXPIRY_MARGIN_SECONDS)
}

/// 再発行を試せる形か (署名は検証できないので alg/iss/aud/exp の有無だけ確認)。
/// 期限切れでも true になる — 猶予内かはサーバ `/auth/refresh` が署名込みで決める。
pub fn is_refreshable_session_token(token: &str) -> bool {
    session_token_expiry(token).is_some()
}

/// 有効だが期限が近いか。iss/aud は見ず exp だけを見る (呼ぶ前に妥当性は確認済み)。
pub fn is_session_token_near_expiry(
    token: &str,
    now_epoch_seconds: i64,
    within_seconds: f64,
) -> bool {
    decode_jwt_payload(token)
        .and_then(|payload| payload.time_interval("exp"))
        .is_some_and(|exp| seconds_until(exp, now_epoch_seconds) < within_seconds)
}

/// Apple identityToken 用の期限判定。exp が読めない時は「切れている」に倒す
/// (読めないトークンを保持し続けても API で 401 になるだけ)。
pub fn is_jwt_expired(token: &str, now_epoch_seconds: i64) -> bool {
    decode_jwt_payload(token)
        .and_then(|payload| payload.time_interval("exp"))
        .is_none_or(|exp| seconds_until(exp, now_epoch_seconds) < EXPIRY_MARGIN_SECONDS)
}

/// 保存済み sessionToken をどう扱うか。
pub fn session_token_disposition(token: &str, now_epoch_seconds: i64) -> SessionTokenDisposition {
    if is_valid_session_token(token, now_epoch_seconds) {
        if is_session_token_near_expiry(token, now_epoch_seconds, NEAR_EXPIRY_SECONDS) {
            SessionTokenDisposition::UseAndRefresh
        } else {
            SessionTokenDisposition::Use
        }
    } else if is_refreshable_session_token(token) {
        SessionTokenDisposition::RefreshOnly
    } else {
        SessionTokenDisposition::Discard
    }
}

// ── 起動時の復元 ─────────────────────────────────────────

/// 保存済みの認証状態を復元する (アプリ起動時に 1 回)。
///
/// `user_id` が無ければ何も復元しない。保存済みトークンにも触らない
/// (サインイン済みでない端末の残骸を勝手に消さない)。
pub fn restore_stored_state(stored: StoredAuthState, now_epoch_seconds: i64) -> RestoredAuthState {
    if stored.user_id.is_none() {
        return RestoredAuthState {
            is_signed_in: false,
            identity_token: None,
            session_token: None,
            session_disposition: SessionTokenDisposition::Absent,
            should_refresh_session: false,
            should_delete_stored_session_token: false,
            is_admin: false,
            is_banned: false,
        };
    }

    let disposition = stored
        .session_token
        .as_deref()
        .map_or(SessionTokenDisposition::Absent, |token| {
            session_token_disposition(token, now_epoch_seconds)
        });

    use SessionTokenDisposition::{Discard, RefreshOnly, Use, UseAndRefresh};
    let adopted_session_token = match disposition {
        Use | UseAndRefresh => stored.session_token,
        // RefreshOnly は再発行が返るまで無効なトークンなので状態には載せない。
        _ => None,
    };

    RestoredAuthState {
        is_signed_in: true,
        // 期限切れの identityToken は載せないだけで、保存からは消さない (iOS と同じ)。
        identity_token: stored
            .identity_token
            .filter(|token| !is_jwt_expired(token, now_epoch_seconds)),
        session_token: adopted_session_token,
        session_disposition: disposition,
        should_refresh_session: matches!(disposition, UseAndRefresh | RefreshOnly),
        should_delete_stored_session_token: disposition == Discard,
        is_admin: decode_stored_flag(stored.is_admin_flag.as_deref()),
        is_banned: decode_stored_flag(stored.is_banned_flag.as_deref()),
    }
}

/// 保存値 → bool。"1" だけが true (未保存・"0"・"true" などはすべて false)。
pub fn decode_stored_flag(stored: Option<&str>) -> bool {
    stored == Some(STORED_FLAG_TRUE)
}

/// bool → 保存値。
pub fn stored_flag_value(flag: bool) -> String {
    let value = if flag { STORED_FLAG_TRUE } else { STORED_FLAG_FALSE };
    value.to_string()
}

// ── リクエストに載せるトークン ────────────────────────────

/// Authorization ヘッダに載せるトークン。sessionToken (長命) を優先し、
/// 無ければ identityToken (10 分) にフォールバックする。
///
/// ⚠️ **有効性は見ない**。ここで期限を判定して「送らない」にすると、401 →
/// 自動リフレッシュ → 再送 の経路が動かず無言で失敗する。失効の判定はサーバに任せる。
pub fn bearer_token(
    session_token: Option<String>,
    identity_token: Option<String>,
) -> Option<String> {
    session_token.or(identity_token)
}

// ── セッション再発行 ─────────────────────────────────────

/// `/auth/refresh` に載せるトークン。None なら **リクエストごと送らない**。
///
/// メモリ上のトークンが無くても保存済みを拾うのは、期限切れで状態に載せなかった
/// トークン (RefreshOnly) からでも Apple 再認証なしに復帰させるため。
pub fn session_refresh_candidate(
    in_memory_token: Option<String>,
    stored_token: Option<String>,
) -> Option<String> {
    in_memory_token
        .or(stored_token)
        .filter(|token| is_refreshable_session_token(token))
}

// ── サーバ応答の反映 ─────────────────────────────────────

/// `/auth/login` `/auth/refresh` が返したセッションを採用してよいか。
///
/// サーバ署名は API 側で検証済みだが、想定外のトークンをそのまま保持しないよう
/// クライアントでも claim を照合する。落ちた時は admin も表示名も
/// **サインイン状態も** 一切触らない (原本もその場で return するだけ)。
pub fn adopt_session_response(
    response: SessionResponse,
    now_epoch_seconds: i64,
) -> SessionAdoption {
    if !is_valid_session_token(&response.session_token, now_epoch_seconds) {
        return SessionAdoption {
            accepted: false,
            session_token: None,
            is_admin: None,
            display_name: None,
            is_signed_in: None,
        };
    }
    SessionAdoption {
        accepted: true,
        session_token: Some(response.session_token),
        is_admin: Some(response.is_admin),
        // 空文字で既存の表示名を消さない。
        display_name: response.display_name.filter(|name| !name.is_empty()),
        // 401 → refresh 成功でサインイン状態を復帰させる (詳細は SessionAdoption の doc)。
        is_signed_in: Some(true),
    }
}

/// `GET /auth/me` の反映内容を決める。
///
/// admin/BAN は毎回サーバの値で上書きする (BAN はサーバ側でしか立たず、
/// `/auth/login` の応答にも含まれないので、この再取得が唯一の反映経路)。
/// 表示名は変化がある時だけ差し替える。
pub fn apply_me_response(me: MeResponse, current_display_name: Option<&str>) -> ProfileRefresh {
    ProfileRefresh {
        is_admin: me.is_admin,
        is_banned: me.is_banned,
        display_name: me
            .display_name
            .filter(|name| Some(name.as_str()) != current_display_name),
    }
}

// ── トークン交換のリトライ ────────────────────────────────

/// identityToken → sessionToken の交換を続けるか。`attempt` は 0 始まり。
///
/// 401 は identityToken 自体が無効ということなので、待っても状況は変わらない。
/// それ以外の失敗 (通信エラー等) だけ、identityToken がまだ生きているうちに数回粘る。
pub fn token_exchange_retry(attempt: u32, outcome: TokenExchangeOutcome) -> RetryDecision {
    match outcome {
        TokenExchangeOutcome::Succeeded | TokenExchangeOutcome::Unauthorized => RetryDecision::Stop,
        TokenExchangeOutcome::Failed if attempt + 1 < TOKEN_EXCHANGE_MAX_ATTEMPTS => {
            RetryDecision::RetryAfter {
                delay_millis: TOKEN_EXCHANGE_RETRY_DELAY_MILLIS,
            }
        }
        TokenExchangeOutcome::Failed => RetryDecision::Stop,
    }
}

// ── Apple サインイン ─────────────────────────────────────

/// Apple が返した姓名から表示名を組み立てる。空になるなら採用しない
/// (Apple は初回認証時しか氏名を返さないので、空で既存の表示名を潰さない)。
///
/// 姓 → 名 の順で空白 1 つで繋ぐ。nil は落とすが空文字は落とさない
/// (`compactMap` は nil しか除かない) ので、姓が空文字なら先頭に空白が残る。
pub fn display_name_from_apple_name(
    family_name: Option<String>,
    given_name: Option<String>,
) -> Option<String> {
    let parts: Vec<String> = [family_name, given_name].into_iter().flatten().collect();
    let joined = parts.join(" ");
    (!joined.is_empty()).then_some(joined)
}

/// Apple ID 資格情報の状態から次の一手を決める。
///
/// `is_recheck` は「revoked を受けて待ってから問い合わせ直した 2 回目か」。
/// 2 回目は revoked が続いた時だけサインアウトする — 1 回目で即切ると、
/// 一時的に revoked を返すだけの端末でサインアウトしてしまう。
/// 逆に notFound / transferred / 未知の値は 1 回目で確定させる (復帰しない状態なので)。
pub fn credential_check_action(
    state: AppleCredentialState,
    is_recheck: bool,
) -> CredentialCheckAction {
    match (state, is_recheck) {
        (AppleCredentialState::Authorized, _) => CredentialCheckAction::KeepSession,
        (AppleCredentialState::Revoked, false) => CredentialCheckAction::RecheckAfter {
            delay_millis: CREDENTIAL_RECHECK_DELAY_MILLIS,
        },
        (AppleCredentialState::Revoked, true) => CredentialCheckAction::SignOut,
        // 2 回目は revoked 以外を「復帰した」とみなして触らない (元実装の分岐がそうなっている)。
        (_, true) => CredentialCheckAction::KeepSession,
        (_, false) => CredentialCheckAction::SignOut,
    }
}

// ── admin 権限 ───────────────────────────────────────────

/// admin フラグから開く操作を解決する。
///
/// BAN・未ログインは見ない。iOS は失効 (`handleSessionExpired`) で `isSignedIn` を
/// false にしても `isAdmin` は残す作りで、admin 導線はそのまま出る。ここで条件を
/// 足すと挙動が変わるので足さない。
pub fn admin_capabilities(is_admin: bool) -> AdminCapabilities {
    AdminCapabilities {
        can_moderate_users: is_admin,
        can_apply_master_edit_directly: is_admin,
        can_edit_lyrics: is_admin,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 元実装 (iOS `AuthService.swift` の private static) を Apple Foundation 上で
    /// 実行して作った期待値表。手で書いた値ではないので「Rust の実装に合わせて
    /// 期待値を書いた」事故が起きない。
    ///
    /// 作り方 (作り直す時も同じ): `AuthService.swift` の
    /// `isValidSessionToken` / `isRefreshableSessionToken` / `isSessionTokenNearExpiry` /
    /// `isJWTExpired` と JWT デコード群を逐語コピーした Swift プログラムを用意し
    /// (`timeIntervalSinceNow` だけを引数の now に置換)、下の token を食わせて
    /// 出力をこの表の形で書き出す。`disposition` は `AuthService.init` の
    /// sessionToken 復元分岐をそのまま辿った結果。
    struct OracleRow {
        name: &'static str,
        token: &'static str,
        now: i64,
        is_valid: bool,
        is_refreshable: bool,
        is_near_expiry: bool,
        is_jwt_expired: bool,
        disposition: &'static str,
    }

    const ORACLE: &[OracleRow] = &[
        OracleRow { name: "valid_far_future", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODMxNTM2MDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: false, is_jwt_expired: false, disposition: "Use" },
        OracleRow { name: "exp_exactly_plus_60", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDAwMDYwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "RefreshOnly" },
        OracleRow { name: "exp_plus_61", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDAwMDYxfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "exp_plus_59", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDAwMDU5fQ.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "exp_equals_now", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDAwMDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "exp_past", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxNzk5MTM2MDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "near_expiry_6d", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwNTE4NDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "near_expiry_exactly_7d", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwNjA0ODAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: false, is_jwt_expired: false, disposition: "Use" },
        OracleRow { name: "near_expiry_7d_minus_1s", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwNjA0Nzk5fQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "near_expiry_8d", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwNjkxMjAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: false, is_jwt_expired: false, disposition: "Use" },
        OracleRow { name: "alg_rs256", token: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "alg_missing", token: "eyJ0eXAiOiJKV1QifQ.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "alg_number", token: "eyJhbGciOjI1Nn0.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "iss_wrong", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJldmlsIiwiYXVkIjoiaW1hcy1saXZlLWRiLWlvcyIsImV4cCI6MTgwMDA4NjQwMH0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "iss_missing", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "aud_wrong", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItYW5kcm9pZCIsImV4cCI6MTgwMDA4NjQwMH0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "aud_missing", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJleHAiOjE4MDAwODY0MDB9.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "exp_missing", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIn0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "exp_string", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoiMTgwMDAwMDA2MCJ9.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "exp_bool_true", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjp0cnVlfQ.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "exp_null", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjpudWxsfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "exp_negative", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjotNX0.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "exp_zero", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjowfQ.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "exp_fractional", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDAwMDYwLjV9.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "exp_fractional_just_over", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDAwMDYwLjB9.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "RefreshOnly" },
        OracleRow { name: "exp_huge", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxZSsxOH0.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: false, is_jwt_expired: false, disposition: "Use" },
        OracleRow { name: "exp_array", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjpbMSwyXX0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_is_array", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.WzEsMl0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_is_number", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.MTIz.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_is_string_json", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ImhpIg.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_invalid_utf8", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.__57fQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_not_base64", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.!!!!.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_len_mod4_is_1", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AAAAA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_with_newline", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e3\n0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_empty_object", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "two_segments", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "four_segments", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig.extra", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "empty_middle_segment", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "trailing_dot", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig.", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "leading_dot", token: ".eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "empty_token", token: "", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "only_dots", token: "...", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "no_dots", token: "abc", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "duplicate_exp_key", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxLCJleHAiOjE5MDAwMDAwMDB9.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "standard_base64_plus_slash", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwLCJzdWIiOiI/Pz8+Pj4ifQ==.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "extra_claims_ok", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwLCJ1aWQiOiJ1MSIsImlhdCI6MTc5OTk5OTk5MH0.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "apple_identity_style_exp_only", token: "eyJhbGciOiJSUzI1NiIsImtpZCI6ImsifQ.eyJleHAiOjE4MDAwMDA2MDAsInN1YiI6ImFwcGxlIn0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "apple_identity_expired", token: "eyJhbGciOiJSUzI1NiIsImtpZCI6ImsifQ.eyJleHAiOjE3OTk5OTk5OTksInN1YiI6ImFwcGxlIn0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "apple_identity_no_exp", token: "eyJhbGciOiJSUzI1NiIsImtpZCI6ImsifQ.eyJzdWIiOiJhcHBsZSJ9.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "whitespace_padding_json", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ICB7ImV4cCI6MTkwMDAwMDAwMH0gIA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "exp_bool_false", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjpmYWxzZX0.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "dup_alg_first_bad", token: "eyJhbGciOiJub25lIiwiYWxnIjoiSFMyNTYifQ.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: true, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "dup_alg_first_good", token: "eyJhbGciOiJIUzI1NiIsImFsZyI6Im5vbmUifQ.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "equals_in_middle", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ab=c.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "payload_len_mod4_is_3", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "crlf_around_json", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE5MDAwMDAwMDB9DQo.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "json_escaped_iss", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJcdTAwNjltYXMtbGl2ZS1kYiIsImF1ZCI6ImltYXMtbGl2ZS1kYi1pb3MiLCJleHAiOjE4MDAwODY0MDB9.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "exp_int64_max", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjo5MjIzMzcyMDM2ODU0Nzc1ODA3fQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "exp_overflow_1e400", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxZTQwMH0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "tab_before_json", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.CXsiZXhwIjoxOTAwMDAwMDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: false, disposition: "Discard" },
        OracleRow { name: "exp_2pow53", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjo5MDA3MTk5MjU0NzQwOTkyfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: false, is_jwt_expired: false, disposition: "Use" },
        OracleRow { name: "exp_2pow53_plus_1", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjo5MDA3MTk5MjU0NzQwOTkzfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "exp_neg_2pow53_minus_1", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjotOTAwNzE5OTI1NDc0MDk5M30.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "exp_uint64_max", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODQ0Njc0NDA3MzcwOTU1MTYxNX0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "exp_int_with_exponent", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxLjgwMDAwMDA2ZTl9.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "RefreshOnly" },
        // ── JSON のテキストエンコーディング ──
        // JSONSerialization は UTF-8 / UTF-16(LE,BE) / UTF-32(LE,BE) を BOM の有無ごと
        // 自動判別する。UTF-8 しか読めない実装だと、この一群で答えが反転する。
        OracleRow { name: "enc_utf8_plain", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf8_bom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.77u_eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf16le_nobom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQA.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf16le_bom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.__57ACIAaQBzAHMAIgA6ACIAaQBtAGEAcwAtAGwAaQB2AGUALQBkAGIAIgAsACIAYQB1AGQAIgA6ACIAaQBtAGEAcwAtAGwAaQB2AGUALQBkAGIALQBpAG8AcwAiACwAIgBlAHgAcAAiADoAMQA4ADAAMAAwADgANgA0ADAAMAB9AA.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf16be_nobom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AHsAIgBpAHMAcwAiADoAIgBpAG0AYQBzAC0AbABpAHYAZQAtAGQAYgAiACwAIgBhAHUAZAAiADoAIgBpAG0AYQBzAC0AbABpAHYAZQAtAGQAYgAtAGkAbwBzACIALAAiAGUAeABwACIAOgAxADgAMAAwADAAOAA2ADQAMAAwAH0.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf16be_bom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9._v8AewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf32le_nobom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAAACIAAABpAAAAcwAAAHMAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAiAAAALAAAACIAAABhAAAAdQAAAGQAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAtAAAAaQAAAG8AAABzAAAAIgAAACwAAAAiAAAAZQAAAHgAAABwAAAAIgAAADoAAAAxAAAAOAAAADAAAAAwAAAAMAAAADgAAAA2AAAANAAAADAAAAAwAAAAfQAAAA.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf32le_bom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.__4AAHsAAAAiAAAAaQAAAHMAAABzAAAAIgAAADoAAAAiAAAAaQAAAG0AAABhAAAAcwAAAC0AAABsAAAAaQAAAHYAAABlAAAALQAAAGQAAABiAAAAIgAAACwAAAAiAAAAYQAAAHUAAABkAAAAIgAAADoAAAAiAAAAaQAAAG0AAABhAAAAcwAAAC0AAABsAAAAaQAAAHYAAABlAAAALQAAAGQAAABiAAAALQAAAGkAAABvAAAAcwAAACIAAAAsAAAAIgAAAGUAAAB4AAAAcAAAACIAAAA6AAAAMQAAADgAAAAwAAAAMAAAADAAAAA4AAAANgAAADQAAAAwAAAAMAAAAH0AAAA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf32be_nobom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AAAAewAAACIAAABpAAAAcwAAAHMAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAiAAAALAAAACIAAABhAAAAdQAAAGQAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAtAAAAaQAAAG8AAABzAAAAIgAAACwAAAAiAAAAZQAAAHgAAABwAAAAIgAAADoAAAAxAAAAOAAAADAAAAAwAAAAMAAAADgAAAA2AAAANAAAADAAAAAwAAAAfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf32be_bom", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AAD-_wAAAHsAAAAiAAAAaQAAAHMAAABzAAAAIgAAADoAAAAiAAAAaQAAAG0AAABhAAAAcwAAAC0AAABsAAAAaQAAAHYAAABlAAAALQAAAGQAAABiAAAAIgAAACwAAAAiAAAAYQAAAHUAAABkAAAAIgAAADoAAAAiAAAAaQAAAG0AAABhAAAAcwAAAC0AAABsAAAAaQAAAHYAAABlAAAALQAAAGQAAABiAAAALQAAAGkAAABvAAAAcwAAACIAAAAsAAAAIgAAAGUAAAB4AAAAcAAAACIAAAA6AAAAMQAAADgAAAAwAAAAMAAAADAAAAA4AAAANgAAADQAAAAwAAAAMAAAAH0.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_hdr_utf16le", token: "ewAiAGEAbABnACIAOgAiAEgAUwAyADUANgAiACwAIgB0AHkAcAAiADoAIgBKAFcAVAAiAH0A.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_hdr_and_payload_utf16le", token: "ewAiAGEAbABnACIAOgAiAEgAUwAyADUANgAiACwAIgB0AHkAcAAiADoAIgBKAFcAVAAiAH0A.ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQA.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_hdr_utf32be", token: "AAAAewAAACIAAABhAAAAbAAAAGcAAAAiAAAAOgAAACIAAABIAAAAUwAAADIAAAA1AAAANgAAACIAAAAsAAAAIgAAAHQAAAB5AAAAcAAAACIAAAA6AAAAIgAAAEoAAABXAAAAVAAAACIAAAB9.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf16le_far_future", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAzADEANQAzADYAMAAwADAAfQA.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: false, is_jwt_expired: false, disposition: "Use" },
        OracleRow { name: "enc_utf16be_expired", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AHsAIgBpAHMAcwAiADoAIgBpAG0AYQBzAC0AbABpAHYAZQAtAGQAYgAiACwAIgBhAHUAZAAiADoAIgBpAG0AYQBzAC0AbABpAHYAZQAtAGQAYgAtAGkAbwBzACIALAAiAGUAeABwACIAOgAxADcAOQA5ADEAMwA2ADAAMAAwAH0.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "enc_utf32be_far_future", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AAAAewAAACIAAABpAAAAcwAAAHMAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAiAAAALAAAACIAAABhAAAAdQAAAGQAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAtAAAAaQAAAG8AAABzAAAAIgAAACwAAAAiAAAAZQAAAHgAAABwAAAAIgAAADoAAAAxAAAAOAAAADMAAAAxAAAANQAAADMAAAA2AAAAMAAAADAAAAAwAAAAfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: false, is_jwt_expired: false, disposition: "Use" },
        OracleRow { name: "enc_utf16le_truncated", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf16le_trailing_nul", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQAAAA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_double_bom_utf16le", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.__7__nsAIgBpAHMAcwAiADoAIgBpAG0AYQBzAC0AbABpAHYAZQAtAGQAYgAiACwAIgBhAHUAZAAiADoAIgBpAG0AYQBzAC0AbABpAHYAZQAtAGQAYgAtAGkAbwBzACIALAAiAGUAeABwACIAOgAxADgAMAAwADAAOAA2ADQAMAAwAH0A.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_double_bom_utf8", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.77u_77u_eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_bom16le_body_utf8", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.__57ImlzcyI6ImltYXMtbGl2ZS1kYiIsImF1ZCI6ImltYXMtbGl2ZS1kYi1pb3MiLCJleHAiOjE4MDAwODY0MDB9.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_bom8_body_utf16le", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.77u_ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf16le_array", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.WwAxACwAMgBdAA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf16le_empty_object", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewB9AA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf16le_empty_object_padded", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewB9ACAA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf32be_empty_object", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AAAAewAAAH0.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf16le_lone_surrogate", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAD3YbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf32le_out_of_range", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAAACIAAABpAAAAcwAAAHMAAAAiAAAAOgAAACIAAAAAABEAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAiAAAALAAAACIAAABhAAAAdQAAAGQAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAtAAAAaQAAAG8AAABzAAAAIgAAACwAAAAiAAAAZQAAAHgAAABwAAAAIgAAADoAAAAxAAAAOAAAADAAAAAwAAAAMAAAADgAAAA2AAAANAAAADAAAAAwAAAAfQAAAA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf32le_surrogate_scalar", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAAACIAAABpAAAAcwAAAHMAAAAiAAAAOgAAACIAAAAA2AAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAiAAAALAAAACIAAABhAAAAdQAAAGQAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAtAAAAaQAAAG8AAABzAAAAIgAAACwAAAAiAAAAZQAAAHgAAABwAAAAIgAAADoAAAAxAAAAOAAAADAAAAAwAAAAMAAAADgAAAA2AAAANAAAADAAAAAwAAAAfQAAAA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf16le_control_char", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAAEAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQA.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
        OracleRow { name: "enc_utf16le_duplicate_exp", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEALAAiAGUAeABwACIAOgAxADkAMAAwADAAMAAwADAAMAAwAH0A.sig", now: 1800000000, is_valid: false, is_refreshable: true, is_near_expiry: true, is_jwt_expired: true, disposition: "RefreshOnly" },
        OracleRow { name: "enc_utf16le_nonascii_claim", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAALAAiAG4AIgA6ACIAQjAiAH0A.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf32be_nonascii_claim", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AAAAewAAACIAAABpAAAAcwAAAHMAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAiAAAALAAAACIAAABhAAAAdQAAAGQAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAtAAAAaQAAAG8AAABzAAAAIgAAACwAAAAiAAAAZQAAAHgAAABwAAAAIgAAADoAAAAxAAAAOAAAADAAAAAwAAAAMAAAADgAAAA2AAAANAAAADAAAAAwAAAALAAAACIAAABuAAAAIgAAADoAAAAiAAAwQgAAACIAAAB9.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        // 末尾の半端なバイトは原本が黙って捨てる (長さが揃っていなくても通る)。
        OracleRow { name: "enc_utf16le_trailing_byte", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAiAGkAcwBzACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiACIALAAiAGEAdQBkACIAOgAiAGkAbQBhAHMALQBsAGkAdgBlAC0AZABiAC0AaQBvAHMAIgAsACIAZQB4AHAAIgA6ADEAOAAwADAAMAA4ADYANAAwADAAfQBB.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf16be_trailing_byte", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AHsAIgBpAHMAcwAiADoAIgBpAG0AYQBzAC0AbABpAHYAZQAtAGQAYgAiACwAIgBhAHUAZAAiADoAIgBpAG0AYQBzAC0AbABpAHYAZQAtAGQAYgAtAGkAbwBzACIALAAiAGUAeABwACIAOgAxADgAMAAwADAAOAA2ADQAMAAwAH0A.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf32le_trailing_3", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewAAACIAAABpAAAAcwAAAHMAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAiAAAALAAAACIAAABhAAAAdQAAAGQAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAtAAAAaQAAAG8AAABzAAAAIgAAACwAAAAiAAAAZQAAAHgAAABwAAAAIgAAADoAAAAxAAAAOAAAADAAAAAwAAAAMAAAADgAAAA2AAAANAAAADAAAAAwAAAAfQAAAEFCQw.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf32be_trailing_2", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.AAAAewAAACIAAABpAAAAcwAAAHMAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAiAAAALAAAACIAAABhAAAAdQAAAGQAAAAiAAAAOgAAACIAAABpAAAAbQAAAGEAAABzAAAALQAAAGwAAABpAAAAdgAAAGUAAAAtAAAAZAAAAGIAAAAtAAAAaQAAAG8AAABzAAAAIgAAACwAAAAiAAAAZQAAAHgAAABwAAAAIgAAADoAAAAxAAAAOAAAADAAAAAwAAAAMAAAADgAAAA2AAAANAAAADAAAAAwAAAAff_-.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf16le_bom_trailing_byte", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.__57ACIAaQBzAHMAIgA6ACIAaQBtAGEAcwAtAGwAaQB2AGUALQBkAGIAIgAsACIAYQB1AGQAIgA6ACIAaQBtAGEAcwAtAGwAaQB2AGUALQBkAGIALQBpAG8AcwAiACwAIgBlAHgAcAAiADoAMQA4ADAAMAAwADgANgA0ADAAMAB9AH8.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_hdr_utf16le_trailing_byte", token: "ewAiAGEAbABnACIAOgAiAEgAUwAyADUANgAiACwAIgB0AHkAcAAiADoAIgBKAFcAVAAiAH0AQQ.eyJpc3MiOiJpbWFzLWxpdmUtZGIiLCJhdWQiOiJpbWFzLWxpdmUtZGItaW9zIiwiZXhwIjoxODAwMDg2NDAwfQ.sig", now: 1800000000, is_valid: true, is_refreshable: true, is_near_expiry: true, is_jwt_expired: false, disposition: "UseAndRefresh" },
        OracleRow { name: "enc_utf16le_five_bytes", token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewB9AEE.sig", now: 1800000000, is_valid: false, is_refreshable: false, is_near_expiry: false, is_jwt_expired: true, disposition: "Discard" },
    ];

    fn token_named(name: &str) -> &'static str {
        ORACLE
            .iter()
            .find(|row| row.name == name)
            .unwrap_or_else(|| panic!("unknown vector {name}"))
            .token
    }

    fn disposition_name(disposition: SessionTokenDisposition) -> &'static str {
        match disposition {
            SessionTokenDisposition::Absent => "Absent",
            SessionTokenDisposition::Use => "Use",
            SessionTokenDisposition::UseAndRefresh => "UseAndRefresh",
            SessionTokenDisposition::RefreshOnly => "RefreshOnly",
            SessionTokenDisposition::Discard => "Discard",
        }
    }

    const NOW: i64 = 1_800_000_000;

    // ── 元実装との一致 ────────────────────────────────────

    #[test]
    fn matches_the_original_swift_implementation_on_every_vector() {
        for row in ORACLE {
            let (token, now, name) = (row.token, row.now, row.name);
            assert_eq!(
                is_valid_session_token(token, now),
                row.is_valid,
                "is_valid: {name}"
            );
            assert_eq!(
                is_refreshable_session_token(token),
                row.is_refreshable,
                "is_refreshable: {name}"
            );
            assert_eq!(
                is_session_token_near_expiry(token, now, NEAR_EXPIRY_SECONDS),
                row.is_near_expiry,
                "is_near_expiry: {name}"
            );
            assert_eq!(
                is_jwt_expired(token, now),
                row.is_jwt_expired,
                "is_jwt_expired: {name}"
            );
            assert_eq!(
                disposition_name(session_token_disposition(token, now)),
                row.disposition,
                "disposition: {name}"
            );
        }
    }

    /// 使えるトークンは必ず再発行もできる (逆は成り立たない)。
    /// この含意が崩れると、期限切れ直後に再発行の種を捨ててしまう。
    #[test]
    fn a_usable_token_can_always_be_refreshed() {
        for row in ORACLE {
            assert!(
                !row.is_valid || row.is_refreshable,
                "{}: is_valid なのに is_refreshable でない",
                row.name
            );
        }
    }

    /// 表そのものが痩せて「全部通った」になっていないかの番人。
    #[test]
    fn the_oracle_table_covers_both_answers_for_every_predicate() {
        // 下限は表を増やしたら一緒に上げる (増えた分がまとめて消せてしまわないように)。
        assert!(ORACLE.len() >= 100, "vectors={}", ORACLE.len());
        fn covers_both(name: &str, mut values: impl Iterator<Item = bool> + Clone) {
            assert!(values.clone().any(|v| v), "{name} に true のケースが無い");
            assert!(values.any(|v| !v), "{name} に false のケースが無い");
        }
        covers_both("is_valid", ORACLE.iter().map(|row| row.is_valid));
        covers_both("is_refreshable", ORACLE.iter().map(|row| row.is_refreshable));
        covers_both("is_near_expiry", ORACLE.iter().map(|row| row.is_near_expiry));
        covers_both("is_jwt_expired", ORACLE.iter().map(|row| row.is_jwt_expired));
        for expected in ["Use", "UseAndRefresh", "RefreshOnly", "Discard"] {
            assert!(
                ORACLE.iter().any(|row| row.disposition == expected),
                "disposition {expected} is not covered"
            );
        }
    }

    /// 表から「非 UTF-8 のエンコーディング」が抜け落ちるのを防ぐ番人。
    ///
    /// 述語ごとに true/false が揃っているかだけ見る番人では、この入力クラスが 1 本も
    /// 無い状態を検出できない (実際、UTF-16/32 の payload で原本と判定が反転したまま
    /// 「oracle 全一致」になっていた)。ここでは **採用される側の例** が
    /// エンコーディングごとに残っていることまで要求する — デコーダを UTF-8 専用に
    /// 戻すと、これらが軒並み false に落ちて気づける。
    #[test]
    fn the_oracle_table_covers_every_json_text_encoding() {
        fn row(name: &str) -> &'static OracleRow {
            ORACLE
                .iter()
                .find(|row| row.name == name)
                .unwrap_or_else(|| panic!("{name} のベクタが表から消えている"))
        }
        for name in [
            "enc_utf8_plain",
            "enc_utf8_bom",
            "enc_utf16le_nobom",
            "enc_utf16le_bom",
            "enc_utf16be_nobom",
            "enc_utf16be_bom",
            "enc_utf32le_nobom",
            "enc_utf32be_nobom",
            "enc_utf32be_bom",
            "enc_hdr_utf16le",
        ] {
            assert!(
                row(name).is_valid,
                "{name}: 原本は採用する。false ならエンコーディング判別が効いていない"
            );
        }
        // BOM 付き UTF-32LE だけは原本も受け付けない (`FF FE` を UTF-16LE と読むため)。
        // 「全部 true」に均してしまう実装を弾くために、この 1 本を明示的に押さえる。
        assert!(!row("enc_utf32le_bom").is_valid);
    }

    /// エンコーディング判別の規則そのもの (原本 `JSONSerialization` の実測結果)。
    /// ORACLE 経由だと token 越しにしか見えないので、直に押さえておく。
    #[test]
    fn json_text_encoding_is_detected_the_way_foundation_does() {
        use JsonTextEncoding::{Utf16Be, Utf16Le, Utf32Be, Utf32Le, Utf8};

        // BOM は 1 個ぶんだけ本文の外に出る。
        assert_eq!(detect_json_encoding(b"\xEF\xBB\xBF{}"), (Utf8, 3));
        assert_eq!(detect_json_encoding(b"\xFE\xFF\0{\0}"), (Utf16Be, 2));
        assert_eq!(detect_json_encoding(b"\xFF\xFE{\0}\0"), (Utf16Le, 2));
        assert_eq!(detect_json_encoding(b"\0\0\xFE\xFF\0\0\0{"), (Utf32Be, 4));
        // `FF FE 00 00` は UTF-32LE の BOM に見えるが、原本は UTF-16LE と読む。
        assert_eq!(detect_json_encoding(b"\xFF\xFE\0\0{\0\0\0"), (Utf16Le, 2));

        // BOM 無しは先頭 4 バイトの NUL の並びで決まる。
        assert_eq!(detect_json_encoding(b"{\0\"\0a\0\"\0"), (Utf16Le, 0));
        assert_eq!(detect_json_encoding(b"\0{\0\"\0a\0\""), (Utf16Be, 0));
        assert_eq!(detect_json_encoding(b"{\0\0\0\"\0\0\0"), (Utf32Le, 0));
        assert_eq!(detect_json_encoding(b"\0\0\0{\0\0\0\""), (Utf32Be, 0));
        assert_eq!(detect_json_encoding(b"{\"a\":1}"), (Utf8, 0));

        // 4 バイトちょうどでは判別が効かず UTF-8 扱い (原本が nil を返す挙動と一致)。
        assert_eq!(detect_json_encoding(b"{\0}\0"), (Utf8, 0));
        assert_eq!(detect_json_encoding(b"\0{\0}"), (Utf8, 0));
        // 6 バイトあれば効く。
        assert_eq!(detect_json_encoding(b"{\0}\0 \0"), (Utf16Le, 0));
    }

    /// デコードできないバイト列は原本と同じく「解析失敗」に倒す。
    #[test]
    fn undecodable_wide_text_is_rejected() {
        // 対にならないサロゲート。判別は先頭 4 バイトで決まるので、壊す場所は
        // それより後ろ (`{"` の次) に置く。
        assert_eq!(json_text_as_utf8(b"{\0\"\0\x3d\xd8\"\0}\0"), None);
        // スカラ値の範囲外 (0x00110000)。
        assert_eq!(json_text_as_utf8(b"{\0\0\0\0\0\x11\0"), None);
        // 健全な UTF-16LE は UTF-8 に落ちる。
        assert_eq!(
            json_text_as_utf8(b"{\0}\0 \0").as_deref(),
            Some(b"{} ".as_slice())
        );
    }

    /// モジュール doc に書いた「意図的な原本との差分」を固定する。
    ///
    /// 原本 (`JSONSerialization`) はこの 2 つを受け付けるが、ここでは受け付けない。
    /// どちらも Foundation 側の不具合と見てよい挙動で、真似すると Android にまで
    /// 移植することになる。**緩める方向にズレたら気づけるように**押さえておく
    /// (パーサを差し替えた時に黙って挙動が変わるのを防ぐ)。
    #[test]
    fn the_two_deliberate_divergences_from_foundation_stay_strict() {
        // 1. JSON 文字列中の単独バイト 0xA9。原本はこれだけ U+FFFD にして通す。
        assert!(decode_base64url_json(&base64url(b"{\"e\":\"\xA9x\"}")).is_none());
        // 2. 閉じ括弧直前の余分なカンマ。原本は 1 個だけ許す。
        assert!(decode_base64url_json(&base64url(b"{\"exp\":1,}")).is_none());

        // 比較用: 同じ形で問題のバイト/カンマが無ければ通る (テストが常に None を
        // 見ているだけ、という腐り方を防ぐ)。
        assert!(decode_base64url_json(&base64url(b"{\"e\":\"x\"}")).is_some());
        assert!(decode_base64url_json(&base64url(b"{\"exp\":1}")).is_some());
    }

    /// テスト用の base64url エンコード (パディング無し)。
    fn base64url(bytes: &[u8]) -> String {
        const ALPHABET: &[u8; 64] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        let mut out = String::new();
        for chunk in bytes.chunks(3) {
            let mut block = [0u8; 3];
            block[..chunk.len()].copy_from_slice(chunk);
            let packed = u32::from_be_bytes([0, block[0], block[1], block[2]]);
            // 3 バイト = 4 文字。端数のぶんだけ末尾の文字を落とす (パディングは付けない)。
            for i in 0..chunk.len() + 1 {
                out.push(ALPHABET[(packed >> (18 - 6 * i)) as usize & 0x3F] as char);
            }
        }
        out
    }

    /// 末尾の半端なバイトは黙って捨てる (原本と同じ)。ここを「長さが不正」に
    /// すると、原本が受け付けるトークンを弾いてしまう。
    #[test]
    fn a_trailing_partial_code_unit_is_dropped() {
        // UTF-16LE の `{} ` に 1 バイト足しても、その 1 バイトが消えるだけ。
        assert_eq!(
            json_text_as_utf8(b"{\0}\0 \0\x41").as_deref(),
            Some(b"{} ".as_slice())
        );
        // UTF-32LE も同じ (余りは最大 3 バイト)。
        assert_eq!(
            json_text_as_utf8(b"{\0\0\0}\0\0\0\x41\x42\x43").as_deref(),
            Some(b"{}".as_slice())
        );
        // 逆に 1 バイト削ると末尾の文字ごと落ちる (`}` が欠けて JSON が壊れる経路)。
        assert_eq!(
            json_text_as_utf8(b"{\0}\0 ").as_deref(),
            Some(b"{}".as_slice())
        );
    }

    // ── 起動時の復元 ──────────────────────────────────────

    fn stored(session: Option<&str>, identity: Option<&str>) -> StoredAuthState {
        StoredAuthState {
            user_id: Some("apple-uid".into()),
            identity_token: identity.map(str::to_string),
            session_token: session.map(str::to_string),
            is_admin_flag: Some("0".into()),
            is_banned_flag: Some("0".into()),
        }
    }

    #[test]
    fn a_healthy_session_token_is_restored_as_is() {
        let restored = restore_stored_state(stored(Some(token_named("valid_far_future")), None), NOW);
        assert!(restored.is_signed_in);
        assert_eq!(
            restored.session_token.as_deref(),
            Some(token_named("valid_far_future"))
        );
        assert!(!restored.should_refresh_session);
        assert!(!restored.should_delete_stored_session_token);
    }

    /// 期限が近いだけなら使いながら裏で更新する (起動直後に無効化しない)。
    #[test]
    fn a_near_expiry_session_token_is_used_and_refreshed() {
        let restored = restore_stored_state(stored(Some(token_named("near_expiry_6d")), None), NOW);
        assert_eq!(
            restored.session_disposition,
            SessionTokenDisposition::UseAndRefresh
        );
        assert!(restored.session_token.is_some());
        assert!(restored.should_refresh_session);
        assert!(!restored.should_delete_stored_session_token);
    }

    /// 期限切れは状態に載せない。ただし保存は消さない — 消すと
    /// `/auth/refresh` に出す種が無くなり Apple 再認証が要る。
    #[test]
    fn an_expired_but_wellformed_token_is_kept_for_refresh_only() {
        let restored = restore_stored_state(stored(Some(token_named("exp_past")), None), NOW);
        assert_eq!(
            restored.session_disposition,
            SessionTokenDisposition::RefreshOnly
        );
        assert_eq!(restored.session_token, None);
        assert!(restored.should_refresh_session);
        assert!(!restored.should_delete_stored_session_token);
    }

    #[test]
    fn a_token_with_foreign_claims_is_deleted() {
        let restored = restore_stored_state(stored(Some(token_named("iss_wrong")), None), NOW);
        assert_eq!(restored.session_disposition, SessionTokenDisposition::Discard);
        assert_eq!(restored.session_token, None);
        assert!(!restored.should_refresh_session);
        assert!(restored.should_delete_stored_session_token);
    }

    /// サインイン記録が無い端末では保存済みトークンに一切触らない
    /// (勝手に消すと、別経路で書かれたトークンを壊す)。
    #[test]
    fn nothing_is_restored_without_a_user_id() {
        let restored = restore_stored_state(
            StoredAuthState {
                user_id: None,
                identity_token: Some(token_named("apple_identity_style_exp_only").into()),
                session_token: Some(token_named("iss_wrong").into()),
                is_admin_flag: Some("1".into()),
                is_banned_flag: Some("1".into()),
            },
            NOW,
        );
        assert!(!restored.is_signed_in);
        assert_eq!(restored.identity_token, None);
        assert_eq!(restored.session_token, None);
        assert_eq!(restored.session_disposition, SessionTokenDisposition::Absent);
        assert!(!restored.should_delete_stored_session_token);
        assert!(!restored.is_admin);
        assert!(!restored.is_banned);
    }

    #[test]
    fn a_live_identity_token_survives_but_an_expired_one_does_not() {
        let live = restore_stored_state(
            stored(None, Some(token_named("apple_identity_style_exp_only"))),
            NOW,
        );
        assert!(live.identity_token.is_some());
        assert_eq!(live.session_disposition, SessionTokenDisposition::Absent);

        let dead = restore_stored_state(stored(None, Some(token_named("apple_identity_expired"))), NOW);
        assert_eq!(dead.identity_token, None);
    }

    /// Keychain は文字列しか持てないので "1" だけが true。
    #[test]
    fn only_the_string_one_restores_a_flag() {
        for (raw, expected) in [
            (Some("1"), true),
            (Some("0"), false),
            (Some("true"), false),
            (Some(""), false),
            (None, false),
        ] {
            let restored = restore_stored_state(
                StoredAuthState {
                    user_id: Some("u".into()),
                    identity_token: None,
                    session_token: None,
                    is_admin_flag: raw.map(str::to_string),
                    is_banned_flag: raw.map(str::to_string),
                    },
                NOW,
            );
            assert_eq!(restored.is_admin, expected, "admin flag {raw:?}");
            assert_eq!(restored.is_banned, expected, "banned flag {raw:?}");
        }
    }

    #[test]
    fn stored_flags_round_trip() {
        assert_eq!(stored_flag_value(true), "1");
        assert_eq!(stored_flag_value(false), "0");
        assert!(decode_stored_flag(Some(&stored_flag_value(true))));
        assert!(!decode_stored_flag(Some(&stored_flag_value(false))));
    }

    // ── リクエストに載せるトークン ────────────────────────

    #[test]
    fn the_session_token_wins_over_the_identity_token() {
        assert_eq!(
            bearer_token(Some("session".into()), Some("identity".into())),
            Some("session".into())
        );
        assert_eq!(bearer_token(None, Some("identity".into())), Some("identity".into()));
        assert_eq!(bearer_token(None, None), None);
    }

    /// 期限切れでも「送らない」判断はしない。401 を受けて自動リフレッシュに乗せるのが正で、
    /// ここで弾くと無言で失敗する (過去の投票機能の事故)。
    #[test]
    fn an_expired_token_is_still_sent() {
        let expired = token_named("exp_past").to_string();
        assert_eq!(bearer_token(Some(expired.clone()), None), Some(expired));
    }

    // ── 再発行 ───────────────────────────────────────────

    #[test]
    fn refresh_falls_back_to_the_stored_token() {
        let stored_token = token_named("exp_past").to_string();
        assert_eq!(
            session_refresh_candidate(None, Some(stored_token.clone())),
            Some(stored_token)
        );
    }

    #[test]
    fn refresh_prefers_the_in_memory_token() {
        assert_eq!(
            session_refresh_candidate(
                Some(token_named("valid_far_future").into()),
                Some(token_named("exp_past").into())
            ),
            Some(token_named("valid_far_future").into())
        );
    }

    /// 形が違うトークンで `/auth/refresh` を叩いても 401 が返るだけなので投げない。
    #[test]
    fn a_malformed_token_produces_no_refresh_request() {
        assert_eq!(
            session_refresh_candidate(Some(token_named("alg_rs256").into()), None),
            None
        );
        assert_eq!(session_refresh_candidate(None, None), None);
    }

    // ── サーバ応答の反映 ──────────────────────────────────

    fn login(token: &str, is_admin: bool, display_name: Option<&str>) -> SessionResponse {
        SessionResponse {
            session_token: token.into(),
            is_admin,
            display_name: display_name.map(str::to_string),
        }
    }

    #[test]
    fn a_valid_login_response_is_adopted_whole() {
        let adoption = adopt_session_response(
            login(token_named("valid_far_future"), true, Some("プロデューサー")),
            NOW,
        );
        assert!(adoption.accepted);
        assert_eq!(
            adoption.session_token.as_deref(),
            Some(token_named("valid_far_future"))
        );
        assert_eq!(adoption.is_admin, Some(true));
        assert_eq!(adoption.display_name.as_deref(), Some("プロデューサー"));
    }

    /// claims が想定外なら admin も表示名も反映しない (トークンだけ捨てて他は残す、をやらない)。
    #[test]
    fn a_response_with_foreign_claims_changes_nothing() {
        let adoption = adopt_session_response(login(token_named("aud_wrong"), true, Some("x")), NOW);
        assert!(!adoption.accepted);
        assert_eq!(adoption.session_token, None);
        assert_eq!(adoption.is_admin, None);
        assert_eq!(adoption.display_name, None);
    }

    /// サーバが表示名を空で返しても、ローカルの表示名は消さない。
    #[test]
    fn an_empty_display_name_in_a_login_response_keeps_the_current_one() {
        for name in [None, Some("")] {
            let adoption =
                adopt_session_response(login(token_named("valid_far_future"), false, name), NOW);
            assert!(adoption.accepted);
            assert_eq!(adoption.display_name, None, "name={name:?}");
        }
    }

    /// `/auth/refresh` は表示名を返さない契約。渡さなければ触らない。
    #[test]
    fn a_refresh_response_leaves_the_display_name_alone() {
        let adoption = adopt_session_response(login(token_named("valid_far_future"), true, None), NOW);
        assert!(adoption.accepted);
        assert_eq!(adoption.is_admin, Some(true));
        assert_eq!(adoption.display_name, None);
    }

    /// 401 → `handleSessionExpired` で isSignedIn=false にした後、`/auth/refresh` が
    /// 通ったらサインイン済みに戻す (原本 `performSessionRefresh` の `isSignedIn = true`)。
    /// これを落とすと、ログイン済みなのにログイン導線が出たままになる。
    #[test]
    fn an_adopted_response_restores_the_signed_in_state() {
        let adoption = adopt_session_response(login(token_named("valid_far_future"), true, None), NOW);
        assert!(adoption.accepted);
        assert_eq!(adoption.is_signed_in, Some(true));
    }

    /// 逆に、採用しなかった応答はサインイン状態に触らない (原本はその場で return するだけ)。
    /// ここで false を返すと、401 でない普通の失敗でサインアウトさせてしまう。
    #[test]
    fn a_rejected_response_leaves_the_signed_in_state_alone() {
        let adoption = adopt_session_response(login(token_named("aud_wrong"), true, Some("x")), NOW);
        assert!(!adoption.accepted);
        assert_eq!(adoption.is_signed_in, None);
    }

    // ── /auth/me ─────────────────────────────────────────

    fn me(is_admin: bool, is_banned: bool, display_name: Option<&str>) -> MeResponse {
        MeResponse {
            is_admin,
            is_banned,
            display_name: display_name.map(str::to_string),
        }
    }

    /// BAN はサーバでしか立たず `/auth/login` にも含まれない。ここが唯一の反映経路なので、
    /// 毎回サーバの値で上書きする (false への解除も反映される)。
    #[test]
    fn me_overwrites_admin_and_ban_in_both_directions() {
        let banned = apply_me_response(me(false, true, None), Some("P"));
        assert!(banned.is_banned);
        assert!(!banned.is_admin);

        let lifted = apply_me_response(me(true, false, None), Some("P"));
        assert!(!lifted.is_banned);
        assert!(lifted.is_admin);
    }

    #[test]
    fn me_only_reports_a_display_name_that_actually_changed() {
        assert_eq!(apply_me_response(me(false, false, Some("P")), Some("P")).display_name, None);
        assert_eq!(
            apply_me_response(me(false, false, Some("Q")), Some("P")).display_name,
            Some("Q".into())
        );
        assert_eq!(apply_me_response(me(false, false, None), Some("P")).display_name, None);
        assert_eq!(
            apply_me_response(me(false, false, Some("P")), None).display_name,
            Some("P".into())
        );
    }

    /// iOS は `/auth/me` の空文字を「表示名なし」ではなく値として扱い、既存名を空にする。
    /// Android は空を null 扱いして既存名を残す (= ズレ)。iOS を正として固定する。
    #[test]
    fn me_adopts_an_empty_display_name_ios_style() {
        assert_eq!(
            apply_me_response(me(false, false, Some("")), Some("P")).display_name,
            Some(String::new())
        );
        // 既に空なら「変化なし」。
        assert_eq!(
            apply_me_response(me(false, false, Some("")), Some("")).display_name,
            None
        );
    }

    // ── トークン交換のリトライ ────────────────────────────

    #[test]
    fn a_transport_failure_is_retried_until_the_attempts_run_out() {
        assert_eq!(
            token_exchange_retry(0, TokenExchangeOutcome::Failed),
            RetryDecision::RetryAfter { delay_millis: 1_500 }
        );
        assert_eq!(
            token_exchange_retry(1, TokenExchangeOutcome::Failed),
            RetryDecision::RetryAfter { delay_millis: 1_500 }
        );
        assert_eq!(
            token_exchange_retry(2, TokenExchangeOutcome::Failed),
            RetryDecision::Stop
        );
    }

    /// 401 は identityToken が無効ということなので、待っても結果は変わらない。
    #[test]
    fn an_unauthorized_exchange_is_never_retried() {
        for attempt in 0..TOKEN_EXCHANGE_MAX_ATTEMPTS {
            assert_eq!(
                token_exchange_retry(attempt, TokenExchangeOutcome::Unauthorized),
                RetryDecision::Stop
            );
            assert_eq!(
                token_exchange_retry(attempt, TokenExchangeOutcome::Succeeded),
                RetryDecision::Stop
            );
        }
    }

    /// 3 回で打ち切る = identityToken (10 分) が生きているうちに終わる。
    #[test]
    fn the_whole_retry_budget_stays_well_inside_the_identity_token_lifetime() {
        let total_wait_millis: u64 = (0..TOKEN_EXCHANGE_MAX_ATTEMPTS)
            .filter_map(|attempt| match token_exchange_retry(attempt, TokenExchangeOutcome::Failed) {
                RetryDecision::RetryAfter { delay_millis } => Some(delay_millis),
                RetryDecision::Stop => None,
            })
            .sum();
        assert!(total_wait_millis < 10 * 60 * 1_000, "{total_wait_millis}ms");
    }

    // ── admin 権限 ───────────────────────────────────────

    #[test]
    fn admin_opens_every_moderation_capability_at_once() {
        let admin = admin_capabilities(true);
        assert!(admin.can_moderate_users);
        assert!(admin.can_apply_master_edit_directly);
        assert!(admin.can_edit_lyrics);

        let member = admin_capabilities(false);
        assert!(!member.can_moderate_users);
        assert!(!member.can_apply_master_edit_directly);
        assert!(!member.can_edit_lyrics);
    }

    // ── JWT パースの癖 (元実装と同じであることを名前で残す) ──

    /// Swift の `split(separator:)` が空セグメントを落とすため、末尾/先頭の余分な `.` は無視され、
    /// 逆に空のペイロード (`h..sig`) は 3 分割にならず不正になる。
    #[test]
    fn empty_segments_are_dropped_before_counting() {
        assert!(is_valid_session_token(token_named("trailing_dot"), NOW));
        assert!(is_valid_session_token(token_named("leading_dot"), NOW));
        assert!(!is_valid_session_token(token_named("empty_middle_segment"), NOW));
    }

    /// 重複キーは先勝ち。攻撃者が `{"exp":1,"exp":<遠い未来>}` を持ち込んでも、
    /// 先に書かれた期限切れの方が採用される。
    #[test]
    fn duplicate_claims_resolve_to_the_first_occurrence() {
        assert!(is_jwt_expired(token_named("duplicate_exp_key"), NOW));
        assert!(!is_valid_session_token(token_named("dup_alg_first_bad"), NOW));
        assert!(is_valid_session_token(token_named("dup_alg_first_good"), NOW));
    }

    /// 数値 claim は Double で厳密に表せる時だけ採用される (NSNumber → Double の条件付きキャスト)。
    #[test]
    fn integer_claims_beyond_double_precision_are_rejected() {
        assert!(is_refreshable_session_token(token_named("exp_2pow53")));
        assert!(!is_refreshable_session_token(token_named("exp_2pow53_plus_1")));
        assert!(!is_refreshable_session_token(token_named("exp_uint64_max")));
    }

    // ── Apple サインイン ──────────────────────────────────

    /// 姓 → 名 の順。Apple が氏名を返すのは初回だけなので、空になるなら採用しない。
    #[test]
    fn an_apple_full_name_is_family_then_given() {
        assert_eq!(
            display_name_from_apple_name(Some("天海".into()), Some("春香".into())),
            Some("天海 春香".into())
        );
        assert_eq!(
            display_name_from_apple_name(None, Some("春香".into())),
            Some("春香".into())
        );
        assert_eq!(
            display_name_from_apple_name(Some("天海".into()), None),
            Some("天海".into())
        );
        assert_eq!(display_name_from_apple_name(None, None), None);
    }

    /// nil だけを落として空文字は落とさない (元実装の `compactMap` と同じ) ので、
    /// 姓が空文字なら先頭に空白が残る。ここを "trim して綺麗にする" と挙動が変わる。
    #[test]
    fn an_empty_family_name_keeps_its_separator() {
        assert_eq!(
            display_name_from_apple_name(Some(String::new()), Some("春香".into())),
            Some(" 春香".into())
        );
        assert_eq!(
            display_name_from_apple_name(Some(String::new()), Some(String::new())),
            Some(" ".into())
        );
    }

    /// revoked は 1 回で確定させない (一時的に revoked を返す端末で誤爆する)。
    #[test]
    fn a_revoked_credential_is_confirmed_before_signing_out() {
        assert_eq!(
            credential_check_action(AppleCredentialState::Revoked, false),
            CredentialCheckAction::RecheckAfter { delay_millis: 2_000 }
        );
        assert_eq!(
            credential_check_action(AppleCredentialState::Revoked, true),
            CredentialCheckAction::SignOut
        );
    }

    /// 再確認で revoked 以外が返ったら復帰扱い。サインアウトしない。
    #[test]
    fn a_recheck_only_acts_on_a_second_revocation() {
        for state in [
            AppleCredentialState::Authorized,
            AppleCredentialState::NotFound,
            AppleCredentialState::Transferred,
            AppleCredentialState::Unknown,
        ] {
            assert_eq!(
                credential_check_action(state, true),
                CredentialCheckAction::KeepSession,
                "{state:?}"
            );
        }
    }

    /// 復帰しない状態は 1 回目で確定。未知の値も安全側 (サインアウト) に倒す。
    #[test]
    fn an_unrecoverable_credential_signs_out_immediately() {
        for state in [
            AppleCredentialState::NotFound,
            AppleCredentialState::Transferred,
            AppleCredentialState::Unknown,
        ] {
            assert_eq!(
                credential_check_action(state, false),
                CredentialCheckAction::SignOut,
                "{state:?}"
            );
        }
        assert_eq!(
            credential_check_action(AppleCredentialState::Authorized, false),
            CredentialCheckAction::KeepSession
        );
    }
}
