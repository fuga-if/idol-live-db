//! 楽曲 (song) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};
use serde::{Deserialize, Serialize};

/// `/songs/<id>/` の中身。
///
/// **ページは全曲ぶん作る** (派生曲・`other` ブランドを含む)。共有リンクや検索から
/// 到達できるべきだから。一覧に載せるかどうかだけが `SongListFilter` の判断。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SongPage {
    pub schema_version: u32,
    pub id: String,
    pub path: String,
    pub title: String,
    pub title_kana: Option<String>,
    pub theme_key: String,
    pub brand: Option<Ref>,
    pub song_type: Option<String>,
    pub release_date: Option<String>,
    pub duration_sec: Option<i32>,
    /// `"4:32"`。整形だけなのでここで作る。
    pub duration_display: Option<String>,
    /// `credit_names::split_credits` 済み。
    pub credits: Vec<CreditGroup>,
    pub cd_series: Option<String>,
    pub cd_title: Option<String>,
    pub series_group: Option<String>,
    /// 「シリーズ」行に出す 1 つの値 (`cd_series` が無ければ `series_group`)。
    /// どちらを優先するかは表示の判断なので Rust 側で解決しておく。
    pub series_display: Option<String>,
    /// Apple Music CDN。サイト唯一の外部画像。
    pub artwork_url: Option<String>,
    pub apple_music_url: Option<String>,
    pub jasrac_code: Option<String>,
    pub original_artists: Vec<Ref>,
    pub other_artists: Vec<Ref>,
    pub unit: Option<Ref>,
    /// `songs.unit_name` (マスタに無いユニット表記)。
    pub unit_label: Option<String>,
    /// 派生曲の親。
    pub parent: Option<Ref>,
    /// この曲の派生 (リミックス・ソロver 等)。
    pub variants: Vec<Ref>,
    pub performance_count: u32,
    /// date 降順。
    pub performance_history: Vec<PerformanceRow>,
    pub frequent_singers: Vec<SingerRow>,
    pub co_occurring: Vec<CoOccurRow>,
    pub related: Vec<Ref>,
    pub app: AppOpen,
    pub seo: SeoBlock,
    /// 歌詞は Web に載せない。この固定文だけを出す。
    /// JASRAC 許諾を持つのは**アプリ**であって本サイトではない、という主語を崩さないこと。
    pub lyrics_note: String,
}

/// 作詞 / 作曲 / 編曲 の 1 区分。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct CreditGroup {
    /// 「作詞」「作曲」「編曲」。
    pub role: String,
    /// 分割前の自由文字列 (分割規則が拾えなかった表記もそのまま見せられるように)。
    pub raw: String,
    pub people: Vec<String>,
    /// 1 行で出すときの表記。`people` を `" / "` で繋いだもので、分割できなかったときは
    /// `raw` そのまま。**TS 側で join しない**ための項目 (区切り文字の判断もコアが持つ)。
    pub display: String,
}

/// 披露履歴の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct PerformanceRow {
    pub show: Ref,
    pub event: Ref,
    pub date: String,
    pub short_date: String,
    pub venue: Option<String>,
    /// その公演で何曲目に披露されたか (1 始まり)。0 は不明。
    pub number: u32,
    /// 並び順の鍵。表示用の番号ではない ([`super::show::SetlistRow::number`] を見よ)。
    pub position: i32,
    pub section: Option<String>,
    /// 1 行で出すときの場所表記 (公演名と会場を `" ・ "` で繋いだもの)。
    pub place_display: String,
}

/// 「よく歌う人」の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct SingerRow {
    pub idol: Ref,
    /// この人が歌った回数。
    pub times: u32,
    /// 分母 (この曲の披露回数)。
    pub total: u32,
}

/// 「よく一緒に披露される曲」の 1 行。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ts_rs::TS)]
#[serde(rename_all = "camelCase")]
#[ts(export, export_to = "../../web/src/lib/schema/")]
pub struct CoOccurRow {
    pub song: Ref,
    /// 同じ公演に並んだ回数。
    pub together: u32,
    /// 相手の総披露回数。
    pub performances: u32,
}
