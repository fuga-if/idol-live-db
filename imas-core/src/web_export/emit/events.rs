//! ライブ (event) と公演 (show) の詳細ページ。

use super::context::{simple_json_ld, Ctx};
use crate::domain::costume_queries as costume;
use crate::domain::date_display::{range_with_weekday, short_with_weekday};
use crate::domain::event_detail_queries as detail;
use crate::domain::snapshot::Snapshot;
use crate::domain::event_grouping::group_events_by_year;
use crate::domain::setlist_lineup::{is_full_cast, summarize, FULL_CAST_LABEL, MISSING_LABEL};
use crate::domain::setlist_sections::{group_consecutive, section_label};
use crate::domain::show_naming::show_identity;
use crate::domain::song_detail_queries::FIRST_PERFORMANCE_LABEL;
use crate::web_export::content;
use crate::web_export::dto::*;
use crate::web_export::url::url_segment;
use std::collections::{BTreeMap, BTreeSet};

/// ライブ 1 件ぶんのページ。
pub fn event_page(ctx: &Ctx, event_id: &str) -> Option<EventPage> {
    let record = detail::event_record(ctx.snap, event_id)?;
    let &index = ctx.snap.event_index_by_id.get(event_id)?;
    let event = &ctx.snap.events[index as usize];
    let (first_date, last_date) = ctx.event_dates[index as usize].clone();
    let path = ctx.path(RefKind::Event, event_id);
    let theme_key = ctx.brand_theme(record.brand_id.as_deref());

    let show_records = detail::shows_by_event(ctx.snap, event_id);
    let shows: Vec<ShowSummary> = show_records
        .iter()
        .filter_map(|s| show_summary(ctx, s, ShowContext::InEvent))
        .collect();

    // 会場は初出順で重複排除する (公演の並びが日付順なので、時系列の順になる)。
    let mut seen = std::collections::BTreeSet::new();
    let venues: Vec<Ref> = show_records
        .iter()
        .filter_map(|s| s.venue_id.as_deref())
        .filter(|id| seen.insert(id.to_string()))
        .filter_map(|id| ctx.venue_ref(id))
        .collect();

    let name = event.name.clone();
    let brand = record.brand_id.as_deref().and_then(|b| ctx.brand_ref(b));
    let breadcrumbs = vec![
        Ctx::crumb("ホーム", "/"),
        Ctx::crumb("ライブ", "/events/"),
        Ctx::crumb(&name, &path),
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
        is_upcoming: is_upcoming(ctx, first_date.as_deref()),
        date_display: range_with_weekday(first_date.as_deref(), last_date.as_deref()),
        ticket: TicketInfo {
            open_date: record.ticket_open_date.clone(),
            deadline: record.ticket_deadline.clone(),
            lottery_date: record.ticket_lottery_date.clone(),
            url: record.ticket_url.clone(),
        },
        stat_tiles: event_stat_tiles(detail::event_stats(ctx.snap, event_id)),
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
            event_json_ld(&name, &path, first_date.as_deref(), last_date.as_deref()),
            breadcrumbs,
        ),
    })
}

/// ライブの数の帯 (公演 / のべ曲数 / 曲数 (重複なし) / 出演者)。対応する一覧が無いので押せない。
fn event_stat_tiles(s: detail::EventStatsRecord) -> Vec<StatTile> {
    nonzero_tiles([
        StatTile::new("▤", s.show_count, "公演"),
        StatTile::new("≡", s.total_songs, "のべ曲数"),
        StatTile::new("♬", s.unique_songs, "曲数 (重複なし)"),
        StatTile::new("☺", s.cast_count, "出演者"),
    ])
}

/// 公演の数の帯 (曲数 / 出演者)。
fn show_stat_tiles(setlist_count: u32, cast_count: u32) -> Vec<StatTile> {
    nonzero_tiles([StatTile::new("≡", setlist_count, "曲"), StatTile::new("☺", cast_count, "出演者")])
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
    name: &str,
    path: &str,
    first: Option<&str>,
    last: Option<&str>,
) -> serde_json::Value {
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

/// 出演者を公演ごとに結合する。
///
/// `HashMap` をそのまま serde しないのは、反復順が非決定で出力のバイト一致
/// (再現性) を壊すため。公演の並びは `event_attendance` が返す順 (date ASC,
/// sort_order ASC) をそのまま使う。
fn event_cast(ctx: &Ctx, event_id: &str) -> Option<EventCast> {
    let record = detail::event_attendance(ctx.snap, event_id)?;
    let lead = |show: &str, idol: &str| {
        record.lead_by_show.get(show).is_some_and(|ids| ids.iter().any(|i| i == idol))
    };
    let guest = |show: &str, idol: &str| {
        record.guest_by_show.get(show).is_some_and(|ids| ids.iter().any(|i| i == idol))
    };
    let shows = record
        .shows
        .iter()
        .filter_map(|show| {
            let performers = record
                .presence_by_show
                .get(&show.id)
                .map(|ids| {
                    ids.iter()
                        .filter_map(|idol_id| {
                            Some(EventCastMember {
                                reference: ctx.idol_ref(idol_id)?,
                                is_lead: lead(&show.id, idol_id),
                                is_guest: guest(&show.id, idol_id),
                            })
                        })
                        .collect()
                })
                .unwrap_or_default();
            Some(EventCastShow { show: ctx.show_ref(&show.id)?, performers })
        })
        .collect();
    Some(EventCast { shows })
}

/// 公演の要約をどこに並べるか。見出し・副題・会場名の出し方がこれで決まる。
///
/// 一覧 JSON はページ単位で吐かれるので、どの文脈かは作る側が知っている
/// (TS に `showEvent` / `omitVenue` のような prop を持たせない)。
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ShowContext {
    /// ライブ詳細の中。ライブ名は自明なので見出しは公演名。
    InEvent,
    /// トップの「最近の公演」。公演名だけでは何のライブか分からないので見出しはライブ名。
    Home,
    /// 会場詳細。見出しはライブ名、会場名は全行同じなので出さない。
    AtVenue,
}

/// 公演 1 件の要約。
///
/// 見出し (`title`) と副題の公演名 (`show_label`) の出し分けはここで済ませる。
/// 公演名とライブ名の切り分けは [`show_identity`] 1 本 — ライブ詳細の中 (見出しが
/// ライブ名) では見分けだけ (`Day2`、無ければ日付)、外 (トップ・会場) ではライブ名を
/// 見出しにして見分けを副題に回す。同じ名前を 2 行続けない。
pub fn show_summary(
    ctx: &Ctx,
    show: &detail::ShowRecord,
    context: ShowContext,
) -> Option<ShowSummary> {
    let event = ctx.event_ref(&show.event_id)?;
    let identity = show_identity(&event.name, &show.name, &show.date);
    let (title, show_label) = match context {
        ShowContext::InEvent => (identity.short.into_text(), None),
        ShowContext::Home | ShowContext::AtVenue => (event.name, identity.label),
    };
    Some(ShowSummary {
        reference: ctx.show_ref(&show.id)?,
        title,
        show_label,
        date: show.date.clone(),
        date_badge: DateBadge::from_ymd(&show.date),
        venue_label: (context != ShowContext::AtVenue).then(|| show.venue.clone()).flatten(),
        hall: hall_unless_in(show.hall.as_deref(), show.venue.as_deref()),
        start_time_display: show.start_time.as_deref().map(|t| format!("{t} 開演")),
        // Eff: セトリ本体を組み直さずに本数だけ数える (前計算済みの索引の長さ)。
        setlist_count: ctx.setlist_len(&show.id),
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

    // 出演者は登録分に歌唱メンバーを足した和集合 (歌っているなら出ている)。
    let cast_ids = detail::show_cast_with_performers(ctx.snap, show_id);
    let cast: BTreeSet<&str> = cast_ids.iter().map(String::as_str).collect();
    let rows = setlist_rows(ctx, show_id, &cast);
    let setlist_count = rows.len() as u32;
    let setlist_sections = group_consecutive(rows)
        .into_iter()
        .map(|(label, rows)| SetlistSection { label, rows })
        .collect();

    // 衣装が指すセトリ行を「公演内で何曲目か」に直す (position は全体通しの値で
    // そのままでは読めない)。番号の求め方はセトリ行・曲ページと同じ ctx の規則。
    let costumes: Vec<ShowCostume> = costume::show_costumes(ctx.snap, show_id)
        .into_iter()
        .map(|c| ShowCostume {
            id: c.costume.id,
            name: c.costume.name,
            attribution: c.costume.attribution,
            description: c.costume.description,
            source_url: c.costume.source_url,
            where_label: costume_where_label(
                &c.songs
                    .iter()
                    .map(|s| ctx.setlist_number(show_id, s.position))
                    .filter(|&n| n > 0)
                    .collect::<Vec<_>>(),
                c.somewhere_in_show,
            ),
            wearers_label: c.wearers_label,
        })
        .collect();

    let venue = show.venue_id.as_deref().and_then(|v| ctx.venue_ref(v));
    let identity = show_identity(&event.name, &show.name, &show.date);
    let title = identity.title();
    // 最後の段は見分けだけ (`Day2`)。1 つ前の段がライブ名なので、フルの公演名を置くと
    // 同じ名前が 2 段続く。
    let breadcrumbs = vec![
        Ctx::crumb("ホーム", "/"),
        Ctx::crumb("ライブ", "/events/"),
        Ctx::crumb(&event.name, &event.path),
        Ctx::crumb(identity.short.text(), &path),
    ];

    Some(ShowPage {
        schema_version: SCHEMA_VERSION,
        is_character_live: detail::is_character_live(show.performer_type.as_deref()),
        id: show.id.clone(),
        path: path.clone(),
        heading: identity.heading,
        show_label: identity.label,
        date_badge: DateBadge::from_ymd(&show.date),
        is_upcoming: is_upcoming(ctx, Some(&show.date)),
        theme_key: ctx.brand_theme(brand_id.as_deref()),
        brand: brand_id.as_deref().and_then(|b| ctx.brand_ref(b)),
        fact_rows: show_fact_rows(&show, venue.as_ref()),
        stat_tiles: show_stat_tiles(setlist_count, cast_ids.len() as u32),
        setlist_sections,
        costumes,
        cast: cast_ids.iter().filter_map(|id| ctx.idol_ref(id)).collect(),
        sibling_shows: sibling_shows(ctx, &show.event_id, &event.name),
        app: content::app_open_deeplink("show", &url_segment(&show.id)),
        seo: ctx.seo(
            &title,
            &format!(
                "{}（{}{}）のセットリストと出演者。",
                title,
                show.date,
                show.venue.as_deref().map(|v| format!("・{v}")).unwrap_or_default()
            ),
            &path,
            brand_id.as_deref(),
            show_json_ld(&title, &path, &show.date, venue.as_ref(), show.venue.as_deref()),
            breadcrumbs,
        ),
        event,
    })
}

/// セトリの行 (position 昇順) を、区切りの見出しと組にして返す。
///
/// 歌唱者・原唱者・出演者の集合の関係 (全員曲か、オリメンが揃っているか、誰がいないか) は
/// ここで解いて行に付ける。画面側で集合を比べ直さない。
fn setlist_rows(
    ctx: &Ctx,
    show_id: &str,
    cast: &BTreeSet<&str>,
) -> Vec<(Option<String>, SetlistRow)> {
    let entries = detail::setlist(ctx.snap, show_id);
    let performers = detail::setlist_performers_by_item(ctx.snap, show_id);
    let song_ids: Vec<String> = entries.iter().map(|e| e.song_id.clone()).collect();
    let originals = detail::original_artist_ids_map(ctx.snap, &song_ids);
    // entries と同じ並び (どちらも setlist_items_by_show を position 順に流す)。何回目かは
    // Snapshot 構築時に決まっている (`ordinal_by_item`)。
    let item_indices: &[u32] = ctx
        .snap
        .show_index_by_id
        .get(show_id)
        .map_or(&[], |&s| ctx.snap.setlist_items_by_show[s as usize].as_slice());

    entries
        .iter()
        .zip(item_indices)
        .enumerate()
        .filter_map(|(n, (e, &item))| {
            let performers = performers.get(&e.id).map(Vec::as_slice).unwrap_or_default();
            let performer_ids: BTreeSet<&str> =
                performers.iter().map(|p| p.idol_id.as_str()).collect();
            let original_ids: Vec<&str> = originals
                .get(&e.song_id)
                .map(|ids| ids.iter().map(String::as_str).collect())
                .unwrap_or_default();
            let full_cast = is_full_cast(cast, &performer_ids);
            let row = SetlistRow {
                id: e.id.clone(),
                // entries は position 昇順なので、添字がそのまま「何曲目か」になる。
                number: n as u32 + 1,
                notes: e.notes.clone(),
                unit_label: e.unit_name.clone(),
                song: ctx.song_ref(&e.song_id)?,
                performers: performers
                    .iter()
                    .filter_map(|p| {
                        Some(PerformerRef {
                            reference: ctx.idol_ref(&p.idol_id)?,
                            // 「同じ名前を 2 つ配らない」判断はコアに任せる。
                            cast_name: detail::distinct_cast_name(p).map(str::to_string),
                        })
                    })
                    .collect(),
                full_cast_label: full_cast.then(|| FULL_CAST_LABEL.to_string()),
                lineup: lineup_note_of(ctx, &original_ids, &performer_ids, cast, full_cast),
                is_cover: ctx.snap.song(&e.song_id).is_some_and(Snapshot::is_cover),
                first_performance_label: (ctx.snap.ordinal_by_item[item as usize] == 1)
                    .then(|| FIRST_PERFORMANCE_LABEL.to_string()),
                // チップの文字列は Rust が組んである (着用者の括弧を付けるかも含めて)。
                costumes: costume::setlist_item_costumes(ctx.snap, &e.id)
                    .into_iter()
                    .map(|c| SetlistCostume { id: c.costume.id, label: c.chip_label })
                    .collect(),
            };
            Some((section_label(e.section.as_deref()), row))
        })
        .collect()
}

/// オリメンとの関係の札。規則も文言も `domain::setlist_lineup` (アプリと同じ)。
/// ここは「いたのに歌わなかった人」の id を Ref に解決するだけ。
fn lineup_note_of(
    ctx: &Ctx,
    original: &[&str],
    performers: &BTreeSet<&str>,
    cast: &BTreeSet<&str>,
    full_cast: bool,
) -> Option<LineupNote> {
    let summary = summarize(original, performers, cast, full_cast)?;
    let idols: Vec<Ref> = summary
        .absent_in_cast
        .iter()
        .filter_map(|id| ctx.idol_ref(id))
        .collect();
    Some(LineupNote {
        kind: summary.lineup,
        label: summary.label(),
        missing: (!idols.is_empty()).then(|| MissingOriginals {
            label: MISSING_LABEL.to_string(),
            idols,
        }),
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
        None => simple_json_ld("WebPage", title, path),
    }
}

/// 公演の「事実の並び」(開演・会場・ホール・所在地・配信)。値が無い行は出さない。
/// 日程は日付ブロック (`date_badge`) が持つので、ここには置かない (同じ日付を 2 度出さない)。
/// 会場はマスタに紐付いていればそのページへ飛べる。名前は自由記述 (`shows.venue`) を
/// 優先する — マスタ名より細かい (ホール名込み等) ことがあるため。
fn show_fact_rows(show: &detail::ShowRecord, venue: Option<&Ref>) -> Vec<ProfileRow> {
    let venue_name = show.venue.clone().or_else(|| venue.map(|v| v.name.clone()));
    let hall = hall_unless_in(show.hall.as_deref(), venue_name.as_deref());
    [
        ("開演", show.start_time.clone(), None),
        ("会場", venue_name, venue.map(|v| v.path.clone())),
        ("ホール", hall, None),
        ("所在地", show.venue_city.clone(), None),
        ("配信", show.stream_platform.clone(), None),
    ]
    .into_iter()
    .filter_map(|(label, value, link)| {
        Some(ProfileRow {
            label: label.to_string(),
            value: value.filter(|v| !v.is_empty())?,
            style: "plain".to_string(),
            link,
        })
    })
    .collect()
}

/// ホール名が会場名に含まれているなら (「さいたまスーパーアリーナ(アリーナモード)」の
/// 「アリーナモード」)、ホールの行は同じ語の繰り返しになるので出さない。
fn hall_unless_in(hall: Option<&str>, venue: Option<&str>) -> Option<String> {
    let hall = hall.filter(|h| !h.is_empty())?;
    (!venue.is_some_and(|v| v.contains(hall))).then(|| hall.to_string())
}

/// 衣装を「どこで着たか」の 1 行にする。
///
/// 曲が分かっている番号を並べ、曲まで特定できていない記録があればそれも足す。
/// **どちらも無い状態は作れない** (着用記録が 1 件も無い衣装はそもそも出てこない)。
fn costume_where_label(song_numbers: &[u32], somewhere_in_show: bool) -> String {
    // 番号の中黒は全角スペースを挟まない (「1・5 曲目」で 1 語に見せたい)。
    let numbers = song_numbers.iter().map(u32::to_string).collect::<Vec<_>>().join("・");
    let songs = (!song_numbers.is_empty()).then(|| format!("{numbers} 曲目"));
    let unplaced = somewhere_in_show.then(|| "公演のどこか".to_string());
    [songs, unplaced].into_iter().flatten().collect::<Vec<_>>().join(" / ")
}

/// 「このライブの他の公演」に出すチップ。
///
/// 単日公演のライブでは**空**を返す。自分 1 本しか無いところに「他の公演」を出しても
/// 選べるものが無く、見出しだけが残る。
///
/// 名前は見分けだけの短い形 (`DAY1` / `昼公演` / 見分けが無ければ `9/13 (日)`)。
/// このページの見出しが既にライブ名なので、チップにフルの公演名を並べると同じ文字列が
/// 何度も出て、肝心の見分けが付かなくなる。切り方は [`show_identity`]。
fn sibling_shows(ctx: &Ctx, event_id: &str, event_name: &str) -> Vec<Ref> {
    let shows = detail::shows_by_event(ctx.snap, event_id);
    if shows.len() <= 1 {
        return Vec::new();
    }
    shows
        .iter()
        .filter_map(|s| {
            let mut reference = ctx.show_ref(&s.id)?;
            let identity = show_identity(event_name, &s.name, &s.date);
            // 名前が日付そのもの (見分けが無い) なら、補助表記に日付を重ねない。
            // 添えるのはページ本体と同じ短い形 (`4/4 (土)`)。ISO を並べると見出しと形が違う。
            reference.sub = identity.short.is_name().then(|| short_with_weekday(&s.date));
            reference.name = identity.short.into_text();
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
        .filter_map(|show| show_summary(ctx, show, ShowContext::AtVenue))
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
        .filter_map(|show| show_summary(ctx, show, ShowContext::Home))
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

#[cfg(test)]
mod tests {
    use super::*;

    /// 「どこで着たか」の 1 行。曲が分かる分と分からない分が混ざる。
    #[test]
    fn costume_where_label_joins_songs_and_the_unplaced_wear() {
        assert_eq!(costume_where_label(&[1], false), "1 曲目");
        assert_eq!(costume_where_label(&[1, 5, 12], false), "1・5・12 曲目");
        assert_eq!(costume_where_label(&[], true), "公演のどこか");
        assert_eq!(costume_where_label(&[3], true), "3 曲目 / 公演のどこか");
    }
}
