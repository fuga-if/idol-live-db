//! P名刺の写真の欄の「X のアイコンを使う」。名刺のリンクにある X の ID から、
//! 公開のプロフィール API (ログイン不要・無料) を端末が読み、アイコンの画像を取ってくる。
//!
//! 通信は端末がする (サーバを持たない)。ここは、どの ID を使うか・どこを読むか・返ってきた中身を
//! どう分けるか・アイコンの画像の URL をどの大きさにするか、の規則だけを持つ。

use crate::domain::producer_card::{CardLink, CardLinkKind};

/// 公開のプロフィール API の在り処 (ID を後ろに付ける)。ここ 1 か所だけに書く。
const PROFILE_API_BASE: &str = "https://api.fxtwitter.com/2/profile/";

/// アイコンの画像を取りに行ってよい置き場 (返事の中の URL で、端末から任意の先へ通信させない)。
const AVATAR_IMAGE_ORIGIN: &str = "https://pbs.twimg.com/";

/// X の ID の長さの上限 (X の決まり)。
const MAX_X_HANDLE_CHARS: usize = 15;

/// プロフィールを読んだ結果。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum XAvatarLookup {
    /// アイコンが取れた。`image_urls` は大きい順の候補 (先頭から取りに行き、取れたもので止める)。
    Found { image_urls: Vec<String> },
    /// その ID のアカウントが無い (消えた・凍結・打ち間違い)。
    NotFound,
    /// 鍵アカウント。公開されていないアカウントのアイコンは取らない。
    Protected,
    /// 読めなかった (通信の失敗・混み合い・返事の形が変わった)。時間をおけば取れることがある。
    Unavailable,
}

/// 名刺のリンクから、アイコンを取る X の ID (`@` なし)。X のリンクが無い・ID の形が
/// X の決まりに合わない (英数字と `_` の 15 文字まで) なら None (「X のアイコンを使う」を出さない)。
pub fn card_x_avatar_handle(links: &[CardLink]) -> Option<String> {
    links
        .iter()
        .filter(|l| l.kind == CardLinkKind::X)
        .map(|l| l.value.trim().trim_start_matches('@').to_string())
        .find(|h| is_x_handle(h))
}

/// ID のプロフィールを読む URL。ID の形が合わなければ None。
pub fn x_profile_api_url(handle: &str) -> Option<String> {
    let handle = handle.trim().trim_start_matches('@');
    is_x_handle(handle).then(|| format!("{PROFILE_API_BASE}{handle}"))
}

/// プロフィールの返事 (HTTP の状態と本文) を分ける。`handle` は読みに行った ID
/// (別のアカウントの中身が返ってきたら使わない)。
pub fn x_avatar_lookup(handle: &str, status: u16, body: &str) -> XAvatarLookup {
    let handle = handle.trim().trim_start_matches('@');
    let json: Option<serde_json::Value> = serde_json::from_str(body).ok();
    let code = json
        .as_ref()
        .and_then(|j| j.get("code"))
        .and_then(serde_json::Value::as_u64);
    if status == 404 || code == Some(404) {
        return XAvatarLookup::NotFound;
    }
    if status != 200 {
        return XAvatarLookup::Unavailable;
    }
    let Some(user) = json.as_ref().and_then(|j| j.get("user")) else {
        return XAvatarLookup::Unavailable;
    };
    let same_account = user
        .get("screen_name")
        .and_then(serde_json::Value::as_str)
        .is_some_and(|s| s.eq_ignore_ascii_case(handle));
    if !same_account {
        return XAvatarLookup::Unavailable;
    }
    if user.get("protected").and_then(serde_json::Value::as_bool) == Some(true) {
        return XAvatarLookup::Protected;
    }
    let image_urls = user
        .get("avatar_url")
        .and_then(serde_json::Value::as_str)
        .map(x_avatar_image_urls)
        .unwrap_or_default();
    if image_urls.is_empty() {
        return XAvatarLookup::Unavailable;
    }
    XAvatarLookup::Found { image_urls }
}

/// 取れなかったときの案内 (取れたときは None)。どれも写真から選ぶ形に戻ることを添える。
pub fn x_avatar_lookup_message(lookup: &XAvatarLookup, handle: &str) -> Option<String> {
    let handle = handle.trim().trim_start_matches('@');
    let text = match lookup {
        XAvatarLookup::Found { .. } => return None,
        XAvatarLookup::NotFound => {
            format!("@{handle} のアカウントが見つかりませんでした。写真から選んでください。")
        }
        XAvatarLookup::Protected => {
            format!(
                "@{handle} は鍵アカウントなので、アイコンを取れません。写真から選んでください。"
            )
        }
        XAvatarLookup::Unavailable => {
            "X のアイコンを取れませんでした。時間をおいてもう一度試すか、写真から選んでください。"
                .to_string()
        }
    };
    Some(text)
}

/// アイコンの画像の URL を大きい順の候補にする。X のアイコンは名前の末尾 (`_normal` など) で
/// 大きさが決まり、末尾を外すと元の大きさ、`_400x400` で 400px になる。
/// 名刺の写真の枠 (縦長) に切り抜くので、小さい版 (48px) は使わずに大きい版から取りに行く。
/// X の画像の置き場 (`https://pbs.twimg.com/`) でない URL は使わない。
pub fn x_avatar_image_urls(avatar_url: &str) -> Vec<String> {
    let url = avatar_url.trim();
    if !url.starts_with(AVATAR_IMAGE_ORIGIN) {
        return Vec::new();
    }
    let (path, query) = url.split_once('?').map_or((url, ""), |(p, q)| (p, q));
    let slash = path.rfind('/').map_or(0, |i| i + 1);
    let (dir, file) = path.split_at(slash);
    let (stem, ext) = file
        .rfind('.')
        .map_or((file, ""), |i| (&file[..i], &file[i..]));
    const SIZES: [&str; 6] = [
        "_normal", "_bigger", "_mini", "_200x200", "_400x400", "_x96",
    ];
    let Some(base) = SIZES.iter().find_map(|s| stem.strip_suffix(s)) else {
        return vec![url.to_string()];
    };
    let with = |suffix: &str| {
        let q = if query.is_empty() {
            String::new()
        } else {
            format!("?{query}")
        };
        format!("{dir}{base}{suffix}{ext}{q}")
    };
    vec![with(""), with("_400x400")]
}

fn is_x_handle(s: &str) -> bool {
    !s.is_empty()
        && s.chars().count() <= MAX_X_HANDLE_CHARS
        && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn link(kind: CardLinkKind, value: &str) -> CardLink {
        CardLink {
            kind,
            value: value.into(),
        }
    }

    #[test]
    fn handle_comes_from_the_first_valid_x_link() {
        assert_eq!(card_x_avatar_handle(&[]), None);
        assert_eq!(
            card_x_avatar_handle(&[link(CardLinkKind::Bluesky, "fuga.bsky.social")]),
            None
        );
        assert_eq!(
            card_x_avatar_handle(&[
                link(CardLinkKind::Bluesky, "fuga.bsky.social"),
                link(CardLinkKind::X, "fuga.p"),
                link(CardLinkKind::X, "fuga_p"),
            ]),
            Some("fuga_p".into())
        );
        assert_eq!(
            card_x_avatar_handle(&[link(CardLinkKind::X, "a234567890123456")]),
            None
        );
    }

    #[test]
    fn api_url_only_for_valid_handles() {
        assert_eq!(
            x_profile_api_url("@fuga_p").as_deref(),
            Some("https://api.fxtwitter.com/2/profile/fuga_p")
        );
        assert_eq!(x_profile_api_url("../admin"), None);
        assert_eq!(x_profile_api_url(""), None);
        assert_eq!(x_profile_api_url("a b"), None);
    }

    #[test]
    fn avatar_urls_prefer_larger_sizes() {
        assert_eq!(
            x_avatar_image_urls("https://pbs.twimg.com/profile_images/1/abc_normal.jpg"),
            vec![
                "https://pbs.twimg.com/profile_images/1/abc.jpg".to_string(),
                "https://pbs.twimg.com/profile_images/1/abc_400x400.jpg".to_string(),
            ]
        );
        assert_eq!(
            x_avatar_image_urls("https://pbs.twimg.com/profile_images/1/a_b_bigger.png?x=1"),
            vec![
                "https://pbs.twimg.com/profile_images/1/a_b.png?x=1".to_string(),
                "https://pbs.twimg.com/profile_images/1/a_b_400x400.png?x=1".to_string(),
            ]
        );
        // 大きさの末尾が無ければそのまま。
        assert_eq!(
            x_avatar_image_urls("https://pbs.twimg.com/profile_images/1/abc.jpg"),
            vec!["https://pbs.twimg.com/profile_images/1/abc.jpg".to_string()]
        );
        assert!(x_avatar_image_urls("http://pbs.twimg.com/a_normal.jpg").is_empty());
        assert!(x_avatar_image_urls("https://evil.example/a_normal.jpg").is_empty());
        assert!(x_avatar_image_urls("https://pbs.twimg.com.evil.example/a_normal.jpg").is_empty());
        assert!(x_avatar_image_urls("javascript:alert(1)").is_empty());
    }

    #[test]
    fn messages_only_when_not_found() {
        let found = XAvatarLookup::Found {
            image_urls: vec!["https://a/b.jpg".into()],
        };
        assert_eq!(x_avatar_lookup_message(&found, "fuga_p"), None);
        for lookup in [
            XAvatarLookup::NotFound,
            XAvatarLookup::Protected,
            XAvatarLookup::Unavailable,
        ] {
            let text = x_avatar_lookup_message(&lookup, "@fuga_p").unwrap();
            assert!(text.contains("写真から選んで"), "{text}");
        }
        assert!(
            x_avatar_lookup_message(&XAvatarLookup::Protected, "@fuga_p")
                .unwrap()
                .starts_with("@fuga_p ")
        );
    }

    #[test]
    fn lookup_sorts_out_the_reply() {
        let ok = r#"{"code":200,"message":"OK","user":{"screen_name":"Fuga_P","protected":false,"avatar_url":"https://pbs.twimg.com/profile_images/1/abc_normal.jpg"}}"#;
        assert_eq!(
            x_avatar_lookup("fuga_p", 200, ok),
            XAvatarLookup::Found {
                image_urls: vec![
                    "https://pbs.twimg.com/profile_images/1/abc.jpg".into(),
                    "https://pbs.twimg.com/profile_images/1/abc_400x400.jpg".into(),
                ]
            }
        );
        let locked = r#"{"code":200,"user":{"screen_name":"fuga_p","protected":true,"avatar_url":"https://pbs.twimg.com/a_normal.jpg"}}"#;
        assert_eq!(
            x_avatar_lookup("fuga_p", 200, locked),
            XAvatarLookup::Protected
        );
        assert_eq!(
            x_avatar_lookup("fuga_p", 404, r#"{"code":404,"message":"User not found"}"#),
            XAvatarLookup::NotFound
        );
        assert_eq!(
            x_avatar_lookup("fuga_p", 200, r#"{"code":404,"message":"User not found"}"#),
            XAvatarLookup::NotFound
        );
        assert_eq!(
            x_avatar_lookup("fuga_p", 500, "oops"),
            XAvatarLookup::Unavailable
        );
        assert_eq!(
            x_avatar_lookup("fuga_p", 200, "<html>"),
            XAvatarLookup::Unavailable
        );
        // 別のアカウントの中身は使わない。
        assert_eq!(
            x_avatar_lookup("someone", 200, ok),
            XAvatarLookup::Unavailable
        );
        // アイコンの無い返事。
        let bare = r#"{"code":200,"user":{"screen_name":"fuga_p","protected":false}}"#;
        assert_eq!(
            x_avatar_lookup("fuga_p", 200, bare),
            XAvatarLookup::Unavailable
        );
    }
}
