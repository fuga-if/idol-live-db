//! ライブ (event) と公演 (show) の詳細ページ。

use super::context::{distinguishing_show_name, simple_json_ld, Ctx};
use crate::domain::date_display::{range_with_weekday, with_weekday};
use crate::domain::event_detail_queries as detail;
use crate::domain::snapshot::Snapshot;
use crate::domain::event_grouping::group_events_by_year;
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

/// ライブの数の帯 (公演 / のべ曲数 / 異なり曲数 / 出演者)。
///
/// **0 は「まだ無い」で情報ではない**ので落とす (開催前は曲数が全部 0 で、並べても
/// 何も言わない)。対応する一覧が無いので押せない (`href` 無し)。
fn event_stat_tiles(s: detail::EventStatsRecord) -> Vec<StatTile> {
    [
        ("▤", s.show_count, "公演"),
        ("≡", s.total_songs, "のべ曲数"),
        ("♬", s.unique_songs, "異なり曲数"),
        ("☺", s.cast_count, "出演者"),
    ]
    .into_iter()
    .filter(|(_, value, _)| *value > 0)
    .map(|(glyph, value, label)| StatTile {
        glyph: glyph.to_string(),
        value,
        label: label.to_string(),
        href: None,
    })
    .collect()
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
/// 公演名からライブ名と重なる部分を落とす規則は披露履歴の `placeDisplay` と同じ
/// `distinguishing_show_name` で、公演名がライブ名そのものなら副題は無い
/// (同じ名前を 2 行続けない)。
pub fn show_summary(
    ctx: &Ctx,
    show: &detail::ShowRecord,
    context: ShowContext,
) -> Option<ShowSummary> {
    let (title, show_label) = match context {
        ShowContext::InEvent => (show.name.clone(), None),
        ShowContext::Home | ShowContext::AtVenue => {
            let event = ctx.event_ref(&show.event_id)?;
            let label = distinguishing_show_name(&event.name, &show.name).map(str::to_string);
            (event.name, label)
        }
    };
    Some(ShowSummary {
        reference: ctx.show_ref(&show.id)?,
        title,
        show_label,
        date: show.date.clone(),
        date_badge: DateBadge::from_ymd(&show.date),
        venue_label: (context != ShowContext::AtVenue).then(|| show.venue.clone()).flatten(),
        hall: show.hall.clone(),
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
                                    // 「同じ名前を 2 つ配らない」判断はコアに任せる。
                                    cast_name: detail::distinct_cast_name(p)
                                        .map(str::to_string),
                                })
                            })
                            .collect()
                    })
                    .unwrap_or_default(),
                original_artists: originals
                    .get(&e.song_id)
                    .map(|ids| ids.iter().filter_map(|id| ctx.idol_ref(id)).collect())
                    .unwrap_or_default(),
                is_cover: ctx.snap.song(&e.song_id).is_some_and(Snapshot::is_cover),
            })
        })
        .collect();

    let venue = show.venue_id.as_deref().and_then(|v| ctx.venue_ref(v));
    let siblings = sibling_shows(ctx, &show.event_id, &event.name);
    // ライブ名との重なりを落とした公演名。<title> と見出しの両方がこれを使う (1 回だけ求める)。
    let short_name = distinguishing_show_name(&event.name, &show.name);
    let title = show_title(&event.name, short_name);
    let breadcrumbs = vec![
        Ctx::crumb("ホーム", "/"),
        Ctx::crumb("ライブ", "/events/"),
        Ctx::crumb(&event.name, &event.path),
        Ctx::crumb(&show.name, &path),
    ];

    Some(ShowPage {
        schema_version: SCHEMA_VERSION,
        is_character_live: detail::is_character_live(show.performer_type.as_deref()),
        id: show.id.clone(),
        path: path.clone(),
        name: show.name.clone(),
        short_name: short_name.map(str::to_string),
        date: show.date.clone(),
        theme_key: ctx.brand_theme(brand_id.as_deref()),
        event,
        brand: brand_id.as_deref().and_then(|b| ctx.brand_ref(b)),
        venue_city: show.venue_city.clone(),
        fact_rows: show_fact_rows(&show, venue.as_ref()),
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
        None => simple_json_ld("WebPage", title, path),
    }
}

/// 公演ページの `<title>`。**ライブ名がちょうど 1 回だけ出る形**にする。
///
/// ここは検索結果・ブラウザのタブ・`og:title` (共有カード) に直接出る文字列で、
/// サイトの中で最も人目に触れる。素朴に `<ライブ名> <公演名>` と繋ぐと、実データでは
/// 2 通りの重複が出る:
///
/// ```text
/// 1. 公演名 = ライブ名 (単日公演に多い)
///      ローソン×アイマスキャンペーン 年忘れシークレットパーティ ローソン×アイマスキャンペーン 年忘れシークレットパーティ
/// 2. 公演名が括弧書きでライブ名を再掲している (11 件)
///      24magic 〜…〜 ★オープニング★(THE IDOLM@STER CINDERELLA GIRLS Live Broadcast 24magic 〜…〜)
/// ```
///
/// 1 は重なりを落とすとライブ名だけが残る。2 は**公演名の側が既にライブ名を抱えている**
/// ので、頭に付け足さない。括弧の中身を削るような加工はしない — 名前の途中を切ると
/// 別の意味に読める文字列ができる。
fn show_title(event_name: &str, distinguishing: Option<&str>) -> String {
    match distinguishing {
        // 公演名がライブ名そのもの。日付は description が持つので、ここはライブ名だけ。
        None => event_name.to_string(),
        // 公演名が既にライブ名を含んでいる。前に付けると 2 回になる。
        Some(rest) if rest.contains(event_name) => rest.to_string(),
        Some(rest) => format!("{event_name} {rest}"),
    }
}

/// 公演の「事実の並び」(日程・開演・会場・ホール・配信)。値が無い行は出さない。
/// 会場はマスタに紐付いていればそのページへ飛べる。名前は自由記述 (`shows.venue`) を
/// 優先する — マスタ名より細かい (ホール名込み等) ことがあるため。
fn show_fact_rows(show: &detail::ShowRecord, venue: Option<&Ref>) -> Vec<ProfileRow> {
    let venue_name = show.venue.clone().or_else(|| venue.map(|v| v.name.clone()));
    [
        ("日程", Some(with_weekday(&show.date)), None),
        ("開演", show.start_time.clone(), None),
        ("会場", venue_name, venue.map(|v| v.path.clone())),
        ("ホール", show.hall.clone(), None),
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
