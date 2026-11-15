//! 予習 DJ — 公演 1 つぶんの「流す順」を組む。
//!
//! 2026-11 ユーザー「自動でいい感じに予習セトリをDJしてくれる機能とかも欲しい」。
//!
//! - **開催前 (セトリがまだ無い)**: 機械予測 ([`crate::domain::setlist_forecast`]) の上位を、
//!   本番のセトリらしい流れに並べ直す (予習)。
//! - **セトリがある**: 披露順のまま流す (復習)。並べ替えない。
//!
//! # 並べ方 (予習)
//!
//! 予測の順位は「来そうな順」で、流す順ではない。曲ごとの過去の位置
//! ([`crate::domain::setlist_shape::song_position_profile`]) で置き場を決める:
//!
//! 1. 1 曲目だった回数がいちばん多い曲を頭に置く。
//! 2. 披露の半分以上がアンコールだった曲はアンコールへ (最大 [`MAX_ENCORE`] 曲)。
//! 3. 残りは「序盤 / 中盤 / 終盤のどこで歌われてきたか」の平均の早い順。同じなら予測の順位。
//!    披露が無い曲 (新曲) は真ん中に置く。
//!
//! これは予想ではなく、過去の位置をなぞった並び。当たり外れを言うのは予測の側。
//!
//! # 一言 (fact)
//!
//! 各曲に添える一言は DB の事実だけで作る (予測の理由・オリメン・過去の位置)。
//! 利用者の ChatGPT プランで組んだ流れ ([`crate::agent::tools::prep_dj`]) では、
//! モデルの語り (`talk`) がこれに加わる。事実の行は消さない。

use crate::domain::collection_gap::is_real_live;
use crate::domain::setlist_forecast::{ForecastSongRecord, SetlistForecastRecord};
use crate::domain::setlist_sections::{numbered_setlist, section_label, ENCORE_LABEL};
use crate::domain::setlist_shape::{song_position_profile, Phase, SongPositionProfile};
use crate::domain::snapshot::{Snapshot, Song};
use crate::domain::song_list_queries::is_hidden_variant;
use std::collections::HashSet;

/// 予習で流す曲数 (予測の上位から)。
pub const PREP_TRACKS: usize = 18;
/// 予測から引く曲数。モデルに渡す候補もこの数。
pub const FORECAST_CANDIDATES: u32 = 40;
/// アンコールへ回す曲数の上限。
pub const MAX_ENCORE: usize = 3;
/// モデルが組んだ予習の曲数の上限。復習はセトリの全曲を流すので切らない。
pub const MAX_TRACKS: usize = 40;

/// 何を元に並べたか。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrepDjSource {
    /// 機械予測の上位 (予習)。
    Forecast,
    /// 公開済みのセトリ (復習)。
    Setlist,
}

impl PrepDjSource {
    /// 画面の題・入口の名前。
    pub fn heading(self) -> &'static str {
        match self {
            Self::Forecast => "予習 DJ",
            Self::Setlist => "復習 DJ",
        }
    }
}

/// 流れのどこか。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrepDjPart {
    Opening,
    Middle,
    Closing,
    Encore,
}

impl PrepDjPart {
    pub fn label(self) -> &'static str {
        match self {
            Self::Opening => "開幕",
            Self::Middle => "中盤",
            Self::Closing => "終盤",
            Self::Encore => ENCORE_LABEL,
        }
    }

    /// モデルとやり取りする鍵。
    pub fn key(self) -> &'static str {
        match self {
            Self::Opening => "opening",
            Self::Middle => "middle",
            Self::Closing => "closing",
            Self::Encore => "encore",
        }
    }

    pub fn parse(key: &str) -> Option<Self> {
        [Self::Opening, Self::Middle, Self::Closing, Self::Encore].into_iter().find(|p| p.key() == key)
    }

    /// 本編 `total` 曲の `index` 番目 (0 始まり) がどこか。3 等分。
    pub fn of_main(index: usize, total: usize) -> Self {
        match Phase::of(index + 1, total) {
            Phase::Early => Self::Opening,
            Phase::Middle => Self::Middle,
            Phase::Late => Self::Closing,
        }
    }
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct PrepDjTrack {
    pub song_id: String,
    pub title: String,
    pub artwork_url: Option<String>,
    pub brand_id: Option<String>,
    /// Apple Music の id。無い曲は Apple Music では飛ばす (Spotify は曲名で探す)。
    pub apple_music_id: Option<String>,
    pub part: PrepDjPart,
    /// `part` の見出し (「開幕」)。
    pub part_label: String,
    /// この行から新しい塊が始まるか (先頭は必ず true)。画面は見出しを置くだけ。
    pub starts_part: bool,
    /// DB の事実だけで作った一言。空のこともある。
    pub fact: String,
    /// モデルの語り。コアが組んだ流れでは空。
    pub talk: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct PrepDjPlan {
    pub show_id: String,
    /// 画面の題 (「予習 DJ」「復習 DJ」)。
    pub heading: String,
    /// 流れの名前 (「◯◯ DAY1 の予習」。モデルが付けたものはそれ)。
    pub title: String,
    pub source: PrepDjSource,
    /// 「予測の上位から 18 曲 · 約 82 分」。
    pub summary: String,
    /// 公演の印の注記 (出演者未発表など)。無ければ空。
    pub note: String,
    pub tracks: Vec<PrepDjTrack>,
    /// モデルが組んだ流れか。
    pub by_model: bool,
    /// モデルの答えのうち、DB に無くて落とした曲数。
    pub dropped: u32,
}

/// 公演 1 つの流れをコアだけで組む。
///
/// - セトリがあればその順 (復習)。`forecast` は見ない。
/// - 無ければ `forecast` の上位を並べ直す (予習)。`forecast` が None (予測できない公演) なら None。
/// - 公演が無いとき、セトリが無くてリアルライブでないときも None。
pub fn base_plan(snap: &Snapshot, show_id: &str, forecast: Option<&SetlistForecastRecord>) -> Option<PrepDjPlan> {
    let &show = snap.show_index_by_id.get(show_id)?;
    // セトリがあれば、リアルライブでなくても (リリースイベントなど) 披露順に流せる。
    if !snap.setlist_items_by_show[show as usize].is_empty() {
        return Some(setlist_plan(snap, show));
    }
    if !is_real_live(snap, show) {
        return None;
    }
    let forecast = forecast?;
    let picks: Vec<&ForecastSongRecord> = forecast
        .songs
        .iter()
        .filter(|s| snap.song(&s.song_id).is_some_and(|song| !is_hidden_variant(song)))
        .take(PREP_TRACKS)
        .collect();
    if picks.is_empty() {
        return None;
    }
    let ordered = flow_order(snap, &picks);
    let tracks = ordered
        .into_iter()
        .filter_map(|(part, pick)| {
            let song = snap.song(&pick.song_id)?;
            Some(track(song, part, forecast_fact(snap, pick), String::new()))
        })
        .collect();
    Some(finish(snap, show, PrepDjSource::Forecast, tracks, forecast_note(forecast), None, 0))
}

/// 入口に出す名前 (「予習 DJ」「復習 DJ」)。流れを組めない公演は None (入口を出さない)。
///
/// 予測は引かない (重いので)。セトリが無いリアルライブは「予習 DJ」を返すが、
/// 予測できない公演 (日付が読めないなど) は開いた先で「組めません」になる。
pub fn entry_label(snap: &Snapshot, show_id: &str) -> Option<&'static str> {
    let &show = snap.show_index_by_id.get(show_id)?;
    if !snap.setlist_items_by_show[show as usize].is_empty() {
        return Some(PrepDjSource::Setlist.heading());
    }
    is_real_live(snap, show).then(|| PrepDjSource::Forecast.heading())
}

/// 公演の印の注記 (出演者未発表)。
pub fn forecast_note(forecast: &SetlistForecastRecord) -> String {
    use crate::domain::setlist_forecast::ForecastShowFlag;
    forecast.flags.iter().find(|f| f.flag == ForecastShowFlag::CastUnannounced).map(|f| f.label.clone()).unwrap_or_default()
}

/// 予測の上位を、流す順と置き場に並べ直す。
fn flow_order<'a>(snap: &Snapshot, picks: &[&'a ForecastSongRecord]) -> Vec<(PrepDjPart, &'a ForecastSongRecord)> {
    let profiles: Vec<SongPositionProfile> = picks.iter().map(|p| song_position_profile(snap, &p.song_id)).collect();

    // 1. 頭: 1 曲目だった回数がいちばん多い曲 (同数は予測の順位が上)。
    let opener = (0..picks.len()).filter(|&i| profiles[i].opener > 0).max_by(|&a, &b| {
        profiles[a].opener.cmp(&profiles[b].opener).then(b.cmp(&a))
    });

    // 2. アンコール: 披露の半分以上がアンコールだった曲。多い順に上限まで。
    let mut encore: Vec<usize> = (0..picks.len())
        .filter(|&i| Some(i) != opener)
        .filter(|&i| profiles[i].encore > 0 && profiles[i].encore * 2 >= profiles[i].performances)
        .collect();
    encore.sort_by(|&a, &b| profiles[b].encore.cmp(&profiles[a].encore).then(a.cmp(&b)));
    encore.truncate(MAX_ENCORE);
    // アンコールの中は「最後の曲だった回数」の少ない順 (締めの曲を最後に)。
    encore.sort_by(|&a, &b| profiles[a].closer.cmp(&profiles[b].closer).then(a.cmp(&b)));

    // 3. 残り: 過去の位置の平均の早い順。
    let mut main: Vec<usize> = (0..picks.len()).filter(|&i| Some(i) != opener && !encore.contains(&i)).collect();
    main.sort_by(|&a, &b| mean_phase(&profiles[a]).total_cmp(&mean_phase(&profiles[b])).then(a.cmp(&b)));
    if let Some(o) = opener {
        main.insert(0, o);
    }

    let total = main.len();
    let mut out: Vec<(PrepDjPart, &ForecastSongRecord)> =
        main.into_iter().enumerate().map(|(i, p)| (PrepDjPart::of_main(i, total), picks[p])).collect();
    out.extend(encore.into_iter().map(|p| (PrepDjPart::Encore, picks[p])));
    out
}

/// 序盤 0 / 中盤 1 / 終盤 2 の平均。披露が無い曲は真ん中 (1)。
fn mean_phase(p: &SongPositionProfile) -> f64 {
    let total: u32 = p.phases.iter().sum();
    if total == 0 {
        return 1.0;
    }
    f64::from(p.phase(Phase::Middle) + p.phase(Phase::Late) * 2) / f64::from(total)
}

/// セトリの順のまま (復習)。同じ曲が 2 回あれば最初の 1 回だけ。
fn setlist_plan(snap: &Snapshot, show: u32) -> PrepDjPlan {
    let rows: Vec<(usize, u32)> = numbered_setlist(snap, show).collect();
    let main_total = rows
        .iter()
        .filter(|&&(_, item)| !is_encore(snap.setlist_items[item as usize].section.as_deref()))
        .count();
    let mut seen: HashSet<u32> = HashSet::new();
    let mut main_index = 0usize;
    let mut tracks = Vec::new();
    for (rank, item) in rows {
        let it = &snap.setlist_items[item as usize];
        let encore = is_encore(it.section.as_deref());
        let part = if encore { PrepDjPart::Encore } else { PrepDjPart::of_main(main_index, main_total) };
        if !encore {
            main_index += 1;
        }
        if !seen.insert(it.song) {
            continue;
        }
        tracks.push(track(&snap.songs[it.song as usize], part, format!("{rank} 曲目"), String::new()));
    }
    finish(snap, show, PrepDjSource::Setlist, tracks, String::new(), None, 0)
}

fn is_encore(section: Option<&str>) -> bool {
    section_label(section).as_deref() == Some(ENCORE_LABEL)
}

/// 予測の 1 曲の一言: 予測の理由・オリメン・過去の位置。
pub fn forecast_fact(snap: &Snapshot, pick: &ForecastSongRecord) -> String {
    let mut parts: Vec<String> = pick.reasons.iter().take(2).map(|r| r.label.clone()).collect();
    if let Some(o) = &pick.originals {
        let line = if o.names_listed { o.label.clone() } else if o.summary.is_empty() { String::new() } else { format!("オリメン {}", o.summary) };
        if !line.is_empty() {
            parts.push(line);
        }
    }
    let position = position_fact(&song_position_profile(snap, &pick.song_id));
    if !position.is_empty() {
        parts.push(position);
    }
    parts.join(" · ")
}

/// 過去の位置の一言 (「披露 24 回 · 1 曲目 9 回」)。披露が無ければ空。
pub fn position_fact(p: &SongPositionProfile) -> String {
    if p.performances == 0 {
        return String::new();
    }
    let mut out = format!("披露 {} 回", p.performances);
    // いちばん目立つ位置を 1 つだけ添える。
    let spots = [(p.opener, "1 曲目"), (p.encore, ENCORE_LABEL), (p.closer, "最後の曲")];
    if let Some((n, name)) = spots.into_iter().filter(|(n, _)| *n >= 2).max_by_key(|(n, _)| *n) {
        out.push_str(&format!(" · {name} {n} 回"));
    }
    out
}

pub fn track(song: &Song, part: PrepDjPart, fact: String, talk: String) -> PrepDjTrack {
    PrepDjTrack {
        song_id: song.id.clone(),
        title: song.title.clone(),
        artwork_url: song.artwork_url.clone(),
        brand_id: song.brand_id.clone(),
        apple_music_id: song.apple_music_id.clone().filter(|s| !s.is_empty()),
        part,
        part_label: part.label().to_string(),
        starts_part: false,
        fact,
        talk,
    }
}

/// 塊の頭の印・題・要約を付けて仕上げる。`title` が None か空ならコアの題。
pub fn finish(
    snap: &Snapshot,
    show: u32,
    source: PrepDjSource,
    mut tracks: Vec<PrepDjTrack>,
    note: String,
    title: Option<String>,
    dropped: u32,
) -> PrepDjPlan {
    let mut previous: Option<PrepDjPart> = None;
    for t in &mut tracks {
        t.starts_part = previous != Some(t.part);
        previous = Some(t.part);
    }
    let by_model = title.is_some();
    let heading = source.heading();
    let (verb, from) = match source {
        PrepDjSource::Forecast => ("予習", if by_model { "予測を元に" } else { "予測の上位から" }),
        PrepDjSource::Setlist => ("復習", "セトリの順に"),
    };
    let default_title = format!("{} の{verb}", show_title(snap, show));
    PrepDjPlan {
        show_id: snap.shows[show as usize].id.clone(),
        heading: heading.to_string(),
        title: title.filter(|t| !t.is_empty()).unwrap_or(default_title),
        source,
        summary: summary(snap, from, &tracks),
        note,
        tracks,
        by_model,
        dropped,
    }
}

/// 「予測の上位から 18 曲 · 約 82 分」。長さの分かる曲が半分に満たなければ分は出さない。
fn summary(snap: &Snapshot, from: &str, tracks: &[PrepDjTrack]) -> String {
    let durations: Vec<i64> =
        tracks.iter().filter_map(|t| snap.song(&t.song_id)?.duration_sec).filter(|&d| d > 0).collect();
    let head = format!("{from} {} 曲", tracks.len());
    if durations.is_empty() || durations.len() * 2 < tracks.len() {
        return head;
    }
    // 長さの分からない曲は、分かる曲の平均で埋める。
    let known: i64 = durations.iter().sum();
    let total = known * tracks.len() as i64 / durations.len() as i64;
    format!("{head} · 約 {} 分", (total + 30) / 60)
}

/// 公演の呼び名 (ライブ名 + 公演名。公演名がライブ名と同じ・空ならライブ名だけ)。
pub fn show_title(snap: &Snapshot, show: u32) -> String {
    let s = &snap.shows[show as usize];
    let event = &snap.events[s.event as usize].name;
    match crate::domain::show_naming::distinguishing_show_name(event, &s.name) {
        Some(name) => format!("{event} {name}"),
        None => event.clone(),
    }
}

/// テスト用: セトリがまだ無く、予測できる公演と、その予測 (下ごしらえが重いので 1 回だけ作る)。
#[cfg(test)]
pub(crate) fn test_upcoming_forecast() -> (String, SetlistForecastRecord) {
    use crate::domain::setlist_forecast::ForecastPrep;
    static CACHE: std::sync::OnceLock<(String, SetlistForecastRecord)> = std::sync::OnceLock::new();
    CACHE
        .get_or_init(|| {
            let snap = crate::test_support::bundle_snapshot();
            let prep = ForecastPrep::build(snap);
            snap.shows_in_date_order
                .iter()
                .rev()
                .filter(|&&s| is_real_live(snap, s) && snap.setlist_items_by_show[s as usize].is_empty())
                .find_map(|&s| {
                    let model = prep.train(prep.training_prefix(snap, s)?);
                    let f = crate::domain::setlist_forecast::forecast_show(snap, &prep, &model, s, FORECAST_CANDIDATES)?;
                    (f.songs.len() >= 10).then(|| (snap.shows[s as usize].id.clone(), f))
                })
                .expect("セトリの無い、予測できる公演がある")
        })
        .clone()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;

    /// セトリのある、いちばん新しいリアルライブの公演。
    fn show_with_setlist(snap: &Snapshot) -> String {
        snap.shows_in_date_order
            .iter()
            .rev()
            .find(|&&s| is_real_live(snap, s) && snap.setlist_items_by_show[s as usize].len() >= 10)
            .map(|&s| snap.shows[s as usize].id.clone())
            .expect("セトリのあるライブがある")
    }

    #[test]
    fn セトリがあれば披露順のまま復習になる() {
        let snap = bundle_snapshot();
        let id = show_with_setlist(&snap);
        let plan = base_plan(&snap, &id, None).unwrap();
        assert_eq!(plan.source, PrepDjSource::Setlist);
        assert_eq!(plan.heading, "復習 DJ");
        assert!(plan.title.ends_with("の復習"));
        assert!(!plan.by_model);

        let show = snap.show_index_by_id[&id];
        let mut seen = HashSet::new();
        let expected: Vec<&str> = snap.setlist_items_by_show[show as usize]
            .iter()
            .map(|&i| snap.setlist_items[i as usize].song)
            .filter(|s| seen.insert(*s))
            .map(|s| snap.songs[s as usize].id.as_str())
            .collect();
        let got: Vec<&str> = plan.tracks.iter().map(|t| t.song_id.as_str()).collect();
        assert_eq!(got, expected);
        assert!(plan.tracks[0].starts_part);
        assert!(plan.tracks.iter().all(|t| t.talk.is_empty()));
    }

    #[test]
    fn 予習は予測の上位を重複なく並べ直しアンコールを最後に置く() {
        let snap = bundle_snapshot();
        let (id, forecast) = test_upcoming_forecast();
        let plan = base_plan(&snap, &id, Some(&forecast)).unwrap();
        assert_eq!(plan.source, PrepDjSource::Forecast);
        assert_eq!(plan.heading, "予習 DJ");
        assert!(plan.summary.starts_with("予測の上位から"));
        assert!(plan.tracks.len() <= PREP_TRACKS && plan.tracks[0].starts_part);
        let picks: Vec<&ForecastSongRecord> = forecast.songs.iter().take(PREP_TRACKS).collect();
        let ordered = flow_order(&snap, &picks);

        assert_eq!(ordered.len(), picks.len());
        let ids: HashSet<&str> = ordered.iter().map(|(_, p)| p.song_id.as_str()).collect();
        assert_eq!(ids.len(), picks.len(), "同じ曲を 2 回流さない");

        // アンコールは末尾にまとまり、上限を超えない。
        let first_encore = ordered.iter().position(|(part, _)| *part == PrepDjPart::Encore).unwrap_or(ordered.len());
        assert!(ordered[first_encore..].iter().all(|(part, _)| *part == PrepDjPart::Encore));
        assert!(ordered.len() - first_encore <= MAX_ENCORE);
        // 本編は 開幕 → 中盤 → 終盤 の順に進む。
        let order = |p: PrepDjPart| [PrepDjPart::Opening, PrepDjPart::Middle, PrepDjPart::Closing, PrepDjPart::Encore].iter().position(|x| *x == p).unwrap();
        assert!(ordered.windows(2).all(|w| order(w[0].0) <= order(w[1].0)));

        // 頭は、候補の中で 1 曲目だった回数がいちばん多い曲。
        let best = picks.iter().map(|p| song_position_profile(&snap, &p.song_id).opener).max().unwrap();
        if best > 0 {
            assert_eq!(song_position_profile(&snap, &ordered[0].1.song_id).opener, best);
        }
    }

    #[test]
    fn 予測できない公演と知らない公演は組まない() {
        let snap = bundle_snapshot();
        assert!(base_plan(&snap, "no-such-show", None).is_none());
        // セトリの無い公演は、予測が無ければ組めない。
        let (id, _) = test_upcoming_forecast();
        assert!(base_plan(&snap, &id, None).is_none());
    }

    #[test]
    fn 入口の名前はセトリがあれば復習で無ければリアルライブだけ予習() {
        let snap = bundle_snapshot();
        assert_eq!(entry_label(&snap, &show_with_setlist(&snap)), Some("復習 DJ"));
        let (id, _) = test_upcoming_forecast();
        assert_eq!(entry_label(&snap, &id), Some("予習 DJ"));
        assert_eq!(entry_label(&snap, "no-such-show"), None);
        // リアルライブでない公演: セトリがあれば復習を組め、無ければ入口を出さない。
        for (s, show) in snap.shows.iter().enumerate() {
            if is_real_live(&snap, s as u32) {
                continue;
            }
            let has_setlist = !snap.setlist_items_by_show[s].is_empty();
            assert_eq!(entry_label(&snap, &show.id).is_some(), has_setlist);
            assert_eq!(base_plan(&snap, &show.id, None).is_some(), has_setlist);
        }
    }

    #[test]
    fn 曲の多い公演の復習は全曲を流す() {
        let snap = bundle_snapshot();
        let (show, n) = (0..snap.shows.len())
            .map(|s| {
                let mut seen = HashSet::new();
                (s, snap.setlist_items_by_show[s].iter().filter(|&&i| seen.insert(snap.setlist_items[i as usize].song)).count())
            })
            .max_by_key(|&(_, n)| n)
            .unwrap();
        assert!(n > MAX_TRACKS, "上限より曲の多い公演が実データにある");
        let plan = base_plan(&snap, &snap.shows[show].id, None).unwrap();
        assert_eq!(plan.tracks.len(), n);
    }

    #[test]
    fn 位置の一言は披露が無ければ空で目立つ位置を1つだけ添える() {
        assert_eq!(position_fact(&SongPositionProfile::default()), "");
        let p = SongPositionProfile { performances: 24, opener: 9, closer: 3, encore: 1, ..Default::default() };
        assert_eq!(position_fact(&p), "披露 24 回 · 1 曲目 9 回");
        let p = SongPositionProfile { performances: 5, opener: 1, ..Default::default() };
        assert_eq!(position_fact(&p), "披露 5 回");
    }

    #[test]
    fn 本編の置き場は3等分で鍵は往復する() {
        assert_eq!(PrepDjPart::of_main(0, 9), PrepDjPart::Opening);
        assert_eq!(PrepDjPart::of_main(4, 9), PrepDjPart::Middle);
        assert_eq!(PrepDjPart::of_main(8, 9), PrepDjPart::Closing);
        for p in [PrepDjPart::Opening, PrepDjPart::Middle, PrepDjPart::Closing, PrepDjPart::Encore] {
            assert_eq!(PrepDjPart::parse(p.key()), Some(p));
        }
        assert_eq!(PrepDjPart::parse("intro"), None);
    }
}
