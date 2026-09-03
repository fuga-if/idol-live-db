//! アイドル (idol) 詳細ページの DTO。

use super::common::{AppOpen, Ref, SeoBlock};

web_dto! {
    /// `/idols/<id>/` の中身。
    pub struct IdolPage {
        pub schema_version: u32,
        pub id: String,
        pub path: String,
        pub name: String,
        pub name_kana: Option<String>,
        pub theme_key: String,
        /// 表示名の先頭 1 文字 (アプリの `ImasAvatar` と同じ)。画像は載せない。
        pub monogram: String,
        /// 主ブランド。
        pub brand: Option<Ref>,
        /// `idol_brands` (primary 先頭)。掛け持ちのアイドルが居る。
        pub brands: Vec<Ref>,
        pub color: Option<String>,
        /// `screen_composition::idol_profile_rows` の結果。
        /// **並べる判断はコアが持つ**ので、web は行を上から出すだけ。
        pub profile_rows: Vec<ProfileRow>,
        pub current_voice_actor: Option<String>,
        pub voice_actor_history: Vec<VoiceActorRow>,
        pub units: Vec<Ref>,
        /// 持ち曲 (release_date 降順)。
        pub songs: Vec<IdolSongRow>,
        /// 歌ったことのある曲。
        pub performed_songs: Vec<IdolPerformedRow>,
        pub shows: Vec<IdolShowRow>,
        pub description: Option<String>,
        pub app: AppOpen,
        pub seo: SeoBlock,
    }
}

web_dto! {
    /// プロフィールの 1 行。
    #[derive(Eq)]
    pub struct ProfileRow {
        pub label: String,
        pub value: String,
        /// `"plain"` | `"monospaced"` | `"colorSwatch"` (`screen_composition::RowStyle` の写し)。
        pub style: String,
        /// 誕生日の行だけ `/idols/birth-month/<m>/` が入る。
        /// `CopyValue` / `ToggleExpansion` は Web に書き込み・状態が無いので `None` に落とす。
        pub link: Option<String>,
    }
}

web_dto! {
    /// CV の履歴 1 行。
    #[derive(Eq)]
    pub struct VoiceActorRow {
        pub name: String,
        pub start_date: Option<String>,
        pub end_date: Option<String>,
        pub is_current: bool,
        /// 1 行で出すときの表記 (名前と在任期間を `" ・ "` で繋いだもの)。
        pub display: String,
    }
}

web_dto! {
    /// 持ち曲の 1 行。
    #[derive(Eq)]
    pub struct IdolSongRow {
        pub song: Ref,
        /// `song_artists.role` (`original` / `cover` 等)。
        pub role: Option<String>,
        pub release_date: Option<String>,
        pub performance_count: u32,
        /// 行の副題 (ユニット名・リリース日・披露回数を `" ・ "` で繋いだもの)。空なら `None`。
        pub subtitle: Option<String>,
    }
}

web_dto! {
    /// 「歌ったことのある曲」の 1 行 (原唱者でなくても披露していれば載る)。
    #[derive(Eq)]
    pub struct IdolPerformedRow {
        pub song: Ref,
        pub times: u32,
        /// 行の副題 (ユニット名・披露回数)。空なら `None`。
        pub subtitle: Option<String>,
    }
}

web_dto! {
    /// 出演公演の 1 行。
    #[derive(Eq)]
    pub struct IdolShowRow {
        pub show: Ref,
        pub event: Ref,
        pub date: String,
        pub short_date: String,
        pub venue_label: Option<String>,
        /// このアイドルがこの公演で歌った曲数。
        pub song_count: u32,
        /// 行の副題 (公演名・会場)。
        ///
        /// 公演名はライブ名と重なる部分を落としてある (行のタイトルがライブ名なので、
        /// そのまま繋ぐと同じ名前が 2 行続く)。規則は披露履歴の `placeDisplay` と同じ。
        pub subtitle: Option<String>,
    }
}
