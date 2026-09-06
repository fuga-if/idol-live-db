//! コールガイドの進捗ページ (`/calls/`)。
//!
//! 材料は Worker の `GET /calls/dashboard` の写し。ここでやるのは曲 id を Ref に解決し、
//! 数を言葉にし (件・行、編集の言い方)、日時を JST の日付にすること。
//! 編集の言い方は iOS の `CallGuideDashboardViewModel` と同じ規則。

use super::context::{simple_json_ld, Ctx};
use crate::domain::date_display::with_weekday;
use crate::domain::jst_day::jst_today;
use crate::web_export::calls_dashboard::{Dashboard, Edit};
use crate::web_export::content;
use crate::web_export::dto::*;

pub const PATH: &str = "/calls/";
const TITLE: &str = "コールガイドの進捗";
/// Worker が返す「ガイドのある曲」の上限。これに達していたら打ち切りの断りを添える。
const WORKER_SONGS_LIMIT: usize = 200;

pub fn call_guide_page(ctx: &Ctx, dash: &Dashboard) -> CallGuidePage {
    let with_calls: Vec<CallGuideSongRow> = dash
        .songs_with_calls
        .iter()
        .filter_map(|s| {
            Some(CallGuideSongRow {
                song: ctx.song_ref(&s.song_id)?,
                detail: format!("{} 件・{} 行", s.call_count, s.call_lines),
                updated_display: date_display(s.updated_at),
                updated_by: s.updated_by.clone(),
            })
        })
        .collect();
    let recent_edits: Vec<CallGuideEditRow> = dash
        .recent_edits
        .iter()
        .filter_map(|e| {
            Some(CallGuideEditRow {
                song: ctx.song_ref(&e.song_id)?,
                label: edit_label(e),
                at_display: date_display(e.at),
                by: e.by.clone(),
            })
        })
        .collect();
    let wanted: Vec<Ref> = dash
        .tagged_without_calls
        .iter()
        .filter_map(|id| ctx.song_ref(id))
        .collect();
    let tag = dash.call_tag.as_ref();

    let stat_tiles = vec![
        tile("♬", with_calls.len() as u32, "ガイドあり"),
        tile("✎", wanted.len() as u32, "書き手募集中"),
        tile("#", tag.map_or(0, |t| t.tagged), "コール曲タグ付き"),
    ];
    let wanted_note = tag.and_then(|t| {
        (t.without_lyrics > 0).then(|| {
            format!(
                "ほかに「{}」タグの付いた {} 曲は歌詞が未登録のため、ここには並べていません (歌詞が入ってから書けるようになります)。",
                t.tag_name, t.without_lyrics
            )
        })
    });
    let with_calls_note = (dash.songs_with_calls.len() >= WORKER_SONGS_LIMIT)
        .then(|| format!("ここに出ているのは、最近更新された {WORKER_SONGS_LIMIT} 曲です。"));

    CallGuidePage {
        schema_version: SCHEMA_VERSION,
        path: PATH.to_string(),
        title: TITLE.to_string(),
        intro: content::CALL_GUIDE_INTRO.to_string(),
        snapshot_note: format!("{} 時点の情報です (日次で更新)。", jst_datetime(dash.generated_at)),
        stat_tiles,
        with_calls,
        with_calls_note,
        recent_edits,
        wanted,
        wanted_note,
        seo: ctx.seo(
            TITLE,
            "コールガイドがある曲、最近の編集、コール曲タグが付いているのに未整備の曲。書き込みはアプリから。",
            PATH,
            None,
            simple_json_ld("CollectionPage", TITLE, PATH),
            vec![Ctx::crumb("ホーム", "/"), Ctx::crumb(TITLE, PATH)],
        ),
    }
}

fn tile(glyph: &str, value: u32, label: &str) -> StatTile {
    StatTile {
        glyph: glyph.to_string(),
        value,
        label: label.to_string(),
        href: None,
    }
}

/// 編集 1 件の言い方。iOS の `CallGuideDashboardViewModel.label` と同じ 3 分岐。
fn edit_label(e: &Edit) -> String {
    match (e.call_count_before, e.call_count_after) {
        (0, after) if after > 0 => format!("コールを付けた ({after} 件・{} 行)", e.call_lines_after),
        (before, 0) if before > 0 => format!("コールを削除した ({before} 件 → 0)"),
        (before, after) => format!("コールを更新 ({before} → {after} 件)"),
    }
}

/// 秒 epoch (UTC) → JST の日付に曜日。無ければ「日付不明」。
fn date_display(epoch: Option<i64>) -> String {
    epoch.map_or_else(|| "日付不明".to_string(), |t| with_weekday(&jst_today(t)))
}

/// 秒 epoch (UTC) → `2026-09-06 12:34 (JST)`。
fn jst_datetime(epoch: i64) -> String {
    let jst = epoch + 9 * 3600;
    let (h, m) = (jst.rem_euclid(86_400) / 3600, jst.rem_euclid(3600) / 60);
    format!("{} {h:02}:{m:02} (JST)", jst_today(epoch))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn edit(before: (u32, u32), after: (u32, u32)) -> Edit {
        Edit {
            song_id: "s".into(),
            at: None,
            by: "匿名".into(),
            call_lines_before: before.1,
            call_count_before: before.0,
            call_lines_after: after.1,
            call_count_after: after.0,
        }
    }

    #[test]
    fn edit_labels_follow_the_app() {
        assert_eq!(edit_label(&edit((0, 0), (32, 19))), "コールを付けた (32 件・19 行)");
        assert_eq!(edit_label(&edit((5, 3), (0, 0))), "コールを削除した (5 件 → 0)");
        assert_eq!(edit_label(&edit((5, 3), (7, 3))), "コールを更新 (5 → 7 件)");
    }

    #[test]
    fn times_are_shown_in_jst() {
        // 2026-09-05 23:30 UTC = 2026-09-06 08:30 JST (日付が変わる側)。
        let epoch = 1_788_650_000 + 3_000; // 2026-09-05T23:30:00Z 前後
        assert!(jst_datetime(epoch).ends_with("(JST)"));
        assert_eq!(date_display(None), "日付不明");
        assert!(date_display(Some(epoch)).contains("("));
    }
}
