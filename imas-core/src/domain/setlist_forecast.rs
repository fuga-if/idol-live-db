//! セトリの**機械予測** (公演 1 つについて、歌われそうな曲を点数つきで並べる)。
//!
//! # 仕組み
//!
//! 過去のリアルライブ (events.kind が live / festival) で、出演者とセトリが揃った公演を
//! 1 公演 × 候補曲 = 1 行にして、疎な特徴 (0/1) のロジスティック回帰を学習する。
//! 答えは「その曲がその公演のセトリに入ったか」。
//!
//! 特徴の定義は、答え合わせで効きを確かめた Python の試作 (上位 10 曲の当たり率:
//! DAY1 約 37% / DAY2 以降 約 48%。人気順だけだと 17% / 16%) と同じ:
//!
//! - オリメンのそろい方 × 曲の種別 (と、ブランドを掛けたもの)
//! - 1 年あたりの披露イベント数の段 × 最後の披露からの空きの段
//! - 直近 180 日の披露イベント数
//! - 直前のイベント (と、60 日以内ならツアーの前の公演) で歌ったか
//! - 発売 1 年以内 / 120 日以内の未披露曲
//! - 同じ歌唱者の組の最新曲
//! - 出演者ごとのソロ曲の順位
//! - 同じイベントの前の日程で歌ったか
//!
//! # 未来を漏らさない
//!
//! 公演の特徴は、その**イベントの開始日より前**の披露だけから作る
//! (同じイベントの前の日程のセトリだけは例外で、公演日より前なら使う)。
//! 学習に使う公演も「予測するイベントの開始日より前の公演」だけに絞る。
//!
//! # 重さの扱い
//!
//! 公演ごとの特徴の行は、予測する公演 (= 学習の区切り) に依らない。そこで
//! [`ForecastPrep`] がスナップショット 1 世代につき 1 回だけ全公演の行を作り、
//! 同じ特徴の組ごとに (当たり数, 行数) へ畳んでおく。学習は区切りより前の公演の
//! 組を足し合わせて回すだけなので、数万の組 × 固定回数で済む。
//! 区切りが同じ (= 区切りより前の学習公演の数が同じ) なら重みも同じなので、
//! 呼び出し側は [`ForecastPrep::training_prefix`] の値で重みをキャッシュできる。
//! 未来の公演はどれも「今ある全データ」で学習した同じ重みを使うことになる。
//!
//! 特徴と組の番号は、学習公演を日付順に見て**初めて出た順**に振る。こうすると
//! 区切りより後の公演が増えても減っても、区切りより前で使う番号と足し算の順が
//! 変わらず、重みがビット単位で一致する (未来を漏らさないことのテストの前提)。

use std::collections::HashMap;

use chrono::{Datelike, NaiveDate};

use crate::domain::collection_gap::REAL_LIVE_KINDS;
use crate::domain::snapshot::Snapshot;

// ---- 学習の定数 (乱数は使わない。変えると当たり率が変わるので、答え合わせを流し直すこと) ----

/// 勾配降下の反復回数。
pub const TRAINING_ITERATIONS: usize = 300;
/// 重みの学習率。
pub const WEIGHT_LEARNING_RATE: f64 = 5.0;
/// 切片の学習率。
pub const BIAS_LEARNING_RATE: f64 = 0.5;
/// L2 正則化の強さ。
pub const L2_PENALTY: f64 = 1e-4;
/// これより前の公演は学習に使わない (出演者の登録が薄く、今のライブの作りとも違う)。
pub const TRAINING_FROM: &str = "2015-01-01";

/// ツアーの前の公演とみなす、前のイベントの開始日からの日数。
const TOUR_WINDOW_DAYS: i32 = 60;
/// 「直近」の披露を数える日数。
const RECENT_WINDOW_DAYS: i32 = 180;
/// ユニットの持ち歌のうち「定番」とみなす、最多の披露イベント数に対する割合。
const UNIT_STAPLE_RATIO: f64 = 0.7;

// ---- 表示に出すもの ----

/// 予想の理由。並びは表示の優先順。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum ForecastReason {
    /// 同じイベントの前日の公演で歌った。
    SungPreviousDay,
    /// 同じイベントの前の日程 (前日ではない) で歌った。
    SungEarlierInEvent,
    /// 原唱者が全員出演する。
    FullOriginalCast,
    /// 発売から 1 年以内で、まだライブで歌われていない。
    NewUnperformed,
    /// 直前のライブ (ツアーの前の公演を含む) でも歌った。
    SungAtPreviousLive,
    /// 全体曲で、1 年に 1 回以上歌われている。
    AllSongStaple,
    /// 1 年に 1 回以上歌われている (全体曲以外)。
    FrequentlyPerformed,
    /// 同じ歌唱者の組の持ち歌の中で、披露が最多の 7 割以上。
    UnitStaple,
    /// 同じ歌唱者の組の持ち歌の中で、披露がいちばん少ない・2 番目に少ない。
    UnitRarelyPerformed,
    /// 最後の披露から 3 年以上たっている。
    LongAbsence,
}

impl ForecastReason {
    pub fn label(self) -> &'static str {
        match self {
            Self::SungPreviousDay => "前日に歌った",
            Self::SungEarlierInEvent => "この公演の前の日程で歌った",
            Self::FullOriginalCast => "オリメン全員出演",
            Self::NewUnperformed => "未披露の新曲",
            Self::SungAtPreviousLive => "前回のライブでも歌った",
            Self::AllSongStaple => "全体曲の定番",
            Self::FrequentlyPerformed => "よく歌われている",
            Self::UnitStaple => "ユニットの定番",
            Self::UnitRarelyPerformed => "ユニットであまり歌っていない曲",
            Self::LongAbsence => "3年以上歌われていない",
        }
    }
}

/// 公演に付ける印。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ForecastShowFlag {
    /// 出演者が未発表。オリメンのそろい方を使えないので精度が落ちる。
    CastUnannounced,
    /// セトリが既に入っている公演 (予想ではなく答え合わせとして見る)。
    SetlistPublished,
}

impl ForecastShowFlag {
    pub fn label(self) -> &'static str {
        match self {
            Self::CastUnannounced => "出演者未発表のため精度が低い",
            Self::SetlistPublished => "セトリ公開済み (答え合わせ用)",
        }
    }
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ForecastReasonRecord {
    pub reason: ForecastReason,
    pub label: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ForecastShowFlagRecord {
    pub flag: ForecastShowFlag,
    pub label: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ForecastSongRecord {
    /// 1 始まりの順位。
    pub rank: u32,
    pub song_id: String,
    pub title: String,
    /// セトリに入る推定確率 (0〜1)。
    pub score: f64,
    /// 理由 ([`ForecastReason`] の並び順)。空のこともある。
    pub reasons: Vec<ForecastReasonRecord>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct SetlistForecastRecord {
    pub show_id: String,
    /// 点数の高い順。
    pub songs: Vec<ForecastSongRecord>,
    pub flags: Vec<ForecastShowFlagRecord>,
    /// 学習に使った公演の数 (予測する公演のイベントの開始日より前のもの)。
    pub training_show_count: u32,
}

// ---- 特徴 ----

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum SongKind {
    Solo,
    Unit,
    All,
}

impl SongKind {
    fn parse(song_type: Option<&str>) -> Option<Self> {
        match song_type? {
            "solo" => Some(Self::Solo),
            "unit" => Some(Self::Unit),
            "all" => Some(Self::All),
            _ => None,
        }
    }
}

/// 原唱者が出演者にどれだけ含まれるか。
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Lineup {
    Full,
    HalfOrMore,
    Some,
    Absent,
    /// 原唱者の登録が無い曲。
    NoOriginal,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum RateBand {
    Never,
    /// 1 年に 0.3 回未満。
    Rare,
    /// 1 年に 1 回未満。
    Occasional,
    Frequent,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum GapBand {
    Never,
    UnderOneYear,
    UnderThreeYears,
    ThreeYearsOrMore,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Feature {
    LineupKind(Lineup, SongKind),
    RateGap(RateBand, GapBand),
    /// 直近 180 日の披露イベント数 (3 で頭打ち)。
    Recent(u8),
    /// イベントのブランド (`ForecastPrep::event_brand` の番号。None = ブランド無し) × そろい方 × 種別。
    BrandLineupKind(Option<u32>, Lineup, SongKind),
    PreviousEvent(SongKind, bool),
    TourPrevious(SongKind, bool),
    NewWithinYear,
    NewWithin120Days,
    NewestOfSinger(SongKind),
    /// 出演者の中でのソロ曲の順位 (0 始まり、3 で頭打ち)。
    SoloRank(u8),
    SameEventEarlier(SongKind, bool),
}

/// 公演 × 候補曲 1 行ぶんの中身。特徴に加えて、理由の表示に使う値を持つ。
#[derive(Debug)]
struct Row {
    song: u32,
    features: Vec<Feature>,
    /// 過去の披露イベント数 (人気順の比較と、ユニット内の順位に使う)。
    past_events: u32,
    rate: RateBand,
    gap: GapBand,
    kind: SongKind,
    lineup: Option<Lineup>,
    new_within_year: bool,
    sung_previous: bool,
    earlier_in_event: bool,
}

/// 学習に使う公演 1 つ: 特徴の組ごとの (組の番号, 当たり数, 行数)。組の番号順。
#[derive(Debug)]
struct TrainingShow {
    day: i32,
    groups: Vec<(u32, u32, u32)>,
}

/// スナップショット 1 世代ぶんの下ごしらえ。
#[derive(Debug)]
pub struct ForecastPrep {
    /// 曲ごとの暦日 (発売日)。
    release_day: Vec<Option<i32>>,
    /// 候補になり得る曲 (派生でない・種別が solo/unit/all) の種別。
    kind: Vec<Option<SongKind>>,
    /// 曲 (派生の根) ごとの原唱者 (派生曲の原唱者も根に寄せる)。idol 添字の昇順。
    originals: Vec<Vec<u32>>,
    /// 曲 (根) ごとの披露: (公演日, イベント)。日付順。
    history: Vec<Vec<(i32, u32)>>,
    /// `history` と同じ並びで、その位置までに出たイベントの種類数 (位置を含む)。
    history_distinct: Vec<Vec<u32>>,
    show_day: Vec<Option<i32>>,
    /// 公演ごとのセトリ (根の曲添字、昇順・重複なし)。リアルライブ以外は空。
    setlist: Vec<Vec<u32>>,
    /// イベントの開始日 (配下の公演の最も早い日)。
    event_start: Vec<Option<i32>>,
    /// イベントで歌われた曲 (根、昇順)。
    event_songs: Vec<Vec<u32>>,
    /// イベントのブランド (ブランドの文字列に出た順に振った番号。`Feature::BrandLineupKind` に使う)。
    event_brand: Vec<Option<u32>>,
    /// ブランドごとの、セトリのあるリアルライブのイベント: (開始日, イベント)。開始日順。
    brand_events: HashMap<Option<u32>, Vec<(i32, u32)>>,
    /// 曲の brand_id ごとの候補曲 (曲添字の昇順)。
    candidates_by_brand: HashMap<String, Vec<u32>>,
    /// アイドルごとの所属ブランド (idols.brand_id と idol_brands の和)。
    idol_brands: Vec<Vec<String>>,
    /// アイドルごとのソロ曲 (原唱者がその 1 人だけの候補曲)。
    solo_songs: Vec<Vec<u32>>,
    /// 歌唱者の組 (原唱者の集合) ごとの持ち歌。組の番号は `singer_group` が指す。
    singer_groups: Vec<Vec<u32>>,
    singer_group: Vec<Option<u32>>,
    /// リアルライブでセトリのある公演を (日付, sort_order, 添字) で並べたもの。
    real_shows: Vec<u32>,
    /// 学習に使う公演 (日付順)。
    training: Vec<TrainingShow>,
    feature_ids: HashMap<Feature, u32>,
    feature_set_members: Vec<Vec<u32>>,
}

/// 学習した重み。
#[derive(Debug, Clone, PartialEq)]
pub struct ForecastModel {
    bias: f64,
    weights: Vec<f64>,
    training_show_count: u32,
}

fn parse_day(date: &str) -> Option<i32> {
    let head = date.get(..10)?;
    NaiveDate::parse_from_str(head, "%Y-%m-%d").ok().map(|d| d.num_days_from_ce())
}

fn contains_sorted(list: &[u32], x: u32) -> bool {
    list.binary_search(&x).is_ok()
}

fn sigmoid(z: f64) -> f64 {
    1.0 / (1.0 + (-z).exp())
}

impl ForecastPrep {
    pub fn build(snap: &Snapshot) -> Self {
        let n_songs = snap.songs.len();
        let release_day: Vec<Option<i32>> =
            snap.songs.iter().map(|s| s.release_date.as_deref().and_then(parse_day)).collect();
        let kind: Vec<Option<SongKind>> = snap
            .songs
            .iter()
            .map(|s| if s.parent_song_id.is_some() { None } else { SongKind::parse(s.song_type.as_deref()) })
            .collect();

        let mut originals: Vec<Vec<u32>> = vec![Vec::new(); n_songs];
        for (si, links) in snap.artists_by_song.iter().enumerate() {
            let root = snap.variant_root(si as u32) as usize;
            originals[root].extend(links.iter().filter(|l| l.role == "original").map(|l| l.idol));
        }
        for o in &mut originals {
            o.sort_unstable();
            o.dedup();
        }

        let show_day: Vec<Option<i32>> = snap.shows.iter().map(|s| parse_day(&s.date)).collect();
        let mut event_start: Vec<Option<i32>> = vec![None; snap.events.len()];
        for (si, show) in snap.shows.iter().enumerate() {
            if let Some(day) = show_day[si] {
                let e = &mut event_start[show.event as usize];
                *e = Some(e.map_or(day, |d| d.min(day)));
            }
        }

        let is_real = |show: usize| REAL_LIVE_KINDS.contains(&snap.events[snap.shows[show].event as usize].kind.as_str());
        let mut setlist: Vec<Vec<u32>> = vec![Vec::new(); snap.shows.len()];
        for (si, items) in snap.setlist_items_by_show.iter().enumerate() {
            if !is_real(si) || show_day[si].is_none() {
                continue;
            }
            let list = &mut setlist[si];
            list.extend(items.iter().map(|&it| snap.variant_root(snap.setlist_items[it as usize].song)));
            list.sort_unstable();
            list.dedup();
        }
        let mut real_shows: Vec<u32> = (0..snap.shows.len() as u32).filter(|&s| !setlist[s as usize].is_empty()).collect();
        real_shows.sort_by_key(|&s| (show_day[s as usize], snap.shows[s as usize].sort_order, s));

        let mut history: Vec<Vec<(i32, u32)>> = vec![Vec::new(); n_songs];
        let mut event_songs: Vec<Vec<u32>> = vec![Vec::new(); snap.events.len()];
        for &s in &real_shows {
            let (day, event) = (show_day[s as usize].expect("real show has a day"), snap.shows[s as usize].event);
            for &song in &setlist[s as usize] {
                history[song as usize].push((day, event));
                event_songs[event as usize].push(song);
            }
        }
        for list in &mut event_songs {
            list.sort_unstable();
            list.dedup();
        }
        let history_distinct = history
            .iter()
            .map(|h| {
                let mut seen: Vec<u32> = Vec::new();
                h.iter()
                    .map(|&(_, e)| {
                        if !seen.contains(&e) {
                            seen.push(e);
                        }
                        seen.len() as u32
                    })
                    .collect()
            })
            .collect();

        let mut brands: Vec<String> = Vec::new();
        let event_brand: Vec<Option<u32>> = snap
            .events
            .iter()
            .map(|e| {
                let b = e.brand_id.as_deref()?;
                Some(match brands.iter().position(|x| x == b) {
                    Some(i) => i as u32,
                    None => {
                        brands.push(b.to_string());
                        (brands.len() - 1) as u32
                    }
                })
            })
            .collect();
        let mut brand_events: HashMap<Option<u32>, Vec<(i32, u32)>> = HashMap::new();
        let mut seen_event = vec![false; snap.events.len()];
        for &s in &real_shows {
            let e = snap.shows[s as usize].event as usize;
            if !std::mem::replace(&mut seen_event[e], true) {
                let start = event_start[e].expect("event of a real show has a start");
                brand_events.entry(event_brand[e]).or_default().push((start, e as u32));
            }
        }
        for list in brand_events.values_mut() {
            list.sort_unstable();
        }

        let mut candidates_by_brand: HashMap<String, Vec<u32>> = HashMap::new();
        let mut solo_songs: Vec<Vec<u32>> = vec![Vec::new(); snap.idols.len()];
        let mut group_index: HashMap<&[u32], u32> = HashMap::new();
        let mut singer_groups: Vec<Vec<u32>> = Vec::new();
        let mut singer_group: Vec<Option<u32>> = vec![None; n_songs];
        for (si, song) in snap.songs.iter().enumerate() {
            let Some(k) = kind[si] else { continue };
            if let Some(b) = song.brand_id.as_deref() {
                candidates_by_brand.entry(b.to_string()).or_default().push(si as u32);
            }
            let o = &originals[si];
            if k == SongKind::Solo && o.len() == 1 {
                solo_songs[o[0] as usize].push(si as u32);
            }
            if !o.is_empty() {
                let g = *group_index.entry(o.as_slice()).or_insert_with(|| {
                    singer_groups.push(Vec::new());
                    (singer_groups.len() - 1) as u32
                });
                singer_groups[g as usize].push(si as u32);
                singer_group[si] = Some(g);
            }
        }

        let idol_brands: Vec<Vec<String>> = snap
            .idols
            .iter()
            .enumerate()
            .map(|(ii, idol)| {
                let mut list: Vec<String> = idol.brand_id.iter().cloned().collect();
                for l in &snap.brands_by_idol[ii] {
                    let b = &snap.brands[l.brand as usize].id;
                    if !list.contains(b) {
                        list.push(b.clone());
                    }
                }
                list
            })
            .collect();

        let mut prep = Self {
            release_day,
            kind,
            originals,
            history,
            history_distinct,
            show_day,
            setlist,
            event_start,
            event_songs,
            event_brand,
            brand_events,
            candidates_by_brand,
            idol_brands,
            solo_songs,
            singer_groups,
            singer_group,
            real_shows,
            training: Vec::new(),
            feature_ids: HashMap::new(),
            feature_set_members: Vec::new(),
        };
        prep.build_training(snap);
        prep
    }

    fn build_training(&mut self, snap: &Snapshot) {
        let from = parse_day(TRAINING_FROM).expect("定数の日付");
        let mut set_ids: HashMap<Vec<u32>, u32> = HashMap::new();
        let mut training = Vec::new();
        for show in self.real_shows.clone() {
            let day = self.show_day[show as usize].expect("real show has a day");
            if day < from || snap.cast_by_show[show as usize].is_empty() {
                continue;
            }
            let Some((rows, _)) = self.rows_for(snap, show) else { continue };
            let actual = &self.setlist[show as usize];
            let mut counts: HashMap<u32, (u32, u32)> = HashMap::new();
            for row in rows {
                let mut ids: Vec<u32> = row
                    .features
                    .iter()
                    .map(|f| {
                        let next = self.feature_ids.len() as u32;
                        *self.feature_ids.entry(*f).or_insert(next)
                    })
                    .collect();
                ids.sort_unstable();
                let next = set_ids.len() as u32;
                let set = *set_ids.entry(ids.clone()).or_insert_with(|| {
                    self.feature_set_members.push(ids);
                    next
                });
                let c = counts.entry(set).or_default();
                c.0 += contains_sorted(actual, row.song) as u32;
                c.1 += 1;
            }
            let mut groups: Vec<(u32, u32, u32)> = counts.into_iter().map(|(s, (p, t))| (s, p, t)).collect();
            groups.sort_unstable();
            training.push(TrainingShow { day, groups });
        }
        self.training = training;
    }

    /// `cutoff_day` より前の学習公演の数。重みはこの値だけで決まる (キャッシュの鍵)。
    fn prefix_before(&self, cutoff_day: i32) -> usize {
        self.training.partition_point(|t| t.day < cutoff_day)
    }

    /// 公演を予測するときの学習公演の数 (= 重みのキャッシュの鍵)。予測できない公演は None。
    pub fn training_prefix(&self, snap: &Snapshot, show: u32) -> Option<usize> {
        let start = self.event_start[snap.shows.get(show as usize)?.event as usize]?;
        Some(self.prefix_before(start))
    }

    /// 先頭 `prefix` 公演で学習する。決定的 (同じ入力なら重みはビット単位で一致する)。
    pub fn train(&self, prefix: usize) -> ForecastModel {
        let shows = &self.training[..prefix.min(self.training.len())];
        let n_sets = self.feature_set_members.len();
        let (mut pos, mut tot) = (vec![0u32; n_sets], vec![0u32; n_sets]);
        for show in shows {
            for &(set, p, t) in &show.groups {
                pos[set as usize] += p;
                tot[set as usize] += t;
            }
        }
        let active: Vec<usize> = (0..n_sets).filter(|&s| tot[s] > 0).collect();
        let n: f64 = active.iter().map(|&s| tot[s] as f64).sum();
        let hits: f64 = active.iter().map(|&s| pos[s] as f64).sum();
        let mut weights = vec![0.0; self.feature_ids.len()];
        if n == 0.0 || hits == 0.0 || hits == n {
            let bias = if n == 0.0 { 0.0 } else { (hits / n).clamp(1e-6, 1.0 - 1e-6) };
            return ForecastModel { bias: (bias / (1.0 - bias)).ln(), weights, training_show_count: shows.len() as u32 };
        }
        let mean = hits / n;
        let mut bias = (mean / (1.0 - mean)).ln();
        let mut grad = vec![0.0; weights.len()];
        for _ in 0..TRAINING_ITERATIONS {
            grad.iter_mut().for_each(|g| *g = 0.0);
            let mut grad_bias = 0.0;
            for &s in &active {
                let members = &self.feature_set_members[s];
                let z = bias + members.iter().map(|&f| weights[f as usize]).sum::<f64>();
                let g = tot[s] as f64 * sigmoid(z) - pos[s] as f64;
                grad_bias += g;
                for &f in members {
                    grad[f as usize] += g;
                }
            }
            for (w, g) in weights.iter_mut().zip(&grad) {
                *w -= WEIGHT_LEARNING_RATE * (g / n + L2_PENALTY * *w);
            }
            bias -= BIAS_LEARNING_RATE * grad_bias / n;
        }
        ForecastModel { bias, weights, training_show_count: shows.len() as u32 }
    }

    fn score(&self, model: &ForecastModel, features: &[Feature]) -> f64 {
        model.bias
            + features
                .iter()
                .filter_map(|f| self.feature_ids.get(f))
                .map(|&i| model.weights.get(i as usize).copied().unwrap_or(0.0))
                .sum::<f64>()
    }

    fn past_len(&self, song: u32, before_day: i32) -> usize {
        self.history[song as usize].partition_point(|&(d, _)| d < before_day)
    }

    /// `before_day` より前にその曲が披露されたイベントの数。
    fn past_events(&self, song: u32, before_day: i32) -> u32 {
        match self.past_len(song, before_day) {
            0 => 0,
            n => self.history_distinct[song as usize][n - 1],
        }
    }

    /// 公演 1 つぶんの候補曲の行と、同じイベントの前の日程があるか。
    ///
    /// 見るのは「イベントの開始日より前の披露」と「同じイベントで公演日より前の日程のセトリ」だけ。
    fn rows_for(&self, snap: &Snapshot, show: u32) -> Option<(Vec<Row>, ShowContext)> {
        let sh = snap.shows.get(show as usize)?;
        let event = &snap.events[sh.event as usize];
        if !REAL_LIVE_KINDS.contains(&event.kind.as_str()) {
            return None;
        }
        let date = self.show_day[show as usize]?;
        let start = self.event_start[sh.event as usize]?.min(date);
        let brand = self.event_brand[sh.event as usize];

        let mut cast: Vec<u32> = snap.cast_by_show[show as usize].iter().map(|l| l.idol).collect();
        cast.sort_unstable();
        cast.dedup();
        let cast_known = !cast.is_empty();

        // 候補のブランド: イベントのブランド + 合同ブランド + 出演者が 2 人以上いるブランド。
        let mut cand_brands: Vec<&str> = event.brand_ids().collect();
        let mut per_brand: Vec<(&str, u32)> = Vec::new();
        for &i in &cast {
            for b in &self.idol_brands[i as usize] {
                match per_brand.iter_mut().find(|(x, _)| x == b) {
                    Some(e) => e.1 += 1,
                    None => per_brand.push((b, 1)),
                }
            }
        }
        cand_brands.extend(per_brand.iter().filter(|&&(b, n)| n >= 2 && b != "other").map(|&(b, _)| b));
        cand_brands.sort_unstable();
        cand_brands.dedup();
        let mut candidates: Vec<u32> =
            cand_brands.iter().filter_map(|b| self.candidates_by_brand.get(*b)).flatten().copied().collect();
        candidates.sort_unstable();
        candidates.dedup();

        let previous = self
            .brand_events
            .get(&brand)
            .and_then(|list| list[..list.partition_point(|&(d, _)| d < start)].last().copied());
        let tour_previous = previous.filter(|&(d, _)| start - d <= TOUR_WINDOW_DAYS).map(|(_, e)| e);
        let previous = previous.map(|(_, e)| e);

        // 同じイベントの前の日程 (セトリのあるもの)。
        let mut earlier: Vec<u32> = Vec::new();
        let mut latest_earlier_day: Option<i32> = None;
        for &s in &snap.shows_by_event[sh.event as usize] {
            let (Some(d), list) = (self.show_day[s as usize], &self.setlist[s as usize]) else { continue };
            if d < date && !list.is_empty() {
                earlier.extend(list);
                latest_earlier_day = latest_earlier_day.max(Some(d));
            }
        }
        earlier.sort_unstable();
        earlier.dedup();
        let later_day = latest_earlier_day.is_some();

        let released = |song: u32| self.release_day[song as usize].is_none_or(|r| r <= date);

        // 出演者ごとのソロ曲の順位 (過去の披露イベント数の多い順)。
        let mut solo_rank: HashMap<u32, u8> = HashMap::new();
        for &i in &cast {
            let mut list: Vec<(u32, u32)> = self.solo_songs[i as usize]
                .iter()
                .filter(|&&s| released(s))
                .map(|&s| (self.past_events(s, start), s))
                .collect();
            list.sort_unstable_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
            for (r, &(_, s)) in list.iter().enumerate() {
                solo_rank.insert(s, r.min(3) as u8);
            }
        }

        let mut rows = Vec::with_capacity(candidates.len());
        for song in candidates {
            if !released(song) {
                continue;
            }
            let kind = self.kind[song as usize].expect("候補は種別を持つ");
            let past = self.past_len(song, start);
            let past_events = self.past_events(song, start);
            let originals = &self.originals[song as usize];
            let lineup = cast_known.then(|| {
                if originals.is_empty() {
                    return Lineup::NoOriginal;
                }
                let present = originals.iter().filter(|o| contains_sorted(&cast, **o)).count();
                if present == originals.len() {
                    Lineup::Full
                } else if present * 2 >= originals.len() {
                    Lineup::HalfOrMore
                } else if present > 0 {
                    Lineup::Some
                } else {
                    Lineup::Absent
                }
            });
            let years = self.release_day[song as usize].map_or(10.0, |r| (start - r) as f64 / 365.0).max(0.5);
            let rate_value = past_events as f64 / years;
            let rate = if past == 0 {
                RateBand::Never
            } else if rate_value < 0.3 {
                RateBand::Rare
            } else if rate_value < 1.0 {
                RateBand::Occasional
            } else {
                RateBand::Frequent
            };
            let history = &self.history[song as usize][..past];
            let gap = match history.last() {
                None => GapBand::Never,
                Some(&(d, _)) if start - d < 365 => GapBand::UnderOneYear,
                Some(&(d, _)) if start - d < 1095 => GapBand::UnderThreeYears,
                Some(_) => GapBand::ThreeYearsOrMore,
            };
            let mut recent_events: Vec<u32> =
                history.iter().filter(|&&(d, _)| start - d <= RECENT_WINDOW_DAYS).map(|&(_, e)| e).collect();
            recent_events.sort_unstable();
            recent_events.dedup();

            let mut features = vec![Feature::RateGap(rate, gap), Feature::Recent(recent_events.len().min(3) as u8)];
            if let Some(l) = lineup {
                features.push(Feature::LineupKind(l, kind));
                features.push(Feature::BrandLineupKind(brand, l, kind));
            }
            let sung_previous = previous.is_some_and(|e| contains_sorted(&self.event_songs[e as usize], song));
            if previous.is_some() {
                features.push(Feature::PreviousEvent(kind, sung_previous));
            }
            let sung_tour = tour_previous.is_some_and(|e| contains_sorted(&self.event_songs[e as usize], song));
            if tour_previous.is_some() {
                features.push(Feature::TourPrevious(kind, sung_tour));
            }
            let age = self.release_day[song as usize].map(|r| date - r);
            let new_within_year = past == 0 && age.is_some_and(|a| a <= 365);
            if new_within_year {
                features.push(Feature::NewWithinYear);
            }
            if past == 0 && age.is_some_and(|a| a <= 120) {
                features.push(Feature::NewWithin120Days);
            }
            if lineup == Some(Lineup::Full) && self.is_newest_of_singers(song, date) {
                features.push(Feature::NewestOfSinger(kind));
            }
            if let Some(&r) = solo_rank.get(&song) {
                features.push(Feature::SoloRank(r));
            }
            let earlier_in_event = contains_sorted(&earlier, song);
            if later_day {
                features.push(Feature::SameEventEarlier(kind, earlier_in_event));
            }
            rows.push(Row {
                song,
                features,
                past_events,
                rate,
                gap,
                kind,
                lineup,
                new_within_year,
                sung_previous: sung_previous || sung_tour,
                earlier_in_event,
            });
        }
        let context = ShowContext {
            cast_known,
            previous_day: latest_earlier_day == Some(date - 1),
            start,
        };
        Some((rows, context))
    }

    /// 同じ歌唱者の組の曲のうち、`day` の時点で発売済みの中で最も新しいか。
    fn is_newest_of_singers(&self, song: u32, day: i32) -> bool {
        let (Some(g), Some(rel)) = (self.singer_group[song as usize], self.release_day[song as usize]) else {
            return false;
        };
        self.singer_groups[g as usize]
            .iter()
            .filter_map(|&s| self.release_day[s as usize].filter(|&r| r <= day).map(|r| (r, s)))
            .max()
            == Some((rel, song))
    }

    /// ユニットの持ち歌の中での位置 (理由の表示だけに使う)。
    fn unit_standing(&self, row: &Row, start: i32, date: i32) -> Option<ForecastReason> {
        if row.kind != SongKind::Unit {
            return None;
        }
        let g = self.singer_group[row.song as usize]?;
        if self.originals[row.song as usize].len() < 2 {
            return None;
        }
        let mut counts: Vec<(u32, u32)> = self.singer_groups[g as usize]
            .iter()
            .filter(|&&s| self.kind[s as usize] == Some(SongKind::Unit))
            .filter(|&&s| self.release_day[s as usize].is_none_or(|r| r <= date))
            .map(|&s| (self.past_events(s, start), s))
            .collect();
        if counts.len() < 3 {
            return None;
        }
        counts.sort_unstable();
        let max = counts.last().expect("3 曲以上").0;
        if max > 0 && row.past_events as f64 >= UNIT_STAPLE_RATIO * max as f64 {
            return Some(ForecastReason::UnitStaple);
        }
        counts[..2].iter().any(|&(_, s)| s == row.song).then_some(ForecastReason::UnitRarelyPerformed)
    }

    fn reasons(&self, row: &Row, context: &ShowContext, date: i32) -> Vec<ForecastReason> {
        let mut reasons = Vec::new();
        if row.earlier_in_event {
            reasons.push(if context.previous_day {
                ForecastReason::SungPreviousDay
            } else {
                ForecastReason::SungEarlierInEvent
            });
        }
        if row.lineup == Some(Lineup::Full) {
            reasons.push(ForecastReason::FullOriginalCast);
        }
        if row.new_within_year {
            reasons.push(ForecastReason::NewUnperformed);
        }
        if row.sung_previous {
            reasons.push(ForecastReason::SungAtPreviousLive);
        }
        if row.rate == RateBand::Frequent {
            reasons.push(if row.kind == SongKind::All {
                ForecastReason::AllSongStaple
            } else {
                ForecastReason::FrequentlyPerformed
            });
        }
        reasons.extend(self.unit_standing(row, context.start, date));
        if row.gap == GapBand::ThreeYearsOrMore {
            reasons.push(ForecastReason::LongAbsence);
        }
        reasons.sort_unstable();
        reasons
    }
}

#[derive(Debug, Clone, Copy)]
struct ShowContext {
    cast_known: bool,
    previous_day: bool,
    /// 特徴の区切り (イベントの開始日)。
    start: i32,
}

/// 公演 1 つを予測する。リアルライブでない・日付が読めない公演は None。
///
/// `model` は [`ForecastPrep::train`] に [`ForecastPrep::training_prefix`] の値を渡して作ったもの。
pub fn forecast_show(
    snap: &Snapshot,
    prep: &ForecastPrep,
    model: &ForecastModel,
    show: u32,
    limit: u32,
) -> Option<SetlistForecastRecord> {
    let (rows, context) = prep.rows_for(snap, show)?;
    let date = prep.show_day[show as usize]?;
    let mut scored: Vec<(f64, &Row)> = rows.iter().map(|r| (prep.score(model, &r.features), r)).collect();
    scored.sort_by(|a, b| b.0.total_cmp(&a.0).then(a.1.song.cmp(&b.1.song)));
    let songs = scored
        .into_iter()
        .take(limit as usize)
        .enumerate()
        .map(|(i, (z, row))| {
            let song = &snap.songs[row.song as usize];
            ForecastSongRecord {
                rank: i as u32 + 1,
                song_id: song.id.clone(),
                title: song.title.clone(),
                score: sigmoid(z),
                reasons: prep
                    .reasons(row, &context, date)
                    .into_iter()
                    .map(|reason| ForecastReasonRecord { reason, label: reason.label().to_string() })
                    .collect(),
            }
        })
        .collect();
    let mut flags = Vec::new();
    if !context.cast_known {
        flags.push(ForecastShowFlag::CastUnannounced);
    }
    if !prep.setlist[show as usize].is_empty() {
        flags.push(ForecastShowFlag::SetlistPublished);
    }
    Some(SetlistForecastRecord {
        show_id: snap.shows[show as usize].id.clone(),
        songs,
        flags: flags.into_iter().map(|flag| ForecastShowFlagRecord { flag, label: flag.label().to_string() }).collect(),
        training_show_count: model.training_show_count,
    })
}

/// 下ごしらえから学習・予測までを 1 回で通す (キャッシュを持たない呼び手・テスト用)。
pub fn forecast_show_uncached(snap: &Snapshot, show_id: &str, limit: u32) -> Option<SetlistForecastRecord> {
    let show = *snap.show_index_by_id.get(show_id)?;
    let prep = ForecastPrep::build(snap);
    let model = prep.train(prep.training_prefix(snap, show)?);
    forecast_show(snap, &prep, &model, show, limit)
}


/// 開催前 (`today` 以降) でセトリがまだ無い公演をまとめて予測する (Web の出面用)。
///
/// 下ごしらえは 1 回、重みは学習の区切りごとに 1 回だけ作る (未来の公演はほぼ同じ区切りになる)。
/// 予測できない公演 (リアルライブでない・日付が読めない) は入らない。公演の添字順。
pub fn forecast_upcoming_shows(snap: &Snapshot, today: &str, limit: u32) -> Vec<SetlistForecastRecord> {
    let targets: Vec<u32> = (0..snap.shows.len() as u32)
        .filter(|&s| snap.shows[s as usize].date.as_str() >= today)
        .filter(|&s| snap.setlist_items_by_show[s as usize].is_empty())
        .collect();
    if targets.is_empty() {
        return Vec::new();
    }
    let prep = ForecastPrep::build(snap);
    let mut models: HashMap<usize, ForecastModel> = HashMap::new();
    targets
        .into_iter()
        .filter_map(|show| {
            let prefix = prep.training_prefix(snap, show)?;
            let model = models.entry(prefix).or_insert_with(|| prep.train(prefix));
            forecast_show(snap, &prep, model, show, limit)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::{Event, Idol, SetlistItem, Show, Song};
    use crate::domain::snapshot_build::{build, RawTables};

    fn song(id: &str, song_type: &str, release: Option<&str>) -> Song {
        Song {
            id: id.into(),
            title: id.into(),
            brand_id: Some("ml".into()),
            song_type: Some(song_type.into()),
            release_date: release.map(Into::into),
            ..Default::default()
        }
    }

    fn event(id: &str) -> Event {
        Event {
            id: id.into(),
            brand_id: Some("ml".into()),
            name: id.into(),
            name_kana: None,
            event_type: "live".into(),
            is_streaming: false,
            is_solo: true,
            kind: "live".into(),
            ticket_url: None,
            joint_brand_ids: None,
            has_streaming: None,
            has_live_viewing: None,
        }
    }

    fn show(id: &str, event: u32, date: &str) -> Show {
        Show {
            id: id.into(),
            event,
            name: id.into(),
            date: date.into(),
            venue: None,
            venue_city: None,
            start_time: None,
            sort_order: 0,
            performer_type: None,
            venue_id: None,
            hall: None,
            stream_platform: None,
            has_streaming: None,
            has_live_viewing: None,
        }
    }

    fn item(id: &str, show: u32, song: u32, position: i64) -> SetlistItem {
        SetlistItem { id: id.into(), show, song, position, section: None, notes: None, unit_name: None }
    }

    /// 前のライブ (1/1) → 同じブランドのツアー (2/10 DAY1・2/11 DAY2・出演者未発表の 2/12 DAY3)。
    ///
    /// 曲: 0 unit (i1+i2)・1 solo (i1)・2 all・3 新曲 unit (i1+i2, 1/20 発売)・4 未来の曲 (3/1 発売)。
    fn tour() -> Snapshot {
        let songs = vec![
            song("unit", "unit", None),
            song("solo", "solo", None),
            song("all", "all", None),
            song("new", "unit", Some("2024-01-20")),
            song("future", "unit", Some("2024-03-01")),
        ];
        let original = |s: &str, i: &str| (s.to_string(), i.to_string(), Some("original".to_string()));
        build(RawTables {
            songs,
            idols: vec![
                Idol { id: "i1".into(), brand_id: Some("ml".into()), name: "i1".into(), ..Default::default() },
                Idol { id: "i2".into(), brand_id: Some("ml".into()), name: "i2".into(), ..Default::default() },
            ],
            events: vec![event("prev"), event("tour")],
            units: vec![],
            brands: vec![],
            creators: vec![],
            venues: vec![],
            staff: vec![],
            anniversaries: vec![],
            meta: Default::default(),
            shows: vec![
                show("p1", 0, "2024-01-01"),
                show("t1", 1, "2024-02-10"),
                show("t2", 1, "2024-02-11"),
                show("t3", 1, "2024-02-12"),
            ],
            setlist_items: vec![
                item("a", 0, 0, 1),
                item("b", 0, 1, 2),
                item("c", 0, 2, 3),
                item("d", 1, 0, 1),
            ],
            venue_names: vec![],
            venue_halls: vec![],
            idol_voice_actors: vec![],
            event_releases: vec![],
            costumes: vec![],
            costume_wears: vec![],
            ticket_sales: vec![],
            song_artists: vec![
                original("unit", "i1"),
                original("unit", "i2"),
                original("solo", "i1"),
                original("new", "i1"),
                original("new", "i2"),
                original("future", "i1"),
                original("future", "i2"),
            ],
            setlist_performers: vec![],
            show_cast: ["p1", "t1", "t2"]
                .iter()
                .flat_map(|s| ["i1", "i2"].map(|i| (s.to_string(), i.to_string(), None)))
                .collect(),
            unit_members: vec![],
            idol_brands: vec![],
        })
    }

    fn row<'a>(rows: &'a [Row], snap: &Snapshot, id: &str) -> &'a Row {
        let si = snap.song_index_by_id[id];
        rows.iter().find(|r| r.song == si).unwrap_or_else(|| panic!("{id} が候補に無い"))
    }

    #[test]
    fn features_look_only_before_the_event_start_except_earlier_days() {
        let snap = tour();
        let prep = ForecastPrep::build(&snap);
        let (rows, context) = prep.rows_for(&snap, snap.show_index_by_id["t2"]).unwrap();
        assert!(context.cast_known && context.previous_day);

        let unit = row(&rows, &snap, "unit");
        // DAY1 (2/10) の披露はイベントの開始日以降なので、披露の数には入らない。
        assert_eq!(unit.past_events, 1);
        for f in [
            Feature::LineupKind(Lineup::Full, SongKind::Unit),
            Feature::PreviousEvent(SongKind::Unit, true),
            // 前のライブの開始日から 40 日 = ツアーの前の公演。
            Feature::TourPrevious(SongKind::Unit, true),
            Feature::SameEventEarlier(SongKind::Unit, true),
            Feature::RateGap(RateBand::Rare, GapBand::UnderOneYear),
            Feature::Recent(1),
        ] {
            assert!(unit.features.contains(&f), "{f:?} が無い: {:?}", unit.features);
        }
        assert_eq!(
            prep.reasons(unit, &context, prep.show_day[snap.show_index_by_id["t2"] as usize].unwrap()),
            vec![ForecastReason::SungPreviousDay, ForecastReason::FullOriginalCast, ForecastReason::SungAtPreviousLive]
        );

        let new = row(&rows, &snap, "new");
        for f in [Feature::NewWithinYear, Feature::NewWithin120Days, Feature::NewestOfSinger(SongKind::Unit)] {
            assert!(new.features.contains(&f), "{f:?} が無い: {:?}", new.features);
        }
        assert!(new.features.contains(&Feature::SameEventEarlier(SongKind::Unit, false)));
        // 新曲が出たので、古い方はもう「最新曲」ではない。
        assert!(!unit.features.iter().any(|f| matches!(f, Feature::NewestOfSinger(_))));

        let solo = row(&rows, &snap, "solo");
        assert!(solo.features.contains(&Feature::SoloRank(0)));

        // 公演日より後に出る曲は候補にしない。
        let future = snap.song_index_by_id["future"];
        assert!(rows.iter().all(|r| r.song != future));
    }

    #[test]
    fn a_show_without_cast_is_forecast_without_lineup_and_flagged() {
        let snap = tour();
        let prep = ForecastPrep::build(&snap);
        let t3 = snap.show_index_by_id["t3"];
        let (rows, context) = prep.rows_for(&snap, t3).unwrap();
        assert!(!context.cast_known);
        for r in &rows {
            assert!(r.features.iter().all(|f| !matches!(
                f,
                Feature::LineupKind(..) | Feature::BrandLineupKind(..) | Feature::SoloRank(_) | Feature::NewestOfSinger(_)
            )));
        }
        let model = prep.train(prep.training_prefix(&snap, t3).unwrap());
        let record = forecast_show(&snap, &prep, &model, t3, 10).unwrap();
        assert_eq!(
            record.flags,
            vec![ForecastShowFlagRecord {
                flag: ForecastShowFlag::CastUnannounced,
                label: "出演者未発表のため精度が低い".into()
            }]
        );
        // 学習に使えるのは開始日 (2/10) より前の 1 公演だけ。
        assert_eq!(record.training_show_count, 1);
        assert_eq!(record.songs.iter().map(|s| s.rank).collect::<Vec<_>>(), (1..=record.songs.len() as u32).collect::<Vec<_>>());
        assert!(record.songs.iter().all(|s| (0.0..=1.0).contains(&s.score)));
    }

    #[test]
    fn unit_standing_needs_three_released_songs() {
        let snap = tour();
        let prep = ForecastPrep::build(&snap);
        let t2 = snap.show_index_by_id["t2"];
        let (rows, context) = prep.rows_for(&snap, t2).unwrap();
        let date = prep.show_day[t2 as usize].unwrap();
        // i1+i2 の持ち歌は unit / new / future で、2/11 時点で発売済みは 2 曲 → 3 曲未満なので付けない。
        assert_eq!(prep.unit_standing(row(&rows, &snap, "unit"), context.start, date), None);
    }

    // ---- 実データ ----

    fn day(s: &str) -> i32 {
        parse_day(s).unwrap()
    }

    /// 学習公演 (日付順) の公演添字。`ForecastPrep::training` と同じ並び。
    fn training_shows(snap: &Snapshot, prep: &ForecastPrep) -> Vec<u32> {
        let from = day(TRAINING_FROM);
        prep.real_shows
            .iter()
            .copied()
            .filter(|&s| prep.show_day[s as usize].unwrap() >= from && !snap.cast_by_show[s as usize].is_empty())
            .filter(|&s| prep.rows_for(snap, s).is_some())
            .collect()
    }

    #[derive(Default)]
    struct Tally {
        hits: u32,
        picked: u32,
        shows: u32,
    }

    impl Tally {
        fn add(&mut self, hits: usize, picked: usize) {
            self.hits += hits as u32;
            self.picked += picked as u32;
            self.shows += 1;
        }
        fn rate(&self) -> f64 {
            self.hits as f64 / self.picked.max(1) as f64
        }
    }

    /// 答え合わせ: 2022 年までで学習した重みで、2023 年以降の公演の上位 10 曲の当たり率を測る。
    /// 当たり率は `cargo test setlist_forecast -- --nocapture` で見られる (debug でも数秒)。
    #[test]
    fn backtest_beats_popularity_after_2022() {
        let snap = crate::test_support::bundle_snapshot();
        let t0 = std::time::Instant::now();
        let prep = ForecastPrep::build(snap);
        let t_prep = t0.elapsed();
        let cut = day("2023-01-01");
        let t1 = std::time::Instant::now();
        let model = prep.train(prep.prefix_before(cut));
        let t_train = t1.elapsed();
        eprintln!(
            "下ごしらえ {t_prep:?} / 学習 {t_train:?} (学習公演 {}, 特徴 {}, 組 {})",
            model.training_show_count,
            prep.feature_ids.len(),
            prep.feature_set_members.len()
        );

        let mut model_tally: std::collections::BTreeMap<String, Tally> = Default::default();
        let mut pop_tally: std::collections::BTreeMap<String, Tally> = Default::default();
        for show in training_shows(snap, &prep) {
            if prep.show_day[show as usize].unwrap() < cut {
                continue;
            }
            let (rows, _) = prep.rows_for(snap, show).unwrap();
            let actual: Vec<u32> =
                rows.iter().map(|r| r.song).filter(|&s| contains_sorted(&prep.setlist[show as usize], s)).collect();
            if actual.is_empty() {
                continue;
            }
            let day2 = rows.iter().any(|r| r.features.iter().any(|f| matches!(f, Feature::SameEventEarlier(..))));
            let brand = snap.events[snap.shows[show as usize].event as usize].brand_id.as_deref().unwrap_or("-");
            let keys = [if day2 { "DAY2+" } else { "DAY1" }.to_string(), format!("brand:{brand}"), "ALL".to_string()];

            let mut by_model: Vec<(f64, u32)> = rows.iter().map(|r| (prep.score(&model, &r.features), r.song)).collect();
            by_model.sort_by(|a, b| b.0.total_cmp(&a.0).then(a.1.cmp(&b.1)));
            let mut by_pop: Vec<(u32, u32)> = rows.iter().map(|r| (r.past_events, r.song)).collect();
            by_pop.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
            let hits = |top: Vec<u32>| (top.iter().filter(|s| actual.contains(s)).count(), top.len());
            let (mh, mp) = hits(by_model.iter().take(10).map(|x| x.1).collect());
            let (ph, pp) = hits(by_pop.iter().take(10).map(|x| x.1).collect());
            for k in &keys {
                model_tally.entry(k.clone()).or_default().add(mh, mp);
                pop_tally.entry(k.clone()).or_default().add(ph, pp);
            }
        }
        for (k, m) in &model_tally {
            let p = &pop_tally[k];
            eprintln!("{k:14} 公演 {:4}  予測 {:5.1}%  人気順 {:5.1}%", m.shows, 100.0 * m.rate(), 100.0 * p.rate());
        }
        assert!(model_tally["DAY1"].rate() >= 0.30, "DAY1 の上位 10 曲の当たり率が 30% 未満");
        assert!(model_tally["ALL"].rate() > pop_tally["ALL"].rate(), "人気順に負けた");
    }

    /// 予測する公演の日以降のセトリと出演者を消しても、予測は 1 ビットも変わらない。
    #[test]
    fn later_data_does_not_leak_into_the_forecast() {
        let full = crate::outbound::sqlite_loader::load_raw_tables(crate::test_support::bundle_path()).unwrap();
        let snap = build(full.clone());
        // 2024 年後半の、前の日程のあるイベントの 2 日目以降の公演。
        let target = snap
            .shows_in_date_order
            .iter()
            .copied()
            .find(|&s| {
                let sh = &snap.shows[s as usize];
                sh.date.as_str() >= "2024-07-01"
                    && crate::domain::collection_gap::is_real_live(&snap, s)
                    && !snap.setlist_items_by_show[s as usize].is_empty()
                    && !snap.cast_by_show[s as usize].is_empty()
                    && snap.shows_by_event[sh.event as usize].iter().any(|&o| {
                        snap.shows[o as usize].date < sh.date && !snap.setlist_items_by_show[o as usize].is_empty()
                    })
            })
            .expect("2024 年後半に 2 日目以降の公演がある");
        let target_id = snap.shows[target as usize].id.clone();
        let target_date = snap.shows[target as usize].date.clone();

        let mut cut = full;
        let late: std::collections::HashSet<u32> = cut
            .shows
            .iter()
            .enumerate()
            .filter(|(_, s)| s.date >= target_date)
            .map(|(i, _)| i as u32)
            .collect();
        let late_ids: std::collections::HashSet<String> =
            late.iter().map(|&i| cut.shows[i as usize].id.clone()).filter(|id| *id != target_id).collect();
        let before = cut.setlist_items.len();
        cut.setlist_items.retain(|it| !late.contains(&it.show));
        cut.show_cast.retain(|(show, _, _)| !late_ids.contains(show));
        assert!(cut.setlist_items.len() < before, "消すセトリがある");
        let cut_snap = build(cut);

        let a = forecast_show_uncached(&snap, &target_id, 50).unwrap();
        let b = forecast_show_uncached(&cut_snap, &target_id, 50).unwrap();
        assert_eq!(a.songs, b.songs);
        assert_eq!(a.training_show_count, b.training_show_count);
        assert!(a.training_show_count > 0);
    }
}
