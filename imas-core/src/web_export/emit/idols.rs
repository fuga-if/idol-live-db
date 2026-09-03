//! アイドル (idol) とユニット (unit) の詳細ページ。

use super::context::{distinguishing_show_name, join_parts, monogram_of, simple_json_ld, Ctx};
use crate::domain::idol_queries;
use crate::domain::idol_song_queries;
use crate::domain::screen_composition::{idol_profile_rows, RowAction, RowStyle};
use crate::domain::short_year_month::short_year_month;
use crate::domain::unit_queries;
use crate::web_export::content;
use crate::web_export::dto::*;

pub fn idol_page(ctx: &Ctx, idol_id: &str) -> Option<IdolPage> {
    let record =
        idol_queries::idol_records_by_ids(ctx.snap, &[idol_id.to_string()]).into_iter().next()?;
    let &index = ctx.snap.idol_index_by_id.get(idol_id)?;
    let path = ctx.path(RefKind::Idol, idol_id);
    let brand_id = record.brand_id.clone();

    // 所属ブランド (primary 先頭)。掛け持ちのアイドルが居る。
    let brands: Vec<Ref> = ctx.snap.brands_by_idol[index as usize]
        .iter()
        .filter_map(|link| ctx.brand_ref(&ctx.snap.brands[link.brand as usize].id))
        .collect();

    let breadcrumbs = {
        let mut crumbs = vec![Ctx::crumb("ホーム", "/"), Ctx::crumb("アイドル", "/idols/")];
        if let Some(brand) = brand_id.as_deref().and_then(|b| ctx.brand_ref(b)) {
            if let Some(list) = ctx.brand_list_path("idols", &brand.id) {
                crumbs.push(Ctx::crumb(&brand.name, &list));
            }
        }
        crumbs.push(Ctx::crumb(&record.name, &path));
        crumbs
    };

    let voice_actor = idol_queries::current_voice_actor_name(ctx.snap, idol_id);

    Some(IdolPage {
        schema_version: SCHEMA_VERSION,
        id: record.id.clone(),
        path: path.clone(),
        name: record.name.clone(),
        name_kana: record.name_kana.clone(),
        theme_key: ctx.idol_theme(idol_id),
        monogram: monogram_of(RefKind::Idol, &record.name, None),
        brand: brand_id.as_deref().and_then(|b| ctx.brand_ref(b)),
        brands,
        color: record.color.clone(),
        profile_rows: profile_rows(&record),
        voice_actor_history: idol_queries::voice_actor_history(ctx.snap, idol_id)
            .into_iter()
            .map(|v| {
                let period = period_display(v.valid_from.as_deref(), v.valid_to.as_deref());
                VoiceActorRow {
                    is_current: voice_actor.as_deref() == Some(v.name.as_str())
                        && v.valid_to.is_none(),
                    display: join_parts([Some(v.name.clone()), period.clone()])
                        .unwrap_or_else(|| v.name.clone()),
                    name: v.name,
                    start_date: v.valid_from,
                    end_date: v.valid_to,
                }
            })
            .collect(),
        current_voice_actor: voice_actor,
        units: idol_queries::idol_units(ctx.snap, idol_id)
            .iter()
            .filter_map(|u| ctx.unit_ref(&u.id))
            .collect(),
        songs: idol_song_queries::idol_songs(ctx.snap, idol_id, None)
            .into_iter()
            .filter_map(|s| {
                let performance_count = ctx
                    .snap
                    .song_index_by_id
                    .get(&s.song_id)
                    .map(|&i| ctx.snap.performance_counts[i as usize])
                    .unwrap_or(0);
                let song = ctx.song_ref(&s.song_id)?;
                Some(IdolSongRow {
                    subtitle: join_parts([
                        song.sub.clone(),
                        s.release_date.clone(),
                        (performance_count > 0).then(|| format!("{performance_count} 回披露")),
                    ]),
                    song,
                    role: Some(s.role),
                    release_date: s.release_date,
                    performance_count,
                })
            })
            .collect(),
        performed_songs: idol_song_queries::idol_performed_songs(ctx.snap, idol_id)
            .into_iter()
            .filter_map(|s| {
                let song = ctx.song_ref(&s.song_id)?;
                Some(IdolPerformedRow {
                    subtitle: join_parts([
                        song.sub.clone(),
                        Some(format!("{} 回披露", s.perform_count)),
                    ]),
                    song,
                    times: s.perform_count,
                })
            })
            .collect(),
        shows: idol_shows(ctx, idol_id, index),
        description: record.description.clone(),
        app: content::app_open_plain(),
        seo: ctx.seo(
            &record.name,
            &format!(
                "{}のプロフィール・CV・所属ユニット・持ち曲・出演したライブ。",
                record.name
            ),
            &path,
            brand_id.as_deref(),
            simple_json_ld("WebPage", &record.name, &path),
            breadcrumbs,
        ),
    })
}

/// プロフィール行。
///
/// 「何を並べるか」は `screen_composition::idol_profile_rows`、「値をどう作るか」は
/// `idol_queries::idol_profile_input` が持つ。ここは `RowAction` を Web の形
/// (リンクか、リンクでないか) に写すだけ。
fn profile_rows(record: &idol_queries::IdolRecord) -> Vec<ProfileRow> {
    idol_profile_rows(&idol_queries::idol_profile_input(record))
        .into_iter()
        .map(|row| ProfileRow {
            label: row.label,
            value: row.value,
            style: match row.style {
                RowStyle::Plain => "plain",
                RowStyle::Monospaced => "monospaced",
                RowStyle::ColorSwatch => "colorSwatch",
            }
            .to_string(),
            link: match row.action {
                RowAction::FilterByBirthMonth { month } => {
                    Some(format!("/idols/birth-month/{month}/"))
                }
                // Web は書き込みも状態も持たないので、写しボタンも開閉も作らない。
                RowAction::CopyValue | RowAction::ToggleExpansion | RowAction::None => None,
            },
        })
        .collect()
}

/// 在任期間の表記。片側しか無ければその側だけを出す。どちらも無ければ行に出さない。
pub fn period_display(start: Option<&str>, end: Option<&str>) -> Option<String> {
    match (start.filter(|s| !s.is_empty()), end.filter(|s| !s.is_empty())) {
        (None, None) => None,
        (Some(s), None) => Some(format!("{s} 〜")),
        (None, Some(e)) => Some(format!("〜 {e}")),
        (Some(s), Some(e)) => Some(format!("{s} 〜 {e}")),
    }
}

/// 出演公演の行。
///
/// 「その公演で歌った曲数」を公演ごとに求めると、公演の全セトリ項目から HashSet を
/// 作り直すことになる (アイドル 394 人 × 出演公演で 1 万回超)。**アイドルの
/// 披露項目を 1 度だけ集合にして**、公演ごとに数え上げる。
fn idol_shows(ctx: &Ctx, idol_id: &str, idol_index: u32) -> Vec<IdolShowRow> {
    let sung: std::collections::HashSet<u32> =
        ctx.snap.performed_items_by_idol[idol_index as usize].iter().copied().collect();
    idol_queries::idol_shows(ctx.snap, idol_id)
        .into_iter()
        .filter_map(|s| {
            let song_count = ctx
                .snap
                .show_index_by_id
                .get(&s.show_id)
                .map_or(0, |&show| {
                    ctx.snap.setlist_items_by_show[show as usize]
                        .iter()
                        .filter(|i| sung.contains(i))
                        .count() as u32
                });
            // 行のタイトルがライブ名なので、公演名から重なる部分を落とす
            // (披露履歴の placeDisplay と同じ規則)。
            let show_label =
                distinguishing_show_name(&s.event_name, &s.show_name).map(str::to_string);
            Some(IdolShowRow {
                subtitle: join_parts([show_label, s.venue.clone()]),
                show: ctx.show_ref(&s.show_id)?,
                event: ctx.event_ref(&s.event_id)?,
                short_date: short_year_month(&s.date),
                date: s.date,
                venue_label: s.venue,
                song_count,
            })
        })
        .collect()
}

pub fn unit_page(ctx: &Ctx, unit_id: &str) -> Option<UnitPage> {
    let record = unit_queries::unit_by_id(ctx.snap, unit_id)?;
    let path = ctx.path(RefKind::Unit, unit_id);
    let breadcrumbs = {
        let mut crumbs = vec![Ctx::crumb("ホーム", "/"), Ctx::crumb("ユニット", "/units/")];
        if let Some(brand) = ctx.brand_ref(&record.brand_id) {
            if let Some(list) = ctx.brand_list_path("units", &brand.id) {
                crumbs.push(Ctx::crumb(&brand.name, &list));
            }
        }
        crumbs.push(Ctx::crumb(&record.name, &path));
        crumbs
    };

    Some(UnitPage {
        schema_version: SCHEMA_VERSION,
        id: record.id.clone(),
        path: path.clone(),
        name: record.name.clone(),
        name_kana: record.name_kana.clone(),
        name_alt: record.name_alt.clone(),
        theme_key: ctx.brand_theme(Some(&record.brand_id)),
        monogram: monogram_of(RefKind::Idol, &record.name, None),
        is_permanent: record.is_permanent,
        brand: ctx.brand_ref(&record.brand_id),
        members: unit_queries::unit_member_idol_ids(ctx.snap, unit_id)
            .iter()
            .filter_map(|id| ctx.idol_ref(id))
            .collect(),
        songs: unit_queries::unit_song_ids(ctx.snap, unit_id)
            .iter()
            .filter_map(|id| ctx.song_ref(id))
            .collect(),
        app: content::app_open_plain(),
        seo: ctx.seo(
            &record.name,
            &format!("{}のメンバーとユニット曲。", record.name),
            &path,
            Some(&record.brand_id),
            simple_json_ld("MusicGroup", &record.name, &path),
            breadcrumbs,
        ),
    })
}
