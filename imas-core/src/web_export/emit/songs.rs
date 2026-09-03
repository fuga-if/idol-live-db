//! 楽曲 (song) の詳細ページ。
//!
//! **ページは全曲ぶん作る** (派生曲・`other` ブランドを含む)。共有リンクと検索から
//! 到達できるべきだから。一覧に載せるかどうかだけが `SongListFilter` の判断で、
//! それは `lists.rs` の関心事。

use super::context::{duration_display, Ctx};
use crate::domain::credit_names::split_credits;
use crate::domain::performance_stats;
use crate::domain::short_year_month::short_year_month;
use crate::domain::song_detail_queries as detail;
use crate::web_export::content;
use crate::web_export::dto::*;

/// 「よく歌う人」「よく一緒に披露される曲」に出す件数。アプリの詳細画面と同じ。
const TOP_N: u32 = 10;
/// 関連曲の件数。
const RELATED_N: u32 = 12;

pub fn song_page(ctx: &Ctx, song_id: &str) -> Option<SongPage> {
    let record = detail::song_records_by_ids(ctx.snap, std::slice::from_ref(&song_id.to_string()))
        .into_iter()
        .next()?;
    let &index = ctx.snap.song_index_by_id.get(song_id)?;
    let path = ctx.path(RefKind::Song, song_id);
    let brand_id = record.brand_id.clone();

    let credits = [
        ("作詞", record.lyricist.as_deref()),
        ("作曲", record.composer.as_deref()),
        ("編曲", record.arranger.as_deref()),
    ]
    .into_iter()
    .filter_map(|(role, raw)| {
        let raw = raw.filter(|r| !r.is_empty())?;
        let people = split_credits(raw);
        Some(CreditGroup {
            role: role.to_string(),
            // 1 行表記は Rust 側で決める。区切りを TS に選ばせない。
            display: if people.is_empty() { raw.to_string() } else { people.join(" / ") },
            raw: raw.to_string(),
            people,
        })
    })
    .collect();

    // 原唱者とそれ以外を分ける。role の意味は Snapshot::song_artists が持っている。
    let original_artists: Vec<Ref> = ctx
        .snap
        .song_artists(song_id, Some("original"))
        .iter()
        .filter_map(|i| ctx.idol_ref(&i.id))
        .collect();
    let other_artists: Vec<Ref> = ctx.snap.artists_by_song[index as usize]
        .iter()
        .filter(|link| link.role != "original")
        .filter_map(|link| ctx.idol_ref(&ctx.snap.idols[link.idol as usize].id))
        .collect();

    let breadcrumbs = {
        let mut crumbs = vec![ctx.crumb("ホーム", "/"), ctx.crumb("楽曲", "/songs/")];
        // `other` にはブランド別一覧を作っていないので、パンくずにも入れない
        // (入れると存在しないページへのリンクになる)。
        if !ctx.is_other_brand(brand_id.as_deref()) {
            if let Some(brand) = brand_id.as_deref().and_then(|b| ctx.brand_ref(b)) {
                crumbs.push(ctx.crumb(&brand.name, &format!("/songs/brand/{}/", brand.id)));
            }
        }
        crumbs.push(ctx.crumb(&record.title, &path));
        crumbs
    };

    Some(SongPage {
        schema_version: SCHEMA_VERSION,
        id: record.id.clone(),
        path: path.clone(),
        title: record.title.clone(),
        title_kana: record.title_kana.clone(),
        theme_key: ctx.brand_theme(brand_id.as_deref()),
        brand: brand_id.as_deref().and_then(|b| ctx.brand_ref(b)),
        song_type: record.song_type.clone(),
        release_date: record.release_date.clone(),
        duration_display: record.duration_sec.map(duration_display),
        duration_sec: record.duration_sec.map(|s| s as i32),
        credits,
        // 「シリーズ」行に出すのは 1 つ。CD シリーズを優先し、無ければ系列名。
        series_display: record.cd_series.clone().or_else(|| record.series_group.clone()),
        cd_series: record.cd_series.clone(),
        cd_title: record.cd_title.clone(),
        series_group: record.series_group.clone(),
        artwork_url: record.artwork_url.clone(),
        apple_music_url: record
            .apple_music_id
            .as_deref()
            .map(|id| format!("https://music.apple.com/jp/song/{id}")),
        jasrac_code: record.jasrac_code.clone(),
        original_artists,
        other_artists,
        unit: record.unit_id.as_deref().and_then(|u| ctx.unit_ref(u)),
        unit_label: record.unit_name.clone(),
        parent: record.parent_song_id.as_deref().and_then(|p| ctx.song_ref(p)),
        variants: detail::variant_song_records(ctx.snap, song_id)
            .iter()
            .filter_map(|v| ctx.song_ref(&v.id))
            .collect(),
        performance_count: ctx.snap.performance_counts[index as usize],
        performance_history: detail::performance_history(ctx.snap, song_id)
            .into_iter()
            .filter_map(|h| {
                let show_name = distinguishing_show_name(&h.event_name, &h.show_name);
                let place_display = [show_name, h.venue.as_deref()]
                    .into_iter()
                    .flatten()
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>()
                    .join(" ・ ");
                let number = ctx.setlist_number(&h.show_id, h.position);
                Some(PerformanceRow {
                    show: ctx.show_ref(&h.show_id)?,
                    event: ctx.event_ref(&h.event_id)?,
                    short_date: short_year_month(&h.date),
                    date: h.date,
                    venue: h.venue,
                    number,
                    position: h.position as i32,
                    section: h.section,
                    place_display,
                })
            })
            .collect(),
        frequent_singers: performance_stats::singers_for_song(ctx.snap, song_id, &[], TOP_N)
            .into_iter()
            .filter_map(|t| {
                Some(SingerRow { idol: ctx.idol_ref(&t.idol_id)?, times: t.times, total: t.total })
            })
            .collect(),
        co_occurring: performance_stats::co_occurring_songs(ctx.snap, song_id, TOP_N)
            .into_iter()
            .filter_map(|c| {
                Some(CoOccurRow {
                    song: ctx.song_ref(&c.song_id)?,
                    together: c.together,
                    performances: c.performances,
                })
            })
            .collect(),
        related: detail::related_songs(ctx.snap, song_id, RELATED_N)
            .iter()
            .filter_map(|s| ctx.song_ref(&s.id))
            .collect(),
        app: content::app_open_plain(),
        seo: ctx.seo(
            &record.title,
            &song_description(&record),
            &path,
            brand_id.as_deref(),
            song_json_ld(&record, &path),
            breadcrumbs,
        ),
        // 歌詞は載せない。許諾を持つのはアプリであって本サイトではない。
        lyrics_note: content::LYRICS_NOTE.to_string(),
    })
}

/// 披露履歴の行に出す公演名。行のタイトルがライブ名なので、**ライブ名と重なる部分は落とす**。
///
/// 公演名はライブ名を頭に含んでいることが多い:
///
/// ```text
///   ライブ名: THE IDOLM@STER MILLION THE@TER WAVE 11&12 発売記念イベント
///   公演名  : THE IDOLM@STER MILLION THE@TER WAVE 11&12 発売記念イベント【第一回】
/// ```
///
/// そのまま繋ぐと同じ長い名前が 2 行続いて、公演を見分ける手掛かり (`【第一回】`) が
/// 行末に埋もれる。重なりを取り除いて残った部分だけを出し、公演が 1 本しかないライブ
/// (公演名 = ライブ名) では公演名ごと落とす。
fn distinguishing_show_name<'a>(event_name: &str, show_name: &'a str) -> Option<&'a str> {
    let rest = show_name.strip_prefix(event_name).unwrap_or(show_name);
    // 区切りの空白と中黒だけを落とす。`【` や `第` は見分けに要るので残す。
    let rest = rest.trim_start_matches([' ', '\u{3000}', '-', '~', '～', '・']).trim();
    (!rest.is_empty()).then_some(rest)
}

fn song_description(record: &detail::SongDetailRecord) -> String {
    let unit = record
        .unit_name
        .as_deref()
        .map(|u| format!("{u}の楽曲。"))
        .unwrap_or_else(|| "楽曲情報。".to_string());
    let release = record
        .release_date
        .as_deref()
        .map(|d| format!("{d} リリース。"))
        .unwrap_or_default();
    format!("{}{}{}クレジット・原唱者・ライブでの披露履歴。", record.title, unit, release)
}

fn song_json_ld(record: &detail::SongDetailRecord, path: &str) -> serde_json::Value {
    let mut value = serde_json::json!({
        "@type": "MusicRecording",
        "name": record.title,
        "url": content::absolute(path),
    });
    // アイドル名は入れない (実在の人物ではないため)。ユニット表記までに留める。
    if let Some(unit) = &record.unit_name {
        value["byArtist"] = serde_json::json!({ "@type": "MusicGroup", "name": unit });
    }
    if let Some(date) = &record.release_date {
        value["datePublished"] = serde_json::Value::String(date.clone());
    }
    if let Some(sec) = record.duration_sec {
        // ISO 8601 duration。
        value["duration"] = serde_json::Value::String(format!("PT{}M{}S", sec / 60, sec % 60));
    }
    if let Some(album) = &record.cd_title {
        value["inAlbum"] = serde_json::json!({ "@type": "MusicAlbum", "name": album });
    }
    value
}

#[cfg(test)]
mod tests {
    use super::distinguishing_show_name;

    #[test]
    fn a_show_named_after_its_event_adds_nothing() {
        // 公演が 1 本しかないライブ。行のタイトルと同じ名前を繰り返さない。
        assert_eq!(distinguishing_show_name("A LIVE", "A LIVE"), None);
        assert_eq!(distinguishing_show_name("A LIVE", "A LIVE "), None);
    }

    #[test]
    fn only_the_part_that_tells_shows_apart_is_kept() {
        assert_eq!(
            distinguishing_show_name("MILLION THE@TER WAVE 発売記念イベント", "MILLION THE@TER WAVE 発売記念イベント【第一回】"),
            Some("【第一回】")
        );
        assert_eq!(
            distinguishing_show_name("SideM 2nd STAGE", "SideM 2nd STAGE Shining Side"),
            Some("Shining Side")
        );
        // 区切りの中黒や波ダッシュは落とすが、見分けに要る文字は残す。
        assert_eq!(distinguishing_show_name("ツアー", "ツアー ・ 第1回公演"), Some("第1回公演"));
    }

    #[test]
    fn an_unrelated_show_name_is_left_alone() {
        assert_eq!(distinguishing_show_name("A LIVE", "DAY2"), Some("DAY2"));
        assert_eq!(distinguishing_show_name("A LIVE", "昼公演"), Some("昼公演"));
    }
}
