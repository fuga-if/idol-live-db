//! マスタ DB の不変インメモリスナップショット (Phase 2 の中核)。
//!
//! 設計 (docs/SHARED_CORE_STUDY.md「インメモリスナップショット方式」):
//! - SQLite は永続の正 (CloudKit 同期の着地・UserMark 保全)。読み取りはここには来ない。
//! - 本構造体は起動時 + sync 後に outbound::sqlite_loader が一括構築する派生キャッシュ。
//!   不変なのでロック不要・メインスレッドから同期で読んで良い (µs 級)。
//! - 実測 (2026-08-25): 12万行ロード 61ms / +37MB / 全曲走査 268µs (Mac, release)。
//! - **user_marks (担当/お気に入り/メモ/回収) は載せない**。ユーザーデータは書き込みが
//!   頻繁でプラットフォーム側が正。必要な判定は解決済み id 集合を引数で受け取る
//!   (SongListFiltering と同じ流儀)。
//! - **song_calls / song_videos も載せない**。コミュニティ投稿はローカル編集経路が
//!   スナップショット再ロードを促さない契約 (iOS CoreSnapshotManager の
//!   SnapshotInvalidatingSongWriting) で確定済みで、載せると「投稿直後に自分の投稿が
//!   見えない」回帰になる。読み取りは SQL 経路 (fallback) に残す。
//!
//! 索引は「クエリ関数が O(1)/O(log n) で入れる形」をロード時に前計算する。
//! 行の参照は Vec の添字 (u32) で持つ (String id の再引きを避ける)。
//! SQL 時代に毎回払っていた ORDER BY (sort_order 順・日付順・position 順) も
//! 構築時に一度だけ払い、クエリ側は前計算済みの並びをそのまま流す。
//!
//! ## Documents 専用の列・表 (Phase 3-5 引き継ぎ)
//! アプリ側マイグレーションが Documents DB にだけ足すもの。Bundle の master.sqlite には
//! 無いので、ローダが PRAGMA/sqlite_master で有無を動的検出し「あれば読む・無ければ既定値」:
//! - 列: events/shows の has_streaming・has_live_viewing、brands.icon_url → 無い DB では None。
//! - 表: event_releases → 無い DB では空 Vec。

use std::collections::HashMap;

/// songs 全カラム。GRDB Record / Room Entity と同じ「Record = Entity 兼用」の現実的判断。
#[derive(Debug, Clone)]
pub struct Song {
    pub id: String,
    pub title: String,
    pub title_kana: Option<String>,
    pub brand_id: Option<String>,
    pub song_type: Option<String>,
    pub release_date: Option<String>,
    pub duration_sec: Option<i64>,
    pub composer: Option<String>,
    pub lyricist: Option<String>,
    pub arranger: Option<String>,
    pub cd_series: Option<String>,
    pub cd_title: Option<String>,
    pub artwork_url: Option<String>,
    pub preview_url: Option<String>,
    pub apple_music_id: Option<String>,
    pub apple_music_album_id: Option<String>,
    pub isrc: Option<String>,
    pub lyrics_url: Option<String>,
    pub parent_song_id: Option<String>,
    pub singer_label: Option<String>,
    pub unit_name: Option<String>,
    pub unit_id: Option<String>,
    pub series_group: Option<String>,
    pub jasrac_code: Option<String>,
}

/// idols 全カラム (Bundle スキーマ基準)。
///
/// Phase 2 では一覧・検索に要る主要カラムだけだったが、Phase 3 で idol 詳細
/// (fetchIdol) とフィルタ (星座・出身地・血液型) が乗るため全カラムに拡張した。
/// height/weight/bust/waist/hip は REAL 列なので f64 で持つ。
#[derive(Debug, Clone)]
pub struct Idol {
    pub id: String,
    pub brand_id: Option<String>,
    pub name: String,
    pub name_kana: Option<String>,
    pub name_romaji: Option<String>,
    pub color: Option<String>,
    pub sort_order: Option<i64>,
    pub birthday: Option<String>,
    pub blood_type: Option<String>,
    pub height: Option<f64>,
    pub weight: Option<f64>,
    pub birth_place: Option<String>,
    pub age: Option<i64>,
    pub bust: Option<f64>,
    pub waist: Option<f64>,
    pub hip: Option<f64>,
    pub constellation: Option<String>,
    pub hobbies: Option<String>,
    pub talents: Option<String>,
    pub description: Option<String>,
    pub gender: Option<String>,
    pub handedness: Option<String>,
    pub family_name: Option<String>,
    pub given_name: Option<String>,
    pub nickname: Option<String>,
    pub debut_date: Option<String>,
    pub attribute: Option<String>,
    pub is_external: bool,
    pub aliases: Option<String>,
}

/// events 全カラム。
#[derive(Debug, Clone)]
pub struct Event {
    pub id: String,
    pub brand_id: Option<String>,
    pub name: String,
    /// ライブ名の読み。漢字のライブ名をかなで引けるようにする (曲・アイドルと同じ扱い)。
    pub name_kana: Option<String>,
    pub event_type: String,
    /// 互換のため残置 (iOS Event と同じ注記)。新コードからは参照しない。
    pub is_streaming: bool,
    /// 互換のため残置。新コードからは参照しない。
    pub is_solo: bool,
    /// イベント種別 ("live"/"festival"/"release_event"/"radio"/"stream")。
    /// 回収判定の「リアルライブのみ」(live/festival) の絞り込みに使う。
    pub kind: String,
    pub ticket_open_date: Option<String>,
    pub ticket_deadline: Option<String>,
    pub ticket_lottery_date: Option<String>,
    pub ticket_url: Option<String>,
    /// 合同ライブの追加ブランド ID (カンマ区切り)。nil なら単一ブランド。
    pub joint_brand_ids: Option<String>,
    /// Documents 専用列 (配信あり)。Bundle DB では常に None (列自体が無い)。
    pub has_streaming: Option<bool>,
    /// Documents 専用列 (ライブビューイングあり)。Bundle DB では常に None。
    pub has_live_viewing: Option<bool>,
}

/// shows 全カラム。event は events Vec の添字。
#[derive(Debug, Clone)]
pub struct Show {
    pub id: String,
    /// 親イベント (events の添字)。FK 孤児はロード時に読み飛ばすので必ず有効。
    pub event: u32,
    pub name: String,
    /// YYYY-MM-DD。並びの前計算はすべてこの文字列順 (辞書順 = 日付順)。
    pub date: String,
    pub venue: Option<String>,
    pub venue_city: Option<String>,
    pub start_time: Option<String>,
    pub sort_order: i64,
    pub performer_type: Option<String>,
    pub venue_id: Option<String>,
    pub hall: Option<String>,
    pub stream_platform: Option<String>,
    /// Documents 専用列 (公演単位の配信有無)。Bundle DB では常に None。
    pub has_streaming: Option<bool>,
    /// Documents 専用列 (公演単位の LV 有無)。Bundle DB では常に None。
    pub has_live_viewing: Option<bool>,
}

/// setlist_items の行。show / song は各 Vec の添字。
#[derive(Debug, Clone)]
pub struct SetlistItem {
    pub id: String,
    pub show: u32,
    pub song: u32,
    pub position: i64,
    pub section: Option<String>,
    pub notes: Option<String>,
    /// この披露限りのユニット表記 (恒常ユニットは songs.unit_name 側)。
    pub unit_name: Option<String>,
}

/// units 全カラム。
#[derive(Debug, Clone)]
pub struct Unit {
    pub id: String,
    pub brand_id: String,
    pub name: String,
    pub is_permanent: bool,
    pub name_alt: Option<String>,
    /// 読み。漢字のユニット名 (「可惜夜月」「星纏天女」) を かなで引くために持つ。
    /// 表記から機械的に起こせないので、入っているのは人が確かめた分だけ。
    pub name_kana: Option<String>,
}

/// brands 全カラム。
#[derive(Debug, Clone)]
pub struct Brand {
    pub id: String,
    pub name: String,
    pub short_name: String,
    pub color: Option<String>,
    pub sort_order: i64,
    /// Documents 専用列。Bundle DB では常に None。
    pub icon_url: Option<String>,
}

/// 作詞・作曲・編曲の作家。
///
/// **読みを持つためだけに存在する。** 曲側のクレジット欄 (`songs.composer` 等) は
/// 「BNSI(中川浩二)／烏屋茶房」のような自由文字列で、そのままでは かなで引けない。
/// `credit_names` で人ごとに割った表記を鍵に、ここの `name_kana` を当てる。
#[derive(Debug, Clone)]
pub struct Creator {
    pub id: String,
    /// `canonical_credit_key` を通した後の表記。
    pub name: String,
    pub name_kana: String,
    /// 曲側に現れる別表記 (改行区切り)。
    pub aliases: Option<String>,
}

/// venues 全カラム (会場マスタ)。VenueDirectory 相当の解決はクエリ層がメモリ上で行う。
#[derive(Debug, Clone)]
pub struct Venue {
    pub id: String,
    /// 現行名。過去公演の表示当時名は venue_names 側。
    pub name: String,
    pub name_kana: Option<String>,
    pub prefecture: Option<String>,
    pub city: Option<String>,
    /// 検索用の別名 (改行区切り)。
    pub aliases: Option<String>,
    pub capacity: Option<i64>,
    pub sort_order: i64,
}

/// venue_names (会場の期間つき名称履歴)。venue は venues Vec の添字。
#[derive(Debug, Clone)]
pub struct VenueName {
    pub id: String,
    pub venue: u32,
    pub name: String,
    pub valid_from: Option<String>,
    pub valid_to: Option<String>,
}

/// venue_halls (会場のホール/構成)。venue は venues Vec の添字。
#[derive(Debug, Clone)]
pub struct VenueHall {
    pub id: String,
    pub venue: u32,
    pub name: String,
    pub capacity: Option<i64>,
}

/// staff 全カラム (アイドル本人ではない関係者。カレンダー誕生日用)。
/// brand_id は brands に無い id でも保持する (表示に FK 整合は不要なため)。
#[derive(Debug, Clone)]
pub struct Staff {
    pub id: String,
    pub brand_id: String,
    pub name: String,
    pub name_kana: Option<String>,
    pub name_romaji: Option<String>,
    pub role: Option<String>,
    /// '--MM-DD' (年なし)。Idol.birthday と同じ形式。
    pub birthday: Option<String>,
    pub sort_order: i64,
}

/// anniversaries 全カラム (ブランド/アプリの記念日)。date は YYYY-MM-DD (年あり)。
#[derive(Debug, Clone)]
pub struct Anniversary {
    pub id: String,
    pub brand_id: String,
    pub label: String,
    pub date: String,
    pub kind: String,
    pub sort_order: i64,
}

/// idol_voice_actors (期間つき CV 履歴)。idol は idols Vec の添字。
/// 現任は valid_to IS NULL。交代発表後・後任未定の間は現任が居ないこともある。
#[derive(Debug, Clone)]
pub struct IdolVoiceActor {
    pub id: String,
    pub idol: u32,
    pub name: String,
    pub valid_from: Option<String>,
    pub valid_to: Option<String>,
}

/// event_releases (ライブ円盤。Documents 専用表)。event は events Vec の添字。
/// 公演単位の円盤なら show を持つ (イベント全体 BOX は None)。
#[derive(Debug, Clone)]
pub struct EventRelease {
    pub id: String,
    pub event: u32,
    pub show: Option<u32>,
    pub product_type: String,
    pub title: String,
    pub catalog_number: Option<String>,
    pub release_date: Option<String>,
    pub jacket_url: Option<String>,
    pub purchase_url: Option<String>,
    pub sort_order: i64,
}

/// 曲→歌唱者リンク。`idol` は idols Vec の添字。
#[derive(Debug, Clone)]
pub struct SongArtistLink {
    pub idol: u32,
    pub role: String,
}

/// アイドル→曲リンク (song_artists の逆引き)。`song` は songs Vec の添字。
/// role を持つのは fetchIdolSongs(role:) 相当の role 絞り込みを O(links) で行うため。
#[derive(Debug, Clone)]
pub struct IdolSongLink {
    pub song: u32,
    pub role: String,
}

/// 公演→出演者リンク (show_cast)。`idol` は idols Vec の添字。
/// cast_role は 'member' / 'lead' / 'guest' (スキーマ既定 'member')。
#[derive(Debug, Clone)]
pub struct ShowCastLink {
    pub idol: u32,
    pub cast_role: String,
}

/// ブランド→所属アイドルリンク (idol_brands)。`idol` は idols Vec の添字。
/// is_external の除外や DISTINCT はクエリ層の責務 (リンクは表の生データを保つ)。
#[derive(Debug, Clone)]
pub struct BrandMemberLink {
    pub idol: u32,
    pub is_primary: bool,
}

/// アイドル→所属ブランドリンク (idol_brands の逆引き)。`brand` は brands Vec の添字。
#[derive(Debug, Clone)]
pub struct IdolBrandLink {
    pub brand: u32,
    pub is_primary: bool,
}

/// 不変スナップショット本体。構築は outbound::sqlite_loader のみが行う。
///
/// 「◯◯_by_△△」の Vec は △△ 側と同じ添字で並ぶ逆引き索引。各索引の並び順は
/// SQL 時代の ORDER BY を構築時に前計算したもの (各フィールドの doc に明記)。
/// SQL では未規定だった同順位の並びは、添字を最終キーに使って決定的にしてある
/// (プラットフォーム間で同一結果を返すことが共有コアの目的なので、非決定性は残さない)。
#[derive(Debug, Default)]
pub struct Snapshot {
    pub songs: Vec<Song>,
    pub idols: Vec<Idol>,
    pub events: Vec<Event>,
    pub shows: Vec<Show>,
    pub setlist_items: Vec<SetlistItem>,
    pub units: Vec<Unit>,
    pub brands: Vec<Brand>,
    pub creators: Vec<Creator>,
    /// 作家の読み・別表記を畳んだ検索用の綴り列 (`creators` と同じ並び)。
    /// 打鍵ごとに組み直さないよう読み込み時に 1 回だけ作る。
    pub creator_spellings: Vec<Vec<String>>,
    pub venues: Vec<Venue>,
    /// 並びはテーブル出現順 (SQL 時代の fetchAll も ORDER BY なし)。
    pub venue_names: Vec<VenueName>,
    /// 並びはテーブル出現順。
    pub venue_halls: Vec<VenueHall>,
    /// 並びはテーブル出現順。カレンダーの誕生日抽出はクエリ層が
    /// birthday 有無で絞る (SQL 時代も ORDER BY なし + Swift 側ソート)。
    pub staff: Vec<Staff>,
    pub anniversaries: Vec<Anniversary>,
    pub idol_voice_actors: Vec<IdolVoiceActor>,
    /// Documents 専用表。表が無い DB (Bundle) では空。
    pub event_releases: Vec<EventRelease>,
    /// meta 表 (key → value)。value が NULL の行は載せない
    /// (SQL 時代の getValue も NULL と行なしを区別せず nil を返していた)。
    pub meta: HashMap<String, String>,

    /// songs と同じ添字。リンクは idol の sort_order 順に格納済み
    /// (SQL 時代の `ORDER BY i.sort_order` を構築時に前計算)。
    pub artists_by_song: Vec<Vec<SongArtistLink>>,
    /// idols と同じ添字。song_artists の逆引き (role つき)。
    /// release_date 降順 (SQL 時代の fetchIdolSongs `ORDER BY s.release_date DESC`)。
    /// NULL の release_date は末尾 (SQLite の DESC と同じ NULLS LAST)。
    pub songs_by_idol: Vec<Vec<IdolSongLink>>,
    /// songs と同じ添字。setlist_items における披露回数
    /// (= setlist_items_by_song の各長さ。二重集計しないよう構築時に導出)。
    pub performance_counts: Vec<u32>,

    /// events と同じ添字。配下 show の添字を (date ASC, sort_order ASC) で格納
    /// (iOS fetchShows(eventId:) の `.order(date, sort_order)` と同じ)。
    pub shows_by_event: Vec<Vec<u32>>,
    /// shows と同じ添字。セトリ項目の添字を position 昇順で格納。
    pub setlist_items_by_show: Vec<Vec<u32>>,
    /// songs と同じ添字。披露履歴 (fetchSongPerformanceHistory) の表示順:
    /// show.date DESC。SQL では同日内が未規定だったので、同日は
    /// (show.sort_order ASC, position ASC) で決定的にしてある。
    pub setlist_items_by_song: Vec<Vec<u32>>,
    /// setlist_items と同じ添字。その披露の歌唱メンバー (setlist_performers)。
    /// idol の sort_order 順。
    pub performers_by_item: Vec<Vec<u32>>,
    /// idols と同じ添字。setlist_performers の逆引き (歌った setlist_item 添字群)。
    /// setlist_items_by_song と同じ (show.date DESC) 順 — fetchIdolSongHistory /
    /// fetchIdolPerformedSongs が新しい順で走査するため。
    pub performed_items_by_idol: Vec<Vec<u32>>,

    /// shows と同じ添字。show_cast の出演者リンク。idol の sort_order 順。
    pub cast_by_show: Vec<Vec<ShowCastLink>>,
    /// idols と同じ添字。show_cast の逆引き (出演した show 添字群)。show.date DESC。
    pub cast_shows_by_idol: Vec<Vec<u32>>,

    /// units と同じ添字。メンバー idol 添字を sort_order 順で格納。
    pub members_by_unit: Vec<Vec<u32>>,
    /// idols と同じ添字。所属ユニット添字を unit.name 昇順で格納
    /// (iOS fetchIdolUnits の `ORDER BY u.name`。BINARY 照合 = バイト列比較で一致)。
    pub units_by_idol: Vec<Vec<u32>>,
    /// units と同じ添字。songs.unit_id によるユニット持ち曲。release_date 昇順
    /// (iOS fetchUnitSongs の `.order(release_date)`。NULL は先頭 = SQLite ASC と同じ)。
    pub songs_by_unit: Vec<Vec<u32>>,

    /// songs と同じ添字。この曲を親 (parent_song_id) とする派生曲の添字群。
    /// (title_kana, title) 昇順 — fetchVariantSongs の family 表示順
    /// (根が先頭・続いて子が 50 音順) の「子」の部分を前計算したもの。
    pub variants_by_song: Vec<Vec<u32>>,

    /// brands と同じ添字。所属アイドルリンク (idol_brands)。idol の sort_order 順。
    /// is_external の除外・DISTINCT はクエリ層 (fetchIdols(brandId:) 相当) で行う。
    pub idols_by_brand: Vec<Vec<BrandMemberLink>>,
    /// idols と同じ添字。idol_brands の逆引き。brand の sort_order 順。
    pub brands_by_idol: Vec<Vec<IdolBrandLink>>,

    /// idols と同じ添字。CV 履歴 (idol_voice_actors 添字群) を
    /// `IFNULL(valid_from,'') DESC` 順で格納 (fetchVoiceActorHistory の表示順)。
    /// 現任解決 (fetchCurrentVoiceActor) は `current_voice_actor()` で先頭一致を取る。
    pub voice_actors_by_idol: Vec<Vec<u32>>,
    /// CV 名 (完全一致) → 担当アイドル添字群。歴代すべて対象・重複排除済み・
    /// idol の sort_order 順 (fetchIdolsByVoiceActor の `DISTINCT ... ORDER BY sort_order`)。
    pub idols_by_voice_actor_name: HashMap<String, Vec<u32>>,

    /// venues と同じ添字。名称履歴 (venue_names 添字群)。テーブル出現順。
    pub names_by_venue: Vec<Vec<u32>>,
    /// venues と同じ添字。ホール (venue_halls 添字群)。テーブル出現順。
    pub halls_by_venue: Vec<Vec<u32>>,
    /// shows.venue_id → show 添字群。date DESC (showsByVenue の `ORDER BY date DESC`)。
    /// 同日は (sort_order ASC, 添字) で決定的に。
    pub shows_by_venue_id: HashMap<String, Vec<u32>>,
    /// shows.venue (生の会場文字列) → show 添字群。並びは shows_by_venue_id と同じ。
    /// venue_id を持たない過去公演の後方互換 (「ID 一致 または 生文字列一致」の OR) 用。
    pub shows_by_venue_label: HashMap<String, Vec<u32>>,

    /// events と同じ添字。円盤 (event_releases 添字群) を
    /// (release_date ASC, sort_order ASC) で格納 (fetchEventReleases の表示順。
    /// release_date NULL は先頭 = SQLite ASC と同じ)。
    pub releases_by_event: Vec<Vec<u32>>,

    /// 全ブランドを (sort_order ASC, 添字) で並べた添字列 (fetchBrands の表示順)。
    pub brand_order: Vec<u32>,
    /// 全アイドルを (sort_order ASC, 添字) で並べた添字列
    /// (`ORDER BY sort_order` 系クエリ共通の土台。is_external 除外はクエリ層)。
    pub idol_order: Vec<u32>,
    /// 全ユニットを (brand_id ASC, name ASC, 添字) で並べた添字列 (fetchAllUnits の表示順)。
    pub unit_order: Vec<u32>,
    /// 全会場を (sort_order ASC, 添字) で並べた添字列 (fetchVenueDirectory の表示順)。
    pub venue_order: Vec<u32>,
    /// 全記念日を (date ASC, 添字) で並べた添字列 (Timeline milestoneBars の `ORDER BY date`)。
    pub anniversary_order: Vec<u32>,
    /// 全公演を (date ASC, sort_order ASC, 添字) で並べた添字列。
    /// カレンダーの日付範囲抽出 (`WHERE date >= ? AND date <= ? ORDER BY date, sort_order`)
    /// が二分探索で入れる。末尾要素 = 最新公演 (fetchLatestShow 相当)。
    pub shows_in_date_order: Vec<u32>,
    /// 全イベントを (name ASC, 添字) で並べた添字列 (fetchEventNames の `ORDER BY name`)。
    pub events_by_name_order: Vec<u32>,

    pub song_index_by_id: HashMap<String, u32>,
    pub idol_index_by_id: HashMap<String, u32>,
    pub event_index_by_id: HashMap<String, u32>,
    pub show_index_by_id: HashMap<String, u32>,
    pub unit_index_by_id: HashMap<String, u32>,
    pub brand_index_by_id: HashMap<String, u32>,
    pub venue_index_by_id: HashMap<String, u32>,
}

impl Snapshot {
    pub fn song(&self, id: &str) -> Option<&Song> {
        self.song_index_by_id.get(id).map(|&i| &self.songs[i as usize])
    }

    pub fn idol(&self, id: &str) -> Option<&Idol> {
        self.idol_index_by_id.get(id).map(|&i| &self.idols[i as usize])
    }

    pub fn event(&self, id: &str) -> Option<&Event> {
        self.event_index_by_id.get(id).map(|&i| &self.events[i as usize])
    }

    pub fn show(&self, id: &str) -> Option<&Show> {
        self.show_index_by_id.get(id).map(|&i| &self.shows[i as usize])
    }

    pub fn unit(&self, id: &str) -> Option<&Unit> {
        self.unit_index_by_id.get(id).map(|&i| &self.units[i as usize])
    }

    pub fn brand(&self, id: &str) -> Option<&Brand> {
        self.brand_index_by_id.get(id).map(|&i| &self.brands[i as usize])
    }

    pub fn venue(&self, id: &str) -> Option<&Venue> {
        self.venue_index_by_id.get(id).map(|&i| &self.venues[i as usize])
    }

    /// meta の値。行が無い場合と value NULL は区別しない (SQL 時代の getValue と同じ)。
    pub fn meta_value(&self, key: &str) -> Option<&str> {
        self.meta.get(key).map(String::as_str)
    }

    /// 歌唱者 (role 指定時はその role のみ) を sort_order 順で返す。
    pub fn song_artists(&self, song_id: &str, role: Option<&str>) -> Vec<&Idol> {
        let Some(&si) = self.song_index_by_id.get(song_id) else { return vec![] };
        self.artists_by_song[si as usize]
            .iter()
            .filter(|l| role.is_none_or(|r| l.role == r))
            .map(|l| &self.idols[l.idol as usize])
            .collect()
    }

    /// 派生曲一族の根 (parent_song_id を 1 段遡る)。自分が根ならそのまま。
    ///
    /// fetchVariantSongs と同じく「自分が派生側でも親側でも同じ一族」を引くための入口。
    /// parent_song_id が壊れて未知 id を指す場合は自分を根とみなす (孤児で落ちない)。
    pub fn variant_root(&self, song: u32) -> u32 {
        match &self.songs[song as usize].parent_song_id {
            Some(pid) => self.song_index_by_id.get(pid).copied().unwrap_or(song),
            None => song,
        }
    }

    /// show_cast における cast_role。行が無い (= セトリだけの出演) なら None。
    /// SQL 時代の `COALESCE(..., 'member')` の 'member' 既定はクエリ層で補うこと
    /// (「行が無い」と「member と明記」を区別できる情報を落とさないため)。
    pub fn show_cast_role(&self, show: u32, idol: u32) -> Option<&str> {
        self.cast_by_show[show as usize]
            .iter()
            .find(|l| l.idol == idol)
            .map(|l| l.cast_role.as_str())
    }

    /// 現任 CV (valid_to IS NULL)。交代待ちで後任未定なら None。
    ///
    /// voice_actors_by_idol は `IFNULL(valid_from,'') DESC` で並んでいるので、
    /// 先頭から最初に見つかる現任行が SQL の
    /// `WHERE valid_to IS NULL ORDER BY IFNULL(valid_from,'') DESC LIMIT 1` と一致する。
    pub fn current_voice_actor(&self, idol: u32) -> Option<&IdolVoiceActor> {
        self.voice_actors_by_idol[idol as usize]
            .iter()
            .map(|&i| &self.idol_voice_actors[i as usize])
            .find(|va| va.valid_to.is_none())
    }
}
