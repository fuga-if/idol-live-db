//! ライブ (event) と公演 (show) の詳細ページ。

use super::context::{distinguishing_show_name, join_parts, Ctx};
use crate::domain::event_detail_queries as detail;
use crate::domain::event_grouping::group_events_by_year;
use crate::domain::short_year_month::short_year_month;
use crate::web_export::content;
use crate::web_export::dto::*;
use crate::web_export::url::url_segment;
use std::collections::BTreeMap;

/// ライブ 1 件ぶんのページ。
pub fn event_page(ctx: &Ctx, event_id: &str) -> Option<EventPage> {
    let record = detail::event_record(ctx.snap, event_id)?;
    let &index = ctx.snap.event_index_by_id.get(event_id)?;
    let event = &ctx.snap.events[index as usize];
    let (first_date, last_date) = ctx.event_dates[index as usize].clone();
    let path = ctx.path(RefKind::Event, event_id);
    let theme_key = ctx.brand_theme(record.brand_id.as_deref());

    let shows: Vec<ShowSummary> = detail::shows_by_event(ctx.snap, event_id)
        .into_iter()
        .filter_map(|s| show_summary(ctx, &s, false))
        .collect();

    // 会場は初出順で重複排除する (公演の並びが日付順なので、時系列の順になる)。
    let mut seen = std::collections::BTreeSet::new();
    let venues: Vec<Ref> = shows
        .iter()
        .filter_map(|s| s.venue.clone())
        .filter(|v| seen.insert(v.id.clone()))
        .collect();

    let name = event.name.clone();
    let brand = record.brand_id.as_deref().and_then(|b| ctx.brand_ref(b));
    let breadcrumbs = vec![
        ctx.crumb("ホーム", "/"),
        ctx.crumb("ライブ", "/events/"),
        ctx.crumb(&name, &path),
    ];

    Some(EventPage {
        schema_version: SCHEMA_VERSION,
        id: record.id.clone(),
        path: path.clone(),
        name: name.clone(),
        name_kana: event.name_kana.clone(),
        theme_key,
        brand,
        joint_brands: ctx.joint_brand_refs(record.joint_brand_ids.as_deref()),
        kind: record.kind.clone(),
        kind_label: content::kind_label(&record.kind).to_string(),
        event_type: record.event_type.clone(),
        is_upcoming: is_upcoming(ctx, first_date.as_deref()),
        first_date: first_date.clone(),
        last_date: last_date.clone(),
        ticket: TicketInfo {
            open_date: record.ticket_open_date.clone(),
            deadline: record.ticket_deadline.clone(),
            lottery_date: record.ticket_lottery_date.clone(),
            url: record.ticket_url.clone(),
        },
        stats: {
            let s = detail::event_stats(ctx.snap, event_id);
            EventStats {
                show_count: s.show_count,
                total_songs: s.total_songs,
                unique_songs: s.unique_songs,
                cast_count: s.cast_count,
            }
        },
        cast: event_cast(ctx, event_id),
        releases: detail::event_releases(ctx.snap, event_id)
            .into_iter()
            .map(|r| ReleaseInfo {
                id: r.id,
                title: r.title,
                kind_label: release_kind_label(&r.product_type).to_string(),
                kind: Some(r.product_type),
                release_date: r.release_date,
                url: r.purchase_url,
            })
            .collect(),
        venues,
        shows,
        app: content::app_open_deeplink("event", &url_segment(&record.id)),
        seo: ctx.seo(
            &name,
            &event_description(&name, first_date.as_deref(), last_date.as_deref()),
            &path,
            record.brand_id.as_deref(),
            event_json_ld(ctx, &name, &path, first_date.as_deref(), last_date.as_deref()),
            breadcrumbs,
        ),
    })
}

/// 「今後のライブ」か。
///
/// **`>=` をここに書かない。** 分割規則は `event_grouping::group_events_by_year` が持って
/// いるので、1 要素で呼んで空でないかを見る。一覧とページで境界日の扱いがずれないための
/// 遠回り (境界日はどちらでも upcoming 側)。
fn is_upcoming(ctx: &Ctx, first_date: Option<&str>) -> bool {
    let dates = [first_date.map(str::to_string)];
    !group_events_by_year(&dates, true, &ctx.today).is_empty()
}

/// 円盤の種別表記。種別が分からないものは「リリース」。
fn release_kind_label(product_type: &str) -> &'static str {
    match product_type {
        "bluray" => "Blu-ray",
        "dvd" => "DVD",
        "cd" => "CD",
        "digital" => "配信",
        _ => "リリース",
    }
}

fn event_description(name: &str, first: Option<&str>, last: Option<&str>) -> String {
    match (first, last) {
        (Some(f), Some(l)) if f != l => format!("{name}（{f}〜{l}）の公演・セットリスト・出演者。"),
        (Some(f), _) => format!("{name}（{f}）の公演・セットリスト・出演者。"),
        _ => format!("{name}の公演・セットリスト・出演者。"),
    }
}

fn event_json_ld(
    ctx: &Ctx,
    name: &str,
    path: &str,
    first: Option<&str>,
    last: Option<&str>,
) -> serde_json::Value {
    let _ = ctx;
    let mut value = serde_json::json!({
        "@type": "MusicEvent",
        "name": name,
        "url": content::absolute(path),
    });
    // 過去のイベントに eventStatus は付けない (「予定どおり開催」を今さら宣言しない)。
    if let Some(f) = first {
        value["startDate"] = serde_json::Value::String(f.to_string());
    }
    if let Some(l) = last {
        value["endDate"] = serde_json::Value::String(l.to_string());
    }
    value
}

/// 出演者マトリクス。`HashMap` をそのまま serde しないのは、反復順が非決定で
/// 出力のバイト一致 (再現性) を壊すため。
fn event_cast(ctx: &Ctx, event_id: &str) -> Option<EventCast> {
    let record = detail::event_attendance(ctx.snap, event_id)?;
    // 公演の並びは shows_by_event の順 (date ASC, sort_order ASC) をそのまま使う。
    let show_order: Vec<String> = record.shows.iter().map(|s| s.id.clone()).collect();
    let to_rows = |map: &std::collections::HashMap<String, Vec<String>>| -> Vec<ShowIdolIds> {
        show_order
            .iter()
            .map(|show_id| ShowIdolIds {
                show_id: show_id.clone(),
                idol_ids: map.get(show_id).cloned().unwrap_or_default(),
            })
            .collect()
    };
    Some(EventCast {
        brand_idols: record.brand_idol_ids.iter().filter_map(|id| ctx.idol_ref(id)).collect(),
        presence_by_show: to_rows(&record.presence_by_show),
        lead_by_show: to_rows(&record.lead_by_show),
        guest_by_show: to_rows(&record.guest_by_show),
    })
}

/// 公演 1 件の要約。
///
/// `with_event` は「ライブ名を添えるか」。**副題の出し分けもここで済ませる**:
/// ライブ詳細ページの中では親ライブ名は自明なので入れず、トップと会場詳細では入れる。
/// 一覧 JSON はページ単位で吐かれるので、どちらの文脈かは作る側が知っている
/// (TS に `showEvent` のような prop を持たせない)。
pub fn show_summary(
    ctx: &Ctx,
    show: &detail::ShowRecord,
    with_event: bool,
) -> Option<ShowSummary> {
    let event = if with_event { ctx.event_ref(&show.event_id) } else { None };
    // 公演名からライブ名と重なる部分を落とすのは **どちらの文脈でも**。
    // ライブ詳細ページではページ見出しがライブ名なので、副題にその繰り返しが出ると
    // 「ステージ１回目」のような見分けの手掛かりが行末に埋もれる。
    let event_name = ctx.snap.event(&show.event_id).map(|e| e.name.as_str()).unwrap_or_default();
    let show_label = distinguishing_show_name(event_name, &show.name).map(str::to_string);
    let subtitle = join_parts([
        event.as_ref().map(|e| e.name.clone()),
        show_label,
        show.venue.clone(),
        show.hall.clone(),
        show.start_time.as_deref().map(|t| format!("{t} 開演")),
    ]);
    Some(ShowSummary {
        reference: ctx.show_ref(&show.id)?,
        date: show.date.clone(),
        short_date: short_year_month(&show.date),
        venue_label: show.venue.clone(),
        venue: show.venue_id.as_deref().and_then(|v| ctx.venue_ref(v)),
        hall: show.hall.clone(),
        start_time: show.start_time.clone(),
        setlist_count: detail::setlist(ctx.snap, &show.id).len() as u32,
        stream_platform: show.stream_platform.clone(),
        event,
        subtitle,
    })
}

/// 公演 1 件ぶんのページ。
pub fn show_page(ctx: &Ctx, show_id: &str) -> Option<ShowPage> {
    let show = detail::show_record(ctx.snap, show_id)?;
    let event = ctx.event_ref(&show.event_id)?;
    let brand_id = ctx
        .snap
        .event(&show.event_id)
        .and_then(|e| e.brand_id.clone());
    let path = ctx.path(RefKind::Show, show_id);

    let entries = detail::setlist(ctx.snap, show_id);
    let performers = detail::setlist_performers_by_item(ctx.snap, show_id);
    let song_ids: Vec<String> = entries.iter().map(|e| e.song_id.clone()).collect();
    let originals = detail::original_artist_ids_map(ctx.snap, &song_ids);

    let setlist: Vec<SetlistRow> = entries
        .iter()
        .enumerate()
        .filter_map(|(n, e)| {
            Some(SetlistRow {
                id: e.id.clone(),
                // entries は position 昇順なので、添字がそのまま「何曲目か」になる。
                number: n as u32 + 1,
                position: e.position as i32,
                section: e.section.clone(),
                notes: e.notes.clone(),
                unit_label: e.unit_name.clone(),
                song: ctx.song_ref(&e.song_id)?,
                performers: performers
                    .get(&e.id)
                    .map(|list| {
                        list.iter()
                            .filter_map(|p| {
                                Some(PerformerRef {
                                    reference: ctx.idol_ref(&p.idol_id)?,
                                    display_name: p.display_name.clone(),
                                    idol_name: p.idol_name.clone(),
                                })
                            })
                            .collect()
                    })
                    .unwrap_or_default(),
                original_artists: originals
                    .get(&e.song_id)
                    .map(|ids| ids.iter().filter_map(|id| ctx.idol_ref(id)).collect())
                    .unwrap_or_default(),
                is_cover: ctx
                    .snap
                    .song(&e.song_id)
                    .and_then(|s| s.song_type.as_deref())
                    .is_some_and(|t| t == "cover"),
            })
        })
        .collect();

    let venue = show.venue_id.as_deref().and_then(|v| ctx.venue_ref(v));
    let siblings = sibling_shows(ctx, &show.event_id, &event.name);
    let title = format!("{} {}", event.name, show.name);
    let breadcrumbs = vec![
        ctx.crumb("ホーム", "/"),
        ctx.crumb("ライブ", "/events/"),
        ctx.crumb(&event.name, &event.path),
        ctx.crumb(&show.name, &path),
    ];

    Some(ShowPage {
        schema_version: SCHEMA_VERSION,
        id: show.id.clone(),
        path: path.clone(),
        name: show.name.clone(),
        short_date: short_year_month(&show.date),
        date: show.date.clone(),
        theme_key: ctx.brand_theme(brand_id.as_deref()),
        event,
        brand: brand_id.as_deref().and_then(|b| ctx.brand_ref(b)),
        venue_label: show.venue.clone(),
        venue_city: show.venue_city.clone(),
        hall: show.hall.clone(),
        start_time: show.start_time.clone(),
        stream_platform: show.stream_platform.clone(),
        cast: detail::show_cast_idol_ids(ctx.snap, show_id)
            .iter()
            .filter_map(|id| ctx.idol_ref(id))
            .collect(),
        sibling_shows: siblings,
        app: content::app_open_deeplink("show", &url_segment(&show.id)),
        seo: ctx.seo(
            &title,
            &format!(
                "{}（{}）のセットリスト{}。",
                title,
                show.date,
                show.venue.as_deref().map(|v| format!("・{v}")).unwrap_or_default()
            ),
            &path,
            brand_id.as_deref(),
            show_json_ld(&title, &path, &show.date, venue.as_ref(), show.venue.as_deref()),
            breadcrumbs,
        ),
        venue,
        setlist,
    })
}

/// 公演の JSON-LD。
///
/// **会場が分からない公演には `MusicEvent` を出さない。** `location` を欠いた
/// `MusicEvent` は検索エンジンに必須項目落ちとして扱われるので、素の `WebPage` にする。
fn show_json_ld(
    title: &str,
    path: &str,
    date: &str,
    venue: Option<&Ref>,
    venue_label: Option<&str>,
) -> serde_json::Value {
    let url = content::absolute(path);
    let place_name = venue.map(|v| v.name.clone()).or_else(|| venue_label.map(str::to_string));
    match place_name {
        Some(place) => serde_json::json!({
                "@type": "MusicEvent",
            "name": title,
            "url": url,
            "startDate": date,
            "location": { "@type": "Place", "name": place },
        }),
        None => serde_json::json!({
                "@type": "WebPage",
            "name": title,
            "url": url,
        }),
    }
}

/// 「このライブの他の公演」に出すチップ。
///
/// 単日公演のライブでは**空**を返す。自分 1 本しか無いところに「他の公演」を出しても
/// 選べるものが無く、見出しだけが残る。
///
/// 名前はライブ名との重なりを落とした短い形 (`DAY1` / `昼公演` / `ステージ１回目`)。
/// このページの見出しが既にライブ名なので、チップにフルの公演名を並べると同じ文字列が
/// 何度も出て、肝心の見分けが付かなくなる。落とす規則は披露履歴の `placeDisplay` と同じ。
///
/// **公演名がライブ名と丸ごと同じ公演が実データに 38 件ある** (2 日間開催なのに
/// どちらの公演にも同じ名前が付いている)。重なりを落とすと何も残らないので、
/// その場合は日付をチップの名前にする — 区別できるのが日付しか無いのだから、
/// 出すべきものも日付。
fn sibling_shows(ctx: &Ctx, event_id: &str, event_name: &str) -> Vec<Ref> {
    let shows = detail::shows_by_event(ctx.snap, event_id);
    if shows.len() <= 1 {
        return Vec::new();
    }
    shows
        .iter()
        .filter_map(|s| {
            let mut reference = ctx.show_ref(&s.id)?;
            match distinguishing_show_name(event_name, &s.name) {
                Some(short) => {
                    reference.name = short.to_string();
                    reference.sub = Some(s.date.clone());
                }
                None => {
                    reference.name = s.date.clone();
                    // 名前が日付そのものなので、補助表記に日付を重ねない。
                    reference.sub = None;
                }
            }
            Some(reference)
        })
        .collect()
}

/// 会場ページ用: ある会場で行われた公演の要約。
///
/// 並び (date DESC・同日は sort_order と添字で決定化) と、会場マスタ id を持たない
/// 過去公演を `venue` 文字列で拾う後方互換は、どちらも
/// [`detail::shows_at_venue`] が持っている。ここで並べ直さない。
pub fn shows_at_venue(ctx: &Ctx, venue_id: &str) -> Vec<ShowSummary> {
    detail::shows_at_venue(ctx.snap, venue_id)
        .iter()
        .filter_map(|show| show_summary(ctx, show, true))
        .collect()
}

/// トップの「最近の公演」。
///
/// **当日の公演はここに出ない。**「今日以降は今後」という境界の規則は
/// [`detail::recent_shows`] に置いてあり、`group_events_by_year` /
/// `jst_is_today_or_later` と対称になっている (ここで日付を比べると、同じ公演が
/// 「今後のライブ」と「最近の公演」に二重で並ぶ)。
pub fn recent_shows(ctx: &Ctx, limit: u32) -> Vec<ShowSummary> {
    detail::recent_shows(ctx.snap, &ctx.today, limit)
        .iter()
        .filter_map(|show| show_summary(ctx, show, true))
        .collect()
}

/// ライブ id → その公演 id 一覧 (ルート台帳を組むのに使う)。
pub fn show_ids_by_event(ctx: &Ctx) -> BTreeMap<String, Vec<String>> {
    ctx.snap
        .events
        .iter()
        .enumerate()
        .map(|(i, e)| {
            let shows = ctx.snap.shows_by_event[i]
                .iter()
                .map(|&s| ctx.snap.shows[s as usize].id.clone())
                .collect();
            (e.id.clone(), shows)
        })
        .collect()
}
