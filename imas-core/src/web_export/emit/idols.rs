//! アイドル (idol) とユニット (unit) の詳細ページ。

use super::context::Ctx;
use crate::domain::idol_queries;
use crate::domain::idol_song_queries;
use crate::domain::screen_composition::{idol_profile_rows, RowAction, RowStyle};
use crate::domain::short_year_month::short_year_month;
use crate::domain::unit_queries;
use crate::web_export::content;
use crate::web_export::dto::*;

pub fn idol_page(ctx: &Ctx, idol_id: &str) -> Option<IdolPage> {
    let record = idol_queries::idol_records_by_ids(ctx.snap, std::slice::from_ref(&idol_id.to_string()))
        .into_iter()
        .next()?;
    let &index = ctx.snap.idol_index_by_id.get(idol_id)?;
    let path = ctx.path(RefKind::Idol, idol_id);
    let brand_id = record.brand_id.clone();

    // 所属ブランド (primary 先頭)。掛け持ちのアイドルが居る。
    let brands: Vec<Ref> = ctx.snap.brands_by_idol[index as usize]
        .iter()
        .filter_map(|link| ctx.brand_ref(&ctx.snap.brands[link.brand as usize].id))
        .collect();

    let breadcrumbs = {
        let mut crumbs = vec![ctx.crumb("ホーム", "/"), ctx.crumb("アイドル", "/idols/")];
        if let Some(brand) = brand_id.as_deref().and_then(|b| ctx.brand_ref(b)) {
            crumbs.push(ctx.crumb(&brand.name, &format!("/idols/brand/{}/", brand.id)));
        }
        crumbs.push(ctx.crumb(&record.name, &path));
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
        monogram: record.name.chars().next().map(|c| c.to_string()).unwrap_or_default(),
        brand: brand_id.as_deref().and_then(|b| ctx.brand_ref(b)),
        brands,
        color: record.color.clone(),
        profile_rows: profile_rows(ctx, &record),
        voice_actor_history: idol_queries::voice_actor_history(ctx.snap, idol_id)
            .into_iter()
            .map(|v| VoiceActorRow {
                is_current: voice_actor.as_deref() == Some(v.name.as_str()) && v.valid_to.is_none(),
                name: v.name,
                start_date: v.valid_from,
                end_date: v.valid_to,
                note: None,
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
                Some(IdolSongRow {
                    song: ctx.song_ref(&s.song_id)?,
                    role: Some(s.role),
                    release_date: s.release_date,
                    performance_count,
                })
            })
            .collect(),
        performed_songs: idol_song_queries::idol_performed_songs(ctx.snap, idol_id)
            .into_iter()
            .filter_map(|s| {
                Some(IdolPerformedRow {
                    song: ctx.song_ref(&s.song_id)?,
                    times: s.perform_count,
                    last_date: None,
                })
            })
            .collect(),
        shows: idol_queries::idol_shows(ctx.snap, idol_id)
            .into_iter()
            .filter_map(|s| {
                Some(IdolShowRow {
                    show: ctx.show_ref(&s.show_id)?,
                    event: ctx.event_ref(&s.event_id)?,
                    short_date: short_year_month(&s.date),
                    date: s.date,
                    venue_label: s.venue,
                    song_count: songs_sung_at(ctx, idol_id, &s.show_id),
                })
            })
            .collect(),
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
            serde_json::json!({
                        "@type": "WebPage",
                "name": record.name,
                "url": content::absolute(&path),
            }),
            breadcrumbs,
        ),
    })
}

/// プロフィール行。
///
/// 「何を並べるか」は `screen_composition::idol_profile_rows`、「値をどう作るか」は
/// `idol_queries::idol_profile_input` が持つ。ここは `RowAction` を Web の形
/// (リンクか、リンクでないか) に写すだけ。
fn profile_rows(ctx: &Ctx, record: &idol_queries::IdolRecord) -> Vec<ProfileRow> {
    let _ = ctx;
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

/// そのアイドルがその公演で歌った曲数。
fn songs_sung_at(ctx: &Ctx, idol_id: &str, show_id: &str) -> u32 {
    let (Some(&idol), Some(&show)) =
        (ctx.snap.idol_index_by_id.get(idol_id), ctx.snap.show_index_by_id.get(show_id))
    else {
        return 0;
    };
    let items: std::collections::HashSet<u32> =
        ctx.snap.setlist_items_by_show[show as usize].iter().copied().collect();
    ctx.snap.performed_items_by_idol[idol as usize]
        .iter()
        .filter(|i| items.contains(i))
        .count() as u32
}

pub fn unit_page(ctx: &Ctx, unit_id: &str) -> Option<UnitPage> {
    let record = unit_queries::unit_by_id(ctx.snap, unit_id)?;
    let path = ctx.path(RefKind::Unit, unit_id);
    let breadcrumbs = {
        let mut crumbs = vec![ctx.crumb("ホーム", "/"), ctx.crumb("ユニット", "/units/")];
        // `other` にはブランド別一覧を作っていない (§songs.rs と同じ理由)。
        if !ctx.is_other_brand(Some(&record.brand_id)) {
            if let Some(brand) = ctx.brand_ref(&record.brand_id) {
                crumbs.push(ctx.crumb(&brand.name, &format!("/units/brand/{}/", brand.id)));
            }
        }
        crumbs.push(ctx.crumb(&record.name, &path));
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
        monogram: record.name.chars().next().map(|c| c.to_string()).unwrap_or_default(),
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
            serde_json::json!({
                        "@type": "MusicGroup",
                "name": record.name,
                "url": content::absolute(&path),
            }),
            breadcrumbs,
        ),
    })
}
