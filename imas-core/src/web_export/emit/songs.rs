//! 楽曲 (song) の詳細ページ。
//!
//! **ページは全曲ぶん作る** (派生曲・`other` ブランドを含む)。共有リンクと検索から
//! 到達できるべきだから。一覧に載せるかどうかだけが `SongListFilter` の判断で、
//! それは `lists.rs` の関心事。

use super::context::{distinguishing_show_name, duration_display, join_parts, Ctx, TagScope};
use crate::domain::credit_names::split_credits;
use crate::domain::display_join::join_capped;
use crate::domain::performance_stats;
use crate::domain::song_detail_queries as detail;
use crate::domain::song_detail_queries::performance_ordinal_label;
use crate::web_export::content;
use crate::web_export::dto::*;
use crate::web_export::url;

/// 「よく歌う人」「よく一緒に披露される曲」に出す件数。アプリの詳細画面と同じ。
const TOP_N: u32 = 10;
/// 関連曲の件数。
const RELATED_N: u32 = 12;

pub fn song_page(ctx: &Ctx, song_id: &str) -> Option<SongPage> {
    let record = detail::song_records_by_ids(ctx.snap, &[song_id.to_string()]).into_iter().next()?;
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
        let mut crumbs = vec![Ctx::crumb("ホーム", "/"), Ctx::crumb("楽曲", "/songs/")];
        // 一覧を作っていない組み合わせ (`other`) はパンくずにも入れない。
        // 存在の判断は Ctx が 1 箇所で持つ。
        if let Some(brand) = brand_id.as_deref().and_then(|b| ctx.brand_ref(b)) {
            if let Some(list) = ctx.brand_list_path("songs", &brand.id) {
                crumbs.push(Ctx::crumb(&brand.name, &list));
            }
        }
        crumbs.push(Ctx::crumb(&record.title, &path));
        crumbs
    };

    let series_display = record.cd_series.clone().or_else(|| record.series_group.clone());
    let duration_display = record.duration_sec.map(duration_display);
    let variants: Vec<Ref> = detail::variant_song_records(ctx.snap, song_id)
        .iter()
        .filter_map(|v| ctx.song_ref(&v.id))
        .collect();
    let performance_count = ctx.snap.performance_counts[index as usize];
    // 数の帯。ページ内の節へ飛ぶ (電話では披露履歴が脇の情報の下に来るので、入口を上に置く)。
    let stat_tiles = nonzero_tiles([
        StatTile::new("♪", performance_count, "回披露").with_href("#song-history"),
        StatTile::new("☺", original_artists.len() as u32, "歌唱アイドル"),
        StatTile::new("♬", variants.len() as u32, "派生曲").with_href("#song-variants"),
    ]);
    // 披露履歴 (新しい順)。行ごとの歌唱メンバーは、同じ並びの setlist_items の添字から引く。
    let history_items = detail::performance_item_indices(ctx.snap, song_id);
    let performer_names = |item: u32| -> Vec<&str> {
        ctx.snap.performers_by_item[item as usize]
            .iter()
            .map(|&idol| ctx.snap.idols[idol as usize].name.as_str())
            .collect()
    };

    Some(SongPage {
        schema_version: SCHEMA_VERSION,
        // 歌詞。**出すかどうかは content::LYRICS_ON_WEB 1 箇所で決まる。**
        lyrics: LyricsBlock {
            available: content::LYRICS_ON_WEB,
            status_label: content::lyrics_status_label(),
            note: content::lyrics_note().to_string(),
            license_number: content::LYRICS_ON_WEB
                .then(|| content::JASRAC_LICENSE_NUMBER.to_string()),
            license_note: content::LYRICS_ON_WEB
                .then(|| content::LYRICS_ON_WEB_NOTE.to_string()),
            // 1 リクエスト 1 曲。まとめて取れる形の URL は出さない。
            source_url: content::LYRICS_ON_WEB.then(|| {
                format!("{}/songs/{}/lyrics", content::API_ORIGIN, url::url_segment(&record.id))
            }),
            read_label: content::LYRICS_ON_WEB.then(|| content::LYRICS_READ_LABEL.to_string()),
            call_guide: content::LYRICS_ON_WEB.then(content::call_guide_vocabulary),
        },
        id: record.id.clone(),
        path: path.clone(),
        title: record.title.clone(),
        title_kana: record.title_kana.clone(),
        community: SongCommunity {
            tags: super::context::tag_chips(ctx, TagScope::Song, ctx.community.song_tags(&record.id)),
            favorites: ctx.community.favorites(&record.id).max(0) as u32,
            penlight: ctx
                .community
                .penlight(&record.id)
                .iter()
                .map(|p| PenlightSetDto { key: p.color_set_key.clone(), count: p.count.max(0) as u32 })
                .collect(),
        },
        theme_key: ctx.brand_theme(brand_id.as_deref()),
        brand: brand_id.as_deref().and_then(|b| ctx.brand_ref(b)),
        joint_brands: ctx.joint_brand_refs(record.joint_brand_ids.as_deref()),
        collab_label: record.is_collab.then(|| content::SONG_COLLAB_LABEL.to_string()),
        song_type_label: record
            .song_type
            .as_deref()
            .and_then(content::song_type_label)
            .map(str::to_string),
        release_date: record.release_date.clone(),
        duration_display: duration_display.clone(),
        credits,
        // 「シリーズ」行に出すのは 1 つ。CD シリーズを優先し、無ければ系列名。
        series_display: series_display.clone(),
        cd_title: record.cd_title.clone(),
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
        variants,
        performance_count,
        stat_tiles,
        performance_history: detail::performance_history(ctx.snap, song_id)
            .into_iter()
            .zip(history_items)
            .filter_map(|(h, &item)| {
                let show_name = distinguishing_show_name(&h.event_name, &h.show_name);
                let place_display =
                    join_parts([show_name, h.venue.as_deref()]).unwrap_or_default();
                Some(PerformanceRow {
                    show: ctx.show_ref(&h.show_id)?,
                    event: ctx.event_ref(&h.event_id)?,
                    date_badge: DateBadge::from_ymd(&h.date),
                    number: ctx.setlist_number(&h.show_id, h.position),
                    date: h.date,
                    venue: h.venue,
                    place_display,
                    performers_display: join_capped(&performer_names(item), "・", 3, "人"),
                    ordinal_label: performance_ordinal_label(h.ordinal),
                })
            })
            .collect(),
        frequent_singers: performance_stats::singers_for_song(ctx.snap, song_id, &[], TOP_N)
            .into_iter()
            .filter_map(|t| {
                Some(SingerRow { idol: ctx.idol_ref(&t.idol_id)?, times: t.times, total: t.total })
            })
            .collect(),
        co_occurring: ctx.co_occur.co_occurring(ctx.snap, song_id, TOP_N)
            .into_iter()
            .filter_map(|c| {
                Some(CoOccurRow { song: ctx.song_ref(&c.song_id)?, together: c.together })
            })
            .collect(),
        related: detail::related_songs(ctx.snap, song_id, RELATED_N)
            .iter()
            .filter_map(|s| ctx.song_ref(&s.id))
            .collect(),
        fact_rows: song_fact_rows(&record, series_display.as_deref(), duration_display.as_deref()),
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
    })
}

/// 曲の「基本情報」行。値が無い行は出さない (アイドルの `profile_rows` と同じ規則)。
fn song_fact_rows(
    record: &detail::SongDetailRecord,
    series_display: Option<&str>,
    duration_display: Option<&str>,
) -> Vec<ProfileRow> {
    [
        ("リリース", record.release_date.as_deref(), "monospaced"),
        ("収録", record.cd_title.as_deref(), "plain"),
        ("シリーズ", series_display, "plain"),
        ("再生時間", duration_display, "monospaced"),
        ("JASRAC 作品コード", record.jasrac_code.as_deref(), "monospaced"),
    ]
    .into_iter()
    .filter_map(|(label, value, style)| {
        Some(ProfileRow {
            label: label.to_string(),
            value: value.filter(|v| !v.is_empty())?.to_string(),
            style: style.to_string(),
            link: None,
        })
    })
    .collect()
}

/// 検索結果や共有カードに出る 1 文。曲名は「」で括り、ユニットは丸括弧で添える
/// (「Thank You!楽曲情報。」のように助詞が抜けた文にしない)。
fn song_description(record: &detail::SongDetailRecord) -> String {
    let unit = record.unit_name.as_deref().map(|u| format!("（{u}）")).unwrap_or_default();
    let release = record
        .release_date
        .as_deref()
        .map(|d| format!("{d} リリース。"))
        .unwrap_or_default();
    format!("「{}」{}の楽曲情報。{}クレジット・歌唱アイドル・ライブでの披露履歴。", record.title, unit, release)
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
