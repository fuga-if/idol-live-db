//! 年表 (ブランド史) のクエリ群 (SQL 時代の集計を Snapshot 上の純粋関数へ移送)。
//!
//! SQL 時代の対応: iOS `AppDatabase+TimelineQueries.fetchTimelineBarsQuery`
//! (= `TimelineReading.timelineBars(brandId:)` の全量)。
//! 「節目 / ライブ / 楽曲シリーズ / その他」を 1 本の時間軸に載せる素材を、
//! milestone → event → series → cdSeries → oneOff の順で連結して返す
//! (Swift 原本の `+` 連結順をそのまま固定)。
//!
//! 結果は Phase 1 の domain::timeline_layout がそのまま食べられる射影
//! ([`TimelineBarRecord`]: epoch 秒 + index なし) で返す。日付→epoch は JST 0 時固定
//! (端末タイムゾーンで年境界がずれると「1/1 のリリースが前年の帯に入る」— Swift
//! `TimelineDateParser` と同じ理由)。
//!
//! SQL の暗黙挙動をコードで明示して固定する:
//! - `GROUP BY brand_id, ...`: NULL の brand_id は 1 グループに畳まれる。Rust では
//!   `Option<&str>` をキーに使う (None < Some は SQLite の NULL 最小と同じ並び)。
//! - `ORDER BY first_date` / `ORDER BY year` の同順位は SQL では未規定 (SQLite の
//!   ソータは安定保証がない)。共有コアは「グループキー (brand, 名前) → 添字」を
//!   最終キーに使って決定的に並べる (プラットフォーム間で同一結果を返すのが目的)。
//!   照合テストは song_list_queries と同じ「同順位区間を集合比較」で突き合わせる。
//! - `STRFTIME('%Y', d)`: 不正な日付は NULL になり、その行は Swift 側の
//!   `guard let year` で落ちていた。[`strftime_year`] が同じ判定を一次実装する
//!   (検証内容は sqlite3 実測でピン留め。テスト参照)。
//!
//! 意図的な Swift 原本との差分 (呼び出し側の責務):
//! - イベント帯の `title` は events.name の **正式名称のまま** 返す。Swift 原本は
//!   フェッチ時に `eventDisplayName` (作品名プレフィックス省略) を掛けていたが、
//!   あれは UserDefaults の表示設定に依存する端末状態なので core には置けない。
//!   アダプタ側で `target == .event` の帯にだけ適用すること。
//! - バッジ ("3公演" / "12曲") は SQL 時代と同じくクエリ層 (= ここ) で組み立てる。
//!   iOS/Android で同一表示を保証するため、書式をプラットフォームに重複させない。

use crate::domain::snapshot::Snapshot;
use chrono::{FixedOffset, TimeZone};
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// 年表のスイムレーン。iOS `TimelineLane` の 1:1 対応。
///
/// 名前を iOS 側と揃えていないのは意図的: 生成バインディングがアプリと同一モジュールに
/// 入るため、既存 Swift enum と衝突する (song_list_queries の前例と同じ判断)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum TimelineBarLane {
    /// サービス開始・アニメ放映などの節目 (単日)。
    Milestone,
    /// ライブ・フェス (events.kind = 'live' / 'festival')。
    Live,
    /// 楽曲の CD シリーズ・単発リリース (期間を持つ)。
    Music,
    /// リリイベ・ラジオ・配信番組など (上記以外の events.kind)。
    Other,
}

/// 帯タップ時の遷移先。iOS `TimelineTarget` の 1:1 対応 (名前は衝突回避で変更)。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq, Hash)]
pub enum TimelineBarTarget {
    Event { id: String },
    SeriesGroup { name: String },
    /// series_group 未設定だが同じ CD にまとまっている塊。
    CdSeries { name: String },
    /// 束ねる相手のいない単発リリースの年 ("YYYY")。
    ReleaseYear { year: String },
    /// 遷移先を持たない (節目など)。
    None,
}

/// 年表に置く 1 本の帯 (FFI 射影)。単日の出来事は start == end。
///
/// 日付はすべて JST 0 時の epoch 秒 — domain::timeline_layout
/// (`TimelineBarPeriod` / `timeline_x_positions`) がそのまま受け取れる形。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Hash)]
pub struct TimelineBarRecord {
    /// "ms_<id>" / "ev_<id>" / "sg_<brand>_<series>" / "cds_<brand>_<cd>" /
    /// "oneoff_<brand>_<year>" (brand なしは "-"。Swift 原本と同じ採番)。
    pub id: String,
    pub lane: TimelineBarLane,
    /// 帯のラベル。イベント帯は events.name の正式名称のまま
    /// (表示用省略はアダプタの責務 — モジュール doc 参照)。
    pub title: String,
    /// 期間の開始 (JST 日付の 0 時)。
    pub start_epoch_seconds: i64,
    /// 期間の終了。単日なら start と同値。
    pub end_epoch_seconds: i64,
    /// 帯上に打つ点 (公演日 / リリース日)。重複を畳んで昇順。
    pub mark_epoch_seconds: Vec<i64>,
    /// 色シード (ブランドカラー hex)。無ければ category_key から安定色を導出する。
    pub seed_hex: Option<String>,
    /// 実体色を持たない帯に安定色を割り当てるためのキー。
    pub category_key: String,
    /// 右肩の小バッジ ("25曲" / "3公演")。
    pub badge: Option<String>,
    pub target: TimelineBarTarget,
}

/// JST は UTC+9 固定・夏時間なし (timeline_layout と同じ前提)。
const JST_OFFSET_SECONDS: i32 = 9 * 3600;

fn jst() -> FixedOffset {
    FixedOffset::east_opt(JST_OFFSET_SECONDS).expect("JST offset は常に有効")
}

/// `YYYY-MM-DD` (先頭 10 バイト固定桁) を JST 0 時の epoch 秒へ。
/// Swift `TimelineDateParser.date` の一次実装。壊れた日付は None (Swift の
/// compactMap と同じく行/点ごと落とす)。
///
/// Swift は Calendar が 2/30 等を翌月へ繰り上げるが、ここは暦として不正な日付を
/// 明示的に落とす (chrono の検証)。実データは SQLite `date()` 検証済みの
/// YYYY-MM-DD のみなので分岐に到達しない — 挙動をコードで固定するための明示。
fn epoch_from_date(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    if b.len() < 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let all_digits =
        |r: std::ops::Range<usize>| b[r].iter().all(u8::is_ascii_digit);
    if !(all_digits(0..4) && all_digits(5..7) && all_digits(8..10)) {
        return None;
    }
    let year: i32 = text[..4].parse().ok()?;
    let month: u32 = text[5..7].parse().ok()?;
    let day: u32 = text[8..10].parse().ok()?;
    jst()
        .with_ymd_and_hms(year, month, day, 0, 0, 0)
        .single()
        .map(|dt| dt.timestamp())
}

/// SQLite `STRFTIME('%Y', d)` の一次実装 (oneOff の年グループ用)。
///
/// sqlite3 実測 (2026-08-25) をピン留め:
/// - 4-2-2 桁固定・月 01-12・日 01-31 のみ検証 ('2015-02-31' は月ごとの日数を
///   見ないので **通る**)。桁割れ ('2015-1-1') や範囲外は NULL。
/// - 11 バイト目が ' ' / 'T' なら時刻付きとして年を返す。他の続きは NULL。
/// - 純数値文字列 ('2015') はユリウス日解釈で別の年になるが、ここでは None に倒す
///   (release_date にユリウス日が入ることはなく、照合テストが実データで守る)。
fn strftime_year(text: &str) -> Option<&str> {
    let b = text.as_bytes();
    if b.len() < 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let all_digits =
        |r: std::ops::Range<usize>| b[r].iter().all(u8::is_ascii_digit);
    if !(all_digits(0..4) && all_digits(5..7) && all_digits(8..10)) {
        return None;
    }
    let month: u32 = text[5..7].parse().ok()?;
    let day: u32 = text[8..10].parse().ok()?;
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    if b.len() > 10 && b[10] != b' ' && b[10] != b'T' {
        return None;
    }
    Some(&text[..4])
}

/// `IFNULL(x,'') != ''` (NULL と空文字を同一視した「値あり」判定)。
fn non_blank(value: &Option<String>) -> Option<&str> {
    value.as_deref().filter(|v| !v.is_empty())
}

/// brand_id → カラー hex (`IFNULL(color,'') != ''` の行のみ)。帯の色シード。
fn brand_colors(snap: &Snapshot) -> HashMap<&str, &str> {
    snap.brands
        .iter()
        .filter_map(|b| match b.color.as_deref() {
            Some(color) if !color.is_empty() => Some((b.id.as_str(), color)),
            _ => None,
        })
        .collect()
}

/// 年表の帯を全レーン分まとめて返す。`brand_id` が None なら全ブランド横断。
/// 連結順は Swift 原本の `+` と同じ (モジュール doc 参照)。
pub fn timeline_bars(snap: &Snapshot, brand_id: Option<&str>) -> Vec<TimelineBarRecord> {
    let colors = brand_colors(snap);
    let mut bars = milestone_bars(snap, brand_id, &colors);
    bars.extend(event_bars(snap, brand_id, &colors));
    bars.extend(series_bars(snap, brand_id, &colors));
    bars.extend(cd_series_bars(snap, brand_id, &colors));
    bars.extend(one_off_release_bars(snap, brand_id, &colors));
    bars
}

/// 節目 (anniversaries)。元 SQL:
/// `WHERE IFNULL(date,'') != '' [AND brand_id = ?] ORDER BY date`。
/// anniversary_order が (date ASC, 添字) を前計算済みなのでそのまま流す。
fn milestone_bars(
    snap: &Snapshot,
    brand_id: Option<&str>,
    colors: &HashMap<&str, &str>,
) -> Vec<TimelineBarRecord> {
    snap.anniversary_order
        .iter()
        .filter_map(|&ai| {
            let a = &snap.anniversaries[ai as usize];
            if a.date.is_empty() {
                return None;
            }
            if brand_id.is_some_and(|b| a.brand_id != b) {
                return None;
            }
            let epoch = epoch_from_date(&a.date)?;
            Some(TimelineBarRecord {
                id: format!("ms_{}", a.id),
                lane: TimelineBarLane::Milestone,
                title: a.label.clone(),
                start_epoch_seconds: epoch,
                end_epoch_seconds: epoch,
                mark_epoch_seconds: vec![epoch],
                seed_hex: colors.get(a.brand_id.as_str()).map(|&c| c.to_string()),
                // スキーマは kind NOT NULL (Swift の `?? "milestone"` は防御)。空文字は
                // Swift 同様そのまま保つ (安定色キーが変わると帯色が揺れるため)。
                category_key: a.kind.clone(),
                badge: None,
                target: TimelineBarTarget::None,
            })
        })
        .collect()
}

/// events.kind → レーン。ライブ・フェスだけを主役の「ライブ」レーンに置き、
/// リリイベ・ラジオ・配信は「その他」へ (Swift `lane(forEventKind:)` の写し)。
fn lane_for_event_kind(kind: &str) -> TimelineBarLane {
    match kind {
        "live" | "festival" => TimelineBarLane::Live,
        _ => TimelineBarLane::Other,
    }
}

/// ライブ / その他イベント (events + shows)。元 SQL:
/// `JOIN shows ... WHERE IFNULL(s.date,'') != '' [AND e.brand_id = ?]
///  GROUP BY e.id ORDER BY MIN(s.date)`。
///
/// shows_by_event は (date ASC, sort_order ASC) 前計算済みなので、空日付を除いた
/// 先頭/末尾がそのまま MIN/MAX(date)。同 first_date の並びは events 添字
/// (= rowid 読み込み順) で決定的にする (安定ソート)。
fn event_bars(
    snap: &Snapshot,
    brand_id: Option<&str>,
    colors: &HashMap<&str, &str>,
) -> Vec<TimelineBarRecord> {
    let mut bars: Vec<(&str, TimelineBarRecord)> = Vec::new();
    for (ei, event) in snap.events.iter().enumerate() {
        // `e.brand_id = ?`: brand_id が NULL の行はどの値とも一致しない。
        if brand_id.is_some_and(|b| event.brand_id.as_deref() != Some(b)) {
            continue;
        }
        let dates: Vec<&str> = snap.shows_by_event[ei]
            .iter()
            .map(|&si| snap.shows[si as usize].date.as_str())
            .filter(|d| !d.is_empty())
            .collect();
        // JOIN なので日付を持つ show が 1 つもないイベントは行ごと消える。
        let (Some(&first), Some(&last)) = (dates.first(), dates.last()) else {
            continue;
        };
        let (Some(start), Some(end)) = (epoch_from_date(first), epoch_from_date(last)) else {
            continue; // Swift compactMap: 端の日付が壊れていたら帯ごと落とす
        };
        // GROUP_CONCAT → Set → sorted (Swift TimelineDateParser.dates) と同じく
        // epoch 化してから畳む (文字列違いでも同日なら 1 点)。
        let marks: BTreeSet<i64> = dates.iter().filter_map(|d| epoch_from_date(d)).collect();
        let brand = event.brand_id.as_deref();
        bars.push((
            first,
            TimelineBarRecord {
                id: format!("ev_{}", event.id),
                lane: lane_for_event_kind(&event.kind),
                title: event.name.clone(),
                start_epoch_seconds: start,
                end_epoch_seconds: end,
                mark_epoch_seconds: marks.into_iter().collect(),
                seed_hex: brand.and_then(|b| colors.get(b)).map(|&c| c.to_string()),
                // 帯色の系統はブランド優先。ブランド無所属イベントは種別で安定させる
                // (kind はロード時に NOT NULL 既定 'live' 適用済み = Swift `?? "live"`)。
                category_key: brand.unwrap_or(&event.kind).to_string(),
                badge: (dates.len() > 1).then(|| format!("{}公演", dates.len())),
                target: TimelineBarTarget::Event { id: event.id.clone() },
            },
        ));
    }
    // ORDER BY first_date (TEXT 昇順 = 日付順)。安定ソートで同順位は添字順のまま。
    bars.sort_by_key(|&(first, _)| first);
    bars.into_iter().map(|(_, bar)| bar).collect()
}

/// リリース日つき曲グループの集計素材 (series / cdSeries / oneOff 共用)。
struct ReleaseGroup<'a> {
    count: u32,
    first: &'a str,
    last: &'a str,
    /// GROUP_CONCAT(DISTINCT release_date) 相当 (文字列レベルの重複排除 + 昇順)。
    dates: BTreeSet<&'a str>,
}

impl<'a> ReleaseGroup<'a> {
    fn add(&mut self, date: &'a str) {
        self.count += 1;
        // MIN/MAX(release_date) は TEXT 比較 (= 辞書順 = 日付順)。
        if date < self.first {
            self.first = date;
        }
        if date > self.last {
            self.last = date;
        }
        self.dates.insert(date);
    }

    fn seed(date: &'a str) -> Self {
        Self { count: 1, first: date, last: date, dates: BTreeSet::from([date]) }
    }
}

/// (brand, 名前) でグループした帯を first_date 順に組み立てる共通部。
/// `make` が id / タイトル / 遷移先などレーン固有の項を埋める。
///
/// 同 first_date の並びは BTreeMap のキー順 (brand: None 最小 = SQLite の
/// NULL 最小、次いで名前のバイト列昇順 = BINARY 照合) で決定的にする。
fn grouped_release_bars<'a>(
    groups: BTreeMap<(Option<&'a str>, &'a str), ReleaseGroup<'a>>,
    colors: &HashMap<&str, &str>,
    make: impl Fn(Option<&str>, &str, &ReleaseGroup<'a>) -> (String, String, String, TimelineBarTarget),
) -> Vec<TimelineBarRecord> {
    let mut bars: Vec<(&str, TimelineBarRecord)> = Vec::new();
    for ((brand, name), group) in &groups {
        let (Some(start), Some(end)) =
            (epoch_from_date(group.first), epoch_from_date(group.last))
        else {
            continue; // Swift compactMap と同じく端の日付が壊れた帯は落とす
        };
        let marks: BTreeSet<i64> =
            group.dates.iter().filter_map(|d| epoch_from_date(d)).collect();
        let (id, title, category_key, target) = make(*brand, name, group);
        bars.push((
            group.first,
            TimelineBarRecord {
                id,
                lane: TimelineBarLane::Music,
                title,
                start_epoch_seconds: start,
                end_epoch_seconds: end,
                mark_epoch_seconds: marks.into_iter().collect(),
                // 色はブランドカラー基準。シリーズごとの塗り分けは View 側が
                // category_key でバリエーションを振る (Swift 原本のコメント踏襲)。
                seed_hex: brand.and_then(|b| colors.get(b)).map(|&c| c.to_string()),
                category_key,
                badge: Some(format!("{}曲", group.count)),
                target,
            },
        ));
    }
    bars.sort_by_key(|&(first, _)| first); // ORDER BY first_date (安定)
    bars.into_iter().map(|(_, bar)| bar).collect()
}

/// 楽曲シリーズ (songs.series_group)。元 SQL:
/// `WHERE IFNULL(series_group,'') != '' AND IFNULL(release_date,'') != ''
///  [AND brand_id = ?] GROUP BY brand_id, series_group ORDER BY MIN(release_date)`。
fn series_bars(
    snap: &Snapshot,
    brand_id: Option<&str>,
    colors: &HashMap<&str, &str>,
) -> Vec<TimelineBarRecord> {
    let mut groups: BTreeMap<(Option<&str>, &str), ReleaseGroup<'_>> = BTreeMap::new();
    for song in &snap.songs {
        let Some(series) = non_blank(&song.series_group) else { continue };
        let Some(date) = non_blank(&song.release_date) else { continue };
        if brand_id.is_some_and(|b| song.brand_id.as_deref() != Some(b)) {
            continue;
        }
        groups
            .entry((song.brand_id.as_deref(), series))
            .and_modify(|g| g.add(date))
            .or_insert_with(|| ReleaseGroup::seed(date));
    }
    grouped_release_bars(groups, colors, |brand, series, _| {
        (
            format!("sg_{}_{}", brand.unwrap_or("-"), series),
            series.to_string(),
            series.to_string(),
            TimelineBarTarget::SeriesGroup { name: series.to_string() },
        )
    })
}

/// series_group 未設定でも同じ CD (cd_series) に 2 曲以上あるものは実質シリーズとして
/// 1 本の帯にする (帯の中身が読めない「その他のリリース」丸めをやめた経緯は Swift 原本
/// のコメント参照)。元 SQL: `WHERE IFNULL(series_group,'') = '' AND
/// IFNULL(cd_series,'') != '' AND IFNULL(release_date,'') != '' [AND brand_id = ?]
/// GROUP BY brand_id, cd_series HAVING COUNT(*) >= 2 ORDER BY MIN(release_date)`。
fn cd_series_bars(
    snap: &Snapshot,
    brand_id: Option<&str>,
    colors: &HashMap<&str, &str>,
) -> Vec<TimelineBarRecord> {
    let mut groups: BTreeMap<(Option<&str>, &str), ReleaseGroup<'_>> = BTreeMap::new();
    for song in &snap.songs {
        if non_blank(&song.series_group).is_some() {
            continue;
        }
        let Some(cd) = non_blank(&song.cd_series) else { continue };
        let Some(date) = non_blank(&song.release_date) else { continue };
        if brand_id.is_some_and(|b| song.brand_id.as_deref() != Some(b)) {
            continue;
        }
        groups
            .entry((song.brand_id.as_deref(), cd))
            .and_modify(|g| g.add(date))
            .or_insert_with(|| ReleaseGroup::seed(date));
    }
    groups.retain(|_, g| g.count >= 2); // HAVING COUNT(*) >= 2
    grouped_release_bars(groups, colors, |brand, cd, _| {
        (
            format!("cds_{}_{}", brand.unwrap_or("-"), cd),
            cd.to_string(),
            cd.to_string(),
            TimelineBarTarget::CdSeries { name: cd.to_string() },
        )
    })
}

/// どのシリーズにも CD にも束ねられない単発リリースを年ごとに 1 本へまとめる
/// (ここを省くとシリーズ表記の薄いブランドで楽曲レーンがスカスカに見える — Swift 原本)。
///
/// 元 SQL: `WHERE IFNULL(series_group,'') = '' AND IFNULL(release_date,'') != ''
///  AND (IFNULL(cd_series,'') = '' OR <同一 brand・同一 cd_series の曲数> = 1)
///  [AND brand_id = ?] GROUP BY brand_id, STRFTIME('%Y', release_date) ORDER BY year`。
///
/// 相関サブクエリの「同じ CD が 1 曲しかない」判定は、全曲を 1 パスした
/// (brand, cd_series) → 曲数マップで置き換える (サブクエリは外側の brand 絞りに
/// 依存しないので、brand_id 引数に関わらず全曲で数えるのが正)。
fn one_off_release_bars(
    snap: &Snapshot,
    brand_id: Option<&str>,
    colors: &HashMap<&str, &str>,
) -> Vec<TimelineBarRecord> {
    // `t.brand_id IS s.brand_id` は NULL 同士も一致する IS 比較 → Option の == と同じ。
    // `t.cd_series = s.cd_series` は = 比較なので NULL の cd_series は数えない。
    let mut bundle_counts: HashMap<(Option<&str>, &str), u32> = HashMap::new();
    for song in &snap.songs {
        if non_blank(&song.series_group).is_some() || non_blank(&song.release_date).is_none() {
            continue;
        }
        if let Some(cd) = song.cd_series.as_deref() {
            *bundle_counts.entry((song.brand_id.as_deref(), cd)).or_insert(0) += 1;
        }
    }

    // GROUP BY brand_id, year → ORDER BY year は (year, brand) キーの BTreeMap で
    // 一度に固定する (year 同値のブランド並びは SQL 未規定 → NULL 最小 + id 昇順)。
    let mut groups: BTreeMap<(&str, Option<&str>), ReleaseGroup<'_>> = BTreeMap::new();
    for song in &snap.songs {
        if non_blank(&song.series_group).is_some() {
            continue;
        }
        let Some(date) = non_blank(&song.release_date) else { continue };
        if brand_id.is_some_and(|b| song.brand_id.as_deref() != Some(b)) {
            continue;
        }
        let brand = song.brand_id.as_deref();
        let is_one_off = match non_blank(&song.cd_series) {
            std::option::Option::None => true, // CD 名なし = 束ねる相手がいない
            Some(cd) => bundle_counts.get(&(brand, cd)).copied() == Some(1),
        };
        if !is_one_off {
            continue;
        }
        // STRFTIME が NULL を返す壊れた日付は year NULL グループ行きで、
        // Swift 側 `guard let year` が落としていた — ここで同じく落とす。
        let Some(year) = strftime_year(date) else { continue };
        groups
            .entry((year, brand))
            .and_modify(|g| g.add(date))
            .or_insert_with(|| ReleaseGroup::seed(date));
    }

    let mut bars: Vec<TimelineBarRecord> = Vec::new();
    for ((year, brand), group) in &groups {
        let (Some(start), Some(end)) =
            (epoch_from_date(group.first), epoch_from_date(group.last))
        else {
            continue;
        };
        let marks: BTreeSet<i64> =
            group.dates.iter().filter_map(|d| epoch_from_date(d)).collect();
        bars.push(TimelineBarRecord {
            id: format!("oneoff_{}_{}", brand.unwrap_or("-"), year),
            lane: TimelineBarLane::Music,
            title: "単発リリース".to_string(),
            start_epoch_seconds: start,
            end_epoch_seconds: end,
            mark_epoch_seconds: marks.into_iter().collect(),
            seed_hex: brand.and_then(|b| colors.get(b)).map(|&c| c.to_string()),
            category_key: "oneoff".to_string(),
            badge: Some(format!("{}曲", group.count)),
            target: TimelineBarTarget::ReleaseYear { year: (*year).to_string() },
        });
    }
    bars // BTreeMap 走査が既に (year ASC, brand) 順
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::{Anniversary, Brand, Event, Show, Song};
    use crate::outbound::sqlite_loader::load_snapshot;
    use rusqlite::{Connection, OpenFlags};
    use std::collections::HashSet;
    use std::sync::OnceLock;

    fn db_path() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    /// スナップショットは全テストで共有 (不変なので安全・ロードを 1 回にする)。
    fn snap() -> &'static Snapshot {
        static SNAP: OnceLock<Snapshot> = OnceLock::new();
        SNAP.get_or_init(|| load_snapshot(&db_path()).expect("bundle DB はロードできる"))
    }

    fn conn() -> Connection {
        Connection::open_with_flags(
            db_path(),
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .expect("bundle DB を開ける")
    }

    /// ORDER BY キーが同値の区間を集合として比較する等価判定 (song_list_queries と
    /// 同じ理由: SQLite のソータは安定でなく同値行の並びは未規定。共有コアは
    /// グループキーを最終キーに決定的に並べるため、同値区間は集合で突き合わせる)。
    fn assert_matches_up_to_ties<T, K>(
        label: &str,
        actual: &[T],
        expected: &[T],
        key: impl Fn(&T) -> K,
    ) where
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

    /// 元 SQL の brandColorMap を rusqlite で直接引く (照合の基準側)。
    fn sql_brand_colors(c: &Connection) -> HashMap<String, String> {
        let mut stmt = c
            .prepare("SELECT id, color FROM brands WHERE IFNULL(color,'') != ''")
            .unwrap();
        stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
            .unwrap()
            .map(Result::unwrap)
            .collect()
    }

    /// GROUP_CONCAT のカンマ区切り日付 → epoch 集合 (Swift TimelineDateParser.dates 写経)。
    fn parse_marks(concat: &str) -> Vec<i64> {
        let set: BTreeSet<i64> = concat.split(',').filter_map(epoch_from_date).collect();
        set.into_iter().collect()
    }

    /// ブランド絞りの WHERE 断片 (Swift brandFilter 写経)。
    fn brand_filter(column: &str, brand_id: Option<&str>) -> (String, Vec<String>) {
        match brand_id {
            Some(b) => (format!(" AND {column} = ?"), vec![b.to_string()]),
            None => (String::new(), Vec::new()),
        }
    }

    // ---- 日付ヘルパの挙動ピン留め ----

    #[test]
    fn epoch_from_date_is_jst_midnight() {
        // 2020-01-01 00:00 JST = 2019-12-31 15:00 UTC。
        assert_eq!(epoch_from_date("2020-01-01"), Some(1_577_804_400));
        assert_eq!(epoch_from_date("1970-01-01"), Some(-9 * 3600));
        // Swift prefix(10) と同じく 10 バイト目以降は無視する。
        assert_eq!(epoch_from_date("2020-01-01 18:00"), Some(1_577_804_400));
        assert_eq!(epoch_from_date("2020-1-1"), None); // 桁割れ
        assert_eq!(epoch_from_date("2020-02-30"), None); // 暦として不正
        assert_eq!(epoch_from_date(""), None);
        assert_eq!(epoch_from_date("こんにちは!!"), None); // 非 ASCII 10 バイト超
    }

    #[test]
    fn strftime_year_pins_sqlite_observed_behavior() {
        // sqlite3 実測 (2026-08-25): SELECT STRFTIME('%Y', x) の結果に合わせる。
        assert_eq!(strftime_year("2015-02-31"), Some("2015")); // 月ごとの日数は見ない
        assert_eq!(strftime_year("2015-13-01"), None);
        assert_eq!(strftime_year("2015-00-10"), None);
        assert_eq!(strftime_year("2015-01-32"), None);
        assert_eq!(strftime_year("2015-1-1"), None);
        assert_eq!(strftime_year("2015-01-01 20:00"), Some("2015"));
        assert_eq!(strftime_year("2015-01-01T20:00"), Some("2015"));
        assert_eq!(strftime_year("2015-01-01x"), None);
        assert_eq!(strftime_year("0000-01-01"), Some("0000"));
        // ユリウス日解釈 ('2015' → '-4707') は意図的に非対応 → None (関数 doc 参照)。
        assert_eq!(strftime_year("2015"), None);
    }

    // ---- SQL 照合: 節目 ----

    fn expected_milestone_bars(brand_id: Option<&str>) -> Vec<TimelineBarRecord> {
        let c = conn();
        let colors = sql_brand_colors(&c);
        let (filter_sql, args) = brand_filter("brand_id", brand_id);
        let sql = format!(
            "SELECT id, brand_id, label, date, kind
             FROM anniversaries
             WHERE IFNULL(date,'') != ''{filter_sql}
             ORDER BY date"
        );
        let mut stmt = c.prepare(&sql).unwrap();
        stmt.query_map(rusqlite::params_from_iter(&args), |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, Option<String>>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, Option<String>>(4)?,
            ))
        })
        .unwrap()
        .map(Result::unwrap)
        .filter_map(|(id, brand, label, date, kind)| {
            let epoch = epoch_from_date(&date)?;
            Some(TimelineBarRecord {
                id: format!("ms_{id}"),
                lane: TimelineBarLane::Milestone,
                title: label,
                start_epoch_seconds: epoch,
                end_epoch_seconds: epoch,
                mark_epoch_seconds: vec![epoch],
                seed_hex: brand.as_ref().and_then(|b| colors.get(b)).cloned(),
                category_key: kind.unwrap_or_else(|| "milestone".to_string()),
                badge: None,
                target: TimelineBarTarget::None,
            })
        })
        .collect()
    }

    #[test]
    fn milestone_bars_match_sql() {
        for brand in [None, Some("cg"), Some("ml")] {
            let colors = brand_colors(snap());
            let actual = milestone_bars(snap(), brand, &colors);
            let expected = expected_milestone_bars(brand);
            assert!(brand.is_some() || !expected.is_empty(), "全件が空だと照合にならない");
            assert_matches_up_to_ties(
                &format!("milestones brand={brand:?}"),
                &actual,
                &expected,
                |b| b.start_epoch_seconds,
            );
        }
    }

    // ---- SQL 照合: イベント ----

    fn expected_event_bars(brand_id: Option<&str>) -> Vec<TimelineBarRecord> {
        let c = conn();
        let colors = sql_brand_colors(&c);
        let (filter_sql, args) = brand_filter("e.brand_id", brand_id);
        let sql = format!(
            "SELECT e.id, e.name, e.brand_id, e.kind,
                    MIN(s.date) AS first_date, MAX(s.date) AS last_date,
                    COUNT(s.id) AS show_count,
                    GROUP_CONCAT(s.date) AS dates
             FROM events e
             JOIN shows s ON s.event_id = e.id
             WHERE IFNULL(s.date,'') != ''{filter_sql}
             GROUP BY e.id
             ORDER BY first_date"
        );
        let mut stmt = c.prepare(&sql).unwrap();
        stmt.query_map(rusqlite::params_from_iter(&args), |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Option<String>>(2)?,
                r.get::<_, Option<String>>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, String>(5)?,
                r.get::<_, i64>(6)?,
                r.get::<_, String>(7)?,
            ))
        })
        .unwrap()
        .map(Result::unwrap)
        .filter_map(|(id, name, brand, kind, first, last, show_count, dates)| {
            let start = epoch_from_date(&first)?;
            let end = epoch_from_date(&last)?;
            let kind = kind.unwrap_or_else(|| "live".to_string());
            Some(TimelineBarRecord {
                id: format!("ev_{id}"),
                lane: lane_for_event_kind(&kind),
                // core は正式名称のまま返す (eventDisplayName はアダプタ責務 — モジュール doc)。
                title: name,
                start_epoch_seconds: start,
                end_epoch_seconds: end,
                mark_epoch_seconds: parse_marks(&dates),
                seed_hex: brand.as_ref().and_then(|b| colors.get(b)).cloned(),
                category_key: brand.clone().unwrap_or(kind),
                badge: (show_count > 1).then(|| format!("{show_count}公演")),
                target: TimelineBarTarget::Event { id },
            })
        })
        .collect()
    }

    #[test]
    fn event_bars_match_sql() {
        for brand in [None, Some("cg"), Some("765as")] {
            let colors = brand_colors(snap());
            let actual = event_bars(snap(), brand, &colors);
            let expected = expected_event_bars(brand);
            assert!(!expected.is_empty(), "brand={brand:?} で空だと照合にならない");
            assert_matches_up_to_ties(
                &format!("events brand={brand:?}"),
                &actual,
                &expected,
                |b| b.start_epoch_seconds,
            );
        }
    }

    // ---- 回帰: イベント帯 title は正式名称のまま (意図的な Swift 差分の固定) ----

    /// iOS `Extensions/EventDisplayName.swift` の作品名プレフィックス一覧の写し。
    /// core が省略を「していない」ことを実データで証明するためだけに使う。
    const EVENT_DISPLAY_PREFIXES: [&str; 12] = [
        "THE IDOLM@STER CINDERELLA GIRLS ",
        "THE IDOLM@STER MILLION LIVE! ",
        "THE IDOLM@STER MILLION LIVE!",
        "THE IDOLM@STER SideM ",
        "THE IDOLM@STER SHINY COLORS ",
        "THE IDOLM@STER ",
        "アイドルマスター シンデレラガールズ ",
        "アイドルマスター ミリオンライブ! ",
        "アイドルマスター シャイニーカラーズ ",
        "アイドルマスター SideM ",
        "学園アイドルマスター ",
        "アイドルマスター ",
    ];

    /// Swift `eventDisplayName` (省略設定 ON 時) の写経 (テスト専用)。
    /// 最初に一致した 1 プレフィックスだけ除去し、除去後 2 文字未満なら元の名前。
    fn swift_event_display_name(name: &str) -> &str {
        for prefix in EVENT_DISPLAY_PREFIXES {
            if let Some(rest) = name.strip_prefix(prefix) {
                let stripped = rest.trim();
                return if stripped.chars().count() >= 2 { stripped } else { name };
            }
        }
        name
    }

    /// 移送時の意図的な差分の回帰固定: Swift 原本はフェッチ時に eventDisplayName
    /// (作品名プレフィックス省略) を掛けていたが、core は events.name の正式名称を
    /// そのまま返す。省略は UserDefaults 依存の表示状態なのでアダプタが
    /// `target == Event` の帯にだけ適用する契約 (モジュール doc)。
    /// core 側で省略を始めるとアダプタと二重適用になり、逆にアダプタが忘れると
    /// 帯タイトルが長い正式名称に化ける — 前者をここで、後者をアダプタ側の
    /// テストで検出する分担。省略対象の実データで「未加工のまま」を発火させる。
    #[test]
    fn event_bar_titles_stay_official_names() {
        let c = conn();
        let mut stmt = c.prepare("SELECT id, name FROM events").unwrap();
        let names: HashMap<String, String> = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
            .unwrap()
            .map(Result::unwrap)
            .collect();

        let colors = brand_colors(snap());
        let bars = event_bars(snap(), None, &colors);
        let mut abbreviation_would_change = 0usize;
        for bar in &bars {
            let TimelineBarTarget::Event { id } = &bar.target else {
                unreachable!("イベント帯の target は必ず Event ({})", bar.id);
            };
            let official = &names[id];
            assert_eq!(&bar.title, official, "ev_{id}: title は events.name 未加工のまま");
            if swift_event_display_name(official) != official.as_str() {
                abbreviation_would_change += 1;
            }
        }
        // 省略対象の名前が実在してこそ「未加工」の照合が回帰を守る
        // (2026-08 bundle では 600 件超が該当)。
        assert!(
            abbreviation_would_change > 0,
            "eventDisplayName が短縮するはずの名前が bundle に 1 件も無いと回帰を検出できない"
        );
    }

    // ---- SQL 照合: series / cdSeries / oneOff ----

    /// series / cdSeries の集計行 → 期待レコード (Swift の帯組み立て写経)。
    #[allow(clippy::too_many_arguments)]
    fn release_bar(
        colors: &HashMap<String, String>,
        id_prefix: &str,
        name: String,
        brand: Option<String>,
        count: i64,
        first: &str,
        last: &str,
        dates: &str,
        target: TimelineBarTarget,
    ) -> Option<TimelineBarRecord> {
        let start = epoch_from_date(first)?;
        let end = epoch_from_date(last)?;
        Some(TimelineBarRecord {
            id: format!("{id_prefix}_{}_{}", brand.as_deref().unwrap_or("-"), name),
            lane: TimelineBarLane::Music,
            title: name.clone(),
            start_epoch_seconds: start,
            end_epoch_seconds: end,
            mark_epoch_seconds: parse_marks(dates),
            seed_hex: brand.as_ref().and_then(|b| colors.get(b)).cloned(),
            category_key: name,
            badge: Some(format!("{count}曲")),
            target,
        })
    }

    fn expected_series_bars(brand_id: Option<&str>) -> Vec<TimelineBarRecord> {
        let c = conn();
        let colors = sql_brand_colors(&c);
        let (filter_sql, args) = brand_filter("brand_id", brand_id);
        let sql = format!(
            "SELECT series_group, brand_id,
                    COUNT(*) AS song_count,
                    MIN(release_date) AS first_date, MAX(release_date) AS last_date,
                    GROUP_CONCAT(DISTINCT release_date) AS dates
             FROM songs
             WHERE IFNULL(series_group,'') != '' AND IFNULL(release_date,'') != ''{filter_sql}
             GROUP BY brand_id, series_group
             ORDER BY first_date"
        );
        let mut stmt = c.prepare(&sql).unwrap();
        stmt.query_map(rusqlite::params_from_iter(&args), |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, Option<String>>(1)?,
                r.get::<_, i64>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, String>(5)?,
            ))
        })
        .unwrap()
        .map(Result::unwrap)
        .filter_map(|(series, brand, count, first, last, dates)| {
            let target = TimelineBarTarget::SeriesGroup { name: series.clone() };
            release_bar(&colors, "sg", series, brand, count, &first, &last, &dates, target)
        })
        .collect()
    }

    #[test]
    fn series_bars_match_sql() {
        for brand in [None, Some("ml")] {
            let colors = brand_colors(snap());
            let actual = series_bars(snap(), brand, &colors);
            let expected = expected_series_bars(brand);
            assert!(!expected.is_empty(), "brand={brand:?} で空だと照合にならない");
            assert_matches_up_to_ties(
                &format!("series brand={brand:?}"),
                &actual,
                &expected,
                |b| b.start_epoch_seconds,
            );
        }
    }

    fn expected_cd_series_bars(brand_id: Option<&str>) -> Vec<TimelineBarRecord> {
        let c = conn();
        let colors = sql_brand_colors(&c);
        let (filter_sql, args) = brand_filter("brand_id", brand_id);
        let sql = format!(
            "SELECT cd_series, brand_id,
                    COUNT(*) AS song_count,
                    MIN(release_date) AS first_date, MAX(release_date) AS last_date,
                    GROUP_CONCAT(DISTINCT release_date) AS dates
             FROM songs
             WHERE IFNULL(series_group,'') = '' AND IFNULL(cd_series,'') != ''
               AND IFNULL(release_date,'') != ''{filter_sql}
             GROUP BY brand_id, cd_series
             HAVING COUNT(*) >= 2
             ORDER BY first_date"
        );
        let mut stmt = c.prepare(&sql).unwrap();
        stmt.query_map(rusqlite::params_from_iter(&args), |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, Option<String>>(1)?,
                r.get::<_, i64>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, String>(5)?,
            ))
        })
        .unwrap()
        .map(Result::unwrap)
        .filter_map(|(cd, brand, count, first, last, dates)| {
            let target = TimelineBarTarget::CdSeries { name: cd.clone() };
            release_bar(&colors, "cds", cd, brand, count, &first, &last, &dates, target)
        })
        .collect()
    }

    #[test]
    fn cd_series_bars_match_sql() {
        for brand in [None, Some("cg")] {
            let colors = brand_colors(snap());
            let actual = cd_series_bars(snap(), brand, &colors);
            let expected = expected_cd_series_bars(brand);
            assert!(!expected.is_empty(), "brand={brand:?} で空だと照合にならない");
            assert_matches_up_to_ties(
                &format!("cd_series brand={brand:?}"),
                &actual,
                &expected,
                |b| b.start_epoch_seconds,
            );
        }
    }

    fn expected_one_off_bars(brand_id: Option<&str>) -> Vec<TimelineBarRecord> {
        let c = conn();
        let colors = sql_brand_colors(&c);
        let (filter_sql, args) = brand_filter("brand_id", brand_id);
        let sql = format!(
            "SELECT STRFTIME('%Y', release_date) AS year,
                    brand_id,
                    COUNT(*) AS song_count,
                    MIN(release_date) AS first_date, MAX(release_date) AS last_date,
                    GROUP_CONCAT(DISTINCT release_date) AS dates
             FROM songs s
             WHERE IFNULL(s.series_group,'') = '' AND IFNULL(s.release_date,'') != ''
               AND (
                     IFNULL(s.cd_series,'') = ''
                  OR (SELECT COUNT(*) FROM songs t
                       WHERE IFNULL(t.series_group,'') = ''
                         AND t.brand_id IS s.brand_id
                         AND t.cd_series = s.cd_series
                         AND IFNULL(t.release_date,'') != '') = 1
                   ){filter_sql}
             GROUP BY brand_id, year
             ORDER BY year"
        );
        let mut stmt = c.prepare(&sql).unwrap();
        stmt.query_map(rusqlite::params_from_iter(&args), |r| {
            Ok((
                r.get::<_, Option<String>>(0)?,
                r.get::<_, Option<String>>(1)?,
                r.get::<_, i64>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, String>(5)?,
            ))
        })
        .unwrap()
        .map(Result::unwrap)
        .filter_map(|(year, brand, count, first, last, dates)| {
            let year = year?; // Swift `guard let year` — STRFTIME NULL の行は落ちる
            let start = epoch_from_date(&first)?;
            let end = epoch_from_date(&last)?;
            Some(TimelineBarRecord {
                id: format!("oneoff_{}_{}", brand.as_deref().unwrap_or("-"), year),
                lane: TimelineBarLane::Music,
                title: "単発リリース".to_string(),
                start_epoch_seconds: start,
                end_epoch_seconds: end,
                mark_epoch_seconds: parse_marks(&dates),
                seed_hex: brand.as_ref().and_then(|b| colors.get(b)).cloned(),
                category_key: "oneoff".to_string(),
                badge: Some(format!("{count}曲")),
                target: TimelineBarTarget::ReleaseYear { year },
            })
        })
        .collect()
    }

    #[test]
    fn one_off_bars_match_sql() {
        for brand in [None, Some("sidem")] {
            let colors = brand_colors(snap());
            let actual = one_off_release_bars(snap(), brand, &colors);
            let expected = expected_one_off_bars(brand);
            assert!(!expected.is_empty(), "brand={brand:?} で空だと照合にならない");
            assert_matches_up_to_ties(
                &format!("one_off brand={brand:?}"),
                &actual,
                &expected,
                |b| match &b.target {
                    TimelineBarTarget::ReleaseYear { year } => year.clone(),
                    _ => unreachable!("oneOff の target は必ず ReleaseYear"),
                },
            );
        }
    }

    // ---- 連結順・全体形状 ----

    #[test]
    fn timeline_bars_concatenates_in_swift_order() {
        let bars = timeline_bars(snap(), None);
        let colors = brand_colors(snap());
        let concatenated: Vec<TimelineBarRecord> = [
            milestone_bars(snap(), None, &colors),
            event_bars(snap(), None, &colors),
            series_bars(snap(), None, &colors),
            cd_series_bars(snap(), None, &colors),
            one_off_release_bars(snap(), None, &colors),
        ]
        .into_iter()
        .flatten()
        .collect();
        assert_eq!(bars, concatenated, "Swift 原本の + 連結順のまま");

        // 未知ブランドは全レーン空 (WHERE brand_id = ? が全行不一致)。
        assert!(timeline_bars(snap(), Some("存在しないブランド")).is_empty());

        // ブランド絞りは全件の部分集合 (id 基準)。
        let all_ids: HashSet<String> = bars.iter().map(|b| b.id.clone()).collect();
        let cg = timeline_bars(snap(), Some("cg"));
        assert!(!cg.is_empty());
        assert!(cg.iter().all(|b| all_ids.contains(&b.id)));

        // 帯の不変条件: 期間は非逆転、marks は期間内・昇順・重複なし。
        for bar in &bars {
            assert!(bar.start_epoch_seconds <= bar.end_epoch_seconds, "{}", bar.id);
            assert!(!bar.mark_epoch_seconds.is_empty(), "{}", bar.id);
            assert!(
                bar.mark_epoch_seconds.windows(2).all(|w| w[0] < w[1]),
                "{}: marks は昇順・重複なし",
                bar.id
            );
            assert!(
                bar.mark_epoch_seconds.first().copied() >= Some(bar.start_epoch_seconds)
                    && bar.mark_epoch_seconds.last().copied() <= Some(bar.end_epoch_seconds),
                "{}: marks は期間内",
                bar.id
            );
        }
    }

    // ---- 合成スナップショットでの境界ケース (bundle に無いデータ形を固定する) ----

    /// bundle には NULL brand の曲・空日付 show などが無いので、SQL との照合では
    /// 通らない分岐を合成データで固定する。
    fn synthetic_snapshot() -> Snapshot {
        fn song(id: &str, brand: Option<&str>, series: Option<&str>, cd: Option<&str>, date: Option<&str>) -> Song {
            Song {
                id: id.into(),
                title: id.into(),
                title_kana: None,
                brand_id: brand.map(Into::into),
                song_type: None,
                release_date: date.map(Into::into),
                duration_sec: None,
                composer: None,
                lyricist: None,
                arranger: None,
                cd_series: cd.map(Into::into),
                cd_title: None,
                artwork_url: None,
                preview_url: None,
                apple_music_id: None,
                apple_music_album_id: None,
                isrc: None,
                lyrics_url: None,
                parent_song_id: None,
                singer_label: None,
                unit_name: None,
                unit_id: None,
                series_group: series.map(Into::into),
                jasrac_code: None,
            }
        }

        let mut snap = Snapshot {
            brands: vec![Brand {
                id: "cg".into(),
                name: "シンデレラガールズ".into(),
                short_name: "CG".into(),
                color: Some("#2681C8".into()),
                sort_order: 1,
                icon_url: None,
            }],
            anniversaries: vec![
                Anniversary {
                    id: "a1".into(),
                    brand_id: "cg".into(),
                    label: "空日付は帯にならない".into(),
                    date: String::new(),
                    kind: "service".into(),
                    sort_order: 0,
                },
                Anniversary {
                    id: "a2".into(),
                    brand_id: "unknown".into(),
                    label: "色マップ外ブランド".into(),
                    date: "2011-11-28".into(),
                    kind: "service".into(),
                    sort_order: 0,
                },
            ],
            events: vec![Event {
                id: "e1".into(),
                brand_id: Some("cg".into()),
                name: "空日付公演だけのイベント".into(),
                event_type: "live".into(),
                is_streaming: false,
                is_solo: false,
                kind: "live".into(),
                ticket_open_date: None,
                ticket_deadline: None,
                ticket_lottery_date: None,
                ticket_url: None,
                joint_brand_ids: None,
                has_streaming: None,
                has_live_viewing: None,
            }],
            shows: vec![Show {
                id: "s1".into(),
                event: 0,
                name: "DAY1".into(),
                date: String::new(), // IFNULL(s.date,'') != '' で JOIN から消える
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
            }],
            songs: vec![
                // NULL brand 同士は `t.brand_id IS s.brand_id` で束なる → 2 曲 CD は cds 帯
                song("n1", None, None, Some("無所属CD"), Some("2020-01-01")),
                song("n2", None, None, Some("無所属CD"), Some("2020-03-01")),
                // 同名 CD でもブランドが違えば別グループ → 1 曲なので oneOff 行き
                song("c1", Some("cg"), None, Some("無所属CD"), Some("2020-02-02")),
                // 同日 2 リリース: marks は畳まれ、badge の曲数は 2 のまま
                song("d1", None, None, None, Some("2021-05-05")),
                song("d2", None, None, None, Some("2021-05-05")),
            ],
            ..Snapshot::default()
        };
        snap.anniversary_order = vec![0, 1]; // (date ASC, 添字): "" < "2011-11-28"
        snap.shows_by_event = vec![vec![0]];
        snap
    }

    #[test]
    fn synthetic_edges_null_brand_and_blank_dates() {
        let snap = synthetic_snapshot();
        let bars = timeline_bars(&snap, None);

        // 空日付の節目・空日付公演しか持たないイベントは帯にならない。
        // 色マップ外ブランドの節目は seed 無しで残る。
        let ids: Vec<&str> = bars.iter().map(|b| b.id.as_str()).collect();
        // oneOff の順は (year ASC, brand: NULL 最小): 2020(cg) が 2021(NULL) より先。
        assert_eq!(ids, vec!["ms_a2", "cds_-_無所属CD", "oneoff_cg_2020", "oneoff_-_2021"]);
        assert_eq!(bars[0].seed_hex, None);

        // NULL brand の 2 曲 CD: id の brand 部は "-"、期間は 1 月〜3 月。
        let cds = &bars[1];
        assert_eq!(cds.badge.as_deref(), Some("2曲"));
        assert_eq!(cds.mark_epoch_seconds.len(), 2);
        assert_eq!(cds.seed_hex, None);
        assert_eq!(cds.target, TimelineBarTarget::CdSeries { name: "無所属CD".into() });

        // cg の 1 曲 CD は同名でもブランド違いで束ならず oneOff 行き (IS 比較の写し)。
        assert_eq!(bars[2].seed_hex.as_deref(), Some("#2681C8"));
        assert_eq!(bars[2].target, TimelineBarTarget::ReleaseYear { year: "2020".into() });

        // 同日 2 リリース: marks は 1 点に畳まれ、badge の曲数は 2 のまま。
        let none_brand = &bars[3];
        assert_eq!(none_brand.badge.as_deref(), Some("2曲"));
        assert_eq!(none_brand.mark_epoch_seconds.len(), 1);
        assert_eq!(none_brand.start_epoch_seconds, none_brand.end_epoch_seconds);

        // ブランド絞り: NULL brand の曲は `brand_id = ?` に一致しない。
        let cg_only = timeline_bars(&snap, Some("cg"));
        let cg_ids: Vec<&str> = cg_only.iter().map(|b| b.id.as_str()).collect();
        assert_eq!(cg_ids, vec!["oneoff_cg_2020"]);
    }
}
