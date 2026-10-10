//! 楽曲一覧のクエリ群 (SQL 時代の一覧系を Snapshot 上の純粋関数へ移送)。
//!
//! SQL 時代の対応:
//! - iOS `AppDatabase+SongQueries.fetchSongsByFilterQuery` (動的 WHERE + DISTINCT + 既定ソート)
//! - iOS `AppDatabase+EventQueries` の criterion 系 (cd_series / series_group / リリース年 / id 集合)
//! - iOS `AppDatabase+SongQueries.totalSongPerformanceCountMap` / `attendedSongCountMap`
//! - iOS `AppDatabase+UserMarks.fetchSongCollectedCountsQuery` (現地回収バッジ)
//!
//! シリーズ一覧 (fetchSeries / fetchSeriesGroups) は song_detail_queries 側へ移送済み
//! (`series_summaries` / `series_group_names`)。二重管理を避けるためここには置かない。
//!
//! SQL の暗黙挙動をコードで明示して固定する:
//! - `ORDER BY` の NULL 位置: SQLite は ASC で NULL 先頭 / DESC で NULL 末尾。
//!   Rust の `Option` は `None < Some` なので ASC はそのまま、DESC は左右反転で一致する。
//! - 文字列比較は BINARY 照合 (= バイト列比較)。Rust の `str`/`String` の `Ord` と同じ。
//! - `LIKE '%q%'` は ASCII だけ大文字小文字を無視する部分一致。UTF-8 の多バイト文字は
//!   継続バイトが 0x80 以上で ASCII と衝突しないため、バイト列上の大小無視検索で等価になる。
//! - SQL が未規定だった同順位の並びは添字 (= 読み込み順。主キー順) を最終キーにして決定的にする
//!   (プラットフォーム間で同一結果を返すのが共有コアの目的)。
//!
//! **user_marks はスナップショットに無い** (書き込みが頻繁でプラットフォームが正)。
//! 回収系は「参加済みの show/event id 集合」を解決済みで受け取る (SongListFiltering と同じ流儀)。

use crate::domain::collection_gap::attended_real_live_shows;
use crate::domain::display_join::non_empty;
use crate::domain::snapshot::Snapshot;
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use crate::domain::text_search_index::FoldedNeedle;

/// 楽曲一覧の動的絞り込み条件。iOS `SongSearchFilter` の 1:1 対応。
///
/// 名前を iOS 側と揃えていないのは意図的: 生成バインディングがアプリと同一モジュールに
/// 入るため、既存 Swift struct と衝突する (song_list_filtering.rs の前例と同じ判断)。
#[derive(uniffi::Record, Clone, Debug, Default)]
pub struct SongListFilter {
    /// 空 = 全ブランド対象。複数選択は OR 結合 (SQL の `IN`)。
    pub brand_ids: Vec<String>,
    /// 曲名検索 (title / title_kana の部分一致)。None・空文字は条件なし。
    pub title: Option<String>,
    /// アイドル名検索 (name / name_kana の部分一致、role='original' 限定)。
    /// `idol_ids` があればそちらが優先される (iOS の else-if を踏襲)。
    pub idol_name: Option<String>,
    /// 歌唱アイドル id での絞り込み (role='original' 限定)。iOS は `[String]?` だが
    /// nil も [] も「指定なし」なので Vec で受ける。
    pub idol_ids: Vec<String>,
    /// 作家検索 (composer / lyricist / arranger の部分一致)。
    pub songwriter: Option<String>,
    /// CD シリーズ名の部分一致。
    pub cd_series: Option<String>,
    /// 上位シリーズ (series_group) の完全一致。空文字は条件なし。
    pub series_group: Option<String>,
    /// ライブ名 (イベント名) の部分一致。セトリに載った曲だけが対象になる。
    pub live_name: Option<String>,
    /// 曲種別の完全一致。iOS は空チェックなしで適用するので Some("") も条件になる。
    pub song_type: Option<String>,
    /// false ならリミックス・別バージョン (parent_song_id あり) を隠す。
    pub include_remixes: bool,
    /// ブランド未選択時に brand_id='other' (歌枠カバー等) を含めるか。
    /// brand_ids を明示した場合はそちらが優先 (このフラグは無視)。
    pub include_other_brand: bool,
    /// ライブ履歴にしか存在しないファントム曲 (カタログメタ皆無) を隠すか。
    pub exclude_live_only: bool,
    /// 音楽カードゲーム「KAMISABI」の収録曲だけに絞るか (false = 絞らない)。
    pub kamisabi_only: bool,
}

/// 一覧の絞り込み条件を、**出面 (JSON) で運ぶための形**。
///
/// `SongListFilter` + 並べ替え。ページを組んだ Rust が土台として書き出し、
/// ブラウザの wasm がそのまま読んで `song_list_indexes` を回す。
///
/// **これが Rust ↔ wasm ↔ TS の唯一の定義**。以前は
/// (a) `emit::lists::query_base_json` の手書き camelCase JSON、
/// (b) wasm 側の写し、(c) TS の手書き interface、と 3 つに割れていて、
/// 軸を 1 本足すと 3 箇所を人手で揃える必要があった (型でもテストでも捕まらない)。
///
/// ts-rs は `web-export` のときだけ付く。wasm 側はこの型を素の serde で読む。
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase", default)]
#[cfg_attr(
    feature = "web-export",
    derive(ts_rs::TS),
    ts(export, export_to = "../../web/src/lib/schema/")
)]
pub struct SongQuery {
    pub brand_ids: Vec<String>,
    pub title: Option<String>,
    pub idol_name: Option<String>,
    pub idol_ids: Vec<String>,
    pub songwriter: Option<String>,
    pub cd_series: Option<String>,
    pub series_group: Option<String>,
    pub live_name: Option<String>,
    pub song_type: Option<String>,
    pub include_remixes: bool,
    pub include_other_brand: bool,
    pub exclude_live_only: bool,
    /// KAMISABI 収録曲だけに絞るか。
    pub kamisabi_only: bool,
    /// `SongListSort::key()` の値。未知の鍵は既定 (50 音順) に倒れる。
    pub sort: String,
    /// 省略時はその並びの既定方向 (`SongListSort::default_ascending`)。
    pub ascending: Option<bool>,
}

impl Default for SongQuery {
    /// 一覧ページの既定。`SongListFilter::default()` ではなく
    /// **一覧を組むときに使う既定** (ライブ履歴のみの曲は隠す) に合わせる。
    fn default() -> Self {
        Self {
            brand_ids: Vec::new(),
            title: None,
            idol_name: None,
            idol_ids: Vec::new(),
            songwriter: None,
            cd_series: None,
            series_group: None,
            live_name: None,
            song_type: None,
            include_remixes: false,
            include_other_brand: false,
            exclude_live_only: true,
            kamisabi_only: false,
            sort: "kana".to_string(),
            ascending: None,
        }
    }
}

impl SongQuery {
    /// 絞り込み条件だけを取り出す。
    pub fn to_filter(&self) -> SongListFilter {
        SongListFilter {
            brand_ids: self.brand_ids.clone(),
            title: self.title.clone(),
            idol_name: self.idol_name.clone(),
            idol_ids: self.idol_ids.clone(),
            songwriter: self.songwriter.clone(),
            cd_series: self.cd_series.clone(),
            series_group: self.series_group.clone(),
            live_name: self.live_name.clone(),
            song_type: self.song_type.clone(),
            include_remixes: self.include_remixes,
            include_other_brand: self.include_other_brand,
            exclude_live_only: self.exclude_live_only,
            kamisabi_only: self.kamisabi_only,
        }
    }

    /// 並べ替え軸。
    pub fn sort_order(&self) -> SongListSort {
        SongListSort::from_key(&self.sort)
    }

    /// 一覧を組んだ条件から土台を作る (並べ替えは既定のまま)。
    pub fn from_filter(f: &SongListFilter) -> Self {
        Self {
            brand_ids: f.brand_ids.clone(),
            title: f.title.clone(),
            idol_name: f.idol_name.clone(),
            idol_ids: f.idol_ids.clone(),
            songwriter: f.songwriter.clone(),
            cd_series: f.cd_series.clone(),
            series_group: f.series_group.clone(),
            live_name: f.live_name.clone(),
            song_type: f.song_type.clone(),
            include_remixes: f.include_remixes,
            include_other_brand: f.include_other_brand,
            exclude_live_only: f.exclude_live_only,
            kamisabi_only: f.kamisabi_only,
            ..Self::default()
        }
    }
}

/// 楽曲一覧のソート軸。iOS `SongSortOrder` の 1:1 対応 (名前は衝突回避で変更)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SongListSort {
    TitleKana,
    ReleaseDate,
    PerformanceCount,
    CollectedCount,
    CollectedRate,
}

impl SongListSort {
    /// 既定方向。50 音順は昇順、日付/回数系は降順 (新しい/多い順)。iOS `defaultAscending` と同じ。
    pub fn default_ascending(self) -> bool {
        matches!(self, SongListSort::TitleKana)
    }

    /// URL・保存値に使う鍵。**序数を使わない** (並べ替えた瞬間に別物になる)。
    pub fn key(self) -> &'static str {
        match self {
            Self::TitleKana => "kana",
            Self::ReleaseDate => "release",
            Self::PerformanceCount => "performance",
            Self::CollectedCount => "collected",
            Self::CollectedRate => "collected_rate",
        }
    }

    /// 画面に出す文言。
    pub fn label(self) -> &'static str {
        match self {
            Self::TitleKana => "五十音順",
            Self::ReleaseDate => "リリース日順",
            Self::PerformanceCount => "披露回数順",
            Self::CollectedCount => "回収数順",
            Self::CollectedRate => "回収率順",
        }
    }

    /// この並びに、その人の回収記録が要るか。
    ///
    /// 要るものは**ログインもユーザーデータも持たない出面 (Web) では出せない**。
    /// 「どれを出すか」を出面側が列挙し直すと、並びを 1 つ足したときに
    /// 片方だけ古いまま残る。
    pub fn requires_user_marks(self) -> bool {
        matches!(self, Self::CollectedCount | Self::CollectedRate)
    }

    pub fn all() -> Vec<Self> {
        vec![
            Self::TitleKana,
            Self::ReleaseDate,
            Self::PerformanceCount,
            Self::CollectedCount,
            Self::CollectedRate,
        ]
    }

    /// 鍵からの復元。未知の鍵は既定 (50 音順)。
    pub fn from_key(key: &str) -> Self {
        Self::all().into_iter().find(|s| s.key() == key).unwrap_or(Self::TitleKana)
    }
}

/// 並べ替え 1 つぶんの選択肢。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SongListSortOption {
    pub key: String,
    pub label: String,
    pub default_ascending: bool,
}

/// ユーザーデータを持たない出面で選べる並べ替え。
pub fn song_list_sort_options_without_user_marks() -> Vec<SongListSortOption> {
    SongListSort::all()
        .into_iter()
        .filter(|s| !s.requires_user_marks())
        .map(|s| SongListSortOption {
            key: s.key().to_string(),
            label: s.label().to_string(),
            default_ascending: s.default_ascending(),
        })
        .collect()
}

// ---- LIKE (%q% / q%) の明示実装 ----

/// SQLite の `LIKE 'needle%'` 相当 (前方一致)。リリース年フィルタで使う。
fn like_prefix(haystack: &str, needle: &str) -> bool {
    let (h, n) = (haystack.as_bytes(), needle.as_bytes());
    n.len() <= h.len() && h[..n.len()].eq_ignore_ascii_case(n)
}

/// iOS 側の「nil も空文字も条件なし」を 1 箇所に固定する。
/// 打った語が読み・別表記に当たった作家の、**曲側の欄に出る表記**を返す。
///
/// 曲の欄は自由文字列なので、そこに読みは書かれていない。「からすやさぼう」を
/// 「烏屋茶房」に翻訳してから欄を見る、という 2 段構えにしている。
///
/// 別表記 (`aliases`) も鍵に含めるのは、同じ人が「滝澤俊輔(TRYTONELABO)」
/// 「滝澤俊輔［TRYTONELABO］」のように複数の書き方で欄に出るため。
/// 綴り列は読み込み時に 1 回だけ組んである (`Snapshot::creator_spellings`)。
fn creator_names_matching<'a>(snap: &'a Snapshot, needle: &FoldedNeedle) -> Vec<&'a str> {
    snap.creator_spellings
        .iter()
        .enumerate()
        .filter(|(_, spellings)| spellings.iter().any(|sp| needle.matches(sp)))
        .map(|(i, _)| snap.creators[i].name.as_str())
        .collect()
}

// ---- 絞り込み ----

/// 動的 WHERE (iOS `fetchSongsByFilterQuery` の条件部) を適用し、通過した曲の添字を
/// スナップショット順 (= 読み込み順。主キー順) で返す。
///
/// 元 SQL の `SELECT DISTINCT s.*` + JOIN は「条件を満たす関連行が 1 つでもあるか」の
/// 存在判定と等価なので、曲ごとの述語に置き換えている (JOIN の行複製と DISTINCT の
/// 打ち消し合いを持ち込まない)。
/// 既定の一覧で隠す派生曲か。
///
/// 元 SQL は `parent_song_id IS NULL` だった (空文字は NULL ではないので `Some("")` は
/// 派生扱いのまま)。そこに 1 つだけ例外を足してある:
///
/// **カードが付いている派生曲は隠さない。** KAMISABI のカードは派生曲にも付く
/// (`Welcome!! (レジェンドデイズ Ver.)` は全体曲 `Welcome!!` の別録音)。隠すと、
/// 一覧に出てこない曲が収録 150 曲に混じり、所持コンプの分母が実物と合わなくなる。
///
/// **これを「KAMISABI で絞っているときだけ隠さない」という形にしてはいけない。**
/// 軸どうしが絡むと、同じ絡みを iOS の GRDB 経路・Android の SQL 経路・出面の静的土台に
/// 写す必要が出る (実際に写して、そのうち 2 つが 149 件になった)。ここを「その曲自体が
/// 商品として立っているか」の規則にしておけば、各 OS の SQL は
/// `(parent_song_id IS NULL OR has_kamisabi_card = 1)` の**無条件 1 行**で済む。
pub fn is_hidden_variant(s: &crate::domain::snapshot::Song) -> bool {
    s.parent_song_id.is_some() && !s.has_kamisabi_card
}

/// 原唱者がちょうど 1 人の曲か (= その人ひとりの持ち歌)。
///
/// `is_hidden_variant` の隣に置いてあるのは、どちらも「その曲が誰のものか」を
/// 曲の側から決める述語で、一覧・LLM ツール・セトリの型のどこからも同じ答えが
/// 要るため。原唱者の濾しは `Snapshot::song_artists` が正本なので、ここで
/// `role == "original"` を書き直さない。
///
/// **`songs.song_type == "solo"` とは別物。**あちらは商品としての名義 (カタログが
/// 「ソロ曲」と呼んでいるか) で、こちらは `song_artists` から導いた人数。原則は
/// 一致するが、名義が付いていない曲・共演が後から足された曲ではズレうるので、
/// 「何人の持ち歌か」を数えるときは必ずこちらを使う。
pub fn is_solo_song(snap: &Snapshot, song: u32) -> bool {
    snap.song_artists(&snap.songs[song as usize].id, Some("original")).len() == 1
}

pub fn filter_song_indexes(snap: &Snapshot, filter: &SongListFilter) -> Vec<u32> {
    let brand_set: HashSet<&str> = filter.brand_ids.iter().map(String::as_str).collect();
    let idol_set: HashSet<&str> = filter.idol_ids.iter().map(String::as_str).collect();
    // 検索語は行ごとではなく**ここで 1 回だけ**畳む (`FoldedNeedle`)。
    // 当たり方は一覧の索引 (`TextSearchCatalog`) と同じ規則 — かなの表記違いも畳む。
    let title_q = non_empty(&filter.title).map(FoldedNeedle::new);
    let idol_name_q = non_empty(&filter.idol_name).map(FoldedNeedle::new);
    let songwriter_q = non_empty(&filter.songwriter).map(FoldedNeedle::new);
    let cd_series_q = non_empty(&filter.cd_series).map(FoldedNeedle::new);
    let series_group_q = non_empty(&filter.series_group);
    let live_name_q = non_empty(&filter.live_name).map(FoldedNeedle::new);

    snap.songs
        .iter()
        .enumerate()
        .filter(|&(i, s)| {
            // KAMISABI 収録だけの一覧。曲の属性ではなく商品への収録なので、
            // ここは列を見るだけ (何が収録かを推測しない)。
            if filter.kamisabi_only && !s.has_kamisabi_card {
                return false;
            }
            // 既定で派生曲 (リミックス・別バージョン) を隠す。
            if !filter.include_remixes && is_hidden_variant(s) {
                return false;
            }
            if !brand_set.is_empty() {
                // `brand_id IN (...)`: NULL はどの値とも一致しない。
                // 合同曲は `joint_brand_ids` の側でも当たる (参加ブランド全部の一覧に出す)。
                if !s.brand_ids().any(|b| brand_set.contains(b)) {
                    return false;
                }
            } else if !filter.include_other_brand && s.brand_id.as_deref() == Some("other") {
                // `brand_id IS NOT 'other'`: IS NOT なので NULL は通る (!= との違いに注意)。
                return false;
            }
            if filter.exclude_live_only {
                // カタログメタ (配信ID/リリース日/CD/作家) か歌唱者を 1 つでも持てば正規曲。
                let has_meta = [
                    &s.apple_music_id,
                    &s.release_date,
                    &s.cd_title,
                    &s.cd_series,
                    &s.composer,
                    &s.lyricist,
                    &s.arranger,
                ]
                .iter()
                .any(|v| non_empty(v).is_some());
                // EXISTS (song_artists) は role を問わない (original 限定ではない)。
                if !has_meta && snap.artists_by_song[i].is_empty() {
                    return false;
                }
            }
            if let Some(q) = &title_q {
                // 全行を舐めるので、読み込み時に畳んだ索引と突き合わせる
                // (行ごとに畳むと 3,154 曲で 7.4ms → 索引なら 0.6ms)。
                if !snap.song_search[i].matches(q.as_bytes()) {
                    return false;
                }
            }
            if let Some(q) = &songwriter_q {
                let hit = q.matches_opt(s.composer.as_deref())
                    || q.matches_opt(s.lyricist.as_deref())
                    || q.matches_opt(s.arranger.as_deref())
                    // クレジット欄は「BNSI(中川浩二)／烏屋茶房」のような自由文字列なので、
                    // 生の欄だけを見ると**読みでは永久に当たらない** (「からすやさぼう」で
                    // 烏屋茶房 の 36 曲が 0 件になっていた)。読みで当たった作家の表記に
                    // 置き換えてもう一度欄を見る。
                    || creator_names_matching(snap, q).iter().any(|n| {
                        let name = FoldedNeedle::new(n);
                        name.matches_opt(s.composer.as_deref())
                            || name.matches_opt(s.lyricist.as_deref())
                            || name.matches_opt(s.arranger.as_deref())
                    });
                if !hit {
                    return false;
                }
            }
            if let Some(q) = &cd_series_q {
                if !q.matches_opt(s.cd_series.as_deref()) {
                    return false;
                }
            }
            if let Some(g) = series_group_q {
                if s.series_group.as_deref() != Some(g) {
                    return false;
                }
            }
            // iOS は songType の空チェックをしていない (Some("") も条件になる) — 忠実に再現。
            if let Some(t) = filter.song_type.as_deref() {
                if s.song_type.as_deref() != Some(t) {
                    return false;
                }
            }
            // アイドル絞り込みは持ち曲 (role='original') 限定。performer まで拾うと
            // 「一度ライブで歌っただけの他人の持ち曲」が並ぶ (iOS 側コメントの経緯)。
            if !idol_set.is_empty() || idol_name_q.is_some() {
                let matched = snap.artists_by_song[i].iter().any(|link| {
                    if link.role != "original" {
                        return false;
                    }
                    let idol = &snap.idols[link.idol as usize];
                    if !idol_set.is_empty() {
                        idol_set.contains(idol.id.as_str())
                    } else {
                        let q = idol_name_q.as_ref().expect("idol_name_q は Some の分岐");
                        q.matches(&idol.name) || q.matches_opt(idol.name_kana.as_deref())
                    }
                });
                if !matched {
                    return false;
                }
            }
            if let Some(q) = &live_name_q {
                // セトリ → show → event と辿り、イベント名が一致する披露が 1 つでもあるか。
                // 数えない公演 (配信だけのライブ等) で歌われた曲も、名前で引けば当たる。
                let matched = snap.all_setlist_items_by_song[i].iter().any(|&ti| {
                    let show = &snap.shows[snap.setlist_items[ti as usize].show as usize];
                    q.matches(&snap.events[show.event as usize].name)
                });
                if !matched {
                    return false;
                }
            }
            true
        })
        .map(|(i, _)| i as u32)
        .collect()
}

// ---- 整列 ----

/// 方向つき比較。SQLite の DESC は列単位の反転なので、複合キーは列ごとにこれを重ねる
/// (タプル全体を反転すると最終キーの添字まで反転してしまい、決定性規約が崩れる)。
fn cmp_dir<T: Ord>(a: &T, b: &T, asc: bool) -> Ordering {
    if asc {
        a.cmp(b)
    } else {
        b.cmp(a)
    }
}

/// 50 音順の同着タイブレーク: title_kana ASC (NULL 先頭) → title ASC → 添字。
///
/// 数値系ソートの同数時に使う。SQL 時代は ORDER BY なし + Swift の不安定ソートで
/// 同数の並びが未規定だったため、既定ソートと同じ 50 音で決定的にした (意図的な明確化)。
fn kana_tiebreak(snap: &Snapshot, l: u32, r: u32) -> Ordering {
    let (a, b) = (&snap.songs[l as usize], &snap.songs[r as usize]);
    a.title_kana
        .cmp(&b.title_kana)
        .then_with(|| a.title.cmp(&b.title))
        .then(l.cmp(&r))
}

/// 絞り込み + 整列した曲添字列 (iOS `fetchSongs(filter:sortOrder:ascending:)` の一覧本体)。
///
/// `attended_show_ids` / `attended_event_ids` は参加マーク (user_marks) を
/// プラットフォーム側で解決した id 集合。CollectedCount / CollectedRate の並び替えでだけ
/// 使う。iOS の並び替え (`attendedSongCountMap`) は回収バッジと違い **kind も参加種別も
/// 絞らない** ので、呼び出し側は「attended の show マーク全部 (種別条件なし)」を渡すこと。
pub fn song_list_indexes(
    snap: &Snapshot,
    filter: &SongListFilter,
    sort: SongListSort,
    ascending: Option<bool>,
    attended_show_ids: &[String],
    attended_event_ids: &[String],
) -> Vec<u32> {
    let mut indexes = filter_song_indexes(snap, filter);
    let asc = ascending.unwrap_or(sort.default_ascending());

    match sort {
        SongListSort::TitleKana => {
            // ORDER BY title_kana dir, title dir (両列とも同方向)。
            indexes.sort_by(|&l, &r| {
                let (a, b) = (&snap.songs[l as usize], &snap.songs[r as usize]);
                cmp_dir(&a.title_kana, &b.title_kana, asc)
                    .then_with(|| cmp_dir(&a.title, &b.title, asc))
                    .then(l.cmp(&r))
            });
        }
        SongListSort::ReleaseDate => {
            // ORDER BY release_date dir, title_kana (2 列目は常に昇順 — 元 SQL のまま)。
            indexes.sort_by(|&l, &r| {
                let (a, b) = (&snap.songs[l as usize], &snap.songs[r as usize]);
                cmp_dir(&a.release_date, &b.release_date, asc)
                    .then_with(|| a.title_kana.cmp(&b.title_kana))
                    .then(l.cmp(&r))
            });
        }
        SongListSort::PerformanceCount => {
            indexes.sort_by(|&l, &r| {
                let (ca, cb) = (
                    snap.performance_counts[l as usize],
                    snap.performance_counts[r as usize],
                );
                cmp_dir(&ca, &cb, asc).then_with(|| kana_tiebreak(snap, l, r))
            });
        }
        SongListSort::CollectedCount => {
            let counts =
                collected_counts_by_song(snap, attended_show_ids, attended_event_ids, false);
            indexes.sort_by(|&l, &r| {
                cmp_dir(&counts[l as usize], &counts[r as usize], asc)
                    .then_with(|| kana_tiebreak(snap, l, r))
            });
        }
        SongListSort::CollectedRate => {
            let attended =
                collected_counts_by_song(snap, attended_show_ids, attended_event_ids, false);
            // 回収率 = 回収数 / 披露数 (披露 0 回は 0 扱い)。iOS と同じ Double (f64) 演算。
            let rate = |i: u32| {
                let total = snap.performance_counts[i as usize];
                if total > 0 {
                    f64::from(attended[i as usize]) / f64::from(total)
                } else {
                    0.0
                }
            };
            indexes.sort_by(|&l, &r| {
                let (ra, rb) = (rate(l), rate(r));
                if ra != rb {
                    let ord = ra.partial_cmp(&rb).expect("回収率は有限値のみ");
                    return if asc { ord } else { ord.reverse() };
                }
                // 同率なら回収数そのもの → 50 音 (iOS は回収数までで打ち切り・以降未規定)。
                cmp_dir(&attended[l as usize], &attended[r as usize], asc)
                    .then_with(|| kana_tiebreak(snap, l, r))
            });
        }
    }
    indexes
}

// ---- criterion 系一覧 (cd_series / series_group / リリース年 / id 集合) ----

/// (release_date ASC, title_kana ASC, 添字) の整列。criterion 系 3 種の共通 ORDER BY
/// (`ORDER BY release_date, title_kana`。ASC の NULL は先頭)。
fn sort_by_release_then_kana(snap: &Snapshot, mut indexes: Vec<u32>) -> Vec<u32> {
    indexes.sort_by(|&l, &r| {
        let (a, b) = (&snap.songs[l as usize], &snap.songs[r as usize]);
        a.release_date
            .cmp(&b.release_date)
            .then_with(|| a.title_kana.cmp(&b.title_kana))
            .then(l.cmp(&r))
    });
    indexes
}

/// CD シリーズ名の完全一致で引く (iOS `songsByCdSeriesQuery`)。
pub fn songs_by_cd_series(snap: &Snapshot, series: &str) -> Vec<u32> {
    let indexes = (0..snap.songs.len() as u32)
        .filter(|&i| snap.songs[i as usize].cd_series.as_deref() == Some(series))
        .collect();
    sort_by_release_then_kana(snap, indexes)
}

/// シリーズ (series_group) の完全一致で引く (iOS `songsBySeriesGroupQuery`)。
pub fn songs_by_series_group(snap: &Snapshot, name: &str) -> Vec<u32> {
    let indexes = (0..snap.songs.len() as u32)
        .filter(|&i| snap.songs[i as usize].series_group.as_deref() == Some(name))
        .collect();
    sort_by_release_then_kana(snap, indexes)
}

/// リリース年 (release_date の前方一致 'YYYY%') で引く (iOS `songsByReleaseYearQuery`)。
pub fn songs_by_release_year(snap: &Snapshot, year: &str) -> Vec<u32> {
    let indexes = (0..snap.songs.len() as u32)
        .filter(|&i| {
            snap.songs[i as usize]
                .release_date
                .as_deref()
                .is_some_and(|d| like_prefix(d, year))
        })
        .collect();
    sort_by_release_then_kana(snap, indexes)
}

/// リリース日の範囲で引く (`from` <= release_date <= `to`・どちらも省略可)。
///
/// [`songs_by_release_year`] は 1 年ちょうどしか取れないので、「2020 年以降」
/// 「2023〜2024 年」のような問いに答えられない。境界は **文字列の前方比較**で見る:
/// release_date は `YYYY-MM-DD` 固定なので辞書順がそのまま日付順になり、
/// `"2024"` / `"2024-05"` のような粗い境界もそのまま「その年/その月ぜんぶ」を含む
/// (日付側を境界の長さに切ってから比べる)。
///
/// release_date を持たない曲は範囲に入れようがないので必ず落とす
/// (「未定」を「古い」とも「新しい」とも読ませない)。
/// 並びは criterion 系と同じ (release_date ASC, title_kana ASC)。
pub fn songs_in_release_range(snap: &Snapshot, from: Option<&str>, to: Option<&str>) -> Vec<u32> {
    let indexes = (0..snap.songs.len() as u32)
        .filter(|&i| {
            let Some(date) = snap.songs[i as usize].release_date.as_deref() else { return false };
            from.is_none_or(|b| bound_cmp(date, b) != Ordering::Less)
                && to.is_none_or(|b| bound_cmp(date, b) != Ordering::Greater)
        })
        .collect();
    sort_by_release_then_kana(snap, indexes)
}

/// 日付を境界の粒度へ切ってから比べる (`"2024-05-01"` を `"2024"` と比べると等しい)。
fn bound_cmp(date: &str, bound: &str) -> Ordering {
    let n = bound.len().min(date.len());
    date[..n].cmp(&bound[..n])
}

/// 任意の id 集合を 50 音順に並べて引く (iOS `songsByIdsOrderedQuery`)。
/// SQL の `IN` と同じく、重複 id は 1 回・未知 id は無視。
pub fn songs_by_ids_ordered(snap: &Snapshot, ids: &[String]) -> Vec<u32> {
    let unique: HashSet<u32> = ids
        .iter()
        .filter_map(|id| snap.song_index_by_id.get(id).copied())
        .collect();
    let mut indexes: Vec<u32> = unique.into_iter().collect();
    // ORDER BY title_kana, title (ASC の NULL は先頭)。
    indexes.sort_by(|&l, &r| kana_tiebreak(snap, l, r));
    indexes
}

// ---- 一覧バッジ用集計 (披露回数・現地回収数) ----

/// song_id → 全公演での披露回数 (iOS `totalSongPerformanceCountMap`)。
/// SQL の `GROUP BY song_id` と同じく、披露 0 回の曲はマップに載せない。
pub fn performance_count_map(snap: &Snapshot) -> HashMap<String, u32> {
    snap.songs
        .iter()
        .zip(&snap.performance_counts)
        .filter(|&(_, &count)| count > 0)
        .map(|(song, &count)| (song.id.clone(), count))
        .collect()
}

/// 参加済み show/event の id 集合から、曲ごとの回収数 (= 参加した公演のうちその曲が
/// 披露された公演の異なり数) を songs と同じ添字で返す。
///
/// - `attended_show_ids`: show 単位の参加マークの entity_id (未知 id は無視)。
/// - `attended_event_ids`: event 単位の参加マーク。配下の全 show を参加扱いに展開する
///   (shows は master データなので展開は共有コア側の仕事)。
/// - `real_live_only`: 回収バッジは event.kind が live/festival の「リアルライブ」だけを
///   数える (iOS `fetchSongCollectedCountsQuery`)。一覧の並び替え (`attendedSongCountMap`)
///   は kind を絞らないので false を渡す — この非対称は iOS の現行挙動の忠実な再現。
pub fn collected_counts_by_song(
    snap: &Snapshot,
    attended_show_ids: &[String],
    attended_event_ids: &[String],
    real_live_only: bool,
) -> Vec<u32> {
    // 「参加した公演」と「回収の対象になる催し」の定義は collection_gap が正本
    // (セトリの「初回収 / 未回収」と一覧の回収バッジが違う数を言わないように)。
    let attended = attended_real_live_shows(snap, attended_show_ids, attended_event_ids, real_live_only);

    let mut counts = vec![0u32; snap.songs.len()];
    let mut seen: HashSet<u32> = HashSet::new();
    // 回収 (real_live_only) は披露に数える行だけ。並び替え用は iOS の現行どおり何も絞らない。
    let by_song =
        if real_live_only { &snap.setlist_items_by_song } else { &snap.all_setlist_items_by_song };
    for (song, items) in by_song.iter().enumerate() {
        seen.clear();
        for &item in items {
            let show = snap.setlist_items[item as usize].show;
            if !attended.contains(&show) {
                continue;
            }
            // COUNT(DISTINCT show_id): 同一公演でのアンコール再披露は 1 回。
            seen.insert(show);
        }
        counts[song] = seen.len() as u32;
    }
    counts
}

/// song_id → 回収数のマップ (0 回の曲は載せない = SQL の GROUP BY 出力と同じ)。
pub fn collected_count_map(
    snap: &Snapshot,
    attended_show_ids: &[String],
    attended_event_ids: &[String],
    real_live_only: bool,
) -> HashMap<String, u32> {
    collected_counts_by_song(snap, attended_show_ids, attended_event_ids, real_live_only)
        .into_iter()
        .enumerate()
        .filter(|&(_, count)| count > 0)
        .map(|(i, count)| (snap.songs[i].id.clone(), count))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{bundle_conn, bundle_path, bundle_snapshot};
    use crate::domain::event_list_queries::AttendanceMarkRecord;
    use rusqlite::Connection;

    /// 空白だけの検索語は、絞り込みなしと同じ (non_empty は前後の空白を落とす。Q-07)。
    #[test]
    fn blank_text_filters_are_ignored() {
        let snap = crate::test_support::bundle_snapshot();
        let all = filter_song_indexes(snap, &SongListFilter::default());
        let blank = SongListFilter {
            title: Some("  ".into()),
            songwriter: Some("\u{3000}".into()),
            live_name: Some(" ".into()),
            ..SongListFilter::default()
        };
        assert_eq!(filter_song_indexes(snap, &blank), all);
    }

    /// Swift `String.likeEscaped` の写経 (テスト側で元 SQL を組むのに使う)。
    fn like_escaped(s: &str) -> String {
        s.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
    }

    fn ids_of(indexes: &[u32]) -> Vec<String> {
        indexes.iter().map(|&i| bundle_snapshot().songs[i as usize].id.clone()).collect()
    }

    /// ORDER BY キーが同値の区間を集合として比較する等価判定。
    ///
    /// SQLite のソータは安定ではなく、キーが完全に同値の行の並びは実行計画依存で
    /// 未規定 (実測でも brand 絞りの有無で入れ替わる)。共有コアは添字/名前を最終キーに
    /// して決定的に並べるため、「キー列が一致し、同値区間のメンバーが一致」を等価とみなす。
    fn assert_matches_up_to_ties<T, K>(label: &str, actual: &[T], expected: &[T], key: impl Fn(&T) -> K)
    where
        T: std::hash::Hash + Eq + std::fmt::Debug,
        K: PartialEq + std::fmt::Debug,
    {
        assert_eq!(actual.len(), expected.len(), "{label}: 件数");
        let mut start = 0;
        while start < expected.len() {
            let k = key(&expected[start]);
            let mut end = start;
            while end < expected.len() && key(&expected[end]) == k {
                end += 1;
            }
            let expected_group: HashSet<&T> = expected[start..end].iter().collect();
            let actual_group: HashSet<&T> = actual[start..end].iter().collect();
            assert_eq!(actual_group, expected_group, "{label}: キー {k:?} の同順位グループ");
            start = end;
        }
    }

    /// (title_kana, title) — titleKana ソートと ids_ordered の ORDER BY キー。
    fn kana_key(id: &String) -> (Option<String>, String) {
        let song = &bundle_snapshot().songs[bundle_snapshot().song_index_by_id[id] as usize];
        (song.title_kana.clone(), song.title.clone())
    }

    /// (release_date, title_kana) — releaseDate ソートと criterion 系の ORDER BY キー。
    fn release_key(id: &String) -> (Option<String>, Option<String>) {
        let song = &bundle_snapshot().songs[bundle_snapshot().song_index_by_id[id] as usize];
        (song.release_date.clone(), song.title_kana.clone())
    }

    /// iOS `fetchSongsByFilterQuery` の SQL 構築の写経。ORDER BY まで含めて同じ文字列を
    /// 組み立て、rusqlite で直接実行した id 列を返す (これが等価性の基準)。
    fn run_original_filter_sql(
        filter: &SongListFilter,
        sort: SongListSort,
        ascending: Option<bool>,
    ) -> Vec<String> {
        let asc = ascending.unwrap_or(sort.default_ascending());
        let mut conditions: Vec<String> = Vec::new();
        let mut args: Vec<String> = Vec::new();

        if !filter.include_remixes {
            // `is_hidden_variant` を SQL で書くとこの 1 行。
            // iOS / Android のフォールバックもこの形を写すこと。
            conditions.push("(s.parent_song_id IS NULL OR s.has_kamisabi_card = 1)".into());
        }
        if !filter.brand_ids.is_empty() {
            let ph = vec!["?"; filter.brand_ids.len()].join(",");
            // 合同曲はカンマ区切りの joint_brand_ids 側でも当たる (本体の
            // `Song::belongs_to_brand` と同じ規則を SQL でも書く)。
            let joint = filter
                .brand_ids
                .iter()
                .map(|_| "(',' || COALESCE(s.joint_brand_ids, '') || ',') LIKE ?")
                .collect::<Vec<_>>()
                .join(" OR ");
            conditions.push(format!("(s.brand_id IN ({ph}) OR {joint})"));
            args.extend(filter.brand_ids.iter().cloned());
            args.extend(filter.brand_ids.iter().map(|b| format!("%,{b},%")));
        } else if !filter.include_other_brand {
            conditions.push("s.brand_id IS NOT 'other'".into());
        }
        if filter.exclude_live_only {
            conditions.push(
                "(
                    (s.apple_music_id IS NOT NULL AND s.apple_music_id <> '')
                    OR (s.release_date IS NOT NULL AND s.release_date <> '')
                    OR (s.cd_title IS NOT NULL AND s.cd_title <> '')
                    OR (s.cd_series IS NOT NULL AND s.cd_series <> '')
                    OR (s.composer IS NOT NULL AND s.composer <> '')
                    OR (s.lyricist IS NOT NULL AND s.lyricist <> '')
                    OR (s.arranger IS NOT NULL AND s.arranger <> '')
                    OR EXISTS (SELECT 1 FROM song_artists sa WHERE sa.song_id = s.id)
                )"
                .into(),
            );
        }
        if let Some(title) = non_empty(&filter.title) {
            conditions.push("(s.title LIKE ? ESCAPE '\\' OR s.title_kana LIKE ? ESCAPE '\\')".into());
            args.push(format!("%{}%", like_escaped(title)));
            args.push(format!("%{}%", like_escaped(title)));
        }
        if let Some(w) = non_empty(&filter.songwriter) {
            conditions.push(
                "(s.composer LIKE ? ESCAPE '\\' OR s.lyricist LIKE ? ESCAPE '\\' OR s.arranger LIKE ? ESCAPE '\\')".into(),
            );
            for _ in 0..3 {
                args.push(format!("%{}%", like_escaped(w)));
            }
        }
        if let Some(cd) = non_empty(&filter.cd_series) {
            conditions.push("s.cd_series LIKE ? ESCAPE '\\'".into());
            args.push(format!("%{}%", like_escaped(cd)));
        }
        if let Some(g) = non_empty(&filter.series_group) {
            conditions.push("s.series_group = ?".into());
            args.push(g.to_string());
        }
        if let Some(t) = filter.song_type.as_deref() {
            conditions.push("s.song_type = ?".into());
            args.push(t.to_string());
        }

        let has_idol_ids = !filter.idol_ids.is_empty();
        let has_idol_name = non_empty(&filter.idol_name).is_some();
        let mut sql = "SELECT DISTINCT s.* FROM songs s".to_string();
        if has_idol_ids || has_idol_name {
            sql += " JOIN song_artists sa ON s.id = sa.song_id AND sa.role = 'original'";
            sql += " JOIN idols i ON sa.idol_id = i.id";
            if has_idol_ids {
                let ph = vec!["?"; filter.idol_ids.len()].join(",");
                conditions.push(format!("sa.idol_id IN ({ph})"));
                args.extend(filter.idol_ids.iter().cloned());
            } else if let Some(name) = non_empty(&filter.idol_name) {
                conditions.push("(i.name LIKE ? ESCAPE '\\' OR i.name_kana LIKE ? ESCAPE '\\')".into());
                args.push(format!("%{}%", like_escaped(name)));
                args.push(format!("%{}%", like_escaped(name)));
            }
        }
        if let Some(live) = non_empty(&filter.live_name) {
            sql += " JOIN setlist_items si ON s.id = si.song_id JOIN shows sh ON si.show_id = sh.id JOIN events ev ON sh.event_id = ev.id";
            conditions.push("ev.name LIKE ? ESCAPE '\\'".into());
            args.push(format!("%{}%", like_escaped(live)));
        }
        if !conditions.is_empty() {
            sql += &format!(" WHERE {}", conditions.join(" AND "));
        }
        let dir = if asc { "ASC" } else { "DESC" };
        match sort {
            SongListSort::TitleKana => {
                sql += &format!(" ORDER BY s.title_kana {dir}, s.title {dir}");
            }
            SongListSort::ReleaseDate => {
                sql += &format!(" ORDER BY s.release_date {dir}, s.title_kana");
            }
            _ => {}
        }

        let db = bundle_conn();
        let mut stmt = db.prepare(&sql).expect("元 SQL は妥当");
        let rows = stmt
            .query_map(rusqlite::params_from_iter(args.iter()), |r| r.get::<_, String>("id"))
            .expect("元 SQL を実行できる");
        rows.collect::<Result<Vec<_>, _>>().expect("行を読める")
    }

    fn browse_filter() -> SongListFilter {
        // 楽曲一覧ブラウズの既定: 派生・other ブランド・ファントム曲を隠す。
        SongListFilter {
            include_other_brand: false,
            exclude_live_only: true,
            ..SongListFilter::default()
        }
    }

    /// KAMISABI 軸は列を見るだけで、曲の他の属性からは推測しない。
    #[test]
    fn kamisabi_only_keeps_exactly_the_flagged_songs() {
        use crate::domain::snapshot::Song;
        let song = |id: &str, flagged: bool| Song {
            id: id.into(),
            title: id.into(),
            has_kamisabi_card: flagged,
            ..Song::default()
        };
        // 派生曲 (別バージョン) にもカードは付く。
        let variant = Song {
            id: "s4".into(),
            title: "s4".into(),
            parent_song_id: Some("s1".into()),
            has_kamisabi_card: true,
            ..Song::default()
        };
        let mini = Snapshot {
            songs: vec![song("s1", true), song("s2", false), song("s3", true), variant],
            ..Snapshot::default()
        };

        // 収録 = 3 曲。派生の s4 も落とさない (落とすとコンプの分母が実物と合わない)。
        let on = SongListFilter { kamisabi_only: true, ..SongListFilter::default() };
        assert_eq!(filter_song_indexes(&mini, &on), vec![0, 2, 3]);

        // 既定でも同じ 4 件。**カードが付いた派生曲は軸に関係なく隠さない**
        // (「KAMISABI で絞っているときだけ隠さない」という軸の絡みにすると、
        // 同じ絡みを各 OS の SQL に写す羽目になる)。
        let off = SongListFilter::default();
        assert_eq!(filter_song_indexes(&mini, &off), vec![0, 1, 2, 3]);
    }

    /// 派生曲を隠す規則は「その曲自体が商品として立っているか」で決まる。
    #[test]
    fn hidden_variant_keeps_derived_songs_that_have_a_card() {
        use crate::domain::snapshot::Song;
        let derived = |card: bool| Song {
            parent_song_id: Some("parent".into()),
            has_kamisabi_card: card,
            ..Song::default()
        };
        assert!(is_hidden_variant(&derived(false)));
        assert!(!is_hidden_variant(&derived(true)));
        // 空文字は NULL ではないので派生扱いのまま (元 SQL と同じ)。
        assert!(is_hidden_variant(&Song { parent_song_id: Some(String::new()), ..Song::default() }));
        assert!(!is_hidden_variant(&Song::default()));
    }

    /// 回帰 (2026-08-28): 作家の読みで曲を引けなかった。
    ///
    /// `creators` に「烏屋茶房 = からすやさぼう」は入っていたのに、クレジット欄の
    /// 生文字列しか見ていなかったので「からすやさぼう」で 0 件になっていた。
    /// **ここは元 SQL と意図的に振る舞いが違う** (SQL は読みを知らない)。
    #[test]
    fn songwriter_filter_matches_the_creator_reading() {
        let by_name = |q: &str| {
            let filter = SongListFilter { songwriter: Some(q.into()), ..browse_filter() };
            song_list_indexes(bundle_snapshot(), &filter, SongListSort::TitleKana, None, &[], &[]).len()
        };
        let kanji = by_name("烏屋茶房");
        assert!(kanji > 0, "表記で引けない時点でこのテストは無意味");
        // 読みでも同じ集合が出る。
        assert_eq!(by_name("からすやさぼう"), kanji);
        // 部分一致でも当たる (打鍵の途中で 0 件にならない)。
        assert!(by_name("からすや") >= kanji);
    }

    /// 別表記でも同じ人に当たる。
    ///
    /// 同じ作家が「滝澤俊輔(TRYTONELABO)」「滝澤俊輔［TRYTONELABO］」のように
    /// 複数の書き方で欄に出るので、綴り列には aliases も入れてある。
    #[test]
    fn songwriter_filter_matches_through_aliases() {
        let by_name = |q: &str| {
            let filter = SongListFilter { songwriter: Some(q.into()), ..browse_filter() };
            song_list_indexes(bundle_snapshot(), &filter, SongListSort::TitleKana, None, &[], &[]).len()
        };
        assert!(by_name("たきざわしゅんすけ") > 0);
    }

    // ---- 照合テスト (元 SQL との等価性保証) ----

    #[test]
    fn browse_default_matches_sql_both_directions() {
        let filter = browse_filter();
        for asc in [None, Some(true), Some(false)] {
            let expected = run_original_filter_sql(&filter, SongListSort::TitleKana, asc);
            let actual = ids_of(&song_list_indexes(bundle_snapshot(), &filter, SongListSort::TitleKana, asc, &[], &[]));
            assert!(!expected.is_empty());
            assert_matches_up_to_ties(&format!("titleKana asc={asc:?}"), &actual, &expected, kana_key);
        }
    }

    #[test]
    fn brand_type_remix_matches_sql_release_order() {
        // 複数ブランド + 曲種 + リミックス込み、リリース日順 (昇降両方)。
        let filter = SongListFilter {
            brand_ids: vec!["cg".into(), "ml".into()],
            song_type: Some("unit".into()),
            include_remixes: true,
            include_other_brand: true,
            ..SongListFilter::default()
        };
        for asc in [Some(false), Some(true)] {
            let expected = run_original_filter_sql(&filter, SongListSort::ReleaseDate, asc);
            let actual = ids_of(&song_list_indexes(bundle_snapshot(), &filter, SongListSort::ReleaseDate, asc, &[], &[]));
            assert!(!expected.is_empty());
            assert_matches_up_to_ties(&format!("releaseDate asc={asc:?}"), &actual, &expected, release_key);
        }
    }

    #[test]
    fn search_terms_match_sql() {
        // 検索語 5 系統 (曲名 [ASCII 大小無視]・作家・CD シリーズ・シリーズ・ライブ名)。
        let cases = [
            SongListFilter { title: Some("star".into()), ..browse_filter() },
            SongListFilter { title: Some("STAR".into()), ..browse_filter() },
            SongListFilter { songwriter: Some("俊".into()), ..browse_filter() },
            SongListFilter { cd_series: Some("MASTER".into()), ..browse_filter() },
            SongListFilter { series_group: Some("LIVE THE@TER HARMONY".into()), ..browse_filter() },
            SongListFilter { live_name: Some("感謝祭".into()), ..SongListFilter { include_other_brand: true, ..SongListFilter::default() } },
        ];
        for (n, filter) in cases.iter().enumerate() {
            let expected = run_original_filter_sql(filter, SongListSort::TitleKana, None);
            let actual = ids_of(&song_list_indexes(bundle_snapshot(), filter, SongListSort::TitleKana, None, &[], &[]));
            assert!(!expected.is_empty(), "case {n} は 1 件以上ヒットする前提");
            assert_matches_up_to_ties(&format!("case {n}"), &actual, &expected, kana_key);
        }
        // ASCII 大小無視の LIKE が実際に混在ヒットしている (全部大文字/小文字だけなら退化)。
        let star = run_original_filter_sql(&cases[0], SongListSort::TitleKana, None);
        let upper = run_original_filter_sql(&cases[1], SongListSort::TitleKana, None);
        assert_eq!(star, upper, "LIKE は大文字小文字を無視するので同一結果のはず");
    }

    #[test]
    fn idol_filters_match_sql() {
        let by_ids = SongListFilter {
            idol_ids: vec!["765as_天海春香".into(), "cg_双葉杏".into()],
            ..browse_filter()
        };
        let by_name = SongListFilter { idol_name: Some("春香".into()), ..browse_filter() };
        // 名前と id 両指定は id が勝つ (iOS の else-if)。
        let both = SongListFilter {
            idol_ids: vec!["cg_双葉杏".into()],
            idol_name: Some("春香".into()),
            ..browse_filter()
        };
        for (n, filter) in [&by_ids, &by_name, &both].into_iter().enumerate() {
            let expected = run_original_filter_sql(filter, SongListSort::TitleKana, None);
            let actual = ids_of(&song_list_indexes(bundle_snapshot(), filter, SongListSort::TitleKana, None, &[], &[]));
            assert!(!expected.is_empty(), "case {n} は 1 件以上ヒットする前提");
            assert_matches_up_to_ties(&format!("case {n}"), &actual, &expected, kana_key);
        }
    }

    #[test]
    fn criterion_lists_match_sql() {
        let db = bundle_conn();
        let run = |sql: &str, params: &[&str]| -> Vec<String> {
            let mut stmt = db.prepare(sql).unwrap();
            stmt.query_map(rusqlite::params_from_iter(params.iter()), |r| r.get::<_, String>(0))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap()
        };
        // 実データから曲数の多い cd_series を 1 つ選ぶ (テストをデータ更新に強くする)。
        let cd: String = db
            .query_row(
                "SELECT cd_series FROM songs WHERE cd_series IS NOT NULL AND cd_series<>''
                 GROUP BY cd_series HAVING COUNT(*) >= 5 ORDER BY cd_series LIMIT 1",
                [],
                |r| r.get(0),
            )
            .unwrap();

        let expected = run("SELECT id FROM songs WHERE cd_series = ? ORDER BY release_date, title_kana", &[&cd]);
        assert!(!expected.is_empty());
        assert_matches_up_to_ties("cd_series", &ids_of(&songs_by_cd_series(bundle_snapshot(), &cd)), &expected, release_key);

        let expected = run(
            "SELECT id FROM songs WHERE series_group = ? ORDER BY release_date, title_kana",
            &["LIVE THE@TER HARMONY"],
        );
        assert!(!expected.is_empty());
        assert_matches_up_to_ties(
            "series_group",
            &ids_of(&songs_by_series_group(bundle_snapshot(), "LIVE THE@TER HARMONY")),
            &expected,
            release_key,
        );

        let expected = run("SELECT id FROM songs WHERE release_date LIKE '2015%' ORDER BY release_date, title_kana", &[]);
        assert!(!expected.is_empty());
        assert_matches_up_to_ties(
            "release_year",
            &ids_of(&songs_by_release_year(bundle_snapshot(), "2015")),
            &expected,
            release_key,
        );

        // id 集合: 実在 8 件 + 重複 + 未知 id。IN と同じく重複 1 回・未知は無視。
        let mut ids = run("SELECT id FROM songs ORDER BY id LIMIT 8", &[]);
        ids.push(ids[0].clone());
        ids.push("存在しないid".into());
        let ph = vec!["?"; ids.len()].join(",");
        let expected = run(
            &format!("SELECT id FROM songs WHERE id IN ({ph}) ORDER BY title_kana, title"),
            &ids.iter().map(String::as_str).collect::<Vec<_>>(),
        );
        assert_eq!(expected.len(), 8);
        assert_matches_up_to_ties("ids_ordered", &ids_of(&songs_by_ids_ordered(bundle_snapshot(), &ids)), &expected, kana_key);
    }

    #[test]
    fn performance_count_map_matches_sql() {
        let db = bundle_conn();
        let mut stmt = db
            .prepare(
                "SELECT si.song_id, COUNT(*) FROM setlist_items si JOIN shows sh ON sh.id = si.show_id
                 WHERE COALESCE(sh.performer_type, '') <> 'screening'
                   AND COALESCE(sh.venue_mode, '') <> 'online' GROUP BY si.song_id",
            )
            .unwrap();
        let expected: HashMap<String, u32> = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, u32>(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert!(expected.len() > 500);
        assert_eq!(performance_count_map(bundle_snapshot()), expected);
    }

    /// user_marks は bundle DB に無いので、メモリ DB に作って master を ATTACH し、
    /// 元 SQL (未修飾テーブル名が main → attached の順で解決される) をそのまま流す。
    fn marks_db() -> Connection {
        let db = Connection::open_in_memory().unwrap();
        db.execute("ATTACH DATABASE ?1 AS m", [bundle_path()]).unwrap();
        db.execute_batch(
            "CREATE TABLE user_marks (
                id INTEGER PRIMARY KEY, entity_type TEXT, entity_id TEXT,
                kind TEXT, bool_value INTEGER, text_value TEXT)",
        )
        .unwrap();

        // フィクスチャ: リアルライブ 5 公演 (現地 2 + 配信 1 + 現地と配信 1 + 配信と LV 1)・非リアルライブ 1 公演・
        // event 単位参加 1 件・bool_value=0 の無効マーク・未知 id。すべて実データから選ぶ。
        let pick = |sql: &str, n: usize| -> Vec<String> {
            let mut stmt = db.prepare(sql).unwrap();
            let v: Vec<String> = stmt
                .query_map([], |r| r.get(0))
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap();
            assert!(v.len() >= n, "フィクスチャ抽出 {n} 件未満: {sql}");
            v
        };
        let live_shows = pick(
            "SELECT sh.id FROM shows sh JOIN events e ON e.id = sh.event_id
             WHERE e.kind IN ('live','festival')
               AND EXISTS (SELECT 1 FROM setlist_items si WHERE si.show_id = sh.id)
             ORDER BY sh.id LIMIT 6",
            6,
        );
        let other_shows = pick(
            "SELECT sh.id FROM shows sh JOIN events e ON e.id = sh.event_id
             WHERE e.kind NOT IN ('live','festival')
               AND EXISTS (SELECT 1 FROM setlist_items si WHERE si.show_id = sh.id)
             ORDER BY sh.id LIMIT 1",
            1,
        );
        let events = pick(
            "SELECT e.id FROM events e JOIN shows sh ON sh.event_id = e.id
             WHERE e.kind = 'live'
               AND EXISTS (SELECT 1 FROM setlist_items si WHERE si.show_id = sh.id)
             GROUP BY e.id HAVING COUNT(sh.id) >= 2 ORDER BY e.id LIMIT 1",
            1,
        );

        let insert = |etype: &str, eid: &str, boolv: i64, text: Option<&str>| {
            db.execute(
                "INSERT INTO user_marks (entity_type, entity_id, kind, bool_value, text_value)
                 VALUES (?1, ?2, 'attended', ?3, ?4)",
                rusqlite::params![etype, eid, boolv, text],
            )
            .unwrap();
        };
        insert("show", &live_shows[0], 1, None); // 現地参加
        insert("show", &live_shows[1], 1, Some("live")); // 現地参加 (明示)
        insert("show", &live_shows[2], 1, Some("stream")); // 配信参加 → バッジ既定では除外
        insert("show", &live_shows[3], 0, None); // 取り消し済み → 無効
        insert("show", &live_shows[4], 1, Some("stream,live")); // 現地 + 配信 → 現地として数える
        insert("show", &live_shows[5], 1, Some("stream,live_viewing")); // 現地なし → 既定では除外
        insert("show", &other_shows[0], 1, None); // 非リアルライブ → kind 絞りで除外対象
        insert("show", "存在しないshow", 1, None); // 未知 id は無視される
        insert("event", &events[0], 1, None); // event 単位参加 → 配下 show へ展開
        db
    }

    /// プラットフォーム側の user_marks → id 集合の解決 (Wire 実装がやる SQL の写経)。
    fn resolve_marks(db: &Connection, sql: &str) -> Vec<String> {
        let mut stmt = db.prepare(sql).unwrap();
        stmt.query_map([], |r| r.get(0)).unwrap().collect::<Result<_, _>>().unwrap()
    }

    fn count_map_from_sql(db: &Connection, sql: &str) -> HashMap<String, u32> {
        let mut stmt = db.prepare(sql).unwrap();
        stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, u32>(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap()
    }

    #[test]
    fn collected_badge_counts_match_sql() {
        let db = marks_db();
        // iOS fetchSongCollectedCountsQuery (回収=現地のみ設定) の SQL。参加形態の条件は
        // iOS と同じくコアから受け取る (複数形態 "stream,live" も読む)。
        let cond = crate::domain::collection_gap::collection_attendance_sql_condition(false);
        let expected = count_map_from_sql(
            &db,
            &format!("SELECT si.song_id, COUNT(DISTINCT si.show_id)
             FROM setlist_items si
             JOIN shows sh ON sh.id = si.show_id
             JOIN events e ON e.id = sh.event_id
             WHERE e.kind IN ('live','festival')
             AND COALESCE(sh.performer_type, '') <> 'screening'
             AND COALESCE(sh.venue_mode, '') <> 'online'
             AND (
                 si.show_id IN (
                     SELECT entity_id FROM user_marks
                     WHERE entity_type='show' AND kind='attended' AND bool_value=1
                       AND {cond}
                 ) OR si.show_id IN (
                     SELECT id FROM shows WHERE event_id IN (
                         SELECT entity_id FROM user_marks
                         WHERE entity_type='event' AND kind='attended' AND bool_value=1
                     )
                 )
             )
             GROUP BY si.song_id"),
        );
        // Rust 経路 (collection_attended_show_ids) で選んだ show が SQL と同じ件数を出す。
        let marks: Vec<AttendanceMarkRecord> = {
            let mut stmt = db
                .prepare("SELECT entity_id, text_value FROM user_marks WHERE entity_type='show' AND kind='attended' AND bool_value=1")
                .unwrap();
            stmt.query_map([], |r| Ok(AttendanceMarkRecord { entity_id: r.get(0)?, attendance_type: r.get(1)? }))
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap()
        };
        let show_ids = crate::domain::collection_gap::collection_attended_show_ids(marks, false);
        let event_ids = resolve_marks(
            &db,
            "SELECT entity_id FROM user_marks
             WHERE entity_type='event' AND kind='attended' AND bool_value=1",
        );
        assert!(!expected.is_empty());
        assert_eq!(collected_count_map(bundle_snapshot(), &show_ids, &event_ids, true), expected);
    }

    #[test]
    fn collected_sort_counts_match_sql() {
        let db = marks_db();
        // iOS attendedSongCountMap (並び替え用) の SQL そのまま。kind も参加種別も絞らない。
        let expected = count_map_from_sql(
            &db,
            "SELECT si.song_id, COUNT(DISTINCT si.show_id)
             FROM setlist_items si
             WHERE si.show_id IN (
                 SELECT entity_id FROM user_marks
                 WHERE entity_type='show' AND kind='attended' AND bool_value=1
             ) OR si.show_id IN (
                 SELECT id FROM shows
                 WHERE event_id IN (
                     SELECT entity_id FROM user_marks
                     WHERE entity_type='event' AND kind='attended' AND bool_value=1
                 )
             )
             GROUP BY si.song_id",
        );
        let show_ids = resolve_marks(
            &db,
            "SELECT entity_id FROM user_marks
             WHERE entity_type='show' AND kind='attended' AND bool_value=1",
        );
        let event_ids = resolve_marks(
            &db,
            "SELECT entity_id FROM user_marks
             WHERE entity_type='event' AND kind='attended' AND bool_value=1",
        );
        assert!(!expected.is_empty());
        let actual = collected_count_map(bundle_snapshot(), &show_ids, &event_ids, false);
        assert_eq!(actual, expected);
        // 配信参加や非リアルライブ公演も数える (バッジ側との差分が実際に出ていること)。
        let badge = collected_count_map(bundle_snapshot(), &show_ids, &event_ids, true);
        assert!(actual.values().sum::<u32>() > badge.values().sum::<u32>());
    }

    #[test]
    fn numeric_sorts_are_ordered_and_set_equal_to_sql() {
        // 数値系ソートは元実装が「SQL 素通し順 + Swift 不安定ソート」で同数の並びが
        // 未規定だったため、列そのものではなく (a) 集合の一致 (b) キーの単調性 (c) 同数内
        // 50 音の自前規則を検証する。
        let filter = browse_filter();
        let expected_set: HashSet<String> =
            run_original_filter_sql(&filter, SongListSort::PerformanceCount, None).into_iter().collect();

        let db = marks_db();
        let show_ids = resolve_marks(
            &db,
            "SELECT entity_id FROM user_marks
             WHERE entity_type='show' AND kind='attended' AND bool_value=1",
        );
        let event_ids = resolve_marks(
            &db,
            "SELECT entity_id FROM user_marks
             WHERE entity_type='event' AND kind='attended' AND bool_value=1",
        );
        let attended = collected_counts_by_song(bundle_snapshot(), &show_ids, &event_ids, false);

        for sort in [SongListSort::PerformanceCount, SongListSort::CollectedCount, SongListSort::CollectedRate] {
            let indexes = song_list_indexes(bundle_snapshot(), &filter, sort, None, &show_ids, &event_ids);
            let actual_set: HashSet<String> = ids_of(&indexes).into_iter().collect();
            assert_eq!(actual_set, expected_set, "{sort:?}: 絞り込み結果の集合は SQL と一致");

            let key = |i: u32| -> f64 {
                match sort {
                    SongListSort::PerformanceCount => f64::from(bundle_snapshot().performance_counts[i as usize]),
                    SongListSort::CollectedCount => f64::from(attended[i as usize]),
                    SongListSort::CollectedRate => {
                        let total = bundle_snapshot().performance_counts[i as usize];
                        if total > 0 { f64::from(attended[i as usize]) / f64::from(total) } else { 0.0 }
                    }
                    _ => unreachable!(),
                }
            };
            // 既定は降順 (多い順)。
            for pair in indexes.windows(2) {
                assert!(key(pair[0]) >= key(pair[1]), "{sort:?}: キーが単調でない");
            }
        }

        // 同数グループ内は 50 音 (決定性規約)。披露回数順の先頭グループで確認。
        let indexes = song_list_indexes(bundle_snapshot(), &filter, SongListSort::PerformanceCount, None, &[], &[]);
        let top = bundle_snapshot().performance_counts[indexes[0] as usize];
        let group: Vec<u32> = indexes
            .iter()
            .copied()
            .take_while(|&i| bundle_snapshot().performance_counts[i as usize] == top)
            .collect();
        for pair in group.windows(2) {
            assert_ne!(kana_tiebreak(bundle_snapshot(), pair[0], pair[1]), Ordering::Greater);
        }
    }

    // ---- 単体 (SQL 非依存の境界ケース) ----

    /// 絞り込みの当たり方。SQL の `LIKE` より**広い** (一覧の索引と同じ規則)。
    #[test]
    fn search_folds_case_and_kana() {
        let hit = |h: &str, n: &str| FoldedNeedle::new(n).matches(h);
        assert!(hit("READY!!", "ready"));
        assert!(hit("お願い！シンデレラ", "シンデレラ"));
        // ひらがな↔カタカナを畳む。SQL 忠実だった頃はここが当たらず、同じ語が
        // iOS の一覧 (TextSearchCatalog) では当たっていた。
        assert!(hit("お願い！シンデレラ", "しんでれら"));
        // 大小無視は非 ASCII にも及ぶ (畳み込みは `char::to_lowercase` を通す)。
        assert!(hit("ＳＴＡＲ", "ｓｔａｒ"));
        // 多バイト文字の部分一致は文字境界どおりに効く。
        assert!(hit("アイドルマスター", "ドルマ"));
        assert!(!hit("アイドル", "アイド ル"));
        // 全角半角は畳まない (`ＳＴＡＲ` は半角 `star` では引けない)。
        assert!(!hit("ＳＴＡＲ", "star"));
        // 年フィルタの前方一致は SQL の LIKE 'x%' のまま (検索欄ではないので畳まない)。
        assert!(like_prefix("2015-04-15", "2015"));
        assert!(!like_prefix("2015-04-15", "2016"));
    }
}
