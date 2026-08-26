//! SNS へ出す共有文言と共有 URL の組み立て規則。純粋ロジック。
//!
//! 原本は iOS `Views/Share/SocialShare.swift` + `Services/DeeplinkBuilder.swift` と、
//! そこから各画面に散っていた文面 (`SetlistView.shareText` / `QuizResultView.shareText` /
//! `IntroGameResultView.shareText` / `EventDetailView` の ShareLink)、および
//! Android `ui/share/SocialShare.kt` ほか同名の文字列連結。
//!
//! **なぜコアに寄せるか**: 共有文は「アプリの外に出る唯一の成果物」なので、
//! 2 実装に置いたまま片方だけ直すと、同じ操作なのに OS で違う文が飛ぶ。実際に
//! iOS/Android で `pt` 前の空白・イントロドンの文型・イベント共有の URL 有無が
//! すでに食い違っていた (モジュール末尾の「iOS/Android の食い違い」参照)。
//!
//! **移していないもの**: 共有シート/インテントの起動、画像カードの描画。ここは
//! 「何という文字列を渡すか」だけを決める。
//!
//! ## OS 依存を持ち込まない箇所
//!
//! - 締切の「M月d日」は端末ローカル暦で出す文言なので、時刻は epoch ミリ秒、
//!   タイムゾーンは **その瞬間の UTC オフセット秒** を引数で受け取る
//!   (iOS `DateFormatter` / Android `SimpleDateFormat` はどちらも既定 TZ を使う。
//!   ラッパが `TimeZone.current.secondsFromGMT(for:)` 相当を渡す)。
//! - 乱数・現在時刻は一切参照しない。「開催中か」の判定も呼び出し側の結果を受け取る。

use std::borrow::Cow;

use unicode_normalization::char::is_combining_mark;
use unicode_normalization::{is_nfc_quick, IsNormalized, UnicodeNormalization};

use crate::domain::quiz_generation::QuizGrade;

/// Universal Links を受ける imas-live-api worker のベース URL。
const UNIVERSAL_LINK_BASE: &str = "https://imas-live-api.tokata3011.workers.dev";

/// アプリ共通のハッシュタグ。文面ごとに書き分けると片方だけ変わるので 1 か所に置く。
pub const HASHTAG: &str = "#アイドルライブDB";

/// セトリ共有文に載せる曲数の上限。これを超えた分は「ほか N 曲」に畳む。
/// SNS の文字数制限に当たると本文ごと切られ、末尾の URL まで消えるため。
const SETLIST_SHARE_SONG_LIMIT: usize = 20;

// ---------------------------------------------------------------------------
// percent-encoding (原本の URL 生成が経由していた 2 種類のエスケープ)
// ---------------------------------------------------------------------------

/// 1 バイトを `%XX` (大文字 16 進) にする。
fn push_percent(out: &mut String, byte: u8) {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    out.push('%');
    out.push(HEX[(byte >> 4) as usize] as char);
    out.push(HEX[(byte & 0x0F) as usize] as char);
}

/// `pos` から始まる `%XX` が正しい 16 進 2 桁か。
fn is_valid_percent_triplet(bytes: &[u8], pos: usize) -> bool {
    bytes
        .get(pos + 1)
        .zip(bytes.get(pos + 2))
        .is_some_and(|(a, b)| a.is_ascii_hexdigit() && b.is_ascii_hexdigit())
}

/// 可視 ASCII のうちパスに置けない文字。現行 Swift ツールチェインで実測した集合
/// (空白と制御文字は [`path_byte_needs_encoding`] の範囲判定で先に落ちるので含めない)。
/// `#` `?` は区切りとして解釈されるだけで absoluteString には素のまま残るので入れない。
const PATH_MUST_ENCODE: &[u8] = b"\"<>[\\]^`{|}";

/// そのバイトがパスに素で置けないか (制御文字・空白・非 ASCII を含む)。
fn path_byte_needs_encoding(b: u8) -> bool {
    // 0x21..0x7F = 空白と制御文字を除いた ASCII 可視文字。
    !(0x21..0x7F).contains(&b) || PATH_MUST_ENCODE.contains(&b)
}

/// 「percent-encoding なしでそのまま通せるパス文字列」か。
/// 置けない文字が無く、かつ `%` が全て正しい `%XX` になっていること。
fn is_path_already_valid(s: &str) -> bool {
    let bytes = s.as_bytes();
    bytes.iter().enumerate().all(|(i, &b)| {
        if b == b'%' {
            is_valid_percent_triplet(bytes, i)
        } else {
            !path_byte_needs_encoding(b)
        }
    })
}

/// `URL(string:)` がパスに施す正規化。
///
/// 原本の `DeeplinkBuilder.eventURL` 等は `URL(string: base + "/app/…/" + id)` を通しており、
/// **iOS 17 以降の RFC 3986 パーサはパスに置けない文字を percent-encode してから受け付ける**。
/// ID には日本語や `×` を含むものが実データで 682 件あり (`sh_765pro_..._ふたごぼしのつばさ_1` 等)、
/// 素の連結だけでは共有 URL のバイト列が実機と変わってしまうのでここで同じ正規化をする。
///
/// **エスケープは「全部か・無しか」**: 1 文字でも置けない文字があると、パーサは既にある
/// `%XX` ごと encode し直す (`%` → `%25`)。実測:
/// `a%40b` → `a%40b` / `a%40b×` → `a%2540b%C3%97`。
/// そのため `@` と非 ASCII の両方を持つ ID (`sh_the_idolm@ster_..._発売記念イベント_1` 等) では
/// `@` が `%2540` になる。原本の挙動なのでそのまま再現する。
fn encode_url_path(s: &str) -> String {
    if is_path_already_valid(s) {
        return s.to_string();
    }
    let mut out = String::with_capacity(s.len());
    for &b in s.as_bytes() {
        // ここに来た時点で既存の `%` も encode 対象 (上のコメント参照)。
        if b == b'%' || path_byte_needs_encoding(b) {
            push_percent(&mut out, b);
        } else {
            out.push(b as char);
        }
    }
    out
}

/// `URLComponents.queryItems` がクエリ値に施す percent-encoding。
///
/// `CharacterSet.urlQueryAllowed` から `&` と `=` を除いた集合をそのまま通す
/// (実測: `!$'()*+,-./:;?@` と英数字・`_~` は素通り、空白・`"#%&<>[\]^\`{|}` は encode)。
/// **`+` を残す**のがポイントで、これを encode すると X 側の受け取りが変わる。
fn encode_query_value(s: &str) -> String {
    const EXTRA_ALLOWED: &[u8] = b"!$'()*+,-./:;?@_~";
    let mut out = String::with_capacity(s.len());
    for b in s.as_bytes() {
        if b.is_ascii_alphanumeric() || EXTRA_ALLOWED.contains(b) {
            out.push(*b as char);
        } else {
            push_percent(&mut out, *b);
        }
    }
    out
}

// ---------------------------------------------------------------------------
// 共有 URL (Universal Links)
// ---------------------------------------------------------------------------

/// ID を URL パスに埋める前のエスケープ。
///
/// `@` は RFC 3986 上パスに置けるので素通しされるが、**SNS やメッセージアプリの
/// リンク検出が `@` をメールアドレスの境界と誤認してそこで URL を切る**。
/// `sh_the_idolm@ster_…` が `sh_the_idolm` で切られ 404 になっていた実害があるため
/// 明示的に `%40` にする (受け側は percent-decode するので元の ID に戻る)。
fn escaped_id(id: &str) -> String {
    encode_url_path(&id.replace('@', "%40"))
}

/// イベント詳細への共有 URL。
pub fn event_url(id: &str) -> String {
    format!("{UNIVERSAL_LINK_BASE}/app/events/{}", escaped_id(id))
}

/// 公演セトリへの共有 URL。
pub fn show_url(id: &str) -> String {
    format!("{UNIVERSAL_LINK_BASE}/app/shows/{}", escaped_id(id))
}

/// みんなの投票のお題への共有 URL。
pub fn poll_url(id: &str) -> String {
    format!("{UNIVERSAL_LINK_BASE}/app/polls/{}", escaped_id(id))
}

// ---------------------------------------------------------------------------
// 共有ペイロード (本文 + 着地先 URL)
// ---------------------------------------------------------------------------

/// 共有する一言と着地先 URL。
///
/// X の intent は本文と URL を **別パラメータ**で受けるとリンクカードが出るので、
/// 連結済みの 1 本の文字列ではなく分けて持つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SharePayload {
    pub message: String,
    /// 着地先。URL を持たない共有 (ゲーム結果など) は `None`。
    pub url: Option<String>,
}

impl SharePayload {
    /// 標準シェアシート用のプレーンテキスト (本文 + 改行 + URL)。
    pub fn plain_text(&self) -> String {
        match &self.url {
            Some(url) => share_text(&self.message, url),
            None => self.message.clone(),
        }
    }

    /// X (Twitter) の投稿画面 URL。X アプリ未インストールでもブラウザの投稿画面に着地する。
    pub fn x_post_url(&self) -> String {
        let mut out = format!(
            "https://x.com/intent/post?text={}",
            encode_query_value(&self.message)
        );
        if let Some(url) = &self.url {
            out.push_str("&url=");
            out.push_str(&encode_query_value(url));
        }
        out
    }
}

/// 「本文 + 改行 + URL」。イベント/公演/投票のどの共有でも同じ形にそろえる。
pub fn share_text(name: &str, url: &str) -> String {
    format!("{name}\n{url}")
}

/// イベント詳細のシェア文 (イベント名 + Universal Link)。
pub fn event_share_text(event_id: &str, event_name: &str) -> String {
    share_text(event_name, &event_url(event_id))
}

// ---------------------------------------------------------------------------
// 投票系の文面
// ---------------------------------------------------------------------------

/// 「A」「B」「C」形式。0 件は空文字 (呼び出し側が共有導線ごと隠す前提)。
pub fn quoted_names(names: &[String]) -> String {
    names.iter().map(|n| format!("「{n}」")).collect()
}

/// セトリ予想の投票シェア。
pub fn prediction_votes_payload(
    show_id: &str,
    show_name: &str,
    song_titles: &[String],
) -> SharePayload {
    SharePayload {
        message: format!(
            "{show_name} のセトリ予想で{}に投票しました！ {HASHTAG}",
            quoted_names(song_titles)
        ),
        url: Some(show_url(show_id)),
    }
}

/// みんなの投票 (お題) への投票シェア。
pub fn poll_votes_payload(
    poll_id: &str,
    poll_title: &str,
    entity_names: &[String],
) -> SharePayload {
    SharePayload {
        message: format!(
            "お題「{poll_title}」で{}に投票しました！ {HASHTAG}",
            quoted_names(entity_names)
        ),
        url: Some(poll_url(poll_id)),
    }
}

/// お題そのもののシェア (まだ投票していない人への誘い)。
///
/// 締切は **開催中のときだけ**載せる (終了済みに締切を出しても意味がない)。
/// `ends_at_epoch_ms` が `None`、または `is_active == false` なら締切節は丸ごと落ちる。
pub fn poll_invite_payload(
    poll_id: &str,
    title: &str,
    ends_at_epoch_ms: Option<i64>,
    is_active: bool,
    tz_offset_seconds: i32,
) -> SharePayload {
    let deadline = ends_at_epoch_ms
        .filter(|_| is_active)
        .map(|ms| format!(" 締切は{}！", month_day(ms, tz_offset_seconds)))
        .unwrap_or_default();
    SharePayload {
        message: format!("お題「{title}」に投票しよう！{deadline} {HASHTAG}"),
        url: Some(poll_url(poll_id)),
    }
}

/// epoch ミリ秒を端末ローカル暦の `"M月d日"` にする (ゼロ埋めなし)。
///
/// タイムゾーンは呼び出し側が渡した固定オフセットで解決する。夏時間は
/// 「その瞬間のオフセット」を渡してもらう前提なので、ここでは扱わない。
fn month_day(epoch_ms: i64, tz_offset_seconds: i32) -> String {
    use chrono::{DateTime, Datelike, FixedOffset};
    // 表現不能な epoch でだけ None。サーバ由来の締切では到達しない。
    let utc = DateTime::from_timestamp_millis(epoch_ms).unwrap_or(DateTime::UNIX_EPOCH);
    let Some(offset) = FixedOffset::east_opt(tz_offset_seconds) else {
        return String::new();
    };
    let local = utc.with_timezone(&offset);
    format!("{}月{}日", local.month(), local.day())
}

// ---------------------------------------------------------------------------
// セトリのシェア文
// ---------------------------------------------------------------------------

/// セトリ共有文の材料。会場の表示名解決 (会場ディレクトリ) は呼び出し側で済ませて渡す。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistShareInput {
    pub show_id: String,
    pub show_name: String,
    /// 親イベント名。取れていなければ `None`。
    pub event_name: Option<String>,
    /// 公演日 (`"yyyy-MM-dd"`)。原本では非 Optional なので、空でも 1 要素として並ぶ。
    pub date: String,
    /// 会場の表示名 (ディレクトリ解決済み → 生の会場名の順のフォールバック結果)。
    pub venue: Option<String>,
    /// セトリの曲名 (演奏順)。
    pub song_titles: Vec<String>,
}

/// NFC 済みならそのまま借用し、そうでなければ NFC 化して所有する。
/// クイックチェックで確定できない `Maybe` は正規化側に倒す
/// (`domain::quiz_generation::canonical` / `domain::intro_quiz_choices::nfc_key` と同じ流儀)。
fn nfc(s: &str) -> Cow<'_, str> {
    match is_nfc_quick(s.chars()) {
        IsNormalized::Yes => Cow::Borrowed(s),
        IsNormalized::No | IsNormalized::Maybe => Cow::Owned(s.nfc().collect()),
    }
}

/// NFC 後もなお直前の文字にぶら下がり、単独では書記素クラスタを始められない文字か。
///
/// 結合文字 (`is_combining_mark` = General_Category が Mark。異体字セレクタもここに入る) に
/// 加えて、UAX #29 が Extend 扱いする ZWJ と絵文字修飾子を見る。どれも「前の文字があれば
/// 必ずそれに continue する」ものだけなので、この判定で落ちるのは **本当に途中で切れている
/// 一致だけ**。逆に Swift が真と答える一致を落とすことはない。
fn is_cluster_extender(c: char) -> bool {
    is_combining_mark(c)
        || c == '\u{200D}' // ZWJ: 絵文字の連結 (👨\u{200D}👩\u{200D}👦 で 1 クラスタ)
        || ('\u{1F3FB}'..='\u{1F3FF}').contains(&c) // 肌の色の絵文字修飾子
}

/// `byte_index` の文字が直前のクラスタの続きか (末尾なら false)。
fn extends_previous_cluster(s: &str, byte_index: usize) -> bool {
    s[byte_index..]
        .chars()
        .next()
        .is_some_and(is_cluster_extender)
}

/// Swift `String.contains(_: StringProtocol)` の判定。
///
/// 素の `str::contains` ではないのは、Swift が次の 3 つを同時に満たすため
/// (いずれも macOS Swift 6.3 / Foundation で実測):
///
/// 1. **空文字は「含まない」**。`"abc".contains("")` も `"".contains("")` も false
///    (`range(of:)` が nil)。Rust の `str::contains("")` は true なので、そのままだと
///    イベント名が空のときだけ結果が反転する。
/// 2. **正準等価で一致する**。`"がっこう"(U+304C).contains("か\u{3099}っこう")` は true。
///    NFC/NFD をまたいで一致するので、バイト同値で比べると取りこぼす。実データにも NFD は
///    実在し (`events.name` の「まりなす7周年記念ライブ」は末尾が `フ` + U+3099)、
///    取りこぼすと **イベント名が公演名に既に入っているのに重ねてしまい**、
///    「イベント名 イベント名 DAY1」という共有文が飛ぶ。
///    ただし **互換等価ではない** (`"①".contains("1")` は false)。だから NFKC ではなく NFC。
/// 3. **書記素クラスタの途中では一致しない**。`"か\u{0301}".contains("か")` は false、
///    `"👨\u{200D}👩\u{200D}👦".contains("👨")` も false。NFC で合成しきれない列が残るので、
///    正規化だけでは足りず境界判定が要る。
///
/// 再現しないのは UAX #29 の残り (地域表示記号の 2 つ組など)。セグメンテーションの依存を
/// 増やさずに済む範囲で止めてある。公演名・イベント名でそこを踏むには、NFC 後も分解された
/// ままの列をイベント名が途中から切り出す必要があり、実データの命名では起こらない。
fn swift_contains(haystack: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return false;
    }
    let haystack = nfc(haystack);
    let needle = nfc(needle);
    haystack
        .match_indices(needle.as_ref())
        .any(|(start, matched)| {
            // 先頭が結合文字なら、その手前に文字がある限りクラスタの途中から切っている。
            (start == 0 || !extends_previous_cluster(&haystack, start))
                && !extends_previous_cluster(&haystack, start + matched.len())
        })
}

/// シェア文に使う公演の表示名。イベント名が取れていれば「イベント名 公演名」、
/// 公演名が既にイベント名を含む場合は重複させない。
fn setlist_share_name(input: &SetlistShareInput) -> String {
    match &input.event_name {
        Some(event_name) if !swift_contains(&input.show_name, event_name) => {
            format!("{event_name} {}", input.show_name)
        }
        _ => input.show_name.clone(),
    }
}

/// セトリ画面のシェア文。**セトリ本文まで載せる**。
///
/// 「公演名 + URL」だけだと、セトリ画面から共有したのに中身が何も入らず、
/// 受け取った側はリンクを踏まないと何のライブか分からなかった。
/// 曲数が多いと SNS の文字数制限に当たるので [`SETLIST_SHARE_SONG_LIMIT`] 曲までにして
/// 残りは「ほか N 曲」と畳む (全部見たい人向けに URL は必ず末尾に残す)。
pub fn setlist_share_text(input: &SetlistShareInput) -> String {
    let mut lines = vec![setlist_share_name(input)];

    // 原本の `[show.date, venue].compactMap { $0 }`: date は非 Optional なので空でも 1 要素。
    let mut sub: Vec<&str> = vec![input.date.as_str()];
    if let Some(venue) = &input.venue {
        sub.push(venue.as_str());
    }
    let sub = sub.join(" ・ ");
    if !sub.is_empty() {
        lines.push(sub);
    }

    if !input.song_titles.is_empty() {
        lines.push(String::new());
        for (index, title) in input
            .song_titles
            .iter()
            .take(SETLIST_SHARE_SONG_LIMIT)
            .enumerate()
        {
            lines.push(format!("{:02}. {title}", index + 1));
        }
        if input.song_titles.len() > SETLIST_SHARE_SONG_LIMIT {
            lines.push(format!(
                "ほか {} 曲",
                input.song_titles.len() - SETLIST_SHARE_SONG_LIMIT
            ));
        }
    }

    lines.push(String::new());
    lines.push(show_url(&input.show_id));
    lines.join("\n")
}

// ---------------------------------------------------------------------------
// ゲーム結果のシェア文
// ---------------------------------------------------------------------------

/// リング内とシェア文言に出すグレードの 1 文字。
fn grade_label(grade: QuizGrade) -> &'static str {
    match grade {
        QuizGrade::S => "S",
        QuizGrade::A => "A",
        QuizGrade::B => "B",
        QuizGrade::C => "C",
        QuizGrade::D => "D",
    }
}

/// クイズ結果のシェア文。`game_display_name` は `GameKind.displayName` (「ソロ曲クイズ」等)。
pub fn quiz_result_share_text(
    game_display_name: &str,
    points: u32,
    max_points: u32,
    grade: QuizGrade,
    correct: u32,
    questions: u32,
) -> String {
    format!(
        "{game_display_name}で {points}/{max_points}pt・グレード{}（正解 {correct}/{questions}）でした！ {HASHTAG}",
        grade_label(grade)
    )
}

/// イントロドンのゲームモード (シェア文の分岐に必要な分だけ)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum IntroDonShareMode {
    /// 固定問数。
    Normal,
    /// 制限時間内に連続出題。
    Rush,
    /// 全曲出し切るまで。タイムと正答率を競う。
    AllSongs,
    /// 1 台 2 人の分割対戦。
    Party,
}

/// イントロドン結果のシェア材料。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct IntroDonShareInput {
    pub mode: IntroDonShareMode,
    /// 正解数。
    pub score: i32,
    /// 実際に回答した問題数 (スキップ含む)。正答率の母数。
    pub answered: i32,
    /// 最大連続正解数。2 以上のときだけ文末に足す。
    pub best_combo: i32,
    /// 全曲チャレンジの経過秒。
    pub elapsed_seconds: f64,
    /// ラッシュの制限秒。
    pub rush_time_limit_seconds: f64,
}

/// 経過秒を `"m:ss"` にする。Swift `Int(t.rounded())` と同じ「0 から遠い側へ丸める」。
fn time_string(seconds: f64) -> String {
    let s = seconds.round() as i64;
    format!("{}:{:02}", s / 60, s % 60)
}

/// イントロドン結果のシェア文 (本家アプリの宣伝も兼ねてハッシュタグ 2 本)。
pub fn intro_don_share_text(input: &IntroDonShareInput) -> String {
    let percentage = if input.answered > 0 {
        input.score * 100 / input.answered
    } else {
        0
    };
    let base = match input.mode {
        IntroDonShareMode::AllSongs => format!(
            "🎵イントロドン 全曲チャレンジ {}・正答率{percentage}% ({}/{})",
            time_string(input.elapsed_seconds),
            input.score,
            input.answered
        ),
        IntroDonShareMode::Rush => format!(
            "🎵イントロドン・ラッシュ {}秒で {}問正解！(正答率{percentage}%)",
            input.rush_time_limit_seconds as i64, input.score
        ),
        IntroDonShareMode::Party => "🎵イントロドン パーティ対戦であそんだよ！".to_string(),
        IntroDonShareMode::Normal => format!(
            "🎵イントロドンで {}/{} 正解！(正答率{percentage}%)",
            input.score, input.answered
        ),
    };
    let combo = if input.best_combo >= 2 {
        format!(" 最大{}連続🔥", input.best_combo)
    } else {
        String::new()
    };
    format!("{base}{combo}\n#イントロドン #アイマス")
}

// ---------------------------------------------------------------------------
// iOS/Android の食い違い (iOS を正として統一した分の記録)
//
// 1. クイズ結果: Android だけ `pt` の前に空白があった (`8/10 pt`)。iOS の `8/10pt` に統一。
// 2. イントロドン: Android は全モードを `🎵イントロドン(モード名)で n/m 正解！` の 1 文型に
//    まとめており、ラッシュ・パーティの専用文がなかった。iOS の 4 分岐に統一。
// 3. イントロドンの経過秒: Android は切り捨て (`elapsedMs / 1000`)、iOS は四捨五入
//    (`t.rounded()`)。iOS に統一。
// 4. お題の締切: Android だけ `Long.MAX_VALUE` を「締切なし」とみなす分岐があった。
//    iOS にその概念はないので落とした (サーバは常に実時刻を返す)。
// 5. イベント共有: Android は「イベント名 + 副題」で URL を載せていなかった。
//    iOS の「イベント名 + Universal Link」に統一 ([`event_share_text`])。
// 6. セトリ共有: Android には導線自体が無かった。iOS の文面 ([`setlist_share_text`]) が正。
// 7. セトリ予想の投票シェア: Android には文面が無かった。iOS の
//    [`prediction_votes_payload`] が正。
// 8. X 投稿 URL のエスケープ: Android の `Uri.encode` は `$+,/:;?@` まで percent-encode し、
//    iOS の `URLComponents` は残す。デコード後は同じ値なので着地は変わらないが、
//    バイト列は iOS 側にそろえた。
// 9. 共有 URL の ID: Android は `Uri.encode(id)` で全体を encode、iOS は `@` だけ置換して
//    `URL(string:)` の正規化に任せる。実データの ID に現れる文字
//    (英数字・`_`・`-`・`~`・`@`・非 ASCII) では両者の出力は一致する。
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn names(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    // -- 共有 URL ------------------------------------------------------------

    /// `@` を含む実データの公演 ID (`shows` に 46 件)。素の `@` のままだと SNS の
    /// リンク検出が `sh_the_idolm` で切って 404 になる。
    #[test]
    fn at_sign_in_id_becomes_percent40() {
        assert_eq!(
            show_url("sh_the_idolm@ster_shiny_colors_8th_live_ito_yume_1"),
            "https://imas-live-api.tokata3011.workers.dev/app/shows/sh_the_idolm%40ster_shiny_colors_8th_live_ito_yume_1"
        );
        assert_eq!(
            event_url("ev_the_idolm@ster_shiny_colors_8th_live_ito_yume"),
            "https://imas-live-api.tokata3011.workers.dev/app/events/ev_the_idolm%40ster_shiny_colors_8th_live_ito_yume"
        );
    }

    /// 非 ASCII を含む実データの ID (`shows`/`events` に 682 件)。
    /// Swift `URL(string:)` の実測値と一致すること。
    #[test]
    fn non_ascii_id_is_utf8_percent_encoded() {
        assert_eq!(
            show_url("sh_765_production_×_961_production_idol_ultimate_once_and_for_all_1"),
            "https://imas-live-api.tokata3011.workers.dev/app/shows/sh_765_production_%C3%97_961_production_idol_ultimate_once_and_for_all_1"
        );
        // Swift 実測: "sh_×_ふたご" → "sh_%C3%97_%E3%81%B5%E3%81%9F%E3%81%94"
        assert_eq!(
            show_url("sh_×_ふたご"),
            "https://imas-live-api.tokata3011.workers.dev/app/shows/sh_%C3%97_%E3%81%B5%E3%81%9F%E3%81%94"
        );
    }

    /// `-` `~` `.` は実 ID に出るが素通し (Swift 実測と同じ)。
    #[test]
    fn unreserved_symbols_pass_through() {
        assert_eq!(
            show_url("sh_315_production_presents_f@ntastic_battle_fes_~wanna_step_in~_1"),
            "https://imas-live-api.tokata3011.workers.dev/app/shows/sh_315_production_presents_f%40ntastic_battle_fes_~wanna_step_in~_1"
        );
        assert_eq!(
            show_url("sh_283_production_solo_live_collection_-master_showpiece-_1"),
            "https://imas-live-api.tokata3011.workers.dev/app/shows/sh_283_production_solo_live_collection_-master_showpiece-_1"
        );
    }

    /// 空白・不正な `%`・絵文字は encode される (Swift `URL(string:)` の実測値)。
    #[test]
    fn invalid_path_bytes_are_encoded_like_swift() {
        assert_eq!(escaped_id("sh a b"), "sh%20a%20b");
        assert_eq!(escaped_id("sh_%zz"), "sh_%25zz");
        assert_eq!(escaped_id("sh_%4"), "sh_%254");
        assert_eq!(escaped_id("a🔥b"), "a%F0%9F%94%A5b");
        // 置けない文字が 1 つも無ければ、既にある triplet は二重 encode しない。
        assert_eq!(escaped_id("a%40b"), "a%40b");
    }

    /// `@` と非 ASCII を両方持つ ID では、`@`→`%40` の後で `URL(string:)` が
    /// **`%` ごと encode し直す**ため `%2540` になる。素朴に `%40` を保つと実機と 1 バイト違う。
    /// (実データ: `shows` に「発売記念イベント」系が該当)
    #[test]
    fn at_sign_gets_double_encoded_when_id_also_has_non_ascii() {
        assert_eq!(
            show_url("sh_the_idolm@ster_shiny_colors_song_for_prism_karma_naraku_発売記念イベント_1"),
            "https://imas-live-api.tokata3011.workers.dev/app/shows/sh_the_idolm%2540ster_shiny_colors_song_for_prism_karma_naraku_%E7%99%BA%E5%A3%B2%E8%A8%98%E5%BF%B5%E3%82%A4%E3%83%99%E3%83%B3%E3%83%88_1"
        );
        // Swift 実測の最小形。
        assert_eq!(escaped_id("a@b×"), "a%2540b%C3%97");
        assert_eq!(escaped_id("a@b"), "a%40b");
    }

    #[test]
    fn poll_url_uses_polls_path() {
        assert_eq!(
            poll_url("p_best_song_2026"),
            "https://imas-live-api.tokata3011.workers.dev/app/polls/p_best_song_2026"
        );
    }

    // -- ペイロード ----------------------------------------------------------

    #[test]
    fn plain_text_joins_message_and_url_with_newline() {
        let p = SharePayload {
            message: "お題「ベストソング」に投票しよう！ #アイドルライブDB".into(),
            url: Some(poll_url("p1")),
        };
        assert_eq!(
            p.plain_text(),
            "お題「ベストソング」に投票しよう！ #アイドルライブDB\nhttps://imas-live-api.tokata3011.workers.dev/app/polls/p1"
        );
    }

    #[test]
    fn plain_text_without_url_is_message_only() {
        let p = SharePayload {
            message: "結果だけ".into(),
            url: None,
        };
        assert_eq!(p.plain_text(), "結果だけ");
    }

    /// Swift `URLComponents` の実測出力と 1 バイト一致すること
    /// (`xcrun swift` で `URLQueryItem` を通した結果をそのまま期待値にしている)。
    #[test]
    fn x_post_url_matches_swift_urlcomponents_encoding() {
        let p = SharePayload {
            message: "お題「ベストソング」に投票しよう！ 締切は9月1日！ #アイドルライブDB".into(),
            url: Some("https://imas-live-api.tokata3011.workers.dev/app/polls/p%401".into()),
        };
        assert_eq!(
            p.x_post_url(),
            "https://x.com/intent/post?text=%E3%81%8A%E9%A1%8C%E3%80%8C%E3%83%99%E3%82%B9%E3%83%88%E3%82%BD%E3%83%B3%E3%82%B0%E3%80%8D%E3%81%AB%E6%8A%95%E7%A5%A8%E3%81%97%E3%82%88%E3%81%86%EF%BC%81%20%E7%B7%A0%E5%88%87%E3%81%AF9%E6%9C%881%E6%97%A5%EF%BC%81%20%23%E3%82%A2%E3%82%A4%E3%83%89%E3%83%AB%E3%83%A9%E3%82%A4%E3%83%96DB&url=https://imas-live-api.tokata3011.workers.dev/app/polls/p%25401"
        );
    }

    /// 記号の扱い (Swift 実測): `&` `=` `#` `%` 空白は encode、`+` `/` `?` `:` `@` は素通し。
    /// 曲名には実際に `Q&A` `#HE4DSHOT` `100%` が存在する。
    #[test]
    fn x_post_url_symbol_handling_matches_swift() {
        let p = SharePayload {
            message: "a+b&c=d/e?f:g@h#i j".into(),
            url: None,
        };
        assert_eq!(
            p.x_post_url(),
            "https://x.com/intent/post?text=a+b%26c%3Dd/e?f:g@h%23i%20j"
        );

        let p2 = SharePayload {
            message: "!'()*~-._".into(),
            url: None,
        };
        assert_eq!(p2.x_post_url(), "https://x.com/intent/post?text=!'()*~-._");

        let p3 = SharePayload {
            message: "M@STERPIECE 100% ~Rock'n'Roll~".into(),
            url: None,
        };
        assert_eq!(
            p3.x_post_url(),
            "https://x.com/intent/post?text=M@STERPIECE%20100%25%20~Rock'n'Roll~"
        );
    }

    /// 改行と絵文字 (サロゲートペア) は UTF-8 バイト列で encode される。
    #[test]
    fn x_post_url_encodes_newline_and_emoji() {
        let p = SharePayload {
            message: "🎵イントロドンで 8/10 正解！(正答率80%) 最大3連続🔥\n#イントロドン #アイマス".into(),
            url: None,
        };
        assert_eq!(
            p.x_post_url(),
            "https://x.com/intent/post?text=%F0%9F%8E%B5%E3%82%A4%E3%83%B3%E3%83%88%E3%83%AD%E3%83%89%E3%83%B3%E3%81%A7%208/10%20%E6%AD%A3%E8%A7%A3%EF%BC%81(%E6%AD%A3%E7%AD%94%E7%8E%8780%25)%20%E6%9C%80%E5%A4%A73%E9%80%A3%E7%B6%9A%F0%9F%94%A5%0A%23%E3%82%A4%E3%83%B3%E3%83%88%E3%83%AD%E3%83%89%E3%83%B3%20%23%E3%82%A2%E3%82%A4%E3%83%9E%E3%82%B9"
        );
    }

    #[test]
    fn event_share_text_is_name_then_link() {
        assert_eq!(
            event_share_text(
                "ev_the_idolm@ster_shiny_colors_8th_live_ito_yume",
                "THE IDOLM@STER SHINY COLORS 8th LIVE iと夢"
            ),
            "THE IDOLM@STER SHINY COLORS 8th LIVE iと夢\nhttps://imas-live-api.tokata3011.workers.dev/app/events/ev_the_idolm%40ster_shiny_colors_8th_live_ito_yume"
        );
    }

    // -- 投票系の文面 --------------------------------------------------------

    #[test]
    fn quoted_names_wraps_each_name() {
        assert_eq!(quoted_names(&names(&["Q&A"])), "「Q&A」");
        assert_eq!(
            quoted_names(&names(&["Q&A", "Love & Joy", "#HE4DSHOT"])),
            "「Q&A」「Love & Joy」「#HE4DSHOT」"
        );
        assert_eq!(quoted_names(&[]), "");
    }

    #[test]
    fn poll_votes_message_matches_original() {
        let p = poll_votes_payload("p1", "一番好きな夏曲", &names(&["Q&A", "LOVE & PEACH"]));
        assert_eq!(
            p.message,
            "お題「一番好きな夏曲」で「Q&A」「LOVE & PEACH」に投票しました！ #アイドルライブDB"
        );
        assert_eq!(
            p.url.as_deref(),
            Some("https://imas-live-api.tokata3011.workers.dev/app/polls/p1")
        );
    }

    #[test]
    fn prediction_votes_message_matches_original() {
        let p = prediction_votes_payload(
            "sh_the_idolm@ster_million_live_13thlive_1",
            "THE IDOLM@STER MILLION LIVE! 13thLIVE DAY1 (高山紗代子主演)",
            &names(&["BRAND NEW FIELD", "∞ Possibilities"]),
        );
        assert_eq!(
            p.message,
            "THE IDOLM@STER MILLION LIVE! 13thLIVE DAY1 (高山紗代子主演) のセトリ予想で「BRAND NEW FIELD」「∞ Possibilities」に投票しました！ #アイドルライブDB"
        );
        assert_eq!(
            p.url.as_deref(),
            Some("https://imas-live-api.tokata3011.workers.dev/app/shows/sh_the_idolm%40ster_million_live_13thlive_1")
        );
    }

    /// 開催中なら締切を挟む。JST (+9h) で 2025-09-01 00:00 = epoch 1756652400000。
    /// Swift `DateFormatter(dateFormat: "M月d日", locale: ja_JP)` の実測値と一致。
    #[test]
    fn poll_invite_includes_deadline_while_active() {
        let p = poll_invite_payload("p1", "ベストソング", Some(1_756_652_400_000), true, 9 * 3600);
        assert_eq!(
            p.message,
            "お題「ベストソング」に投票しよう！ 締切は9月1日！ #アイドルライブDB"
        );
    }

    /// 終了済み (`is_active == false`) は締切節ごと落ちて空白 1 個になる。
    #[test]
    fn poll_invite_drops_deadline_when_finished() {
        let p = poll_invite_payload("p1", "ベストソング", Some(1_756_652_400_000), false, 9 * 3600);
        assert_eq!(p.message, "お題「ベストソング」に投票しよう！ #アイドルライブDB");
        // 締切が未知 (一覧で詳細未取得) のときも同じ文面。
        let q = poll_invite_payload("p1", "ベストソング", None, true, 9 * 3600);
        assert_eq!(q.message, p.message);
    }

    /// 日付は端末 TZ で解決する。同じ瞬間でも JST では 1/1、UTC では 12/31。
    #[test]
    fn deadline_month_day_follows_device_offset() {
        // 2026-01-01 00:00:00 JST = 2025-12-31 15:00:00 UTC
        assert_eq!(month_day(1_767_193_200_000, 9 * 3600), "1月1日");
        assert_eq!(month_day(1_767_193_200_000, 0), "12月31日");
        // ゼロ埋めしない (Swift の "M月d日")。
        assert_eq!(month_day(1_756_652_400_000, 9 * 3600), "9月1日");
    }

    // -- セトリ --------------------------------------------------------------

    fn setlist_input(titles: Vec<String>) -> SetlistShareInput {
        SetlistShareInput {
            show_id: "sh_L1115".into(),
            show_name: "DAY2".into(),
            event_name: Some(
                "THE IDOLM@STER SideM 10th ANNIVERSARY ST@GE ～P@SSION-ING!!!～".into(),
            ),
            date: "2025-07-13".into(),
            venue: Some("神奈川・Kアリーナ横浜".into()),
            song_titles: titles,
        }
    }

    /// master.sqlite の実公演 (sh_L1115 / 70 曲) を 3 曲に縮めた形。
    #[test]
    fn setlist_share_text_matches_original_layout() {
        let text = setlist_share_text(&setlist_input(names(&[
            "BRAND NEW FIELD",
            "∞ Possibilities",
            "バーニン・クールで輝いて",
        ])));
        assert_eq!(
            text,
            "THE IDOLM@STER SideM 10th ANNIVERSARY ST@GE ～P@SSION-ING!!!～ DAY2\n\
             2025-07-13 ・ 神奈川・Kアリーナ横浜\n\
             \n\
             01. BRAND NEW FIELD\n\
             02. ∞ Possibilities\n\
             03. バーニン・クールで輝いて\n\
             \n\
             https://imas-live-api.tokata3011.workers.dev/app/shows/sh_L1115"
        );
    }

    /// 実データ最長の 70 曲。20 曲で切って「ほか 50 曲」に畳み、URL は必ず残す。
    #[test]
    fn setlist_share_text_folds_past_twenty_songs() {
        let titles: Vec<String> = (1..=70).map(|i| format!("曲{i}")).collect();
        let text = setlist_share_text(&setlist_input(titles));
        let lines: Vec<&str> = text.split('\n').collect();
        assert_eq!(lines[3], "01. 曲1");
        assert_eq!(lines[22], "20. 曲20");
        assert_eq!(lines[23], "ほか 50 曲");
        assert_eq!(lines[24], "");
        assert_eq!(
            lines[25],
            "https://imas-live-api.tokata3011.workers.dev/app/shows/sh_L1115"
        );
        assert_eq!(lines.len(), 26);
        // ちょうど 20 曲なら畳まない。
        let exact: Vec<String> = (1..=20).map(|i| format!("曲{i}")).collect();
        assert!(!setlist_share_text(&setlist_input(exact)).contains("ほか"));
    }

    /// セトリ未登録なら曲ブロックごと出ない (見出し + 副題 + 空行 + URL)。
    #[test]
    fn setlist_share_text_without_songs_skips_song_block() {
        let text = setlist_share_text(&setlist_input(vec![]));
        assert_eq!(
            text,
            "THE IDOLM@STER SideM 10th ANNIVERSARY ST@GE ～P@SSION-ING!!!～ DAY2\n\
             2025-07-13 ・ 神奈川・Kアリーナ横浜\n\
             \n\
             https://imas-live-api.tokata3011.workers.dev/app/shows/sh_L1115"
        );
    }

    /// 公演名がイベント名を含むなら重ねない。
    #[test]
    fn setlist_share_name_avoids_duplicating_event_name() {
        let mut input = setlist_input(vec![]);
        input.show_name = "THE IDOLM@STER MILLION LIVE! 13thLIVE DAY1".into();
        input.event_name = Some("THE IDOLM@STER MILLION LIVE! 13thLIVE".into());
        assert_eq!(setlist_share_name(&input), input.show_name);
    }

    /// イベント名未取得なら公演名だけ。
    #[test]
    fn setlist_share_name_without_event_is_show_name_only() {
        let mut input = setlist_input(vec![]);
        input.event_name = None;
        assert_eq!(setlist_share_name(&input), "DAY2");
    }

    /// Swift の `contains("")` は false。原本はそこで「イベント名 + 空白 + 公演名」を選ぶので、
    /// 空イベント名では先頭に空白が 1 個残る。見た目は不格好だが原本の挙動なので保つ。
    #[test]
    fn setlist_share_name_with_empty_event_keeps_swift_leading_space() {
        let mut input = setlist_input(vec![]);
        input.event_name = Some(String::new());
        assert_eq!(setlist_share_name(&input), " DAY2");
    }

    // -- Swift の contains 互換 (正準等価 + 書記素クラスタ境界) ----------------
    //
    // 期待値はすべて macOS Swift 6.3 / Foundation の `String.contains` の実測値。

    /// 正準等価で一致する。`events.name` に NFD が実在する
    /// (「まりなす7周年記念ライブ」の末尾が `フ` + U+3099) ので、バイト同値で比べると
    /// 「公演名に既にイベント名が入っている」のを見落とす。
    #[test]
    fn swift_contains_matches_across_nfc_and_nfd() {
        let nfc_event = "まりなす7周年記念ライブ";
        let nfd_event = "まりなす7周年記念ライフ\u{3099}";
        let nfc_show = format!("{nfc_event} DAY1");
        let nfd_show = format!("{nfd_event} DAY1");
        // 素の str::contains ではどちらの向きも取りこぼす (これが元の不具合)。
        assert!(!nfc_show.contains(nfd_event) && !nfd_show.contains(nfc_event));

        assert!(swift_contains(&nfc_show, nfd_event));
        assert!(swift_contains(&nfd_show, nfc_event));

        // 単一文字の合成 (「が」= か + 濁点) も同じ。
        assert!(swift_contains("がっこう", "か\u{3099}っこう"));
        assert!(swift_contains("か\u{3099}っこう", "がっこう"));

        // 正準単一分解 (Ω U+2126 → Ω U+03A9) とハングルの合成も正準等価。
        assert!(swift_contains("\u{2126}", "\u{03A9}"));
        assert!(swift_contains("\u{1100}\u{1161}\u{11A8}", "\u{AC01}"));
    }

    /// 一致するのは正準等価まで。互換等価 (NFKC) では一致しないので、正規化は NFC で止める。
    #[test]
    fn swift_contains_is_not_compatibility_equivalence() {
        assert!(!swift_contains("\u{2460}", "1")); // ① は 1 を含まない
        assert!(!swift_contains("ｱｲﾏｽ", "アイマス")); // 半角カナ ≠ 全角カナ
    }

    /// 書記素クラスタの途中では一致しない。NFC で合成しきれない列が残るため、
    /// 正規化だけでは足りず境界判定が要る。
    #[test]
    fn swift_contains_does_not_match_mid_cluster() {
        // 合成形のない結合列: 「か + アキュート」は「か」を含まない。
        assert!(!swift_contains("か\u{0301}", "か"));
        // 逆向き (クラスタの途中から始まる一致) も取らない。
        assert!(!swift_contains("か\u{0301}あ", "\u{0301}あ"));
        // 合成済みなら分解した部品も含まない。
        assert!(!swift_contains("\u{00E9}", "e"));
        assert!(!swift_contains("がっこう", "\u{3099}"));
        assert!(!swift_contains("か\u{3099}っこう", "\u{3099}"));
        assert!(!swift_contains("ラブ", "ラフ"));
        // ZWJ で連結した絵文字も 1 クラスタ。
        assert!(!swift_contains(
            "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}",
            "\u{1F468}"
        ));
        // 結合列の先頭だけを切り出さない (異体字セレクタ)。
        assert!(!swift_contains("\u{2764}\u{FE0F}DAY1", "\u{2764}"));

        // 境界で切れていなければ従来どおり一致する (境界判定が一致を殺していないことの確認)。
        assert!(swift_contains("か\u{0301}あ", "か\u{0301}"));
        assert!(swift_contains("\u{2764}\u{FE0F}DAY1", "\u{2764}\u{FE0F}"));
        assert!(swift_contains("がっこう", "がっこ"));
    }

    /// Swift は空文字を「含まない」と答える (haystack が空でも同じ)。
    #[test]
    fn swift_contains_treats_empty_needle_as_absent() {
        assert!(!swift_contains("abc", ""));
        assert!(!swift_contains("", ""));
        assert!(!swift_contains("", "a"));
    }

    /// 上の正準等価が効いていないと、NFD のイベント名だけ
    /// 「イベント名 イベント名 DAY1」と二重に出る共有文になる。
    #[test]
    fn setlist_share_name_avoids_duplicating_nfd_event_name() {
        let mut input = setlist_input(vec![]);
        input.show_name = "まりなす7周年記念ライブ DAY1".into();
        input.event_name = Some("まりなす7周年記念ライフ\u{3099}".into());
        assert_eq!(setlist_share_name(&input), "まりなす7周年記念ライブ DAY1");

        // 公演名側が NFD で、イベント名が NFC でも同じ。
        input.show_name = "まりなす7周年記念ライフ\u{3099} DAY1".into();
        input.event_name = Some("まりなす7周年記念ライブ".into());
        assert_eq!(
            setlist_share_name(&input),
            "まりなす7周年記念ライフ\u{3099} DAY1"
        );
    }

    /// 会場が未解決なら副題は日付だけ。日付が空なら副題行ごと落ちる。
    #[test]
    fn setlist_subtitle_handles_missing_venue_and_date() {
        let mut input = setlist_input(vec![]);
        input.venue = None;
        assert!(setlist_share_text(&input).contains("\n2025-07-13\n"));

        input.date = String::new();
        let text = setlist_share_text(&input);
        assert_eq!(
            text,
            "THE IDOLM@STER SideM 10th ANNIVERSARY ST@GE ～P@SSION-ING!!!～ DAY2\n\
             \n\
             https://imas-live-api.tokata3011.workers.dev/app/shows/sh_L1115"
        );
    }

    /// 日付が空でも会場があれば「空 ・ 会場」で 1 行出る (原本の `compactMap` の挙動:
    /// date は非 Optional なので空文字でも 1 要素として並ぶ)。
    #[test]
    fn setlist_subtitle_keeps_empty_date_slot_like_swift() {
        let mut input = setlist_input(vec![]);
        input.date = String::new();
        assert!(setlist_share_text(&input).contains("\n ・ 神奈川・Kアリーナ横浜\n"));
    }

    // -- ゲーム結果 ----------------------------------------------------------

    #[test]
    fn quiz_result_text_matches_original() {
        assert_eq!(
            quiz_result_share_text("ソロ曲クイズ", 8, 10, QuizGrade::A, 8, 10),
            "ソロ曲クイズで 8/10pt・グレードA（正解 8/10）でした！ #アイドルライブDB"
        );
        assert_eq!(
            quiz_result_share_text("アイドル当てクイズ", 0, 10, QuizGrade::D, 0, 10),
            "アイドル当てクイズで 0/10pt・グレードD（正解 0/10）でした！ #アイドルライブDB"
        );
        assert_eq!(
            quiz_result_share_text("カラーマッチ", 100, 100, QuizGrade::S, 10, 10),
            "カラーマッチで 100/100pt・グレードS（正解 10/10）でした！ #アイドルライブDB"
        );
    }

    fn intro_input(mode: IntroDonShareMode) -> IntroDonShareInput {
        IntroDonShareInput {
            mode,
            score: 8,
            answered: 10,
            best_combo: 0,
            elapsed_seconds: 0.0,
            rush_time_limit_seconds: 60.0,
        }
    }

    #[test]
    fn intro_don_normal_text_matches_original() {
        assert_eq!(
            intro_don_share_text(&intro_input(IntroDonShareMode::Normal)),
            "🎵イントロドンで 8/10 正解！(正答率80%)\n#イントロドン #アイマス"
        );
    }

    #[test]
    fn intro_don_rush_text_uses_time_limit_and_score_only() {
        let mut input = intro_input(IntroDonShareMode::Rush);
        input.rush_time_limit_seconds = 90.0;
        assert_eq!(
            intro_don_share_text(&input),
            "🎵イントロドン・ラッシュ 90秒で 8問正解！(正答率80%)\n#イントロドン #アイマス"
        );
    }

    #[test]
    fn intro_don_party_text_has_no_score() {
        assert_eq!(
            intro_don_share_text(&intro_input(IntroDonShareMode::Party)),
            "🎵イントロドン パーティ対戦であそんだよ！\n#イントロドン #アイマス"
        );
    }

    #[test]
    fn intro_don_all_songs_text_includes_time() {
        let mut input = intro_input(IntroDonShareMode::AllSongs);
        input.score = 253;
        input.answered = 300;
        input.elapsed_seconds = 1265.4;
        assert_eq!(
            intro_don_share_text(&input),
            "🎵イントロドン 全曲チャレンジ 21:05・正答率84% (253/300)\n#イントロドン #アイマス"
        );
    }

    /// 連続正解は 2 以上のときだけ足す (1 は「連続」ではない)。
    #[test]
    fn intro_don_combo_suffix_threshold() {
        let mut input = intro_input(IntroDonShareMode::Normal);
        input.best_combo = 1;
        assert!(!intro_don_share_text(&input).contains("連続"));
        input.best_combo = 2;
        assert!(intro_don_share_text(&input).contains(" 最大2連続🔥\n"));
    }

    /// 未回答は 0 除算せず正答率 0%。
    #[test]
    fn intro_don_zero_answered_is_zero_percent() {
        let mut input = intro_input(IntroDonShareMode::Normal);
        input.score = 0;
        input.answered = 0;
        assert_eq!(
            intro_don_share_text(&input),
            "🎵イントロドンで 0/0 正解！(正答率0%)\n#イントロドン #アイマス"
        );
    }

    /// Swift `Int(t.rounded())` と同じ丸め (0.5 は 0 から遠い側)。
    #[test]
    fn time_string_rounds_like_swift() {
        assert_eq!(time_string(0.0), "0:00");
        assert_eq!(time_string(59.4), "0:59");
        assert_eq!(time_string(59.5), "1:00");
        assert_eq!(time_string(125.6), "2:06");
        assert_eq!(time_string(3599.5), "60:00");
    }
}
