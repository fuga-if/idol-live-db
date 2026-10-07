//! 曲の日付 (初出・CD 発売日・配信開始日) のどれを、どの順で出すか。
//!
//! # 3 つの日付の意味
//!
//! - **初出** (`songs.release_date`): その曲が最初に世に出た日。ゲームへの実装・MV の公開・
//!   アニメの放送も含む (CHANGE!!!! はアニメ第 14 話の 2011-10-07)。列名は歴史的に
//!   `release_date` だが、中身はほとんどの曲で初出になっている (2026-10 に Apple Music の
//!   配信日と全曲を突き合わせて確かめた)。
//! - **CD 発売日** (`songs.cd_release_date`): 最初に収録された CD の発売日。
//! - **配信開始日** (`songs.streaming_date`): 配信が始まった日。
//!
//! 画面に出す初出は、`release_date` とライブでの初披露 (セトリから出す) のうち早いほう。
//! ライブでの初披露は列に持たない — セトリを入れれば決まるので、二重に持つとずれる。
//!
//! 画面ごとに「どの日付を出すか」を書くと、片方だけライブの初披露を見る、といった
//! 食い違いが必ず出るので、行の組み立てまでここで決める。

use crate::domain::snapshot::{Show, Snapshot};

pub const FIRST_APPEARANCE_LABEL: &str = "初出";
pub const CD_RELEASE_DATE_LABEL: &str = "CD 発売日";
pub const STREAMING_DATE_LABEL: &str = "配信開始日";

/// 日付の行の種類。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SongDateKind {
    /// 初出 (`release_date` の日)。アプリは「その年の曲」の一覧へ飛ばす (一覧はこの列で引く)。
    FirstAppearance,
    /// 初出がライブでの初披露だったとき。`detail` に公演名が入る。
    FirstPerformance,
    CdRelease,
    Streaming,
}

/// 曲の日付の 1 行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SongDateRow {
    pub kind: SongDateKind,
    pub label: String,
    /// YYYY-MM-DD (データにある表記のまま)。
    pub date: String,
    /// 初出の行に添える補足。ライブでの初披露なら公演名 (「初星学園 標 DAY1」)、
    /// そうでなければ `songs.first_appearance_note` (「TVアニメ第14話 新OP」)。無ければ `None`。
    pub detail: Option<String>,
    /// 画面に出す値。日付に補足を添えた形 (「2026-09-23（初星学園 標 DAY1）」)。
    /// 添え方を各画面で書くと揃わないので、ここで作る。
    pub display: String,
}

/// 曲の日付の行。並びは 初出 → CD 発売日 → 配信開始日。値の無い行は出さない。
///
/// 初出は `release_date` とライブでの初披露のうち早いほう。同じ日なら `release_date` の側
/// (放送やゲームで出た日に、そのままライブでも歌われた曲で「初出はライブ」と言わないため)。
pub fn song_date_rows(snap: &Snapshot, song_id: &str) -> Vec<SongDateRow> {
    let Some(&si) = snap.song_index_by_id.get(song_id) else { return Vec::new() };
    let song = &snap.songs[si as usize];
    let release = non_empty(&song.release_date);
    let first_live = first_live_show(snap, si);

    let mut rows = Vec::new();
    match (release, first_live) {
        (Some(r), Some(show)) if show.date.as_str() < r => rows.push(live_row(snap, show)),
        (Some(r), _) => {
            let mut first = row(SongDateKind::FirstAppearance, FIRST_APPEARANCE_LABEL, r);
            if let Some(note) = non_empty(&song.first_appearance_note) {
                first.display = format!("{r}（{note}）");
                first.detail = Some(note.to_string());
            }
            rows.push(first);
        }
        (None, Some(show)) => rows.push(live_row(snap, show)),
        (None, None) => {}
    }
    if let Some(d) = non_empty(&song.cd_release_date) {
        rows.push(row(SongDateKind::CdRelease, CD_RELEASE_DATE_LABEL, d));
    }
    if let Some(d) = non_empty(&song.streaming_date) {
        rows.push(row(SongDateKind::Streaming, STREAMING_DATE_LABEL, d));
    }
    rows
}

/// この曲が最初に歌われた公演 (日付が同じなら公演の並び順で早いほう)。
fn first_live_show(snap: &Snapshot, si: u32) -> Option<&Show> {
    snap.setlist_items_by_song[si as usize]
        .iter()
        .map(|&ii| &snap.shows[snap.setlist_items[ii as usize].show as usize])
        .filter(|show| !show.date.is_empty())
        .min_by(|a, b| (&a.date, a.sort_order).cmp(&(&b.date, b.sort_order)))
}

fn live_row(snap: &Snapshot, show: &Show) -> SongDateRow {
    let name = live_name(snap, show);
    SongDateRow {
        kind: SongDateKind::FirstPerformance,
        label: FIRST_APPEARANCE_LABEL.to_string(),
        display: format!("{}（{name}）", show.date),
        date: show.date.clone(),
        detail: Some(name),
    }
}

/// 公演の呼び名。公演名がイベント名を含んでいればそれだけ、でなければ「イベント名 公演名」。
fn live_name(snap: &Snapshot, show: &Show) -> String {
    let event = &snap.events[show.event as usize].name;
    if show.name.is_empty() || show.name == *event {
        event.clone()
    } else if show.name.contains(event.as_str()) {
        show.name.clone()
    } else {
        format!("{event} {}", show.name)
    }
}

fn non_empty(v: &Option<String>) -> Option<&str> {
    v.as_deref().filter(|s| !s.is_empty())
}

fn row(kind: SongDateKind, label: &str, date: &str) -> SongDateRow {
    SongDateRow {
        kind,
        label: label.to_string(),
        date: date.to_string(),
        detail: None,
        display: date.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::{Event, SetlistItem, Song};
    use crate::domain::snapshot_build::{build, RawTables};

    fn song(release: Option<&str>, cd: Option<&str>, streaming: Option<&str>) -> Song {
        Song {
            id: "s".into(),
            title: "CHANGE!!!!".into(),
            song_type: Some("all".into()),
            release_date: release.map(Into::into),
            cd_release_date: cd.map(Into::into),
            streaming_date: streaming.map(Into::into),
            ..Song::default()
        }
    }

    fn show(id: &str, name: &str, date: &str, sort_order: i64) -> Show {
        Show {
            id: id.into(),
            event: 0,
            name: name.into(),
            date: date.into(),
            venue: None,
            venue_city: None,
            start_time: None,
            sort_order,
            performer_type: None,
            venue_id: None,
            hall: None,
            stream_platform: None,
            venue_mode: None,
            has_streaming: None,
            has_live_viewing: None,
        }
    }

    fn snap(song: Song, shows: Vec<Show>) -> Snapshot {
        let setlist_items = (0..shows.len())
            .map(|i| SetlistItem {
                id: format!("i{i}"),
                show: i as u32,
                song: 0,
                position: 1,
                section: None,
                notes: None,
                unit_name: None,
            })
            .collect();
        build(RawTables {
            songs: vec![song],
            idols: vec![],
            events: vec![Event {
                id: "e".into(),
                brand_id: Some("765as".into()),
                name: "初星学園 標".into(),
                name_kana: None,
                event_type: "live".into(),
                is_streaming: false,
                is_solo: true,
                kind: "live".into(),
                ticket_url: None,
                joint_brand_ids: None,
                has_streaming: None,
                has_live_viewing: None,
            }],
            units: vec![],
            brands: vec![],
            creators: vec![],
            venues: vec![],
            staff: vec![],
            anniversaries: vec![],
            meta: Default::default(),
            shows,
            setlist_items,
            venue_names: vec![],
            venue_halls: vec![],
            idol_voice_actors: vec![],
            event_releases: vec![],
            costumes: vec![],
            costume_wears: vec![],
            ticket_sales: vec![],
            show_archives: vec![],
            song_artists: vec![],
            setlist_performers: vec![],
            show_cast: vec![],
            unit_members: vec![],
            idol_brands: vec![],
        })
    }

    fn summary(rows: &[SongDateRow]) -> Vec<(&str, &str, Option<&str>)> {
        rows.iter().map(|r| (r.label.as_str(), r.date.as_str(), r.detail.as_deref())).collect()
    }

    #[test]
    fn broadcast_debut_then_cd_and_streaming() {
        // CHANGE!!!!: 2011-10-07 にアニメ第 14 話で初めて流れ、CD は 11-09。
        let s = snap(song(Some("2011-10-07"), Some("2011-11-09"), Some("2011-11-09")), vec![]);
        assert_eq!(
            summary(&song_date_rows(&s, "s")),
            vec![
                ("初出", "2011-10-07", None),
                ("CD 発売日", "2011-11-09", None),
                ("配信開始日", "2011-11-09", None),
            ]
        );
        assert_eq!(song_date_rows(&s, "s")[0].kind, SongDateKind::FirstAppearance);
    }

    #[test]
    fn live_before_release_names_the_show() {
        // ライブで先に歌われ、翌日に配信が始まった曲。
        let s = snap(
            song(Some("2026-09-24"), None, Some("2026-09-24")),
            vec![show("b", "DAY2", "2026-09-27", 1), show("a", "DAY1", "2026-09-23", 0)],
        );
        let rows = song_date_rows(&s, "s");
        assert_eq!(
            summary(&rows),
            vec![("初出", "2026-09-23", Some("初星学園 標 DAY1")), ("配信開始日", "2026-09-24", None)]
        );
        assert_eq!(rows[0].kind, SongDateKind::FirstPerformance);
        assert_eq!(rows[0].display, "2026-09-23（初星学園 標 DAY1）");
        assert_eq!(rows[1].display, "2026-09-24");
    }

    #[test]
    fn first_appearance_note_is_attached() {
        let mut s = song(Some("2011-10-07"), Some("2011-11-09"), None);
        s.first_appearance_note = Some("TVアニメ第14話 新OP".into());
        let rows = song_date_rows(&snap(s, vec![]), "s");
        assert_eq!(rows[0].detail.as_deref(), Some("TVアニメ第14話 新OP"));
        assert_eq!(rows[0].display, "2011-10-07（TVアニメ第14話 新OP）");
        assert_eq!(rows[0].kind, SongDateKind::FirstAppearance);
    }

    #[test]
    fn live_on_the_same_day_keeps_the_release_date() {
        let s = snap(song(Some("2011-10-07"), None, None), vec![show("a", "", "2011-10-07", 0)]);
        let rows = song_date_rows(&s, "s");
        assert_eq!(summary(&rows), vec![("初出", "2011-10-07", None)]);
        assert_eq!(rows[0].kind, SongDateKind::FirstAppearance);
    }

    #[test]
    fn live_after_release_is_not_the_first_appearance() {
        let s = snap(song(Some("2014-01-22"), None, None), vec![show("a", "", "2014-02-01", 0)]);
        assert_eq!(summary(&song_date_rows(&s, "s")), vec![("初出", "2014-01-22", None)]);
    }

    #[test]
    fn without_release_date_first_live_still_shows() {
        let s = snap(song(None, None, None), vec![show("a", "初星学園 標 DAY1", "2026-09-23", 0)]);
        assert_eq!(
            summary(&song_date_rows(&s, "s")),
            vec![("初出", "2026-09-23", Some("初星学園 標 DAY1"))]
        );
    }

    #[test]
    fn no_dates_no_rows() {
        let s = snap(song(None, None, None), vec![]);
        assert!(song_date_rows(&s, "s").is_empty());
        assert!(song_date_rows(&s, "nope").is_empty());
    }
}
