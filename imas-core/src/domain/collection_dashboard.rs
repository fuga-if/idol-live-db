//! 統計タブの「回収ダッシュボード」: 回収率 (全体・ブランド別・担当のオリ曲)、未回収曲の一覧、
//! 「この公演で未回収が聴けるかも」。
//!
//! 両 OS に写経されていた (iOS `StatsView.loadDashboard` + `AppDatabase+UserMarks` の
//! `fetchBrandCollectionProgress` / `fetchLifetimePlayCounts` / `fetchUncollectedSongs` /
//! `fetchUpcomingCatchChances`、Android `StatsRepository.fetchCollectionDashboard`)。
//! Android は同点の並びが iOS と逆 (曲名かなの降順・公演日の降順) になっていた。
//!
//! 回収済みの曲 (参加したリアルライブのセトリの曲) は OS が持っている集合をそのまま受け取る
//! (参加マークは端末の DB にあり、一覧の回収バッジと同じ集合を使うため)。
//! 1 画面 = 1 FFI: 行の描画と遷移に要るもの (曲・公演の全列) も一緒に返す。
//!
//! ## 原曲単位で数える (2026-11-24)
//!
//! 回収率・未回収・披露回数は **原曲 (ver 違いの一族の根) 単位**。`parent_song_id` を持つ曲
//! (ユニット Ver. / Game Size / -19 colors- / リミックス等) は根の曲にまとめ、一族のどれか
//! 1 曲を生で聴いていれば根の曲を回収済みとする。曲ごとに数えるとミリオンは 1081 曲のうち
//! 624 曲が ver 違い (ほぼ未披露) で、回収率が実態から大きくずれていた。
//!
//! - ブランドは根の曲の `brand_id`。
//! - 披露回数は一族の合計 (どの ver でも「その曲が演られた」ので、定番/レアの目安も一族で見る)。
//! - 「披露済み」は一族のどれかがリアルライブで 1 回以上演られたこと。

use std::collections::{HashMap, HashSet};

use crate::domain::collection_gap::is_real_live;
use crate::domain::event_detail_queries::{show_record_at, ShowRecord};
use crate::domain::event_grouping::is_upcoming_on;
use crate::domain::event_naming::event_short_name;
use crate::domain::snapshot::Snapshot;
use crate::domain::song_detail_queries::SongDetailRecord;

/// 「聴けるかも」の公演を何件まで出すか (両 OS の今の値)。
pub const DEFAULT_CATCH_CHANCE_LIMIT: u32 = 8;

/// `parent_song_id` を遡る上限 (今のデータは 1 段だけ。壊れて輪になっていても止まる)。
const MAX_VARIANT_DEPTH: usize = 8;

/// リアルライブでの披露の多さ。未回収曲の札の文言と色の根拠。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PlayFrequency {
    /// 10 回以上。
    Staple,
    /// 3 回以上。
    Sometimes,
    /// 1 回以上。
    Rare,
    /// まだ披露されていない。
    Never,
}

impl PlayFrequency {
    pub fn of(play_count: u32) -> Self {
        match play_count {
            10.. => Self::Staple,
            3.. => Self::Sometimes,
            1.. => Self::Rare,
            0 => Self::Never,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Staple => "定番",
            Self::Sometimes => "ときどき",
            Self::Rare => "レア",
            Self::Never => "未披露",
        }
    }
}

/// ブランド 1 つの回収率 (原曲単位)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct BrandCollectionProgressRecord {
    pub brand_id: String,
    pub short_name: String,
    pub color: Option<String>,
    /// 回収済みの原曲のうち、根の `brand_id` がこのブランドのもの。
    pub collected: u32,
    /// 根の `brand_id` がこのブランドの原曲の数 (合同曲は主ブランドだけで数える)。
    pub total: u32,
    /// 披露済み (一族のどれかがリアルライブで演られた) の原曲のうち回収済みのもの。
    pub performed_collected: u32,
    /// 披露済みの原曲の数。「披露済みのうち何割回収したか」の分母。
    pub performed_total: u32,
}

/// 担当アイドル 1 人のオリ曲の回収率 (原曲単位)。回収率シェアカードの担当の行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct IdolCollectionProgressRecord {
    pub idol_id: String,
    pub collected: u32,
    /// そのアイドルが原唱者 (`role = original`) の曲 (ver 違いは根にまとめる) の数。
    pub total: u32,
}

/// ver 違い 1 曲と、その ver だけの披露回数。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongVariantPlayRecord {
    pub song: SongDetailRecord,
    /// この ver だけがリアルライブのセトリに載った回数。
    pub play_count: u32,
}

/// 未回収の原曲 1 つ。未回収 = 一族のどれも生で聴いていない (ver 違いも全部未回収)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct UncollectedSongRecord {
    /// 原曲 (一族の根)。
    pub song: SongDetailRecord,
    /// 一族 (原曲 + ver 違い) がリアルライブ (`live` / `festival`) のセトリに載った回数の合計
    /// (同じ公演の再披露も数える)。
    pub play_count: u32,
    pub frequency: PlayFrequency,
    /// `定番` / `ときどき` / `レア` / `未披露`。
    pub frequency_label: String,
    /// 原曲そのものの披露回数 (ver 違いを足さない)。
    pub own_play_count: u32,
    /// ver 違い。披露回数の多い順 → 曲名かなの昇順 → 曲 id 順。無ければ空。
    pub variants: Vec<SongVariantPlayRecord>,
}

/// 今日以降のリアルライブの公演 1 つと、そこで聴けるかもしれない未回収曲の数。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CatchChanceRecord {
    pub show: ShowRecord,
    pub event_name: String,
    /// 作品名を落としたイベント名 (設定で省略するときに出す。[`event_short_name`])。
    pub event_short_name: String,
    /// 親イベントの `brand_id` (主ブランド)。
    pub brand_id: Option<String>,
    pub brand_color: Option<String>,
    /// 親イベントと同じ主ブランドのリアルライブで披露されたことのある未回収の原曲の異なり数 (1 以上)。
    pub likely_count: u32,
}

/// 回収ダッシュボード 1 画面分。数はすべて原曲単位。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CollectionDashboardRecord {
    /// 回収済みの原曲の数。
    pub overall_collected: u32,
    /// `brand_id` を持つ原曲の数。
    pub overall_total: u32,
    /// 披露済みの原曲のうち回収済みのもの。
    pub overall_performed_collected: u32,
    /// 披露済みの原曲の数。
    pub overall_performed_total: u32,
    /// ブランドの表示順 (`sort_order`)。曲の無いブランドも 0 / 0 で載る。
    pub brand_progress: Vec<BrandCollectionProgressRecord>,
    pub my_pick_collected: u32,
    /// 担当アイドルのいずれかが原唱者 (`role = original`) の曲 (根にまとめる) の数。
    pub my_pick_total: u32,
    /// 担当 1 人ずつの回収率。`pick_idol_ids` の順 (重複と未知の id は落とす)。
    pub pick_progress: Vec<IdolCollectionProgressRecord>,
    /// 担当のオリ曲のうち未回収のもの。披露回数の多い順 → 曲名かなの昇順 → 曲 id 順。
    pub pick_uncollected: Vec<UncollectedSongRecord>,
    /// `brand_id` を持つ原曲のうち未回収のもの。並びは `pick_uncollected` と同じ。
    pub all_uncollected: Vec<UncollectedSongRecord>,
    /// 聴けるかもしれない数の多い順 → 公演日の昇順 → 公演の `sort_order` 順 → 公演 id 順。
    pub catch_chances: Vec<CatchChanceRecord>,
}

/// 未回収一覧の画面が見る範囲。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum CollectionScope {
    /// `brand_id` を持つ原曲すべて。
    All,
    /// 根の `brand_id` がこのブランドの原曲。
    Brand { brand_id: String },
    /// 担当アイドルのいずれかが原唱者の曲 (根にまとめる)。
    MyPick { idol_ids: Vec<String> },
}

/// 未回収一覧の画面 1 つ分 (ブランド別の回収率のバー・「すべて見る」の先)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct UncollectedListRecord {
    pub collected: u32,
    pub total: u32,
    pub performed_collected: u32,
    pub performed_total: u32,
    /// 未回収で、披露済みのもの (いま回収できる曲)。並びはダッシュボードと同じ。
    pub performed: Vec<UncollectedSongRecord>,
    /// 未回収で、まだ一度も披露されていないもの。曲名かなの昇順 → 曲 id 順。
    pub unperformed: Vec<UncollectedSongRecord>,
}

/// 曲を原曲 (ver 違いの一族の根) にまとめた表と、一族ごとの回収・披露。
struct Families<'a> {
    snap: &'a Snapshot,
    /// songs と同じ添字。その曲の根。
    root_of: Vec<u32>,
    /// 根の添字 → 根以外の一族 (songs の添字順)。
    variants: HashMap<u32, Vec<u32>>,
    /// 根の添字で引く: 一族のどれかが回収済み。
    collected: Vec<bool>,
    /// 曲単体のリアルライブでの披露回数。
    own_play: Vec<u32>,
    /// 根の添字で引く: 一族の披露回数の合計。
    play: Vec<u32>,
    /// `brand_id` を持つ根 (songs の添字順)。
    branded_roots: Vec<u32>,
}

impl<'a> Families<'a> {
    fn new(snap: &'a Snapshot, collected_song_ids: &[String]) -> Self {
        let n = snap.songs.len();
        let root_of: Vec<u32> = (0..n as u32).map(|song| family_root(snap, song)).collect();
        let mut variants: HashMap<u32, Vec<u32>> = HashMap::new();
        for (song, &root) in root_of.iter().enumerate() {
            if root as usize != song {
                variants.entry(root).or_default().push(song as u32);
            }
        }
        let mut collected = vec![false; n];
        for id in collected_song_ids {
            if let Some(&song) = snap.song_index_by_id.get(id) {
                collected[root_of[song as usize] as usize] = true;
            }
        }
        let own_play = real_live_play_counts(snap);
        let mut play = vec![0u32; n];
        for (song, &count) in own_play.iter().enumerate() {
            play[root_of[song] as usize] += count;
        }
        let branded_roots = (0..n as u32)
            .filter(|&song| root_of[song as usize] == song && snap.songs[song as usize].brand_id.is_some())
            .collect();
        Self { snap, root_of, variants, collected, own_play, play, branded_roots }
    }

    fn is_collected(&self, root: u32) -> bool {
        self.collected[root as usize]
    }

    fn is_performed(&self, root: u32) -> bool {
        self.play[root as usize] > 0
    }

    /// 担当のいずれかが原唱者の曲を根にまとめたもの (songs の添字順、重複なし)。
    fn pick_roots(&self, idol_ids: &[String]) -> Vec<u32> {
        let mut hit = vec![false; self.snap.songs.len()];
        for id in idol_ids {
            let Some(&idol) = self.snap.idol_index_by_id.get(id) else { continue };
            for link in &self.snap.songs_by_idol[idol as usize] {
                if link.role == "original" {
                    hit[self.root_of[link.song as usize] as usize] = true;
                }
            }
        }
        (0..hit.len() as u32).filter(|&song| hit[song as usize]).collect()
    }

    fn roots_of_brand(&self, brand_id: &str) -> Vec<u32> {
        self.branded_roots
            .iter()
            .copied()
            .filter(|&root| self.snap.songs[root as usize].brand_id.as_deref() == Some(brand_id))
            .collect()
    }

    fn roots_in(&self, scope: &CollectionScope) -> Vec<u32> {
        match scope {
            CollectionScope::All => self.branded_roots.clone(),
            CollectionScope::Brand { brand_id } => self.roots_of_brand(brand_id),
            CollectionScope::MyPick { idol_ids } => self.pick_roots(idol_ids),
        }
    }

    /// (回収済み, 総数, 披露済みのうち回収済み, 披露済み)。
    fn progress(&self, roots: &[u32]) -> (u32, u32, u32, u32) {
        let mut p = (0, roots.len() as u32, 0, 0);
        for &root in roots {
            let (got, performed) = (self.is_collected(root), self.is_performed(root));
            p.0 += u32::from(got);
            p.2 += u32::from(got && performed);
            p.3 += u32::from(performed);
        }
        p
    }

    /// 未回収の根。披露回数 (一族の合計) の多い順 → 曲名かなの昇順 → 曲 id 順。
    fn uncollected(&self, roots: &[u32]) -> Vec<u32> {
        let mut rest: Vec<u32> = roots.iter().copied().filter(|&root| !self.is_collected(root)).collect();
        rest.sort_by(|&a, &b| self.order(a, b, &self.play));
        rest
    }

    fn order(&self, a: u32, b: u32, counts: &[u32]) -> std::cmp::Ordering {
        let (sa, sb) = (&self.snap.songs[a as usize], &self.snap.songs[b as usize]);
        counts[b as usize]
            .cmp(&counts[a as usize])
            .then_with(|| sa.title_kana.as_deref().unwrap_or("").cmp(sb.title_kana.as_deref().unwrap_or("")))
            .then_with(|| sa.id.cmp(&sb.id))
    }

    fn row(&self, root: u32) -> UncollectedSongRecord {
        let play_count = self.play[root as usize];
        let frequency = PlayFrequency::of(play_count);
        let mut variants = self.variants.get(&root).cloned().unwrap_or_default();
        variants.sort_by(|&a, &b| self.order(a, b, &self.own_play));
        UncollectedSongRecord {
            song: SongDetailRecord::from(&self.snap.songs[root as usize]),
            play_count,
            frequency,
            frequency_label: frequency.label().to_string(),
            own_play_count: self.own_play[root as usize],
            variants: variants
                .into_iter()
                .map(|song| SongVariantPlayRecord {
                    song: SongDetailRecord::from(&self.snap.songs[song as usize]),
                    play_count: self.own_play[song as usize],
                })
                .collect(),
        }
    }

    fn rows(&self, roots: &[u32]) -> Vec<UncollectedSongRecord> {
        roots.iter().map(|&root| self.row(root)).collect()
    }
}

/// ver 違いの一族の根: `parent_song_id` を辿れるだけ辿る (空文字・未知の id は親無しと同じ)。
/// 辿り着いた先が根でない (親が輪になっている・深すぎる壊れたデータ) ときは自分を根にする
/// (数えから落ちないように)。
fn family_root(snap: &Snapshot, song: u32) -> u32 {
    let root = walk_to_root(snap, song);
    if walk_to_root(snap, root) == root {
        root
    } else {
        song
    }
}

fn walk_to_root(snap: &Snapshot, song: u32) -> u32 {
    let mut root = song;
    for _ in 0..MAX_VARIANT_DEPTH {
        let parent = snap.songs[root as usize]
            .parent_song_id
            .as_deref()
            .filter(|id| !id.is_empty())
            .and_then(|id| snap.song_index_by_id.get(id).copied());
        match parent {
            Some(parent) if parent != root => root = parent,
            _ => break,
        }
    }
    root
}

/// 回収ダッシュボードを組む。
///
/// - `collected_song_ids`: 回収済みの曲 (参加したリアルライブのセトリの曲)。未知の id は無視する。
///   ver 違いの id でも、その原曲を回収済みにする。
/// - `pick_idol_ids`: 担当アイドル。
/// - `today`: JST の今日 (`YYYY-MM-DD`)。「今日以降」は [`is_upcoming_on`] で決める
///   (年・月だけの日付の公演も今年・今月なら入る)。
/// - `chance_limit`: 「聴けるかも」を何件まで返すか (今の画面は [`DEFAULT_CATCH_CHANCE_LIMIT`])。
pub fn collection_dashboard(
    snap: &Snapshot,
    collected_song_ids: &[String],
    pick_idol_ids: &[String],
    today: &str,
    chance_limit: u32,
) -> CollectionDashboardRecord {
    let f = Families::new(snap, collected_song_ids);
    let pick = f.pick_roots(pick_idol_ids);
    let all_uncollected = f.uncollected(&f.branded_roots);
    let pick_uncollected = f.uncollected(&pick);
    let (overall_collected, overall_total, overall_performed_collected, overall_performed_total) =
        f.progress(&f.branded_roots);
    let (my_pick_collected, my_pick_total, _, _) = f.progress(&pick);

    let mut seen: HashSet<&str> = HashSet::new();
    let pick_progress = pick_idol_ids
        .iter()
        .filter(|id| snap.idol_index_by_id.contains_key(id.as_str()) && seen.insert(id.as_str()))
        .map(|id| {
            let (collected, total, _, _) = f.progress(&f.pick_roots(std::slice::from_ref(id)));
            IdolCollectionProgressRecord { idol_id: id.clone(), collected, total }
        })
        .collect();

    CollectionDashboardRecord {
        overall_collected,
        overall_total,
        overall_performed_collected,
        overall_performed_total,
        brand_progress: brand_progress(&f),
        my_pick_collected,
        my_pick_total,
        pick_progress,
        pick_uncollected: f.rows(&pick_uncollected),
        catch_chances: catch_chances(&f, &all_uncollected, today, chance_limit),
        all_uncollected: f.rows(&all_uncollected),
    }
}

/// 未回収一覧の画面 (範囲 1 つ分の回収率と、未回収を「披露済み」「未披露」に分けたもの)。
pub fn uncollected_songs(snap: &Snapshot, collected_song_ids: &[String], scope: &CollectionScope) -> UncollectedListRecord {
    let f = Families::new(snap, collected_song_ids);
    let roots = f.roots_in(scope);
    let (collected, total, performed_collected, performed_total) = f.progress(&roots);
    // 披露回数の多い順なので、未披露 (0 回) は必ず後ろにまとまる。
    let (performed, unperformed): (Vec<u32>, Vec<u32>) =
        f.uncollected(&roots).into_iter().partition(|&root| f.is_performed(root));
    UncollectedListRecord {
        collected,
        total,
        performed_collected,
        performed_total,
        performed: f.rows(&performed),
        unperformed: f.rows(&unperformed),
    }
}

/// 回収した原曲の数 (P名刺・プロフィール帳の「回収曲」)。ダッシュボードの `overall_collected` と同じ数。
pub fn collected_original_song_count(snap: &Snapshot, collected_song_ids: &[String]) -> u32 {
    let f = Families::new(snap, collected_song_ids);
    f.progress(&f.branded_roots).0
}

/// 曲ごとの、リアルライブのセトリに載った回数 (songs と同じ添字)。
fn real_live_play_counts(snap: &Snapshot) -> Vec<u32> {
    snap.setlist_items_by_song
        .iter()
        .map(|items| {
            items
                .iter()
                .filter(|&&item| is_real_live(snap, snap.setlist_items[item as usize].show))
                .count() as u32
        })
        .collect()
}

/// ブランドごとの回収率 (ブランドの表示順)。数えるのは根の `brand_id` (主ブランド) だけ。
fn brand_progress(f: &Families) -> Vec<BrandCollectionProgressRecord> {
    let snap = f.snap;
    let mut by_brand: HashMap<&str, Vec<u32>> = HashMap::new();
    for &root in &f.branded_roots {
        if let Some(brand) = snap.songs[root as usize].brand_id.as_deref() {
            by_brand.entry(brand).or_default().push(root);
        }
    }
    snap.brand_order
        .iter()
        .map(|&brand| {
            let b = &snap.brands[brand as usize];
            let roots = by_brand.get(b.id.as_str()).map(Vec::as_slice).unwrap_or(&[]);
            let (collected, total, performed_collected, performed_total) = f.progress(roots);
            BrandCollectionProgressRecord {
                brand_id: b.id.clone(),
                short_name: b.short_name.clone(),
                color: b.color.clone(),
                collected,
                total,
                performed_collected,
                performed_total,
            }
        })
        .collect()
}

/// 「この公演で未回収が聴けるかも」: 今日以降のリアルライブの公演ごとに、親イベントと同じ
/// 主ブランドのリアルライブで (どの ver でも) 披露されたことのある未回収の原曲の異なり数を数え、多い順に返す。
/// 0 曲の公演は出さない。
fn catch_chances(f: &Families, uncollected: &[u32], today: &str, limit: u32) -> Vec<CatchChanceRecord> {
    let snap = f.snap;
    let mut hits: HashSet<(&str, u32)> = HashSet::new();
    for &root in uncollected {
        let family = std::iter::once(root).chain(f.variants.get(&root).into_iter().flatten().copied());
        for item in family.flat_map(|song| snap.setlist_items_by_song[song as usize].iter().copied()) {
            let show = snap.setlist_items[item as usize].show;
            if !is_real_live(snap, show) {
                continue;
            }
            let event = &snap.events[snap.shows[show as usize].event as usize];
            if let Some(brand) = event.brand_id.as_deref() {
                hits.insert((brand, root));
            }
        }
    }
    let mut likely_by_brand: HashMap<&str, u32> = HashMap::new();
    for (brand, _) in hits {
        *likely_by_brand.entry(brand).or_default() += 1;
    }

    let mut chances: Vec<(u32, u32)> = snap
        .shows_in_date_order
        .iter()
        .filter(|&&show| is_real_live(snap, show) && is_upcoming_on(&snap.shows[show as usize].date, today))
        .filter_map(|&show| {
            let event = &snap.events[snap.shows[show as usize].event as usize];
            let likely = *likely_by_brand.get(event.brand_id.as_deref()?)?;
            (likely > 0).then_some((show, likely))
        })
        .collect();
    // 同じ数・同じ日・同じ sort_order の公演は公演 id 順 (端末の DB の行の順に左右されない)。
    chances.sort_by(|&(a, likely_a), &(b, likely_b)| {
        let (sa, sb) = (&snap.shows[a as usize], &snap.shows[b as usize]);
        likely_b
            .cmp(&likely_a)
            .then_with(|| sa.date.cmp(&sb.date))
            .then_with(|| sa.sort_order.cmp(&sb.sort_order))
            .then_with(|| sa.id.cmp(&sb.id))
    });
    chances.truncate(limit as usize);

    chances
        .into_iter()
        .map(|(show, likely_count)| {
            let event = &snap.events[snap.shows[show as usize].event as usize];
            let brand = event.brand_id.as_deref().and_then(|id| snap.brand_index_by_id.get(id));
            CatchChanceRecord {
                show: show_record_at(snap, show),
                event_name: event.name.clone(),
                event_short_name: event_short_name(&event.name).to_string(),
                brand_id: event.brand_id.clone(),
                brand_color: brand.and_then(|&b| snap.brands[b as usize].color.clone()),
                likely_count,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::idol_song_queries::song_ids_with_any_artist;
    use crate::test_support::{bundle_conn, bundle_snapshot};

    /// SQL で曲 → 原曲 (根) を引く式 (親が空文字・未知の id なら自分)。
    const ROOT_SQL: &str = "CASE WHEN COALESCE(s.parent_song_id, '') <> ''
                                  AND EXISTS (SELECT 1 FROM songs p WHERE p.id = s.parent_song_id)
                             THEN s.parent_song_id ELSE s.id END";

    /// リアルライブの披露の条件 (fetchLifetimePlayCounts の WHERE)。
    const REAL_LIVE_SQL: &str = "e.kind IN ('live','festival') AND COALESCE(sh.performer_type, '') <> 'screening'
                                 AND COALESCE(sh.venue_mode, '') <> 'online'";

    /// 参加したことにする公演: リアルライブの公演を日付順に 1 つおきに 60 公演。
    fn attended_songs(snap: &Snapshot) -> Vec<String> {
        let shows: HashSet<u32> = snap
            .shows_in_date_order
            .iter()
            .copied()
            .filter(|&show| is_real_live(snap, show))
            .step_by(2)
            .take(60)
            .collect();
        let mut ids: Vec<String> = snap
            .setlist_items
            .iter()
            .filter(|item| shows.contains(&item.show))
            .map(|item| snap.songs[item.song as usize].id.clone())
            .collect();
        ids.sort();
        ids.dedup();
        ids
    }

    /// 担当: 原唱曲の多いアイドルを 2 人。
    fn pick_idols(snap: &Snapshot) -> Vec<String> {
        let mut idols: Vec<(usize, &str)> = snap
            .idols
            .iter()
            .enumerate()
            .map(|(i, idol)| (snap.songs_by_idol[i].iter().filter(|l| l.role == "original").count(), idol.id.as_str()))
            .collect();
        idols.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(b.1)));
        idols.iter().take(2).map(|(_, id)| id.to_string()).collect()
    }

    /// 曲 id → 根の id (SQL)。
    fn roots_by_sql() -> HashMap<String, String> {
        let conn = bundle_conn();
        let mut stmt = conn.prepare(&format!("SELECT s.id, {ROOT_SQL} FROM songs s")).unwrap();
        stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect()
    }

    /// 根の id → 一族の披露回数の合計 (SQL)。
    fn family_play_counts_by_sql() -> HashMap<String, u32> {
        let conn = bundle_conn();
        let mut stmt = conn
            .prepare(&format!(
                "SELECT {ROOT_SQL}, COUNT(*) FROM setlist_items si JOIN songs s ON s.id = si.song_id
                 JOIN shows sh ON sh.id = si.show_id JOIN events e ON e.id = sh.event_id
                 WHERE {REAL_LIVE_SQL} GROUP BY 1"
            ))
            .unwrap();
        stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).unwrap().map(Result::unwrap).collect()
    }

    /// 披露されたことのある ver 違いと、その根。
    fn performed_variant_and_root(snap: &Snapshot) -> (String, String) {
        let counts = real_live_play_counts(snap);
        snap.songs
            .iter()
            .enumerate()
            .find_map(|(i, s)| {
                let root = family_root(snap, i as u32);
                (root as usize != i && counts[i] > 0)
                    .then(|| (s.id.clone(), snap.songs[root as usize].id.clone()))
            })
            .expect("演られたことのある ver 違いがある")
    }

    #[test]
    fn frequency_thresholds_and_labels() {
        let cases = [(0, PlayFrequency::Never, "未披露"), (1, PlayFrequency::Rare, "レア"), (2, PlayFrequency::Rare, "レア")];
        let more = [(3, PlayFrequency::Sometimes, "ときどき"), (9, PlayFrequency::Sometimes, "ときどき"), (10, PlayFrequency::Staple, "定番")];
        for (count, frequency, label) in cases.into_iter().chain(more) {
            assert_eq!(PlayFrequency::of(count), frequency, "{count} 回");
            assert_eq!(frequency.label(), label);
        }
    }

    #[test]
    fn totals_and_brand_progress_count_original_songs() {
        let snap = bundle_snapshot();
        let conn = bundle_conn();
        let collected = attended_songs(snap);
        assert!(collected.len() > 100, "参加したことにした公演の曲が十分ある: {}", collected.len());
        let d = collection_dashboard(snap, &collected, &[], "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);

        let roots = roots_by_sql();
        let plays = family_play_counts_by_sql();
        let collected_roots: HashSet<&str> = collected.iter().map(|id| roots[id].as_str()).collect();

        // ブランドごとの原曲 (根の brand_id)。
        let mut stmt = conn
            .prepare(&format!(
                "SELECT b.id, b.short_name, b.color, s.id FROM brands b
                 LEFT JOIN songs s ON b.id = s.brand_id AND {ROOT_SQL} = s.id ORDER BY b.sort_order, s.id"
            ))
            .unwrap();
        let mut expected: Vec<(String, String, Option<String>, u32, u32, u32, u32)> = Vec::new();
        for row in stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get::<_, Option<String>>(3)?))).unwrap() {
            let (brand, short, color, song): (String, String, Option<String>, Option<String>) = row.unwrap();
            if expected.last().is_none_or(|e| e.0 != brand) {
                expected.push((brand, short, color, 0, 0, 0, 0));
            }
            let e = expected.last_mut().unwrap();
            if let Some(song) = song {
                let got = collected_roots.contains(song.as_str());
                let performed = plays.get(&song).copied().unwrap_or(0) > 0;
                e.3 += u32::from(got);
                e.4 += 1;
                e.5 += u32::from(got && performed);
                e.6 += u32::from(performed);
            }
        }
        let got: Vec<_> = d
            .brand_progress
            .iter()
            .map(|b| {
                let (c, t, pc, pt) = (b.collected, b.total, b.performed_collected, b.performed_total);
                (b.brand_id.clone(), b.short_name.clone(), b.color.clone(), c, t, pc, pt)
            })
            .collect();
        assert_eq!(got, expected);

        let sum = |f: fn(&BrandCollectionProgressRecord) -> u32| d.brand_progress.iter().map(f).sum::<u32>();
        assert_eq!(d.overall_total, sum(|b| b.total));
        assert_eq!(d.overall_collected, sum(|b| b.collected));
        assert_eq!(d.overall_performed_total, sum(|b| b.performed_total));
        assert_eq!(d.overall_performed_collected, sum(|b| b.performed_collected));
        assert!(d.overall_collected > 0 && d.overall_collected < d.overall_total);
        assert!(d.overall_performed_total < d.overall_total, "未披露の原曲がある");
        // 回収済みはリアルライブで聴いた曲なので、すべて披露済み。
        assert_eq!(d.overall_performed_collected, d.overall_collected);

        // 曲ごとに数えていた頃より分母が小さい (ver 違いが抜ける)。
        let all_songs: u32 = conn.query_row("SELECT COUNT(*) FROM songs WHERE brand_id IS NOT NULL", [], |r| r.get(0)).unwrap();
        assert!(d.overall_total < all_songs);
        let ml = d.brand_progress.iter().find(|b| b.brand_id == "ml").expect("ミリオン");
        let ml_roots: u32 = conn
            .query_row("SELECT COUNT(*) FROM songs WHERE brand_id = 'ml' AND COALESCE(parent_song_id, '') = ''", [], |r| r.get(0))
            .unwrap();
        assert_eq!(ml.total, ml_roots);
    }

    #[test]
    fn a_collected_variant_collects_its_original_song() {
        let snap = bundle_snapshot();
        let (variant, root) = performed_variant_and_root(snap);
        let none = collection_dashboard(snap, &[], &[], "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);
        let row = none.all_uncollected.iter().find(|r| r.song.id == root).expect("原曲の行がある");
        assert!(row.play_count > row.own_play_count, "ver 違いの披露が原曲の披露回数に入る");
        assert!(row.variants.iter().any(|v| v.song.id == variant && v.play_count > 0));
        assert_eq!(row.play_count, row.own_play_count + row.variants.iter().map(|v| v.play_count).sum::<u32>());
        assert!(none.all_uncollected.iter().all(|r| r.song.parent_song_id.as_deref().unwrap_or("").is_empty()), "行は原曲だけ");

        let d = collection_dashboard(snap, &[variant.clone()], &[], "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);
        assert_eq!(d.overall_collected, 1, "ver 違いを聴いたら原曲 1 曲を回収");
        assert!(d.all_uncollected.iter().all(|r| r.song.id != root && r.variants.iter().all(|v| v.song.id != variant)));
        assert_eq!(collected_original_song_count(snap, &[variant, root]), 1, "同じ一族は 1 曲");
    }

    #[test]
    fn uncollected_songs_are_ordered_by_family_play_count_then_kana_then_id() {
        let snap = bundle_snapshot();
        let collected = attended_songs(snap);
        let picks = pick_idols(snap);
        let d = collection_dashboard(snap, &collected, &picks, "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);
        let roots = roots_by_sql();
        let plays = family_play_counts_by_sql();
        let collected_roots: HashSet<&str> = collected.iter().map(|id| roots[id].as_str()).collect();

        for list in [&d.all_uncollected, &d.pick_uncollected] {
            for row in list.iter() {
                assert_eq!(roots[&row.song.id], row.song.id, "行は原曲");
                assert!(!collected_roots.contains(row.song.id.as_str()), "回収済みは載らない");
                assert_eq!(row.play_count, plays.get(&row.song.id).copied().unwrap_or(0), "{}", row.song.id);
                assert_eq!(row.frequency, PlayFrequency::of(row.play_count));
                assert_eq!(row.frequency_label, row.frequency.label());
                for v in &row.variants {
                    assert_eq!(roots[&v.song.id], row.song.id);
                }
            }
            for pair in list.windows(2) {
                let key = |r: &UncollectedSongRecord| {
                    (std::cmp::Reverse(r.play_count), r.song.title_kana.clone().unwrap_or_default(), r.song.id.clone())
                };
                assert!(key(&pair[0]) < key(&pair[1]), "{} → {}", pair[0].song.id, pair[1].song.id);
            }
        }
        assert_eq!(d.all_uncollected.len() as u32, d.overall_total - d.overall_collected);
        assert!(d.all_uncollected.iter().any(|r| r.frequency == PlayFrequency::Never));
        assert!(d.all_uncollected.iter().any(|r| r.frequency == PlayFrequency::Staple));
        assert!(d.all_uncollected.iter().any(|r| !r.variants.is_empty()));

        // 担当のオリ曲 (song_artists の原唱者) を根にまとめた回収率と未回収。
        let pick_roots: HashSet<&str> =
            song_ids_with_any_artist(snap, &picks).iter().map(|id| roots[id].as_str()).collect();
        assert!(!pick_roots.is_empty());
        assert_eq!(d.my_pick_total, pick_roots.len() as u32);
        let pick_collected = pick_roots.iter().filter(|id| collected_roots.contains(*id)).count() as u32;
        assert_eq!(d.my_pick_collected, pick_collected);
        let mut pick_rest: Vec<&str> = pick_roots.iter().copied().filter(|id| !collected_roots.contains(id)).collect();
        let mut listed: Vec<&str> = d.pick_uncollected.iter().map(|r| r.song.id.as_str()).collect();
        pick_rest.sort();
        listed.sort();
        assert_eq!(listed, pick_rest);

        // 担当 1 人ずつ (入力の順、重複と未知の id は落とす)。
        let noisy = [picks[1].clone(), "存在しない".to_string(), picks[0].clone(), picks[1].clone()];
        let p = collection_dashboard(snap, &collected, &noisy, "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT).pick_progress;
        assert_eq!(p.iter().map(|l| l.idol_id.as_str()).collect::<Vec<_>>(), [picks[1].as_str(), picks[0].as_str()]);
        for line in &p {
            let one = collection_dashboard(snap, &collected, std::slice::from_ref(&line.idol_id), "2026-01-01", 0);
            assert_eq!((line.collected, line.total), (one.my_pick_collected, one.my_pick_total));
        }
    }

    #[test]
    fn uncollected_list_splits_performed_and_unperformed_per_scope() {
        let snap = bundle_snapshot();
        let collected = attended_songs(snap);
        let picks = pick_idols(snap);
        let d = collection_dashboard(snap, &collected, &picks, "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);

        let check = |list: &UncollectedListRecord, expected: Vec<&UncollectedSongRecord>| {
            let got: Vec<&UncollectedSongRecord> = list.performed.iter().chain(&list.unperformed).collect();
            assert_eq!(got, expected, "ダッシュボードの未回収と同じ行・同じ並び");
            assert!(list.performed.iter().all(|r| r.play_count > 0));
            assert!(list.unperformed.iter().all(|r| r.play_count == 0 && r.frequency == PlayFrequency::Never));
            assert_eq!(list.total - list.collected, got.len() as u32);
            assert_eq!(list.performed_total - list.performed_collected, list.performed.len() as u32);
        };

        let all = uncollected_songs(snap, &collected, &CollectionScope::All);
        check(&all, d.all_uncollected.iter().collect());
        assert_eq!(
            (all.collected, all.total, all.performed_collected, all.performed_total),
            (d.overall_collected, d.overall_total, d.overall_performed_collected, d.overall_performed_total)
        );

        for b in d.brand_progress.iter().filter(|b| b.total > 0) {
            let list = uncollected_songs(snap, &collected, &CollectionScope::Brand { brand_id: b.brand_id.clone() });
            let rows = d.all_uncollected.iter().filter(|r| r.song.brand_id.as_deref() == Some(b.brand_id.as_str()));
            check(&list, rows.collect());
            assert_eq!(
                (list.collected, list.total, list.performed_collected, list.performed_total),
                (b.collected, b.total, b.performed_collected, b.performed_total),
                "{}",
                b.brand_id
            );
        }
        let sc = uncollected_songs(snap, &collected, &CollectionScope::Brand { brand_id: "sc".into() });
        assert!(!sc.performed.is_empty() && !sc.unperformed.is_empty());

        let pick = uncollected_songs(snap, &collected, &CollectionScope::MyPick { idol_ids: picks.clone() });
        check(&pick, d.pick_uncollected.iter().collect());
        assert_eq!((pick.collected, pick.total), (d.my_pick_collected, d.my_pick_total));

        let unknown = uncollected_songs(snap, &collected, &CollectionScope::Brand { brand_id: "無い".into() });
        assert_eq!((unknown.total, unknown.performed.len(), unknown.unperformed.len()), (0, 0, 0));
    }

    #[test]
    fn catch_chances_match_the_sql_and_are_ordered_deterministically() {
        let snap = bundle_snapshot();
        let collected = attended_songs(snap);
        check_catch_chances_against_sql(&collected, "2025-06-01");
        let d = collection_dashboard(snap, &collected, &[], "2025-06-01", 1000);
        let limited = collection_dashboard(snap, &collected, &[], "2025-06-01", 3);
        assert_eq!(limited.catch_chances, d.catch_chances[..3].to_vec(), "先頭から chance_limit 件");
    }

    /// iOS `fetchUpcomingCatchChances` の SQL (削除前の b6ea16f8^) の曲を原曲に置き換えたものと、
    /// 今日以降の全公演で突き合わせる。
    fn check_catch_chances_against_sql(collected: &[String], today: &str) {
        let snap = bundle_snapshot();
        let conn = bundle_conn();
        let d = collection_dashboard(snap, collected, &[], today, 1000);
        let uncollected: HashSet<&str> = d.all_uncollected.iter().map(|r| r.song.id.as_str()).collect();

        let mut stmt = conn
            .prepare(&format!(
                "SELECT DISTINCT e.brand_id, {ROOT_SQL} FROM setlist_items si JOIN songs s ON s.id = si.song_id
                 JOIN shows sh ON sh.id = si.show_id JOIN events e ON e.id = sh.event_id
                 WHERE e.brand_id IS NOT NULL AND {REAL_LIVE_SQL}"
            ))
            .unwrap();
        let mut likely_by_brand: HashMap<String, u32> = HashMap::new();
        for row in stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).unwrap() {
            let (brand, song) = row.unwrap();
            if uncollected.contains(song.as_str()) {
                *likely_by_brand.entry(brand).or_default() += 1;
            }
        }
        let mut stmt = conn
            .prepare(
                "SELECT s.id, e.brand_id, s.date FROM shows s JOIN events e ON s.event_id = e.id
                 WHERE s.date >= ? AND e.kind IN ('live','festival')
                   AND COALESCE(s.performer_type, '') <> 'screening'
                   AND COALESCE(s.venue_mode, '') <> 'online' ORDER BY s.date, s.sort_order, s.id",
            )
            .unwrap();
        let mut expected: Vec<(String, u32, String)> = stmt
            .query_map([today], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?)))
            .unwrap()
            .map(Result::unwrap)
            .filter_map(|(show, brand, date)| likely_by_brand.get(&brand).map(|&n| (show, n, date)))
            .collect();
        expected.sort_by_key(|e| std::cmp::Reverse(e.1));
        assert!(expected.len() > 5, "今日以降の公演が十分ある: {}", expected.len());

        let got: Vec<(String, u32, String)> = d
            .catch_chances
            .iter()
            .map(|c| (c.show.id.clone(), c.likely_count, c.show.date.clone()))
            .collect();
        let ids = |v: &[(String, u32, String)]| v.iter().map(|(id, n, _)| (id.clone(), *n)).collect::<Vec<_>>();
        assert_eq!(ids(&got), ids(&expected));
        for pair in got.windows(2) {
            assert!(pair[0].1 > pair[1].1 || (pair[0].1 == pair[1].1 && pair[0].2 <= pair[1].2), "多い順 → 日付の昇順");
        }
        for c in &d.catch_chances {
            assert!(c.likely_count > 0);
            assert_eq!(c.event_short_name, event_short_name(&c.event_name));
            let brand = c.brand_id.as_deref().expect("主ブランドのある公演だけ");
            let color: Option<String> =
                conn.query_row("SELECT color FROM brands WHERE id = ?", [brand], |r| r.get(0)).unwrap();
            assert_eq!(c.brand_color, color);
        }
    }

    #[test]
    fn unknown_and_duplicate_ids_do_not_count_and_nothing_collected_leaves_everything_open() {
        let snap = bundle_snapshot();
        let d = collection_dashboard(snap, &[], &[], "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);
        assert_eq!(d.overall_collected, 0);
        assert_eq!(d.all_uncollected.len() as u32, d.overall_total);
        assert!(d.pick_uncollected.is_empty() && d.my_pick_total == 0 && d.my_pick_collected == 0);
        assert!(d.pick_progress.is_empty());
        assert!(d.brand_progress.iter().all(|b| b.collected == 0 && b.performed_collected == 0));
        assert_eq!(collected_original_song_count(snap, &[]), 0);

        let song = d.all_uncollected[0].song.id.clone();
        let with_noise = [song.clone(), song.clone(), "存在しない曲".to_string()];
        let once = collection_dashboard(snap, &with_noise, &[], "2026-01-01", DEFAULT_CATCH_CHANCE_LIMIT);
        assert_eq!(once.overall_collected, 1, "重複と未知の id は数えない");
        assert!(once.all_uncollected.iter().all(|r| r.song.id != song));
        assert_eq!(collected_original_song_count(snap, &with_noise), 1);
    }

    #[test]
    fn no_chances_after_the_last_show() {
        let snap = bundle_snapshot();
        let d = collection_dashboard(snap, &[], &[], "9999-12-31", DEFAULT_CATCH_CHANCE_LIMIT);
        assert!(d.catch_chances.is_empty());
    }
}
