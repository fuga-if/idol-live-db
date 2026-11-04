//! YouTube の URL の読み方 (動画 id の取り出しと、投稿を受け付けるかの先行判定)。
//!
//! iOS (`YouTube+ID.swift` / `SongCommunityEditView.isYouTubeURL`) と Android
//! (`SongDetailScreen.youTubeVideoId` / `VideoEditSheet.isYouTubeUrl`) に写経されていて、
//! 受け付ける形が割れていた (`/v/<id>` は iOS だけ、パスの途中の `embed/` は Android だけ)。
//! ここでは**両方の和集合**を受け付ける (§8 P5-10)。
//!
//! 投稿の本当の検査はサーバ (`master_validators.ts` の正規表現) が行う。ここは
//! 「送る前に分かる間違い」を弾くのと、表示用のサムネイルを出すための id 取り出しだけ。

/// 動画 id の長さ (YouTube の id は `[A-Za-z0-9_-]` の 11 文字)。
const VIDEO_ID_LEN: usize = 11;

/// id の前に置かれうるパスの語 (`/embed/<id>` / `/shorts/<id>` / `/live/<id>` / `/v/<id>`)。
const ID_PATH_PREFIXES: [&str; 4] = ["embed", "shorts", "live", "v"];

/// 投稿を受け付ける YouTube のホスト。
const YOUTUBE_HOSTS: [&str; 5] =
    ["youtu.be", "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"];

/// http(s) の URL を、ホスト・パスの語・クエリに割ったもの。
struct HttpUrl<'a> {
    /// 小文字にしたホスト (ポートと userinfo は落とす)。
    host: String,
    path: &'a str,
    query: &'a str,
}

/// http / https の URL だけを読む (`javascript:` などは読まない)。ホストが空なら読まない。
fn parse_http(raw: &str) -> Option<HttpUrl<'_>> {
    let (scheme, rest) = raw.split_once("://")?;
    if !scheme.eq_ignore_ascii_case("http") && !scheme.eq_ignore_ascii_case("https") {
        return None;
    }
    let rest = rest.split('#').next().unwrap_or_default();
    let authority_end = rest.find(['/', '?']).unwrap_or(rest.len());
    let (authority, tail) = rest.split_at(authority_end);
    let host_port = authority.rsplit('@').next().unwrap_or_default();
    let host = host_port.split(':').next().unwrap_or_default().to_ascii_lowercase();
    if host.is_empty() {
        return None;
    }
    let (path, query) = tail.split_once('?').unwrap_or((tail, ""));
    Some(HttpUrl { host, path, query })
}

/// `%xx` を戻す (動画 id に要る範囲)。壊れた `%` はそのまま残す。
fn percent_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let hex = |b: u8| (b as char).to_digit(16);
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (hex(bytes[i + 1]), hex(bytes[i + 2])) {
                out.push((h * 16 + l) as u8);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// 候補の文字列の頭から id を取り出す (余分なクエリや記号が続いてもよい)。
/// 頭の英数字・`_`・`-` がちょうど 11 文字で、すべて ASCII のときだけ id とみなす。
fn normalize_id(raw: &str) -> Option<String> {
    let id: String = raw
        .chars()
        .take_while(|c| c.is_alphanumeric() || *c == '_' || *c == '-')
        .collect();
    (id.chars().count() == VIDEO_ID_LEN && id.is_ascii()).then_some(id)
}

/// URL から 11 文字の動画 id を取り出す。取れなければ `None`。
///
/// 受け付ける形: `youtu.be/<id>`、`youtube.com/watch?v=<id>`、`youtube.com/{embed,shorts,live,v}/<id>`
/// (その語はパスのどこにあってもよい)。ホストは「`youtu.be` / `youtube.com` を含む」で見る。
pub fn video_id(url: &str) -> Option<String> {
    let url = parse_http(url)?;
    let mut segments = url.path.split('/').filter(|s| !s.is_empty());
    if url.host.contains("youtu.be") {
        return segments.next().and_then(normalize_id);
    }
    if !url.host.contains("youtube.com") {
        return None;
    }
    let from_query = url
        .query
        .split('&')
        .find_map(|pair| pair.split_once('=').filter(|(k, _)| *k == "v").map(|(_, v)| v))
        .and_then(|v| normalize_id(&percent_decode(v)));
    if from_query.is_some() {
        return from_query;
    }
    let segments: Vec<&str> = segments.collect();
    let at = segments.iter().position(|s| ID_PATH_PREFIXES.contains(s))?;
    segments.get(at + 1).and_then(|s| normalize_id(s))
}

/// 投稿の前に「YouTube の URL か」を見る (http(s) で、ホストが YouTube のもの)。
/// パスの形はサーバの検査に任せる (両 OS と同じ)。
pub fn is_youtube_url(url: &str) -> bool {
    parse_http(url).is_some_and(|u| YOUTUBE_HOSTS.contains(&u.host.as_str()))
}

/// サムネイルの URL。`maxresdefault` (16:9 の高解像度) と、それが無い動画向けの
/// `mqdefault` (16:9 で必ずある)。`hqdefault` は 4:3 で黒帯が入るので使わない。
pub fn thumbnail_urls(video_id: &str) -> (String, String) {
    (
        format!("https://i.ytimg.com/vi/{video_id}/maxresdefault.jpg"),
        format!("https://i.ytimg.com/vi/{video_id}/mqdefault.jpg"),
    )
}

/// 動画 1 本ぶんの読み取り結果 (一覧の行に出すもの)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YouTubeVideoRef {
    /// 11 文字の動画 id。読めない URL なら `None` (行はリンクだけにする)。
    pub video_id: Option<String>,
    /// 16:9 の高解像度サムネイル。
    pub thumbnail_url: Option<String>,
    /// 高解像度が無い動画向けの 16:9 サムネイル。
    pub fallback_thumbnail_url: Option<String>,
}

/// 動画の URL の列を 1 回で読む (入力と同じ並び)。一覧で行ごとに FFI を呼ばないための形。
pub fn video_refs(urls: &[String]) -> Vec<YouTubeVideoRef> {
    urls.iter()
        .map(|url| {
            let id = video_id(url);
            let thumbs = id.as_deref().map(thumbnail_urls);
            YouTubeVideoRef {
                thumbnail_url: thumbs.as_ref().map(|t| t.0.clone()),
                fallback_thumbnail_url: thumbs.map(|t| t.1),
                video_id: id,
            }
        })
        .collect()
}

/// アプリ内の埋め込みプレーヤーが「どこのページか」を名乗る origin。
///
/// YouTube の埋め込みは呼び出し元 (Referer / `origin`) を名乗らないページを
/// エラー 153 で弾く。アプリの WebView は HTML を文字列で読むので、公開サイトの
/// origin を base URL にして名乗る (両 OS 同じ)。
pub const EMBED_ORIGIN: &str = crate::domain::share_text::WEB_ORIGIN;

/// プレーヤーのページから OS へ送る口の名前
/// (iOS は `webkit.messageHandlers.<名前>`、Android は `addJavascriptInterface` の名前)。
pub const PLAYER_BRIDGE_NAME: &str = "imasPlayer";

/// 開始秒の上限 (これより大きい値は誤記として読まない。12 時間)。
const MAX_START_SECONDS: u32 = 12 * 60 * 60;

/// `t=` / `start=` の値を秒に読む。`90`・`90s`・`1m30s`・`1h2m3s` を受け付ける。
fn parse_start(value: &str) -> Option<u32> {
    if value.is_empty() {
        return None;
    }
    if let Ok(secs) = value.parse::<u32>() {
        return Some(secs);
    }
    let mut total: u32 = 0;
    let mut digits = String::new();
    for c in value.chars() {
        if c.is_ascii_digit() {
            digits.push(c);
            continue;
        }
        let n: u32 = digits.parse().ok()?;
        digits.clear();
        let unit = match c {
            'h' => 3600,
            'm' => 60,
            's' => 1,
            _ => return None,
        };
        total = total.checked_add(n.checked_mul(unit)?)?;
    }
    if !digits.is_empty() {
        return None;
    }
    Some(total)
}

/// URL の `t=` / `start=` から開始秒を読む (無い・読めない・0 なら `None`)。
pub fn start_seconds(url: &str) -> Option<u32> {
    let url = parse_http(url)?;
    url.query
        .split('&')
        .filter_map(|pair| pair.split_once('='))
        .find(|(k, _)| *k == "t" || *k == "start")
        .and_then(|(_, v)| parse_start(&percent_decode(v)))
        .filter(|s| *s > 0 && *s <= MAX_START_SECONDS)
}

/// アプリ内で再生するための埋め込みプレーヤー (WebView に読ませる 1 ページ)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct YouTubeEmbedPlayer {
    /// WebView に文字列で読ませる HTML。YouTube の IFrame Player API を使う。
    pub html: String,
    /// HTML を読ませるときの base URL ([`EMBED_ORIGIN`])。これが無いと 153 で弾かれる。
    pub base_url: String,
    /// ページから OS へ送る口の名前 ([`PLAYER_BRIDGE_NAME`])。
    pub bridge_name: String,
}

/// プレーヤーのページが OS へ送る知らせ。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum YouTubePlayerEvent {
    /// 再生できる状態になった。
    Ready,
    /// この動画はアプリ内で再生できない (投稿者が埋め込みを止めている・削除済み・
    /// 読み込めない)。YouTube で開く案内に替える。
    Unplayable,
    /// 知らない知らせ (読み捨てる)。
    Other,
}

/// ページが送る文字列を知らせに読む (`ready` / `unplayable` / `unplayable:<code>`)。
pub fn player_event(message: &str) -> YouTubePlayerEvent {
    match message.split(':').next().unwrap_or_default() {
        "ready" => YouTubePlayerEvent::Ready,
        "unplayable" => YouTubePlayerEvent::Unplayable,
        _ => YouTubePlayerEvent::Other,
    }
}

/// 参考動画の URL から埋め込みプレーヤーを組む。動画 id が読めなければ `None`
/// (その行は外部リンクのまま)。
///
/// その場で再生し (`playsinline`)、押した操作で開くので自動再生する。関連動画は
/// 同じチャンネルに絞る (`rel=0`)。埋め込みを止めている動画 (公式 MV に多い) は
/// YouTube の仕様でどうやっても再生できないので、`onError` で `unplayable` を送る。
pub fn embed_player(url: &str) -> Option<YouTubeEmbedPlayer> {
    let id = video_id(url)?;
    let start = start_seconds(url).unwrap_or(0);
    let origin = EMBED_ORIGIN;
    let bridge = PLAYER_BRIDGE_NAME;
    let html = format!(
        r#"<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><style>html,body{{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}}#player{{position:absolute;inset:0;width:100%;height:100%}}</style></head><body><div id="player"></div><script>
function send(m){{try{{if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.{bridge}){{window.webkit.messageHandlers.{bridge}.postMessage(m)}}else if(window.{bridge}){{window.{bridge}.post(m)}}}}catch(e){{}}}}
var api=document.createElement('script');api.src='https://www.youtube.com/iframe_api';api.onerror=function(){{send('unplayable:load')}};document.head.appendChild(api);
function onYouTubeIframeAPIReady(){{new YT.Player('player',{{width:'100%',height:'100%',videoId:'{id}',playerVars:{{playsinline:1,autoplay:1,rel:0,start:{start},origin:'{origin}',widget_referrer:'{origin}'}},events:{{onReady:function(e){{send('ready');e.target.playVideo()}},onError:function(e){{send('unplayable:'+e.data)}}}}}})}}
</script></body></html>"#
    );
    Some(YouTubeEmbedPlayer {
        html,
        base_url: format!("{origin}/"),
        bridge_name: bridge.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "dQw4w9WgXcQ";

    #[test]
    fn reads_every_form_either_os_accepted() {
        for url in [
            format!("https://www.youtube.com/watch?v={ID}"),
            format!("https://www.youtube.com/watch?feature=share&v={ID}&t=30"),
            format!("https://youtu.be/{ID}"),
            format!("https://youtu.be/{ID}?si=abc"),
            format!("https://www.youtube.com/embed/{ID}"),
            format!("https://youtube.com/shorts/{ID}?feature=share"),
            format!("https://www.youtube.com/live/{ID}"),
            // iOS だけが受け付けていた形。
            format!("https://www.youtube.com/v/{ID}"),
            // Android だけが受け付けていた形 (語がパスの途中にある)。
            format!("https://www.youtube.com/user/foo/embed/{ID}"),
            format!("http://m.youtube.com/watch?v={ID}#t=10"),
            format!("https://music.youtube.com/watch?v={ID}"),
        ] {
            assert_eq!(video_id(&url).as_deref(), Some(ID), "{url}");
        }
    }

    #[test]
    fn rejects_what_is_not_a_video_url() {
        for url in [
            "",
            "javascript:alert(1)",
            "https://example.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=short",
            "https://www.youtube.com/channel/UCxxxxxxxxxxxxxx",
            "https://www.youtube.com/embed/",
            // 11 文字でも ASCII でない id は id ではない。
            "https://youtu.be/あいうえおかきくけこさ",
            "youtube.com/watch?v=dQw4w9WgXcQ",
        ] {
            assert_eq!(video_id(url), None, "{url}");
        }
    }

    #[test]
    fn query_value_is_percent_decoded() {
        assert_eq!(video_id("https://www.youtube.com/watch?v=dQw4w9WgXc%51").as_deref(), Some(ID));
    }

    #[test]
    fn upload_check_looks_only_at_scheme_and_host() {
        assert!(is_youtube_url(&format!("https://youtu.be/{ID}")));
        assert!(is_youtube_url("https://WWW.YouTube.com/anything"));
        assert!(is_youtube_url("http://music.youtube.com/"));
        assert!(!is_youtube_url("https://youtube.com.evil.example/watch?v=x"));
        assert!(!is_youtube_url("ftp://youtube.com/watch?v=x"));
        assert!(!is_youtube_url("https://"));
        assert!(!is_youtube_url(""));
    }

    #[test]
    fn refs_keep_the_input_order_and_leave_unreadable_urls_empty() {
        let refs = video_refs(&[format!("https://youtu.be/{ID}"), "https://example.com".to_string()]);
        assert_eq!(refs[0].video_id.as_deref(), Some(ID));
        assert!(refs[0].thumbnail_url.as_deref().is_some_and(|u| u.ends_with("maxresdefault.jpg")));
        assert_eq!(refs[1], YouTubeVideoRef { video_id: None, thumbnail_url: None, fallback_thumbnail_url: None });
    }

    #[test]
    fn start_seconds_reads_every_form() {
        assert_eq!(start_seconds("https://youtu.be/dQw4w9WgXcQ?t=90"), Some(90));
        assert_eq!(start_seconds("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s"), Some(90));
        assert_eq!(start_seconds("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1h2m3s"), Some(3723));
        assert_eq!(start_seconds("https://www.youtube.com/watch?v=dQw4w9WgXcQ&start=42"), Some(42));
        assert_eq!(start_seconds("https://youtu.be/dQw4w9WgXcQ?t=45s"), Some(45));
        assert_eq!(start_seconds("https://youtu.be/dQw4w9WgXcQ"), None);
        assert_eq!(start_seconds("https://youtu.be/dQw4w9WgXcQ?t=0"), None);
        assert_eq!(start_seconds("https://youtu.be/dQw4w9WgXcQ?t=abc"), None);
        assert_eq!(start_seconds("https://youtu.be/dQw4w9WgXcQ?t=1x"), None);
        assert_eq!(start_seconds("https://youtu.be/dQw4w9WgXcQ?t=99999999"), None);
    }

    #[test]
    fn embed_player_names_the_site_origin_and_carries_id_and_start() {
        let p = embed_player("https://youtu.be/dQw4w9WgXcQ?t=90").unwrap();
        assert_eq!(p.base_url, "https://idollivedb.fugaapp.site/");
        assert_eq!(p.bridge_name, "imasPlayer");
        assert!(p.html.contains("videoId:'dQw4w9WgXcQ'"));
        assert!(p.html.contains("start:90"));
        assert!(p.html.contains("playsinline:1"));
        assert!(p.html.contains("origin:'https://idollivedb.fugaapp.site'"));
        assert!(p.html.contains("window.webkit.messageHandlers.imasPlayer"));
        assert!(p.html.contains("window.imasPlayer.post"));
        assert!(embed_player("https://example.com/watch?v=dQw4w9WgXcQ").is_none());
    }

    #[test]
    fn player_events_are_read_from_the_page_messages() {
        assert_eq!(player_event("ready"), YouTubePlayerEvent::Ready);
        assert_eq!(player_event("unplayable"), YouTubePlayerEvent::Unplayable);
        assert_eq!(player_event("unplayable:150"), YouTubePlayerEvent::Unplayable);
        assert_eq!(player_event("unplayable:load"), YouTubePlayerEvent::Unplayable);
        assert_eq!(player_event("state:1"), YouTubePlayerEvent::Other);
    }
}
