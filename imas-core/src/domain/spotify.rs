//! Spotify 連携。利用者が自分で作った Spotify のアプリ (Client ID) でログインして使う。
//!
//! # なぜ利用者のキーなのか
//!
//! Spotify の Web API は、開発者モードのアプリだと使える人が 5 人まで
//! (2026-02 の改定。オーナーの Premium 契約も必須)。広く公開するための拡張枠は
//! 法人・大規模アプリ向けで、このアプリでは取れない。そこで各自が自分のアカウントで
//! アプリを作り、その Client ID でログインする。PKCE なので Client secret は要らない。
//!
//! # 何がここの持ち物か
//!
//! 通信と画面は各 OS。**どの検索語で探すか・どの結果を同じ曲と見なすか**と、
//! 案内の文言・リダイレクト先・権限はここ。iOS と Android で書き分けると、
//! 片方だけ別の曲を拾う・案内が食い違う、になる。
//!
//! # 曲の突き合わせ
//!
//! DB に Spotify の id も ISRC も無いので、検索して拾う。同名の別曲
//! (カバー・同名異曲) を拾わないよう、**曲名が一致し、かつ歌唱者か収録 CD の手がかりが
//! 1 つ以上ある**ものだけを採る。手がかりが無ければ「見つからない」と返す
//! (間違った曲がプレイリストに入るより、入らない方がまし)。

use crate::domain::snapshot::Snapshot;

/// 利用者が Spotify のアプリに登録するリダイレクト先。iOS・Android 共通。
pub const REDIRECT_URI: &str = "imaslivedb://spotify-callback";
/// 求める権限。プレイリストを作って曲を入れる・Spotify アプリを操作して鳴らす (再生位置を読む)。
pub const SCOPES: &str = "playlist-modify-private playlist-modify-public user-read-playback-state user-modify-playback-state app-remote-control";
/// 鳴らすのに要る権限。前の版でログインした人はこれを持っていない。
/// `app-remote-control` は Spotify アプリと SDK で繋ぐ権限 (iOS は Web API の鍵をそのまま SDK に渡す)。
const PLAYBACK_SCOPES: [&str; 3] = [
    "user-read-playback-state",
    "user-modify-playback-state",
    "app-remote-control",
];
/// 開発者向けのダッシュボード。ここでアプリを作る。
pub const DASHBOARD_URL: &str = "https://developer.spotify.com/dashboard";
/// 書き出したプレイリストの説明。
pub const PLAYLIST_DESCRIPTION: &str = "アイドルライブDB から作成";
/// 1 曲あたりに試す検索の数の上限。
const MAX_QUERIES: usize = 3;

/// 案内を出す端末。Spotify のアプリに登録してもらう値 (Bundle ID / パッケージ名と指紋) が違う。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SpotifyGuidePlatform {
    Ios,
    Android,
}

/// iOS アプリの Bundle ID。Spotify の SDK はこれで呼び出し元を確かめる。
pub const IOS_BUNDLE_ID: &str = "com.fugaif.ImasLiveDB";
/// Android アプリのパッケージ名。
pub const ANDROID_PACKAGE: &str = "site.fugaapp.imaslivedb";
/// Android アプリの署名の指紋 (Play が署名し直した鍵の SHA-1。利用者の端末に届く APK はこれ)。
pub const ANDROID_SHA1: &str = "1F:83:20:23:99:01:62:E7:A8:F1:57:AF:CA:68:9B:1C:BF:25:A2:D9";

/// 設定画面の案内。手順と、貼り付けてもらう値。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SpotifySetupGuide {
    pub dashboard_url: String,
    pub redirect_uri: String,
    pub scopes: String,
    /// 画面の頭の説明。
    pub lead: String,
    pub steps: Vec<SpotifyGuideStep>,
    /// 手順の下の注意 (Premium が要ること・他の人と使うとき)。
    pub notes: Vec<String>,
    /// ログインでつまずいたときの見直し先。Spotify の画面に出る文言と対にする。
    pub troubleshooting: Vec<String>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SpotifyGuideStep {
    pub title: String,
    pub detail: String,
    /// この手順で Spotify の画面に貼る値 (コピーの口を添える)。
    pub values: Vec<SpotifyGuideValue>,
}

/// 貼ってもらう値 1 つ。`label` は Spotify の画面の欄の名前そのまま。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SpotifyGuideValue {
    pub label: String,
    pub value: String,
}

pub fn setup_guide(platform: SpotifyGuidePlatform) -> SpotifySetupGuide {
    let value = |label: &str, value: &str| SpotifyGuideValue {
        label: label.to_string(),
        value: value.to_string(),
    };
    let step = |title: &str, detail: &str, values: Vec<SpotifyGuideValue>| SpotifyGuideStep {
        title: title.to_string(),
        detail: detail.to_string(),
        values,
    };
    let (sdk_step, sdk_values) = match platform {
        SpotifyGuidePlatform::Ios => (
            step(
                "「Web API」と「iOS」にチェックして保存",
                "「Which API/SDKs are you planning to use?」で Web API と iOS にチェックを入れます。出てきた iOS app bundles の欄に下の値を貼って「Add」を押し、規約に同意して「Save」を押します。",
                vec![],
            ),
            vec![value("iOS app bundles", IOS_BUNDLE_ID)],
        ),
        SpotifyGuidePlatform::Android => (
            step(
                "「Web API」と「Android」にチェックして保存",
                "「Which API/SDKs are you planning to use?」で Web API と Android にチェックを入れます。出てきた Android packages の欄に下の 2 つを貼って「Add」を押し、規約に同意して「Save」を押します。",
                vec![],
            ),
            vec![value("Package name", ANDROID_PACKAGE), value("SHA1 fingerprint", ANDROID_SHA1)],
        ),
    };
    SpotifySetupGuide {
        dashboard_url: DASHBOARD_URL.to_string(),
        redirect_uri: REDIRECT_URI.to_string(),
        scopes: SCOPES.to_string(),
        lead: "自分の Spotify アカウントで「アプリ」を作り、その Client ID を貼ると、曲を Spotify でフル尺で鳴らして歌詞を追いかけたり、セトリやプレイリストを Spotify のプレイリストに書き出したりできます。作るのは最初の 1 回だけです。".to_string(),
        steps: vec![
            step(
                "Spotify for Developers を開く",
                "下の「開発者サイトを開く」から、いつもの Spotify アカウントでログインします。初めてのときは利用規約への同意とメールアドレスの確認を求められます。",
                vec![],
            ),
            step(
                "「Create app」でアプリを作る",
                "App name と App description は何でもかまいません (例: アイドルライブDB)。Website は空のままで大丈夫です。",
                vec![],
            ),
            step(
                "Redirect URI を貼って「Add」",
                "下の値をコピーして Redirect URIs の欄に貼り、「Add」を押します。1 文字でも違うとログインできません。",
                vec![value("Redirect URIs", REDIRECT_URI)],
            ),
            SpotifyGuideStep { values: sdk_values, ..sdk_step },
            step(
                "Client ID を写して、ここに貼る",
                "できたアプリの画面 (Settings → Basic Information) にある Client ID をコピーして、下の欄に貼ります。Client secret は使いません。",
                vec![],
            ),
        ],
        notes: vec![
            "Spotify の決まりで、アプリを作った人が Spotify Premium に入っている必要があります。曲を鳴らすには、聴く人も Premium に入っている必要があります。".to_string(),
            "曲を鳴らすには、この端末に Spotify アプリが入っている必要があります (音は Spotify アプリから出ます)。".to_string(),
            "家族など自分以外のアカウントで使うときは、アプリの「User Management」にその人のメールアドレスを足します (5 人まで)。".to_string(),
        ],
        troubleshooting: vec![
            "「INVALID_CLIENT: Invalid redirect URI」と出たら、手順 3 の Redirect URI が 1 文字でも違っています。".to_string(),
            "「INVALID_CLIENT: Invalid client」と出たら、Client ID の貼り間違いです。".to_string(),
            "曲を鳴らすときに Spotify アプリで断られたら、手順 4 の値が 1 文字でも違っていないかを確かめてください。".to_string(),
        ],
    }
}

/// Client ID の入力を確かめた結果。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SpotifyClientIdCheck {
    /// 使える形に整えた値。使えなければ `None`。
    pub normalized: Option<String>,
    /// 入力欄の下に出す誤り。空欄・使える値なら `None`。
    pub problem: Option<String>,
}

/// 貼られた Client ID を確かめる。Spotify の Client ID は 16 進 32 文字。
///
/// 貼り付けで前後や途中に空白・改行が混ざるので取り除く。全角で入っても通す。
pub fn check_client_id(input: &str) -> SpotifyClientIdCheck {
    let cleaned: String = input
        .chars()
        .map(fold_width)
        .filter(|c| !c.is_whitespace())
        .collect::<String>()
        .to_ascii_lowercase();
    if cleaned.is_empty() {
        return SpotifyClientIdCheck {
            normalized: None,
            problem: None,
        };
    }
    if cleaned.len() == 32 && cleaned.chars().all(|c| c.is_ascii_hexdigit()) {
        return SpotifyClientIdCheck {
            normalized: Some(cleaned),
            problem: None,
        };
    }
    let problem = if cleaned.len() == 32 {
        "Client ID は 0〜9 と a〜f の 32 文字です。Client secret を貼っていないか確かめてください。"
    } else {
        "Client ID は 32 文字です。途中で切れていないか確かめてください。"
    };
    SpotifyClientIdCheck {
        normalized: None,
        problem: Some(problem.to_string()),
    }
}

/// Spotify の検索結果の 1 曲。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SpotifyTrackCandidate {
    pub name: String,
    pub artists: Vec<String>,
    pub album: String,
}

/// 突き合わせの材料。snapshot から集める。
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SongClues {
    pub title: String,
    /// 原唱者の名前 (アイドル)。
    pub performers: Vec<String>,
    pub unit_name: Option<String>,
    pub singer_label: Option<String>,
    pub cd_title: Option<String>,
}

impl SongClues {
    pub fn from_snapshot(snap: &Snapshot, song_id: &str) -> Option<Self> {
        let song = snap.song(song_id)?;
        Some(Self {
            title: song.title.clone(),
            performers: snap
                .song_artists(song_id, Some("original"))
                .iter()
                .map(|i| i.name.clone())
                .collect(),
            unit_name: song.unit_name.clone(),
            singer_label: song.singer_label.clone(),
            cd_title: song.cd_title.clone(),
        })
    }
}

/// 試す順に並べた検索語。先頭で見つかれば後ろは投げない。
pub fn search_queries(clues: &SongClues) -> Vec<String> {
    let title = clues.title.trim();
    if title.is_empty() {
        return vec![];
    }
    let mut out: Vec<String> = Vec::new();
    let mut push = |q: String| {
        if !out.contains(&q) {
            out.push(q);
        }
    };
    // 歌唱者名は Spotify の名義 (「島村卯月 (CV: 大橋彩香)」) にそのまま含まれる。
    if let Some(name) = clues
        .performers
        .iter()
        .map(|s| s.trim())
        .find(|s| !s.is_empty())
    {
        push(format!("{title} {name}"));
    }
    if let Some(unit) = non_empty(clues.unit_name.as_deref()) {
        push(format!("{title} {unit}"));
    }
    push(title.to_string());
    out.truncate(MAX_QUERIES);
    out
}

/// 検索結果から同じ曲を選ぶ。無ければ `None`。
///
/// 曲名の一致は必須。そのうえで手がかり (歌唱者・ユニット・収録 CD・アイマスの名義) が
/// 多いものを採り、同点なら Spotify の並び (先の方) を採る。
pub fn pick_track(clues: &SongClues, candidates: &[SpotifyTrackCandidate]) -> Option<usize> {
    let title_key = match_key(&clues.title);
    if title_key.is_empty() {
        return None;
    }
    let people: Vec<String> = clues
        .performers
        .iter()
        .map(String::as_str)
        .chain(non_empty(clues.unit_name.as_deref()))
        .chain(
            clues
                .singer_label
                .as_deref()
                .into_iter()
                .flat_map(|s| s.split(['、', ',', '／', '/', '&', '＆'])),
        )
        .map(match_key)
        // 1 文字の名前は他の名義に紛れて当たってしまう。
        .filter(|k| k.chars().count() >= 2)
        .collect();
    let cd_key = clues
        .cd_title
        .as_deref()
        .map(match_key)
        .filter(|k| !k.is_empty());

    let mut best: Option<(usize, u32)> = None;
    for (index, c) in candidates.iter().enumerate() {
        let name_key = match_key(&c.name);
        if !same_title(&title_key, &name_key) {
            continue;
        }
        let artist_keys: Vec<String> = c.artists.iter().map(|a| match_key(a)).collect();
        let album_key = match_key(&c.album);
        let mut score = 0;
        if people
            .iter()
            .any(|p| artist_keys.iter().any(|a| a.contains(p.as_str())))
        {
            score += 2;
        }
        if let Some(cd) = &cd_key {
            if album_key.contains(cd.as_str())
                || (!album_key.is_empty() && cd.contains(album_key.as_str()))
            {
                score += 1;
            }
        }
        if IMAS_MARKS
            .iter()
            .any(|m| album_key.contains(m) || artist_keys.iter().any(|a| a.contains(m)))
        {
            score += 1;
        }
        if score == 0 {
            continue;
        }
        if best.is_none_or(|(_, s)| score > s) {
            best = Some((index, score));
        }
    }
    best.map(|(i, _)| i)
}

/// アイマスの名義・CD に付く語 (突き合わせ用に畳んだ形)。
const IMAS_MARKS: [&str; 3] = ["idolm@ster", "あいどるますたー", "m@ster"];
/// 曲名に無ければ別の録音 (カラオケ) と見なす語。
const KARAOKE_MARKS: [&str; 4] = ["offvocal", "instrumental", "からおけ", "inst"];

/// 曲名が同じか。Spotify は版の書き方が揺れる (「(M@STER VERSION)」と「- M@STER VERSION」)
/// ので記号は落としてから比べる。カラオケは曲名に書いてなければ別物。
fn same_title(title_key: &str, name_key: &str) -> bool {
    if title_key == name_key {
        return true;
    }
    // 「- Remastered」など、Spotify 側だけに付く版の注記は許す。カラオケは許さない。
    let Some(rest) = name_key.strip_prefix(title_key) else {
        return false;
    };
    !rest.is_empty()
        && !KARAOKE_MARKS.iter().any(|m| rest.contains(m))
        && ["remaster", "version", "ver", "edit", "mix"]
            .iter()
            .any(|m| rest.contains(m))
        && !rest.contains("m@ster")
}

/// 突き合わせの鍵。かな・大小・全角半角を畳み、空白と記号を落とす。
fn match_key(s: &str) -> String {
    let widened: String = s.chars().map(fold_width).collect();
    imas_text_fold::fold(&widened)
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == '@')
        .collect()
}

/// 全角英数記号を半角に。
fn fold_width(c: char) -> char {
    match c as u32 {
        0xFF01..=0xFF5E => char::from_u32(c as u32 - 0xFEE0).unwrap_or(c),
        0x3000 => ' ',
        _ => c,
    }
}

fn non_empty(s: Option<&str>) -> Option<&str> {
    s.map(str::trim).filter(|s| !s.is_empty())
}

/// うまくいかなかったときの種類。文言はここで決める。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SpotifyFailure {
    /// ログインしたアカウントが、アプリの User Management に入っていない (403)。
    NotRegistered,
    /// ログインが切れた (更新もできなかった)。
    SessionExpired,
    /// 呼びすぎ (429)。
    RateLimited,
    /// 通信できない。
    Network,
    /// 鳴らす先 (Spotify アプリ) が見つからない (404 NO_ACTIVE_DEVICE / 端末の一覧が空)。
    NoDevice,
    /// この端末に Spotify アプリが入っていない (SDK が起こせない)。
    AppNotInstalled,
    /// Spotify アプリに繋げなかった (SDK の接続が断られた・待っても戻ってこなかった)。
    ConnectionFailed,
    /// 鳴らすには Spotify Premium が要る (403 PREMIUM_REQUIRED)。
    PremiumRequired,
    /// ログインが鳴らす許可を含んでいない (プレイリストだけの頃にログインした)。
    PlaybackNotAllowed,
    /// それ以外。
    Other,
}

pub fn failure_message(failure: SpotifyFailure) -> String {
    match failure {
        SpotifyFailure::NotRegistered => "このアカウントは Spotify のアプリに登録されていません。アプリを作った人なら Premium に入っているか、ほかの人ならアプリの「User Management」に足されているかを確かめてください。",
        SpotifyFailure::SessionExpired => "Spotify のログインが切れました。設定の「Spotify」からもう一度ログインしてください。",
        SpotifyFailure::RateLimited => "Spotify が混み合っています。少し待ってからもう一度試してください。",
        SpotifyFailure::Network => "Spotify に繋がりませんでした。通信できる所でもう一度試してください。",
        SpotifyFailure::NoDevice => "鳴らす先の Spotify アプリが見つかりません。Spotify アプリを一度開いてから戻ると、そこで鳴らせます。",
        SpotifyFailure::AppNotInstalled => "この端末に Spotify アプリが入っていません。Spotify アプリを入れると、そこで鳴らせます。",
        SpotifyFailure::ConnectionFailed => "Spotify アプリに繋がりませんでした。Spotify アプリでログインしているか、設定の「Spotify」の手順 4 の値が合っているかを確かめてください。",
        SpotifyFailure::PremiumRequired => "Spotify で曲を選んで鳴らすには Spotify Premium が要ります。",
        SpotifyFailure::PlaybackNotAllowed => "Spotify で鳴らす許可がまだありません。設定の「Spotify」からもう一度ログインしてください。",
        SpotifyFailure::Other => "Spotify とのやりとりに失敗しました。もう一度試してください。",
    }
    .to_string()
}

/// ログインで許された権限 (トークン応答の `scope`、空白区切り) で鳴らせるか。
pub fn scopes_allow_playback(granted: &str) -> bool {
    let granted: Vec<&str> = granted.split_whitespace().collect();
    PLAYBACK_SCOPES.iter().all(|s| granted.contains(s))
}

// MARK: - 鳴らす

/// Spotify の鳴らす先 (`GET /me/player/devices` の 1 台)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SpotifyDevice {
    pub id: Option<String>,
    pub is_active: bool,
    pub is_restricted: bool,
    /// "Smartphone" / "Computer" / "Speaker" など。
    pub kind: String,
}

/// どの端末で鳴らすか。いま鳴らしている端末 → この電話 (Smartphone) → ほかの端末の順。
/// 操作を受け付けない端末 (`is_restricted`) と id の無い端末は選ばない。無ければ `None`。
pub fn pick_device(devices: &[SpotifyDevice]) -> Option<usize> {
    let usable =
        |d: &SpotifyDevice| !d.is_restricted && d.id.as_deref().is_some_and(|id| !id.is_empty());
    devices
        .iter()
        .position(|d| usable(d) && d.is_active)
        .or_else(|| {
            devices
                .iter()
                .position(|d| usable(d) && d.kind.eq_ignore_ascii_case("smartphone"))
        })
        .or_else(|| devices.iter().position(usable))
}

/// 今の再生位置 (ms)。Spotify には周期で聞きに行くので、聞いた時刻からの経過を足して埋める
/// (歌詞の行は 1 秒より細かく切り替わる)。止まっていれば聞いた位置のまま。曲の長さを超えない。
pub fn position_now(
    progress_ms: i64,
    fetched_at_ms: i64,
    now_ms: i64,
    is_playing: bool,
    duration_ms: Option<i64>,
) -> i64 {
    let elapsed = if is_playing {
        (now_ms - fetched_at_ms).max(0)
    } else {
        0
    };
    let pos = progress_ms.max(0) + elapsed;
    match duration_ms {
        Some(d) if d > 0 => pos.min(d),
        _ => pos,
    }
}

/// フル尺で鳴らすサービス。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FullPlaybackService {
    AppleMusic,
    Spotify,
}

/// フル尺で鳴らすサービスの選択肢 (設定のメニュー)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct FullPlaybackOption {
    pub service: FullPlaybackService,
    pub label: String,
}

pub fn full_playback_options() -> Vec<FullPlaybackOption> {
    vec![
        FullPlaybackOption {
            service: FullPlaybackService::AppleMusic,
            label: "Apple Music".to_string(),
        },
        FullPlaybackOption {
            service: FullPlaybackService::Spotify,
            label: "Spotify".to_string(),
        },
    ]
}

/// フル尺をどのサービスで鳴らすか。鳴らせなければ `None` (試聴に落とす)。
///
/// 選んであって使えればそれ。選んでいない・選んだ方が使えないなら Apple Music → Spotify の順
/// (Apple Music は端末の契約だけで鳴り、Spotify はアプリを開いておく手間があるため)。
pub fn choose_full_playback(
    preference: Option<FullPlaybackService>,
    apple_music_ready: bool,
    spotify_ready: bool,
) -> Option<FullPlaybackService> {
    let ready = |s: FullPlaybackService| match s {
        FullPlaybackService::AppleMusic => apple_music_ready,
        FullPlaybackService::Spotify => spotify_ready,
    };
    preference.filter(|p| ready(*p)).or_else(|| {
        [
            FullPlaybackService::AppleMusic,
            FullPlaybackService::Spotify,
        ]
        .into_iter()
        .find(|s| ready(*s))
    })
}

/// 書き出しの結果の文。見つからなかった曲の数を必ず言う (黙って抜けると欠けたまま気付かない)。
pub fn export_summary(added: u32, missing: u32) -> String {
    match (added, missing) {
        (0, _) => "Spotify で見つかる曲がありませんでした。".to_string(),
        (a, 0) => format!("{a} 曲を Spotify のプレイリストに入れました。"),
        (a, m) => {
            format!("{a} 曲を入れました。Spotify で見つからなかった {m} 曲は入っていません。")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cand(name: &str, artists: &[&str], album: &str) -> SpotifyTrackCandidate {
        SpotifyTrackCandidate {
            name: name.into(),
            artists: artists.iter().map(|s| s.to_string()).collect(),
            album: album.into(),
        }
    }

    fn clues(title: &str, performers: &[&str]) -> SongClues {
        SongClues {
            title: title.into(),
            performers: performers.iter().map(|s| s.to_string()).collect(),
            ..Default::default()
        }
    }

    #[test]
    fn client_id_accepts_pasted_with_spaces_and_fullwidth() {
        let id = "0123456789abcdef0123456789ABCDEF";
        let check = check_client_id(&format!("  {id}\n"));
        assert_eq!(
            check.normalized.as_deref(),
            Some("0123456789abcdef0123456789abcdef")
        );
        assert_eq!(check.problem, None);
        let fullwidth: String = "０１２３４５６７８９ａｂｃｄｅｆ0123456789abcdef".into();
        assert!(check_client_id(&fullwidth).normalized.is_some());
    }

    #[test]
    fn client_id_explains_wrong_input() {
        assert_eq!(
            check_client_id("   "),
            SpotifyClientIdCheck {
                normalized: None,
                problem: None
            }
        );
        assert!(check_client_id("abc").problem.unwrap().contains("32 文字"));
        let not_hex = "zzzz456789abcdef0123456789abcdef";
        assert!(check_client_id(not_hex)
            .problem
            .unwrap()
            .contains("Client secret"));
    }

    #[test]
    fn queries_go_from_specific_to_plain() {
        let mut c = clues("お願い！シンデレラ", &["島村卯月", "渋谷凛"]);
        c.unit_name = Some("CINDERELLA PROJECT".into());
        assert_eq!(
            search_queries(&c),
            vec![
                "お願い！シンデレラ 島村卯月",
                "お願い！シンデレラ CINDERELLA PROJECT",
                "お願い！シンデレラ"
            ]
        );
        assert_eq!(search_queries(&clues("蒼い鳥", &[])), vec!["蒼い鳥"]);
        assert!(search_queries(&clues("  ", &["x"])).is_empty());
    }

    #[test]
    fn picks_the_idol_recording_over_a_cover() {
        let c = clues("蒼い鳥", &["如月千早"]);
        let results = [
            cand("蒼い鳥", &["カバー歌手"], "カバー集"),
            cand(
                "蒼い鳥",
                &["如月千早 (CV: 今井麻美)"],
                "THE IDOLM@STER MASTER ARTIST 02",
            ),
        ];
        assert_eq!(pick_track(&c, &results), Some(1));
    }

    #[test]
    fn rejects_same_title_without_any_clue() {
        let c = clues("蒼い鳥", &["如月千早"]);
        assert_eq!(
            pick_track(&c, &[cand("蒼い鳥", &["別人"], "別のアルバム")]),
            None
        );
    }

    #[test]
    fn rejects_karaoke_and_other_titles() {
        let c = clues("蒼い鳥", &["如月千早"]);
        let results = [
            cand(
                "蒼い鳥 (オリジナル・カラオケ)",
                &["如月千早 (CV: 今井麻美)"],
                "THE IDOLM@STER",
            ),
            cand(
                "蒼い鳥 (M@STER VERSION)",
                &["如月千早 (CV: 今井麻美)"],
                "THE IDOLM@STER",
            ),
            cand("青い鳥", &["如月千早 (CV: 今井麻美)"], "THE IDOLM@STER"),
        ];
        assert_eq!(pick_track(&c, &results), None);
    }

    #[test]
    fn version_written_two_ways_is_the_same_title() {
        let c = clues("蒼い鳥 (M@STER VERSION)", &["如月千早"]);
        let results = [cand(
            "蒼い鳥 - M@STER VERSION",
            &["如月千早(CV:今井麻美)"],
            "x",
        )];
        assert_eq!(pick_track(&c, &results), Some(0));
    }

    #[test]
    fn width_and_kana_do_not_matter() {
        let c = clues("I＝WE", &[]);
        let mut c = c;
        c.unit_name = Some("イルミネーションスターズ".into());
        let results = [cand(
            "I=WE",
            &["イルミネーションスターズ"],
            "THE IDOLM@STER SHINY COLORS",
        )];
        assert_eq!(pick_track(&c, &results), Some(0));
    }

    #[test]
    fn remaster_suffix_on_spotify_side_is_allowed() {
        let c = clues("GO MY WAY!!", &["天海春香"]);
        let results = [cand(
            "GO MY WAY!! - 2024 Remaster",
            &["天海春香 (CV: 中村繪里子)"],
            "x",
        )];
        assert_eq!(pick_track(&c, &results), Some(0));
    }

    #[test]
    fn singer_label_names_count_as_clues() {
        let mut c = clues("URGENT!!!", &[]);
        c.singer_label = Some("たかはし智秋、今井麻美".into());
        let results = [cand("URGENT!!!", &["今井麻美", "たかはし智秋"], "RADIO")];
        assert_eq!(pick_track(&c, &results), Some(0));
    }

    #[test]
    fn more_clues_win_and_ties_keep_spotify_order() {
        let mut c = clues("空", &["音無小鳥"]);
        c.cd_title = Some("THE IDOLM@STER HISTORY".into());
        let results = [
            cand("空", &["音無小鳥 (CV: 滝田樹里)"], "別盤"),
            cand(
                "空",
                &["音無小鳥 (CV: 滝田樹里)"],
                "THE IDOLM@STER 765PRO ALLSTARS+ GRE@TEST BEST! -THE IDOLM@STER HISTORY-",
            ),
        ];
        assert_eq!(pick_track(&c, &results), Some(1));
        let tie = [results[0].clone(), results[0].clone()];
        assert_eq!(pick_track(&c, &tie), Some(0));
    }

    #[test]
    fn summary_always_says_what_is_missing() {
        assert_eq!(
            export_summary(0, 3),
            "Spotify で見つかる曲がありませんでした。"
        );
        assert_eq!(
            export_summary(5, 0),
            "5 曲を Spotify のプレイリストに入れました。"
        );
        assert!(export_summary(5, 2).contains("見つからなかった 2 曲"));
    }

    #[test]
    fn playback_needs_both_scopes() {
        assert!(scopes_allow_playback(SCOPES));
        assert!(!scopes_allow_playback(
            "playlist-modify-private playlist-modify-public"
        ));
        assert!(!scopes_allow_playback("user-read-playback-state"));
        assert!(!scopes_allow_playback(
            "user-read-playback-state user-modify-playback-state"
        ));
    }

    fn device(id: Option<&str>, active: bool, restricted: bool, kind: &str) -> SpotifyDevice {
        SpotifyDevice {
            id: id.map(str::to_string),
            is_active: active,
            is_restricted: restricted,
            kind: kind.into(),
        }
    }

    #[test]
    fn device_prefers_active_then_phone() {
        let devices = [
            device(Some("pc"), false, false, "Computer"),
            device(Some("phone"), false, false, "Smartphone"),
            device(Some("speaker"), true, false, "Speaker"),
        ];
        assert_eq!(pick_device(&devices), Some(2));
        assert_eq!(pick_device(&devices[..2]), Some(1));
        assert_eq!(pick_device(&devices[..1]), Some(0));
    }

    #[test]
    fn device_skips_restricted_and_idless() {
        let devices = [
            device(Some("tv"), true, true, "TV"),
            device(None, false, false, "Smartphone"),
        ];
        assert_eq!(pick_device(&devices), None);
        assert_eq!(pick_device(&[]), None);
    }

    #[test]
    fn position_runs_only_while_playing_and_stops_at_the_end() {
        assert_eq!(
            position_now(10_000, 1_000, 1_500, true, Some(200_000)),
            10_500
        );
        assert_eq!(
            position_now(10_000, 1_000, 1_500, false, Some(200_000)),
            10_000
        );
        assert_eq!(
            position_now(199_900, 1_000, 2_000, true, Some(200_000)),
            200_000
        );
        // 時計が戻っても位置は戻さない。
        assert_eq!(position_now(10_000, 2_000, 1_000, true, None), 10_000);
    }

    #[test]
    fn full_playback_follows_preference_when_ready() {
        use FullPlaybackService::*;
        assert_eq!(
            choose_full_playback(Some(Spotify), true, true),
            Some(Spotify)
        );
        assert_eq!(choose_full_playback(None, true, true), Some(AppleMusic));
        assert_eq!(
            choose_full_playback(Some(AppleMusic), false, true),
            Some(Spotify)
        );
        assert_eq!(
            choose_full_playback(Some(Spotify), true, false),
            Some(AppleMusic)
        );
        assert_eq!(choose_full_playback(None, false, false), None);
    }

    #[test]
    fn guide_carries_the_values_to_paste() {
        let g = setup_guide(SpotifyGuidePlatform::Ios);
        assert_eq!(g.redirect_uri, "imaslivedb://spotify-callback");
        assert_eq!(g.steps.len(), 5);
        assert!(g.notes.iter().any(|n| n.contains("Premium")));
        assert_eq!(g.steps[2].values[0].value, REDIRECT_URI);
        assert_eq!(
            g.steps[3].values,
            vec![SpotifyGuideValue {
                label: "iOS app bundles".into(),
                value: IOS_BUNDLE_ID.into()
            }]
        );
        let a = setup_guide(SpotifyGuidePlatform::Android);
        assert_eq!(a.steps[3].values.len(), 2);
        assert!(a.steps[3].title.contains("Android"));
    }
}
