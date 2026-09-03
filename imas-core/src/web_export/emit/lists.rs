//! 一覧ページ・トップ・About。
//!
//! 切替 (ブランド別・年別・誕生月別・都道府県別) は**すべて別ページ**として出す。
//! クライアント状態を持たないというユーザー指示の直接の帰結で、切替 UI は
//! [`NavLink`] のリンク集になる。

use super::context::{join_parts, Ctx};
use super::events::show_summary;
use super::places::{brand_counts, UNCLASSIFIED_PREFECTURE};
use crate::domain::event_detail_queries as detail;
use crate::domain::event_grouping::group_events_by_year;
use crate::domain::event_list_queries::{self, EventWithDateRecord};
use crate::domain::idol_queries;
use crate::domain::short_year_month::short_year_month;
use crate::domain::song_list_queries::{song_list_indexes, SongListFilter, SongListSort};
use crate::domain::text_search_index::prepare_needle;
use crate::domain::unit_queries;
use crate::web_export::content;
use crate::web_export::dto::*;
use crate::web_export::url::url_segment;
use std::collections::BTreeMap;

/// 一覧に出すライブの種別。
///
/// **省略しない。** 省略すると `event_list_queries` の既定が効いて、ラジオや配信が
/// 一覧から静かに消える (= そのページが `/` から到達できなくなる)。
pub fn all_event_kinds() -> Vec<String> {
    content::ALL_EVENT_KINDS.iter().map(|k| k.to_string()).collect()
}

/// 1 枚ぶんの出力 (どこに置き、どの URL になるか)。
pub struct Emitted<T> {
    pub path: String,
    pub data: String,
    pub page: T,
}

// ---------------------------------------------------------------------------
// ライブ一覧
// ---------------------------------------------------------------------------

/// 年グループを組む。**分割規則は `group_events_by_year` が持つ**ので、
/// ここは結果の添字で元の配列を引き直すだけ。
fn year_groups(
    ctx: &Ctx,
    records: &[EventWithDateRecord],
    upcoming: bool,
    with_brand: bool,
) -> Vec<YearGroup> {
    let dates: Vec<Option<String>> = records.iter().map(|r| r.first_date.clone()).collect();
    group_events_by_year(&dates, upcoming, &ctx.today)
        .into_iter()
        .map(|g| YearGroup {
            year: g.year,
            events: g
                .indices
                .iter()
                .filter_map(|&i| event_list_item(ctx, &records[i as usize], with_brand))
                .collect(),
        })
        .collect()
}

/// 開催期間の表記。1 日で終わるライブは 1 つだけ出す。
fn date_range_display(first: Option<&str>, last: Option<&str>) -> Option<String> {
    match (first, last) {
        (Some(f), Some(l)) if f != l => Some(format!("{f} 〜 {l}")),
        (Some(f), _) => Some(f.to_string()),
        (None, Some(l)) => Some(l.to_string()),
        (None, None) => None,
    }
}

/// 会場をまとめた 1 行。多いときは畳む (ツアーは 20 会場を超える)。
fn venue_display(labels: &[String]) -> Option<String> {
    const SHOWN: usize = 3;
    if labels.is_empty() {
        return None;
    }
    if labels.len() <= SHOWN {
        return join_parts(labels.iter().map(|l| Some(l.as_str())));
    }
    let head = labels[..SHOWN].join(crate::web_export::emit::context::PARTS_SEPARATOR);
    Some(format!("{head} ほか {} 会場", labels.len() - SHOWN))
}

/// 一覧の 1 行。
///
/// `with_brand` は副題にブランド名を入れるか。**ブランド別ページでは入れない**
/// (そのページの全行が同じブランドなので、行ごとに繰り返しても見分けに効かない)。
/// 一覧 JSON はページ単位で吐かれるので、どちらの文脈かは作る側が知っている。
fn event_list_item(
    ctx: &Ctx,
    record: &EventWithDateRecord,
    with_brand: bool,
) -> Option<EventListItem> {
    let e = &record.event;
    let show_count = ctx
        .snap
        .event_index_by_id
        .get(&e.id)
        .map(|&i| ctx.snap.shows_by_event[i as usize].len() as u32)
        .unwrap_or(0);
    let mut venue_labels: Vec<String> = ctx
        .snap
        .event_index_by_id
        .get(&e.id)
        .map(|&i| {
            ctx.snap.shows_by_event[i as usize]
                .iter()
                .filter_map(|&s| ctx.snap.shows[s as usize].venue.clone())
                .collect()
        })
        .unwrap_or_default();
    venue_labels.dedup();
    let brand = e.brand_id.as_deref().and_then(|b| ctx.brand_ref(b));
    Some(EventListItem {
        reference: ctx.event_ref(&e.id)?,
        short_date: record.first_date.as_deref().map(short_year_month),
        subtitle: join_parts([
            date_range_display(record.first_date.as_deref(), record.last_date.as_deref()),
            with_brand.then(|| brand.as_ref().map(|b| b.name.clone())).flatten(),
            (show_count > 1).then(|| format!("{show_count} 公演")),
            venue_display(&venue_labels),
        ]),
        first_date: record.first_date.clone(),
        last_date: record.last_date.clone(),
        brand,
        kind_label: content::kind_label(&e.kind).to_string(),
        kind: e.kind.clone(),
        show_count,
    })
}

/// ブランド切替のリンク。`other` は入口を作らない (§brand_page と同じ理由)。
fn brand_links(ctx: &Ctx, prefix: &str, current: &str, all_label: &str, all_count: u32) -> Vec<NavLink> {
    let mut links = vec![NavLink {
        label: all_label.to_string(),
        path: format!("/{prefix}/"),
        current: current == format!("/{prefix}/"),
        theme_key: None,
        count: Some(all_count),
    }];
    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        if ctx.is_other_brand(Some(&brand.id)) && prefix != "idols" {
            continue;
        }
        let path = format!("/{prefix}/brand/{}/", url_segment(&brand.id));
        links.push(NavLink {
            label: brand.short_name.clone(),
            current: current == path,
            path,
            theme_key: Some(ctx.brand_theme(Some(&brand.id))),
            count: None,
        });
    }
    links
}

fn scope_links(current: &str, upcoming: u32, past: u32) -> Vec<NavLink> {
    vec![
        NavLink {
            label: "今後のライブ".to_string(),
            path: "/events/upcoming/".to_string(),
            current: current == "/events/upcoming/",
            theme_key: None,
            count: Some(upcoming),
        },
        NavLink {
            label: "開催済み".to_string(),
            path: "/events/past/".to_string(),
            current: current == "/events/past/",
            theme_key: None,
            count: Some(past),
        },
    ]
}

/// ライブ一覧をすべて組む (`/events/` から `/events/brand/<b>/` まで)。
pub fn event_lists(ctx: &Ctx) -> Vec<Emitted<EventListPage>> {
    let kinds = all_event_kinds();
    // include_empty=true にするのは、公演がまだ無いライブ (発表直後) のページも
    // `/` から辿れるようにするため。落とすとそのページが孤立する。
    let all = event_list_queries::events_with_first_date(ctx.snap, None, true, false, Some(&kinds));

    let upcoming_groups = year_groups(ctx, &all, true, true);
    let past_groups = year_groups(ctx, &all, false, true);
    let upcoming_total: u32 = upcoming_groups.iter().map(|g| g.events.len() as u32).sum();
    let past_total: u32 = past_groups.iter().map(|g| g.events.len() as u32).sum();

    let year_links: Vec<NavLink> = past_groups
        .iter()
        .map(|g| NavLink {
            label: format!("{}年", g.year),
            path: format!("/events/past/{}/", url_segment(&g.year)),
            current: false,
            theme_key: None,
            count: Some(g.events.len() as u32),
        })
        .collect();

    let make = |path: &str,
                title: &str,
                kind: EventListKind,
                groups: Vec<YearGroup>,
                data: String,
                description: &str| {
        let total: u32 = groups.iter().map(|g| g.events.len() as u32).sum();
        let year_links = year_links
            .iter()
            .map(|l| NavLink { current: l.path == path, ..l.clone() })
            .collect();
        Emitted {
            path: path.to_string(),
            data,
            page: EventListPage {
                schema_version: SCHEMA_VERSION,
                path: path.to_string(),
                title: title.to_string(),
                kind,
                groups,
                scope_links: scope_links(path, upcoming_total, past_total),
                brand_links: brand_links(ctx, "events", path, "すべて", upcoming_total + past_total),
                year_links,
                total,
                seo: ctx.seo(
                    title,
                    description,
                    path,
                    None,
                    collection_json_ld(title, path),
                    vec![ctx.crumb("ホーム", "/"), ctx.crumb(title, path)],
                ),
            },
        }
    };

    let mut out = vec![
        make(
            "/events/",
            "ライブ",
            EventListKind::Index,
            upcoming_groups.clone(),
            "index/events.json".to_string(),
            "アイドルマスターのライブ・イベントの一覧。今後の開催予定と開催済みを年別に。",
        ),
        make(
            "/events/upcoming/",
            "今後のライブ",
            EventListKind::Upcoming,
            upcoming_groups,
            "index/events-upcoming.json".to_string(),
            "これから開催されるアイドルマスターのライブ・イベント。",
        ),
    ];

    // `/events/past/` は年の入口。中身は最新の年だけ載せる (全部載せると 1 枚が重い)。
    let newest_past = past_groups.first().cloned().into_iter().collect();
    out.push(make(
        "/events/past/",
        "開催済みのライブ",
        EventListKind::Past,
        newest_past,
        "index/events-past.json".to_string(),
        "開催済みのアイドルマスターのライブ・イベントを年別に。",
    ));

    for group in &past_groups {
        let path = format!("/events/past/{}/", url_segment(&group.year));
        out.push(make(
            &path,
            &format!("{}年のライブ", group.year),
            EventListKind::PastYear,
            vec![group.clone()],
            format!("index/events-past-{}.json", group.year),
            &format!("{}年に開催されたアイドルマスターのライブ・イベント。", group.year),
        ));
    }

    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        if ctx.is_other_brand(Some(&brand.id)) {
            continue;
        }
        let records =
            event_list_queries::events_with_first_date(ctx.snap, Some(&brand.id), true, false, Some(&kinds));
        // ブランド別ページなので、行の副題にブランド名は入れない。
        let mut groups = year_groups(ctx, &records, true, false);
        groups.extend(year_groups(ctx, &records, false, false));
        let path = format!("/events/brand/{}/", url_segment(&brand.id));
        out.push(make(
            &path,
            &format!("{}のライブ", brand.name),
            EventListKind::Brand,
            groups,
            format!("index/events-brand-{}.json", ctx.key("brands", &brand.id)),
            &format!("{}のライブ・イベントの一覧。", brand.name),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// 楽曲一覧
// ---------------------------------------------------------------------------

/// 一覧の既定フィルタ。**この 3 つの false/true がコアの「何を隠すか」の判断**で、
/// Web はそれをそのまま使う (派生曲・他ブランド・ライブ限定曲を一覧に出さない)。
fn default_song_filter(brand_ids: Vec<String>) -> SongListFilter {
    SongListFilter {
        brand_ids,
        include_remixes: false,
        include_other_brand: false,
        exclude_live_only: true,
        ..SongListFilter::default()
    }
}

/// 原唱者名を 1 行に畳む。全体曲は 50 人を超えるので、多いときは人数で丸める。
fn artists_display(names: &[&str]) -> Option<String> {
    const SHOWN: usize = 4;
    if names.is_empty() {
        return None;
    }
    if names.len() <= SHOWN {
        return Some(names.join(" / "));
    }
    Some(format!("{} ほか {} 名", names[..SHOWN].join(" / "), names.len() - SHOWN))
}

/// 一覧の 1 行。
///
/// `light` は「`ref` だけの軽い行にするか」。`/songs/all/` は 3,153 行を 1 枚に並べる
/// 到達性のためのハブなので、ジャケ・原唱者・披露回数を落として転送量を削る
/// (付けたままだと 1 ファイル 2MB を超える)。
fn song_list_item(ctx: &Ctx, index: u32, light: bool) -> Option<SongListItem> {
    let song = &ctx.snap.songs[index as usize];
    let mut reference = ctx.song_ref(&song.id)?;
    if light {
        // ジャケも落とす。3,153 枚の外部画像をぶら下げるページにしない。
        reference.artwork_url = None;
        return Some(SongListItem {
            reference,
            release_date: None,
            unit_label: None,
            performance_count: None,
            subtitle: None,
        });
    }
    let names: Vec<&str> = ctx
        .snap
        .song_artists(&song.id, Some("original"))
        .iter()
        .map(|i| i.name.as_str())
        .collect();
    Some(SongListItem {
        subtitle: join_parts([
            song.unit_name.clone(),
            artists_display(&names),
            song.release_date.clone(),
        ]),
        reference,
        release_date: song.release_date.clone(),
        unit_label: song.unit_name.clone(),
        performance_count: Some(ctx.snap.performance_counts[index as usize]),
    })
}

/// ブランドの代表曲 (披露回数の降順)。並べ替えの規則はコアの `song_list_indexes` が持つ。
pub fn brand_top_song_indexes(ctx: &Ctx, brand_id: &str) -> Vec<u32> {
    song_list_indexes(
        ctx.snap,
        &default_song_filter(vec![brand_id.to_string()]),
        SongListSort::PerformanceCount,
        None,
        &[],
        &[],
    )
}

/// よみの先頭 1 文字で切った目次。
///
/// 表示のための区切りなので規則はここに置く (コアの判断ではない)。判定の前に
/// `prepare_needle` を通すので、「ア」も「あ」に入る = 検索の畳み込みと同じ規則になる。
fn kana_sections(ctx: &Ctx, items: &[SongListItem]) -> Vec<KanaSection> {
    let mut sections: Vec<KanaSection> = Vec::new();
    for (i, item) in items.iter().enumerate() {
        let song = ctx.snap.song(&item.reference.id);
        let source = song
            .and_then(|s| s.title_kana.clone())
            .unwrap_or_else(|| item.reference.name.clone());
        let label = kana_label(&source);
        match sections.last_mut() {
            Some(last) if last.label == label => last.count += 1,
            _ => sections.push(KanaSection { label, start_index: i as u32, count: 1 }),
        }
    }
    sections
}

fn kana_label(text: &str) -> String {
    // 畳んでから見るので、カタカナ表記も濁点付きも同じ行に入る。
    let folded = String::from_utf8(prepare_needle(text)).unwrap_or_default();
    let Some(c) = folded.chars().next() else { return "その他".to_string() };
    if c.is_ascii_alphanumeric() {
        return "英数".to_string();
    }
    // ひらがなの行 (小書き・濁点付きも含めて素直に範囲で切る)。
    //
    // 範囲の端に注意: `ゔ` (U+3094) は `ん` (U+3093) の**後ろ**にあるので
    // 「わ行」の範囲に巻き込まれる。`ゕゖ` (U+3095..=U+3096) も同様に末尾にあり、
    // 素直に上から順の範囲だけで書くと「その他」に落ちる。どちらも先に拾う。
    let row = match c {
        // う + 濁点。畳み込みが `う゛` を 1 文字にするので実データに現れる。
        'ゔ' => "あ",
        // 小書きの か / け。
        'ゕ'..='ゖ' => "か",
        'ぁ'..='お' => "あ",
        'か'..='ご' => "か",
        'さ'..='ぞ' => "さ",
        'た'..='ど' => "た",
        'な'..='の' => "な",
        'は'..='ぽ' => "は",
        'ま'..='も' => "ま",
        'ゃ'..='よ' => "や",
        'ら'..='ろ' => "ら",
        'ゎ'..='ん' => "わ",
        _ => return "その他".to_string(),
    };
    row.to_string()
}

pub fn song_lists(ctx: &Ctx) -> Vec<Emitted<SongListPage>> {
    let total_all = ctx.snap.songs.len() as u32;
    // 既定フィルタを通した件数。ブランド切替の「すべて」に出す数はこれ
    // (全 3,153 曲ではなく、その一覧が実際に並べる 2,035 曲)。
    let listed = song_list_indexes(
        ctx.snap,
        &default_song_filter(vec![]),
        SongListSort::TitleKana,
        None,
        &[],
        &[],
    );
    let listed_total = listed.len() as u32;

    let make = |path: String,
                title: String,
                kind: SongListKind,
                indexes: Vec<u32>,
                data: String,
                brand: Option<Ref>,
                description: String| {
        let light = matches!(kind, SongListKind::All);
        let items: Vec<SongListItem> =
            indexes.iter().filter_map(|&i| song_list_item(ctx, i, light)).collect();
        let brand_id = brand.as_ref().map(|b| b.id.clone());
        let mut seo = ctx.seo(
            &title,
            &description,
            &path,
            brand_id.as_deref(),
            collection_json_ld(&title, &path),
            vec![ctx.crumb("ホーム", "/"), ctx.crumb(&title, &path)],
        );
        if matches!(kind, SongListKind::All) {
            // 一覧規則から外れた曲の詳細ページを孤立させないためだけのハブ。
            // 索引には載せず、リンクだけ辿らせる。
            seo.robots = Robots::NoindexFollow;
        }
        Emitted {
            path: path.clone(),
            data,
            page: SongListPage {
                schema_version: SCHEMA_VERSION,
                path: path.clone(),
                title,
                kind,
                brand,
                kana_sections: kana_sections(ctx, &items),
                total: items.len() as u32,
                all_songs_link: (path == "/songs/").then(|| NavLink {
                    label: "派生曲・ライブ限定曲を含む全件".to_string(),
                    path: "/songs/all/".to_string(),
                    current: false,
                    theme_key: None,
                    count: Some(total_all),
                }),
                items,
                brand_links: brand_links(ctx, "songs", &path, "すべて", listed_total),
                seo,
            },
        }
    };

    let mut out = vec![make(
        "/songs/".to_string(),
        "楽曲".to_string(),
        SongListKind::Index,
        listed,
        "index/songs.json".to_string(),
        None,
        "アイドルマスターの楽曲一覧。クレジット・原唱者・ライブでの披露履歴。".to_string(),
    )];

    // 全件ハブ。並びは通常の一覧と同じ規則 (よみ順) にする。
    let all = song_list_indexes(
        ctx.snap,
        &SongListFilter {
            include_remixes: true,
            include_other_brand: true,
            exclude_live_only: false,
            ..SongListFilter::default()
        },
        SongListSort::TitleKana,
        None,
        &[],
        &[],
    );
    out.push(make(
        "/songs/all/".to_string(),
        "楽曲（全件）".to_string(),
        SongListKind::All,
        all,
        "index/songs-all.json".to_string(),
        None,
        format!("収録している全 {total_all} 曲。派生曲・ライブ限定曲を含みます。"),
    ));

    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        if ctx.is_other_brand(Some(&brand.id)) {
            continue;
        }
        let indexes = song_list_indexes(
            ctx.snap,
            &default_song_filter(vec![brand.id.clone()]),
            SongListSort::TitleKana,
            None,
            &[],
            &[],
        );
        out.push(make(
            format!("/songs/brand/{}/", url_segment(&brand.id)),
            format!("{}の楽曲", brand.name),
            SongListKind::Brand,
            indexes,
            format!("index/songs-brand-{}.json", ctx.key("brands", &brand.id)),
            ctx.brand_ref(&brand.id),
            format!("{}の楽曲一覧。", brand.name),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// アイドル一覧
// ---------------------------------------------------------------------------

fn idol_list_item(ctx: &Ctx, record: &idol_queries::IdolRecord) -> Option<IdolListItem> {
    let input = idol_queries::idol_profile_input(record);
    Some(IdolListItem {
        reference: ctx.idol_ref(&record.id)?,
        brand: record.brand_id.as_deref().and_then(|b| ctx.brand_ref(b)),
        current_voice_actor: idol_queries::current_voice_actor_name(ctx.snap, &record.id),
        birthday_display: input.birthday_display,
    })
}

pub fn idol_lists(ctx: &Ctx) -> Vec<Emitted<IdolListPage>> {
    let birth_month_links: Vec<NavLink> = (1..=12u32)
        .map(|m| NavLink {
            label: format!("{m}月"),
            path: format!("/idols/birth-month/{m}/"),
            current: false,
            theme_key: None,
            count: Some(idol_queries::idols_by_birth_month(ctx.snap, m).len() as u32),
        })
        .collect();

    let all_total = idol_queries::idol_list(ctx.snap, None).len() as u32;

    let make = |path: String,
                title: String,
                kind: IdolListKind,
                records: Vec<idol_queries::IdolRecord>,
                data: String,
                brand: Option<Ref>,
                birth_month: Option<u32>,
                description: String| {
        let items: Vec<IdolListItem> =
            records.iter().filter_map(|r| idol_list_item(ctx, r)).collect();
        let brand_id = brand.as_ref().map(|b| b.id.clone());
        Emitted {
            path: path.clone(),
            data,
            page: IdolListPage {
                schema_version: SCHEMA_VERSION,
                path: path.clone(),
                title: title.clone(),
                kind,
                brand,
                birth_month,
                total: items.len() as u32,
                items,
                brand_links: brand_links(ctx, "idols", &path, "すべて", all_total),
                birth_month_links: birth_month_links
                    .iter()
                    .map(|l| NavLink { current: l.path == path, ..l.clone() })
                    .collect(),
                seo: ctx.seo(
                    &title,
                    &description,
                    &path,
                    brand_id.as_deref(),
                    collection_json_ld(&title, &path),
                    vec![ctx.crumb("ホーム", "/"), ctx.crumb(&title, &path)],
                ),
            },
        }
    };

    let mut out = vec![make(
        "/idols/".to_string(),
        "アイドル".to_string(),
        IdolListKind::Index,
        idol_queries::idol_list(ctx.snap, None),
        "index/idols.json".to_string(),
        None,
        None,
        "アイドルマスターのアイドル一覧。プロフィール・CV・持ち曲・出演したライブ。".to_string(),
    )];

    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        out.push(make(
            format!("/idols/brand/{}/", url_segment(&brand.id)),
            format!("{}のアイドル", brand.name),
            IdolListKind::Brand,
            idol_queries::idol_list(ctx.snap, Some(&brand.id)),
            format!("index/idols-brand-{}.json", ctx.key("brands", &brand.id)),
            ctx.brand_ref(&brand.id),
            None,
            format!("{}のアイドル一覧。", brand.name),
        ));
    }

    for month in 1..=12u32 {
        out.push(make(
            format!("/idols/birth-month/{month}/"),
            format!("{month}月生まれのアイドル"),
            IdolListKind::BirthMonth,
            idol_queries::idols_by_birth_month(ctx.snap, month),
            format!("index/idols-birth-month-{month}.json"),
            None,
            Some(month),
            format!("{month}月が誕生日のアイドル一覧。"),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// ユニット一覧
// ---------------------------------------------------------------------------

pub fn unit_lists(ctx: &Ctx) -> Vec<Emitted<UnitListPage>> {
    let index = unit_queries::unit_index_data(ctx.snap);
    let with_songs: std::collections::HashSet<String> = index.song_unit_ids.iter().cloned().collect();
    let member_counts: BTreeMap<String, u32> = index.units.iter().map(|u| {
        let count = ctx
            .snap
            .unit_index_by_id
            .get(&u.id)
            .map(|&i| ctx.snap.members_by_unit[i as usize].len() as u32)
            .unwrap_or(0);
        (u.id.clone(), count)
    }).collect();

    let item = |u: &unit_queries::UnitRecord| -> Option<UnitListItem> {
        let song_count = ctx
            .snap
            .unit_index_by_id
            .get(&u.id)
            .map(|&i| ctx.snap.songs_by_unit[i as usize].len() as u32)
            .unwrap_or(0);
        Some(UnitListItem {
            reference: ctx.unit_ref(&u.id)?,
            brand: ctx.brand_ref(&u.brand_id),
            is_permanent: u.is_permanent,
            member_count: member_counts.get(&u.id).copied().unwrap_or(0),
            song_count: if with_songs.contains(&u.id) { song_count.max(1) } else { song_count },
        })
    };

    let make = |path: String, title: String, units: Vec<&unit_queries::UnitRecord>, data: String, brand: Option<Ref>, description: String| {
        let items: Vec<UnitListItem> = units.iter().filter_map(|u| item(u)).collect();
        let brand_id = brand.as_ref().map(|b| b.id.clone());
        Emitted {
            path: path.clone(),
            data,
            page: UnitListPage {
                schema_version: SCHEMA_VERSION,
                path: path.clone(),
                title: title.clone(),
                brand,
                total: items.len() as u32,
                items,
                brand_links: brand_links(ctx, "units", &path, "すべて", index.units.len() as u32),
                seo: ctx.seo(
                    &title,
                    &description,
                    &path,
                    brand_id.as_deref(),
                    collection_json_ld(&title, &path),
                    vec![ctx.crumb("ホーム", "/"), ctx.crumb(&title, &path)],
                ),
            },
        }
    };

    let mut out = vec![make(
        "/units/".to_string(),
        "ユニット".to_string(),
        index.units.iter().collect(),
        "index/units.json".to_string(),
        None,
        "アイドルマスターのユニット一覧。メンバーとユニット曲。".to_string(),
    )];
    for &i in &ctx.snap.brand_order {
        let brand = &ctx.snap.brands[i as usize];
        if ctx.is_other_brand(Some(&brand.id)) {
            continue;
        }
        out.push(make(
            format!("/units/brand/{}/", url_segment(&brand.id)),
            format!("{}のユニット", brand.name),
            index.units.iter().filter(|u| u.brand_id == brand.id).collect(),
            format!("index/units-brand-{}.json", ctx.key("brands", &brand.id)),
            ctx.brand_ref(&brand.id),
            format!("{}のユニット一覧。", brand.name),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// 会場一覧
// ---------------------------------------------------------------------------

/// 会場の都道府県。空欄は `未分類` にまとめる (実データに 35 件ある)。
pub fn prefecture_of(venue: &crate::domain::snapshot::Venue) -> String {
    match venue.prefecture.as_deref() {
        Some(p) if !p.is_empty() => p.to_string(),
        _ => UNCLASSIFIED_PREFECTURE.to_string(),
    }
}

pub fn venue_lists(ctx: &Ctx) -> Vec<Emitted<VenueListPage>> {
    let show_counts: BTreeMap<&str, u32> = ctx
        .snap
        .venues
        .iter()
        .map(|v| {
            let count =
                ctx.snap.shows_by_venue_id.get(&v.id).map(|s| s.len() as u32).unwrap_or(0);
            (v.id.as_str(), count)
        })
        .collect();

    // 都道府県ごとの並びは venue_order (コアが決めた並び) をそのまま保つ。
    let mut by_prefecture: BTreeMap<String, Vec<u32>> = BTreeMap::new();
    for &i in &ctx.snap.venue_order {
        by_prefecture.entry(prefecture_of(&ctx.snap.venues[i as usize])).or_default().push(i);
    }

    let prefecture_links: Vec<NavLink> = by_prefecture
        .iter()
        .map(|(pref, list)| NavLink {
            label: pref.clone(),
            path: format!("/venues/pref/{}/", url_segment(pref)),
            current: false,
            theme_key: None,
            count: Some(list.len() as u32),
        })
        .collect();

    let item = |i: u32| -> Option<VenueListItem> {
        let v = &ctx.snap.venues[i as usize];
        let location: Vec<&str> = [v.prefecture.as_deref(), v.city.as_deref()]
            .into_iter()
            .flatten()
            .filter(|s| !s.is_empty())
            .collect();
        Some(VenueListItem {
            reference: ctx.venue_ref(&v.id)?,
            prefecture: v.prefecture.clone(),
            city: v.city.clone(),
            location_display: (!location.is_empty()).then(|| location.join(" ")),
            capacity: v.capacity.map(|c| c as i32),
            show_count: show_counts.get(v.id.as_str()).copied().unwrap_or(0),
        })
    };

    let make = |path: String, title: String, indexes: &[u32], data: String, prefecture: Option<String>, description: String| {
        let items: Vec<VenueListItem> = indexes.iter().filter_map(|&i| item(i)).collect();
        Emitted {
            path: path.clone(),
            data,
            page: VenueListPage {
                schema_version: SCHEMA_VERSION,
                path: path.clone(),
                title: title.clone(),
                prefecture,
                total: items.len() as u32,
                items,
                prefecture_links: prefecture_links
                    .iter()
                    .map(|l| NavLink { current: l.path == path, ..l.clone() })
                    .collect(),
                seo: ctx.seo(
                    &title,
                    &description,
                    &path,
                    None,
                    collection_json_ld(&title, &path),
                    vec![ctx.crumb("ホーム", "/"), ctx.crumb(&title, &path)],
                ),
            },
        }
    };

    let all: Vec<u32> = ctx.snap.venue_order.clone();
    let mut out = vec![make(
        "/venues/".to_string(),
        "会場".to_string(),
        &all,
        "index/venues.json".to_string(),
        None,
        "アイドルマスターのライブが行われた会場の一覧。".to_string(),
    )];
    for (pref, indexes) in &by_prefecture {
        out.push(make(
            format!("/venues/pref/{}/", url_segment(pref)),
            format!("{pref}の会場"),
            indexes,
            format!("index/venues-pref-{}.json", ctx.key("venues", pref)),
            Some(pref.clone()),
            format!("{pref}にある、アイドルマスターのライブが行われた会場。"),
        ));
    }
    out
}

// ---------------------------------------------------------------------------
// ブランド一覧 / トップ / About
// ---------------------------------------------------------------------------

/// ブランドカードの見出し。短縮名をそのまま出し、長すぎるものだけ丸める。
fn brand_glyph(short_name: &str) -> String {
    const MAX_CHARS: usize = 6;
    short_name.chars().take(MAX_CHARS).collect()
}

fn brand_list_item(ctx: &Ctx, brand_id: &str) -> Option<BrandListItem> {
    let brand = ctx.brand(brand_id)?;
    let counts = brand_counts(ctx, brand_id);
    Some(BrandListItem {
        reference: ctx.brand_ref(brand_id)?,
        // カードに大きく出す短い名前。短縮名は実データで最長 5 文字なのでそのまま通る。
        // 2 文字に切ると `765AS` → `76`、`学マス` → `学マ` でどれも読めなくなる。
        glyph: brand_glyph(&brand.short_name),
        short_name: Some(brand.short_name.clone()),
        // 素の件数を配ると .astro が組み立て直すことになり、実際にトップと /brands/ で
        // 項目数が食い違っていた (片方だけユニット数が無かった)。
        preview_display: join_parts([
            Some(format!("ライブ {}", counts.events)),
            Some(format!("楽曲 {}", counts.songs)),
            Some(format!("アイドル {}", counts.idols)),
            Some(format!("ユニット {}", counts.units)),
        ])
        .unwrap_or_default(),
    })
}

pub fn brand_list(ctx: &Ctx) -> BrandListPage {
    let path = "/brands/";
    BrandListPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        title: "ブランド".to_string(),
        items: ctx
            .snap
            .brand_order
            .iter()
            .filter_map(|&i| brand_list_item(ctx, &ctx.snap.brands[i as usize].id))
            .collect(),
        seo: ctx.seo(
            "ブランド",
            "アイドルマスターの各ブランドと、その所属アイドル・ユニット・ライブ・楽曲。",
            path,
            None,
            collection_json_ld("ブランド", path),
            vec![ctx.crumb("ホーム", "/"), ctx.crumb("ブランド", path)],
        ),
    }
}

pub fn counts(ctx: &Ctx) -> Counts {
    Counts {
        events: ctx.snap.events.len() as u32,
        shows: ctx.snap.shows.len() as u32,
        songs: ctx.snap.songs.len() as u32,
        idols: ctx.snap.idols.len() as u32,
        units: ctx.snap.units.len() as u32,
        venues: ctx.snap.venues.len() as u32,
        brands: ctx.snap.brands.len() as u32,
        setlist_items: ctx.snap.setlist_items.len() as u32,
    }
}

/// サイト全体の件数タイル。
///
/// `with_links` はタイルから一覧へ飛ばすか (トップは飛ばす / About は読み物なので飛ばさない)。
/// `with_setlist_items` は「セトリ項目」を足すか (About だけ)。
/// どの件数をどの順で出すかの判断はここ 1 箇所にある。
fn site_stat_tiles(counts: Counts, with_links: bool, with_setlist_items: bool) -> Vec<StatTile> {
    let mut rows = vec![
        ("♪", counts.events, "ライブ", "/events/"),
        ("▤", counts.shows, "公演", "/events/past/"),
        ("♬", counts.songs, "楽曲", "/songs/"),
        ("☺", counts.idols, "アイドル", "/idols/"),
        ("❋", counts.units, "ユニット", "/units/"),
        ("⌂", counts.venues, "会場", "/venues/"),
    ];
    if with_setlist_items {
        rows.push(("≡", counts.setlist_items, "セトリ項目", "/songs/"));
    }
    rows.into_iter()
        .map(|(glyph, value, label, href)| StatTile {
            glyph: glyph.to_string(),
            value,
            label: label.to_string(),
            // 「セトリ項目」だけは対応する一覧が無いのでリンクを持たない。
            href: (with_links && label != "セトリ項目").then(|| href.to_string()),
        })
        .collect()
}

/// トップページ。
pub fn home(ctx: &Ctx, upcoming: &[EventListItem], counts: Counts) -> HomePage {
    let path = "/";
    HomePage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        tagline: content::SITE_TAGLINE.to_string(),
        disclaimer: content::SITE_DISCLAIMER.to_string(),
        upcoming: upcoming.iter().take(8).cloned().collect(),
        recent_shows: super::events::recent_shows(ctx, 8),
        stat_tiles: site_stat_tiles(counts, true, false),
        brands: ctx
            .snap
            .brand_order
            .iter()
            .filter_map(|&i| brand_list_item(ctx, &ctx.snap.brands[i as usize].id))
            .collect(),
        app: content::app_links(),
        section_links: vec![
            plain_nav("今後のライブ", "/events/upcoming/", Some(upcoming.len() as u32)),
            plain_nav("開催済み", "/events/past/", None),
            plain_nav("楽曲", "/songs/", Some(counts.songs)),
            plain_nav("アイドル", "/idols/", Some(counts.idols)),
            plain_nav("ユニット", "/units/", Some(counts.units)),
            plain_nav("会場", "/venues/", Some(counts.venues)),
            plain_nav("ブランド", "/brands/", Some(counts.brands)),
            plain_nav("検索", "/search/", None),
            plain_nav("このサイトについて", "/about/", None),
        ],
        seo: ctx.seo(
            content::SITE_NAME,
            content::SITE_TAGLINE,
            path,
            None,
            serde_json::json!({
                        "@type": "WebSite",
                "name": content::SITE_NAME,
                "url": content::absolute("/"),
            }),
            vec![ctx.crumb("ホーム", "/")],
        ),
    }
}

fn plain_nav(label: &str, path: &str, count: Option<u32>) -> NavLink {
    NavLink { label: label.to_string(), path: path.to_string(), current: false, theme_key: None, count }
}

pub fn about(ctx: &Ctx, counts: Counts) -> AboutPage {
    let path = "/about/";
    AboutPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        stat_tiles: site_stat_tiles(counts, false, true),
        data_version: ctx.data_version.clone(),
        content_hash: ctx.content_hash.clone(),
        generated_at: ctx.generated_at.clone(),
        today_jst: ctx.today.clone(),
        app: content::app_links(),
        sections: content::about_sections(),
        seo: ctx.seo(
            "このサイトについて",
            "非公式のファンメイドサイトです。版権方針・ライセンス・アプリ・データの貢献について。",
            path,
            None,
            serde_json::json!({
                        "@type": "AboutPage",
                "name": "このサイトについて",
                "url": content::absolute(path),
            }),
            vec![ctx.crumb("ホーム", "/"), ctx.crumb("このサイトについて", path)],
        ),
    }
}

fn collection_json_ld(name: &str, path: &str) -> serde_json::Value {
    serde_json::json!({
        "@type": "CollectionPage",
        "name": name,
        "url": content::absolute(path),
    })
}

/// 「今後のライブ」のリスト (トップと `/events/upcoming/` が共有する)。
pub fn upcoming_items(ctx: &Ctx) -> Vec<EventListItem> {
    let kinds = all_event_kinds();
    let all = event_list_queries::events_with_first_date(ctx.snap, None, true, false, Some(&kinds));
    year_groups(ctx, &all, true, true).into_iter().flat_map(|g| g.events).collect()
}

/// 会場ページで使う公演要約 (`places.rs` から呼ぶ用の再輸出)。
pub use super::events::show_summary as venue_show_summary;

/// 公演要約を作るときに `detail::ShowRecord` が要るので、その取得口。
pub fn show_record(ctx: &Ctx, show_id: &str) -> Option<ShowSummary> {
    let record = detail::show_record(ctx.snap, show_id)?;
    show_summary(ctx, &record, true)
}
