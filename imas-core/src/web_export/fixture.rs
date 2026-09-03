//! 代表値フィクスチャ (`--emit-fixture`) と、その検証 (`--fixture-check`)。
//!
//! ## 何のためにあるか
//!
//! Astro の実装は DB を読まずに始められた方がよい (cargo を回すのは 1 人だけ、という
//! 取り決めもある)。そこで **DTO の代表値だけを実データと同じ形で書き出す**。
//! web-coder はこれを `web/data` の代わりに読み、ページを組み上げる。
//!
//! 手書きのフィクスチャにしないのは、手で書いた JSON は必ず実スキーマからずれるから。
//! ここから出るものは定義上ずれない (同じ serde 構造体を通っている)。
//!
//! ## 代表値に必ず入れる境界ケース
//!
//! 実データの平均値だけを並べても、崩れるのは端の方なので意味が薄い。以下を必ず 1 件ずつ:
//!
//! * 日本語 + `@` + `×` を含む id (percent-encode の確認)
//! * 危険な文字を含む id → フォールバック slug に落ちたページ
//! * `artworkUrl` が `null` の曲 (ソリッド面フォールバックの確認)
//! * `performers` が空のセトリ行
//! * `deeplink` が `null` のページ
//! * 60 文字の名前 (折り返し・省略の確認)
//! * 空の一覧 (`EmptyState` の確認)
//! * `noindex` のページ (`other` ブランド配下)

use super::content::{self, absolute};
use super::dto::*;
use super::url::{detail_path, path_key, reserved_for};
use super::writer::Writer;
use super::{Result, Stats, WebExportError};
use std::path::Path;

const TODAY: &str = "2026-09-04";
const GENERATED_AT: &str = "2026-09-04T00:00:00Z";

/// 60 文字ちょうどの名前 (折り返しの確認用)。
const LONG_NAME: &str = "THE IDOLM@STER MILLION LIVE! 10thLIVE TOUR Act-4 ROAD TO MEMORIES 幕張";

// ---------------------------------------------------------------------------
// 小道具
// ---------------------------------------------------------------------------

/// `Ref` を 1 個作る。`path` は必ず [`detail_path`] を通す (TS に href を組ませない)。
fn make_ref(kind: RefKind, id: &str, name: &str, sub: Option<&str>, theme_key: &str) -> Ref {
    let collection = kind.collection();
    let key = path_key(id, reserved_for(collection), collection);
    Ref {
        kind,
        id: id.to_string(),
        name: name.to_string(),
        sub: sub.map(str::to_string),
        path: detail_path(collection, &key),
        theme_key: theme_key.to_string(),
        artwork_url: None,
        monogram: match kind {
            RefKind::Brand => sub.unwrap_or(name),
            _ => name,
        }
        .chars()
        .next()
        .map(|c| c.to_string())
        .unwrap_or_default(),
    }
}

fn seo(title: &str, description: &str, path: &str, robots: Robots, crumbs: &[(&str, &str)]) -> SeoBlock {
    SeoBlock {
        title: format!("{title} | {}", content::SITE_NAME),
        description: description.to_string(),
        canonical: absolute(path),
        og_image: absolute(content::DEFAULT_OG_IMAGE),
        robots,
        json_ld: serde_json::json!({
            "@context": "https://schema.org",
            "@type": "WebPage",
            "name": title,
            "url": absolute(path),
        }),
        breadcrumbs: crumbs
            .iter()
            .map(|(name, path)| Crumb { name: name.to_string(), path: path.to_string() })
            .collect(),
    }
}

fn counts() -> Counts {
    Counts {
        events: 851,
        shows: 1341,
        songs: 3153,
        idols: 394,
        units: 1539,
        venues: 234,
        brands: 9,
        setlist_items: 13762,
    }
}

fn nav(label: &str, path: &str, current: bool, theme_key: Option<&str>, count: Option<u32>) -> NavLink {
    NavLink {
        label: label.to_string(),
        path: path.to_string(),
        current,
        theme_key: theme_key.map(str::to_string),
        count,
    }
}

// ---------------------------------------------------------------------------
// 代表値
// ---------------------------------------------------------------------------

fn brand_ml() -> Ref {
    make_ref(RefKind::Brand, "ml", "アイドルマスター ミリオンライブ!", Some("ML"), "brand:ml")
}
fn brand_cg() -> Ref {
    make_ref(RefKind::Brand, "cg", "アイドルマスター シンデレラガールズ", Some("CG"), "brand:cg")
}
fn brand_other() -> Ref {
    make_ref(RefKind::Brand, "other", "その他", Some("その他"), "neutral")
}

fn idol_mirai() -> Ref {
    make_ref(RefKind::Idol, "ml_kasuga_mirai", "春日未来", Some("ミリオンライブ!"), "idol:ml_kasuga_mirai")
}
fn idol_shizuka() -> Ref {
    make_ref(RefKind::Idol, "ml_mogami_shizuka", "最上静香", Some("ミリオンライブ!"), "idol:ml_mogami_shizuka")
}

fn song_sample() -> Ref {
    let mut r = make_ref(RefKind::Song, "ml_sample", "Thank You!", Some("765MILLION ALLSTARS"), "brand:ml");
    r.artwork_url = Some("https://is1-ssl.mzstatic.com/image/thumb/Music/sample/600x600bb.jpg".to_string());
    r
}
/// ジャケ無し (`artworkUrl: null`) の曲。
fn song_no_artwork() -> Ref {
    make_ref(RefKind::Song, "ml_no_artwork", "ジャケットの無い曲", None, "brand:ml")
}
/// 派生曲。
fn song_variant() -> Ref {
    make_ref(RefKind::Song, "ml_sample_variant", "Thank You! (Live ver.)", Some("派生曲"), "brand:ml")
}

fn event_sample() -> Ref {
    make_ref(RefKind::Event, "ev_sample", LONG_NAME, Some("2026"), "brand:ml")
}
/// 日本語 + `@` + `×` を含む id。percent-encode がすべての経路で揃うかの確認用。
fn event_weird_id() -> Ref {
    make_ref(
        RefKind::Event,
        "ev_the_idolm@ster_×_ふたご",
        "THE IDOLM@STER × ふたご星",
        Some("2025"),
        "brand:cg",
    )
}
fn show_sample() -> Ref {
    make_ref(RefKind::Show, "sh_sample_1", "DAY1", Some("2026-04-03"), "brand:ml")
}
fn unit_sample() -> Ref {
    make_ref(RefKind::Unit, "unit_sample", "サンプルユニット", Some("ミリオンライブ!"), "brand:ml")
}
/// 曲もメンバーも持たないユニット (空一覧の確認用)。
fn unit_empty() -> Ref {
    make_ref(RefKind::Unit, "unit_empty", "からっぽユニット", None, "neutral")
}
fn venue_sample() -> Ref {
    make_ref(RefKind::Venue, "venue_makuhari", "幕張メッセ", Some("千葉県"), "neutral")
}
/// 危険な文字 (`/`) を含む id。フォールバック slug に落ちる。
fn venue_broken_id() -> Ref {
    make_ref(
        RefKind::Venue,
        "venue_donalde.stephensconventioncenter/hyattregencyo'hare",
        "Donald E. Stephens Convention Center / Hyatt Regency O'Hare",
        None,
        "neutral",
    )
}

// ---------------------------------------------------------------------------
// ページ
// ---------------------------------------------------------------------------

fn site_meta() -> SiteMeta {
    SiteMeta {
        schema_version: SCHEMA_VERSION,
        generated_at: GENERATED_AT.to_string(),
        today_jst: TODAY.to_string(),
        data_version: Some("2026090401".to_string()),
        content_hash: Some("6c41f0e2b9d4a7c8e5f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f7".to_string()),
        counts: counts(),
        app: content::app_links(),
    }
}

/// テーマ表。実データでは 404 件 (アイドル 394 + ブランド 9 + neutral) になる。
/// 代表値では 4 件だけ出し、**値は実際に `color_engine::derive` を通した結果**にする
/// (手で書いた hex を置くと、web 側が見た目を合わせ込んだ後に実データで動く)。
fn theme_table() -> ThemeTable {
    use crate::domain::color_engine::{derive, theme_hex, ImasThemeColors};

    fn tokens(c: &ImasThemeColors) -> ThemeTokens {
        ThemeTokens {
            accent: theme_hex(c.accent),
            on_accent: theme_hex(c.on_accent),
            tint: theme_hex(c.tint),
            tint_strong: theme_hex(c.tint_strong),
            chip_bg: theme_hex(c.chip_bg),
            chip_text: theme_hex(c.chip_text),
            ring: theme_hex(c.ring),
            bar: theme_hex(c.bar),
            dot: theme_hex(c.dot),
            grad_from: theme_hex(c.grad_from),
            grad_to: theme_hex(c.grad_to),
            separator: theme_hex(c.separator),
            hero_surface: theme_hex(c.hero_surface),
            is_neutral: c.is_neutral,
        }
    }
    fn pair(seed: Option<&str>, brand: Option<&str>) -> ThemePair {
        ThemePair {
            light: tokens(&derive(seed, brand, false)),
            dark: tokens(&derive(seed, brand, true)),
        }
    }

    let mut themes = std::collections::BTreeMap::new();
    // ブランド色は brands.color の値だけを渡す。**ブランド id を seed に渡さない**
    // (first_valid_hex の doc: "876" が #887766 として通ってしまう)。
    themes.insert("neutral".to_string(), pair(None, None));
    themes.insert("brand:ml".to_string(), pair(None, Some("#ffc30b")));
    themes.insert("brand:cg".to_string(), pair(None, Some("#2681c8")));
    themes.insert("idol:ml_kasuga_mirai".to_string(), pair(Some("#f39800"), Some("#ffc30b")));
    ThemeTable { schema_version: SCHEMA_VERSION, themes }
}

fn event_page(reference: &Ref, empty: bool) -> EventPage {
    let key = path_key(&reference.id, reserved_for("events"), "events");
    EventPage {
        schema_version: SCHEMA_VERSION,
        id: reference.id.clone(),
        path: reference.path.clone(),
        name: reference.name.clone(),
        name_kana: Some("さんぷるらいぶ".to_string()),
        theme_key: reference.theme_key.clone(),
        brand: Some(brand_ml()),
        joint_brands: if empty { vec![] } else { vec![brand_cg()] },
        kind: "live".to_string(),
        kind_label: content::kind_label("live").to_string(),
        event_type: "tour".to_string(),
        first_date: Some("2026-04-03".to_string()),
        last_date: Some("2026-04-04".to_string()),
        is_upcoming: true,
        ticket: TicketInfo {
            open_date: Some("2026-02-01".to_string()),
            deadline: Some("2026-02-20".to_string()),
            lottery_date: None,
            url: Some("https://example.com/ticket".to_string()),
        },
        stats: if empty {
            EventStats { show_count: 0, total_songs: 0, unique_songs: 0, cast_count: 0 }
        } else {
            EventStats { show_count: 2, total_songs: 46, unique_songs: 41, cast_count: 18 }
        },
        // 公演ゼロのライブ (空一覧の確認)。
        shows: if empty { vec![] } else { vec![show_summary()] },
        cast: if empty {
            // event_attendance は None を返しうる。
            None
        } else {
            Some(EventCast {
                brand_idols: vec![idol_mirai(), idol_shizuka()],
                presence_by_show: vec![ShowIdolIds {
                    show_id: "sh_sample_1".to_string(),
                    idol_ids: vec!["ml_kasuga_mirai".to_string(), "ml_mogami_shizuka".to_string()],
                }],
                lead_by_show: vec![ShowIdolIds {
                    show_id: "sh_sample_1".to_string(),
                    idol_ids: vec!["ml_kasuga_mirai".to_string()],
                }],
                guest_by_show: vec![ShowIdolIds {
                    show_id: "sh_sample_1".to_string(),
                    idol_ids: vec![],
                }],
            })
        },
        releases: if empty {
            vec![]
        } else {
            vec![ReleaseInfo {
                id: "rel_sample".to_string(),
                title: "Blu-ray BOX".to_string(),
                kind: Some("bluray".to_string()),
                kind_label: "Blu-ray".to_string(),
                release_date: Some("2026-10-01".to_string()),
                url: None,
            }]
        },
        venues: if empty { vec![] } else { vec![venue_sample()] },
        app: content::app_open_deeplink("event", &super::url::url_segment(&key)),
        seo: seo(
            &reference.name,
            "ライブの公演・セットリスト・出演者。",
            &reference.path,
            Robots::IndexFollow,
            &[("ホーム", "/"), ("ライブ", "/events/")],
        ),
    }
}

fn show_summary() -> ShowSummary {
    ShowSummary {
        reference: show_sample(),
        date: "2026-04-03".to_string(),
        short_date: "26/04".to_string(),
        venue_label: Some("幕張メッセ".to_string()),
        venue: Some(venue_sample()),
        hall: Some("イベントホール".to_string()),
        start_time: Some("17:00".to_string()),
        setlist_count: 23,
        stream_platform: Some("ニコニコ生放送".to_string()),
        event: Some(event_sample()),
        subtitle: Some("DAY1 ・ 幕張メッセ ・ イベントホール ・ 17:00 開演".to_string()),
    }
}

fn show_page() -> ShowPage {
    let reference = show_sample();
    ShowPage {
        schema_version: SCHEMA_VERSION,
        id: reference.id.clone(),
        path: reference.path.clone(),
        name: "DAY1".to_string(),
        date: "2026-04-03".to_string(),
        short_date: "26/04".to_string(),
        theme_key: reference.theme_key.clone(),
        event: event_sample(),
        brand: Some(brand_ml()),
        venue_label: Some("幕張メッセ".to_string()),
        venue: Some(venue_sample()),
        venue_city: Some("千葉市".to_string()),
        hall: Some("イベントホール".to_string()),
        start_time: Some("17:00".to_string()),
        stream_platform: None,
        setlist: vec![
            SetlistRow {
                id: "si_1".to_string(),
                number: 1,
                position: 11593,
                section: Some("本編".to_string()),
                notes: None,
                unit_label: Some("765MILLION ALLSTARS".to_string()),
                song: song_sample(),
                performers: vec![PerformerRef {
                    reference: idol_mirai(),
                    display_name: "山崎はるか".to_string(),
                    idol_name: "春日未来".to_string(),
                }],
                original_artists: vec![idol_mirai(), idol_shizuka()],
                is_cover: false,
            },
            // 歌唱メンバーが記録されていない行 (実データに多い)。
            SetlistRow {
                id: "si_2".to_string(),
                number: 2,
                position: 11594,
                section: None,
                notes: Some("映像のみ".to_string()),
                unit_label: None,
                song: song_no_artwork(),
                performers: vec![],
                original_artists: vec![],
                is_cover: true,
            },
        ],
        cast: vec![idol_mirai(), idol_shizuka()],
        sibling_shows: vec![show_sample()],
        app: content::app_open_deeplink("show", "sh_sample_1"),
        seo: seo(
            "DAY1",
            "セットリストと歌唱メンバー。",
            &reference.path,
            Robots::IndexFollow,
            &[("ホーム", "/"), ("ライブ", "/events/")],
        ),
    }
}

fn song_page(reference: &Ref, minimal: bool) -> SongPage {
    SongPage {
        schema_version: SCHEMA_VERSION,
        id: reference.id.clone(),
        path: reference.path.clone(),
        title: reference.name.clone(),
        title_kana: if minimal { None } else { Some("さんきゅー".to_string()) },
        theme_key: reference.theme_key.clone(),
        brand: Some(brand_ml()),
        song_type: Some(if minimal { "other".to_string() } else { "original".to_string() }),
        release_date: if minimal { None } else { Some("2019-03-13".to_string()) },
        duration_sec: if minimal { None } else { Some(272) },
        duration_display: if minimal { None } else { Some("4:32".to_string()) },
        credits: if minimal {
            vec![]
        } else {
            vec![
                CreditGroup {
                    role: "作詞".to_string(),
                    raw: "山崎寛子".to_string(),
                    people: vec!["山崎寛子".to_string()],
                    display: "山崎寛子".to_string(),
                },
                CreditGroup {
                    role: "作曲".to_string(),
                    raw: "睦月周平・EFFY".to_string(),
                    people: vec!["睦月周平".to_string(), "EFFY".to_string()],
                    display: "睦月周平 / EFFY".to_string(),
                },
            ]
        },
        series_display: if minimal { None } else { Some("THE IDOLM@STER MILLION THE@TER WAVE".to_string()) },
        cd_series: if minimal { None } else { Some("THE IDOLM@STER MILLION THE@TER WAVE".to_string()) },
        cd_title: if minimal { None } else { Some("Thank You!".to_string()) },
        series_group: None,
        artwork_url: reference.artwork_url.clone(),
        apple_music_url: if minimal {
            None
        } else {
            Some("https://music.apple.com/jp/song/1451234567".to_string())
        },
        jasrac_code: if minimal { None } else { Some("123-4567-8".to_string()) },
        original_artists: if minimal { vec![] } else { vec![idol_mirai(), idol_shizuka()] },
        other_artists: vec![],
        unit: if minimal { None } else { Some(unit_sample()) },
        unit_label: if minimal { None } else { Some("765MILLION ALLSTARS".to_string()) },
        parent: None,
        variants: if minimal { vec![] } else { vec![song_variant()] },
        performance_count: if minimal { 0 } else { 12 },
        performance_history: if minimal {
            vec![]
        } else {
            vec![PerformanceRow {
                show: show_sample(),
                event: event_sample(),
                date: "2026-04-03".to_string(),
                short_date: "26/04".to_string(),
                venue: Some("幕張メッセ".to_string()),
                number: 1,
                position: 11593,
                section: Some("本編".to_string()),
                place_display: "DAY1 ・ 幕張メッセ".to_string(),
            }]
        },
        frequent_singers: if minimal {
            vec![]
        } else {
            vec![SingerRow { idol: idol_mirai(), times: 8, total: 12 }]
        },
        co_occurring: if minimal {
            vec![]
        } else {
            vec![CoOccurRow { song: song_variant(), together: 5, performances: 9 }]
        },
        related: if minimal { vec![] } else { vec![song_variant()] },
        // 曲に deeplink は無い (DeeplinkRouter が受けない)。
        app: content::app_open_plain(),
        seo: seo(
            &reference.name,
            "クレジット・原唱者・披露履歴。",
            &reference.path,
            Robots::IndexFollow,
            &[("ホーム", "/"), ("楽曲", "/songs/")],
        ),
        lyrics_note: content::LYRICS_NOTE.to_string(),
    }
}

/// 派生曲 (親へのリンクを持つ)。
fn song_variant_page() -> SongPage {
    let reference = song_variant();
    let mut page = song_page(&reference, false);
    page.parent = Some(song_sample());
    page.variants = vec![];
    page.song_type = Some("live_ver".to_string());
    page
}

fn idol_page(reference: &Ref) -> IdolPage {
    IdolPage {
        schema_version: SCHEMA_VERSION,
        id: reference.id.clone(),
        path: reference.path.clone(),
        name: reference.name.clone(),
        name_kana: Some("かすがみらい".to_string()),
        theme_key: reference.theme_key.clone(),
        monogram: reference.name.chars().next().map(|c| c.to_string()).unwrap_or_default(),
        brand: Some(brand_ml()),
        brands: vec![brand_ml()],
        color: Some("#f39800".to_string()),
        profile_rows: vec![
            ProfileRow {
                label: "よみ".to_string(),
                value: "かすがみらい".to_string(),
                style: "plain".to_string(),
                link: None,
            },
            ProfileRow {
                label: "誕生日".to_string(),
                value: "4月3日".to_string(),
                style: "plain".to_string(),
                link: Some("/idols/birth-month/4/".to_string()),
            },
            ProfileRow {
                label: "カラー".to_string(),
                value: "#f39800".to_string(),
                style: "colorSwatch".to_string(),
                link: None,
            },
        ],
        current_voice_actor: Some("山崎はるか".to_string()),
        voice_actor_history: vec![VoiceActorRow {
            name: "山崎はるか".to_string(),
            start_date: Some("2013-02-27".to_string()),
            end_date: None,
            is_current: true,
            note: None,
            display: "山崎はるか ・ 2013-02-27 〜".to_string(),
        }],
        units: vec![unit_sample()],
        songs: vec![IdolSongRow {
            song: song_sample(),
            role: Some("original".to_string()),
            release_date: Some("2019-03-13".to_string()),
            performance_count: 12,
            subtitle: Some("765MILLION ALLSTARS ・ 2019-03-13 ・ 12 回披露".to_string()),
        }],
        performed_songs: vec![IdolPerformedRow {
            song: song_variant(),
            times: 3,
            last_date: Some("2026-04-03".to_string()),
            subtitle: Some("派生曲 ・ 3 回披露".to_string()),
        }],
        shows: vec![IdolShowRow {
            show: show_sample(),
            event: event_sample(),
            date: "2026-04-03".to_string(),
            short_date: "26/04".to_string(),
            venue_label: Some("幕張メッセ".to_string()),
            song_count: 7,
            subtitle: Some("DAY1 ・ 幕張メッセ".to_string()),
        }],
        description: None,
        app: content::app_open_plain(),
        seo: seo(
            &reference.name,
            "プロフィール・CV・所属ユニット・持ち曲・出演公演。",
            &reference.path,
            Robots::IndexFollow,
            &[("ホーム", "/"), ("アイドル", "/idols/")],
        ),
    }
}

fn unit_page(reference: &Ref, empty: bool) -> UnitPage {
    UnitPage {
        schema_version: SCHEMA_VERSION,
        id: reference.id.clone(),
        path: reference.path.clone(),
        name: reference.name.clone(),
        name_kana: if empty { None } else { Some("さんぷるゆにっと".to_string()) },
        name_alt: if empty { None } else { Some("Sample Unit".to_string()) },
        theme_key: reference.theme_key.clone(),
        monogram: reference.name.chars().next().map(|c| c.to_string()).unwrap_or_default(),
        is_permanent: !empty,
        brand: if empty { None } else { Some(brand_ml()) },
        members: if empty { vec![] } else { vec![idol_mirai(), idol_shizuka()] },
        songs: if empty { vec![] } else { vec![song_sample()] },
        app: content::app_open_plain(),
        seo: seo(
            &reference.name,
            "メンバーとユニット曲。",
            &reference.path,
            Robots::IndexFollow,
            &[("ホーム", "/"), ("ユニット", "/units/")],
        ),
    }
}

fn venue_page(reference: &Ref, minimal: bool) -> VenuePage {
    VenuePage {
        schema_version: SCHEMA_VERSION,
        id: reference.id.clone(),
        path: reference.path.clone(),
        name: reference.name.clone(),
        name_kana: if minimal { None } else { Some("まくはりめっせ".to_string()) },
        theme_key: "neutral".to_string(),
        // 都道府県が空の会場が 35 件ある。一覧では「未分類」に集める。
        prefecture: if minimal { None } else { Some("千葉県".to_string()) },
        city: if minimal { None } else { Some("千葉市美浜区".to_string()) },
        location_display: if minimal { None } else { Some("千葉県 千葉市美浜区".to_string()) },
        capacity: if minimal { None } else { Some(9000) },
        aliases: if minimal { vec![] } else { vec!["幕張".to_string()] },
        aliases_display: if minimal { None } else { Some("幕張".to_string()) },
        halls: if minimal {
            vec![]
        } else {
            vec![HallRow { name: "イベントホール".to_string(), capacity: Some(9000) }]
        },
        past_names: if minimal {
            vec![]
        } else {
            vec![VenueNameRow {
                name: "日本コンベンションセンター".to_string(),
                start_date: None,
                end_date: Some("1999-03-31".to_string()),
                period_display: Some("〜 1999-03-31".to_string()),
            }]
        },
        events: if minimal { vec![] } else { vec![event_sample()] },
        shows: if minimal { vec![] } else { vec![show_summary()] },
        app: content::app_open_plain(),
        seo: seo(
            &reference.name,
            "この会場で行われたライブと公演。",
            &reference.path,
            Robots::IndexFollow,
            &[("ホーム", "/"), ("会場", "/venues/")],
        ),
    }
}

fn brand_page(reference: &Ref, noindex: bool) -> BrandPage {
    BrandPage {
        schema_version: SCHEMA_VERSION,
        id: reference.id.clone(),
        path: reference.path.clone(),
        name: reference.name.clone(),
        short_name: reference.sub.clone(),
        color: if noindex { None } else { Some("#ffc30b".to_string()) },
        theme_key: reference.theme_key.clone(),
        counts: counts(),
        idols: if noindex { vec![] } else { vec![idol_mirai(), idol_shizuka()] },
        units: if noindex { vec![] } else { vec![unit_sample()] },
        recent_events: if noindex { vec![] } else { vec![event_sample()] },
        top_songs: if noindex { vec![] } else { vec![song_sample()] },
        // `other` (他フランチャイズの合同ライブ曲) は入口を作らない。
        // `/songs/brand/other/` を作ると「既定フィルタは other を含めない」というコアの
        // 規則と、一覧の入口が存在するという事実が食い違う。到達はアイドル一覧と
        // 検索・個別ページからだけにする。
        section_links: if noindex {
            vec![nav("アイドル", &format!("/idols/brand/{}/", reference.id), false, None, Some(12))]
        } else {
            vec![
                nav("ライブ", &format!("/events/brand/{}/", reference.id), false, Some(&reference.theme_key), Some(120)),
                nav("楽曲", &format!("/songs/brand/{}/", reference.id), false, Some(&reference.theme_key), Some(600)),
                nav("アイドル", &format!("/idols/brand/{}/", reference.id), false, Some(&reference.theme_key), Some(52)),
                nav("ユニット", &format!("/units/brand/{}/", reference.id), false, Some(&reference.theme_key), Some(300)),
            ]
        },
        seo: seo(
            &reference.name,
            "ブランドのアイドル・ユニット・ライブ・楽曲。",
            &reference.path,
            if noindex { Robots::NoindexFollow } else { Robots::IndexFollow },
            &[("ホーム", "/"), ("ブランド", "/brands/")],
        ),
    }
}

// --- 一覧 -------------------------------------------------------------------

fn event_list_item(reference: &Ref, kind: &str) -> EventListItem {
    EventListItem {
        reference: reference.clone(),
        first_date: Some("2026-04-03".to_string()),
        last_date: Some("2026-04-04".to_string()),
        short_date: Some("26/04".to_string()),
        brand: Some(brand_ml()),
        kind: kind.to_string(),
        kind_label: content::kind_label(kind).to_string(),
        show_count: 2,
        venue_display: Some("幕張メッセ".to_string()),
        subtitle: Some("2026-04-03 〜 2026-04-04 ・ アイドルマスター ミリオンライブ! ・ 2 公演 ・ 幕張メッセ".to_string()),
        venue_labels: vec!["幕張メッセ".to_string()],
    }
}

fn event_list_page(path: &str, title: &str, kind: EventListKind, empty: bool) -> EventListPage {
    EventListPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        title: title.to_string(),
        kind,
        groups: if empty {
            vec![]
        } else {
            vec![
                YearGroup {
                    year: "2026".to_string(),
                    events: vec![event_list_item(&event_sample(), "live")],
                },
                YearGroup {
                    year: "2025".to_string(),
                    events: vec![event_list_item(&event_weird_id(), "festival")],
                },
            ]
        },
        scope_links: vec![
            nav("今後のライブ", "/events/upcoming/", path == "/events/upcoming/", None, Some(24)),
            nav("開催済み", "/events/past/", path == "/events/past/", None, Some(827)),
        ],
        brand_links: vec![
            nav("すべて", "/events/", path == "/events/", None, None),
            nav("ミリオンライブ!", "/events/brand/ml/", path == "/events/brand/ml/", Some("brand:ml"), Some(210)),
            nav("シンデレラガールズ", "/events/brand/cg/", false, Some("brand:cg"), Some(180)),
        ],
        year_links: vec![
            nav("2026", "/events/past/2026/", false, None, Some(40)),
            nav("2025", "/events/past/2025/", false, None, Some(52)),
        ],
        total: if empty { 0 } else { 2 },
        seo: seo(title, "ライブの一覧。", path, Robots::IndexFollow, &[("ホーム", "/")]),
    }
}

fn song_list_page(path: &str, title: &str, kind: SongListKind) -> SongListPage {
    let items = vec![
        SongListItem {
            reference: song_sample(),
            release_date: Some("2019-03-13".to_string()),
            unit_label: Some("765MILLION ALLSTARS".to_string()),
            artists_display: Some("春日未来".to_string()),
            performance_count: Some(12),
            subtitle: Some("765MILLION ALLSTARS ・ 春日未来 ・ 2019-03-13".to_string()),
        },
        // `/songs/all/` の軽い行 (ref だけ・ジャケも原唱者も披露回数も無い)。
        SongListItem {
            reference: song_no_artwork(),
            release_date: None,
            unit_label: None,
            artists_display: None,
            performance_count: None,
            subtitle: None,
        },
    ];
    SongListPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        title: title.to_string(),
        kind,
        brand: if matches!(kind, SongListKind::Brand) { Some(brand_ml()) } else { None },
        kana_sections: vec![
            KanaSection { label: "さ".to_string(), start_index: 0, count: 1 },
            KanaSection { label: "英数".to_string(), start_index: 1, count: 1 },
        ],
        items,
        brand_links: vec![
            nav("すべて", "/songs/", path == "/songs/", None, Some(2040)),
            nav("ミリオンライブ!", "/songs/brand/ml/", path == "/songs/brand/ml/", Some("brand:ml"), Some(600)),
        ],
        all_songs_link: if path == "/songs/" {
            Some(nav("派生曲・ライブ限定曲を含む全件", "/songs/all/", false, None, Some(3153)))
        } else {
            None
        },
        total: 2,
        seo: seo(
            title,
            "楽曲の一覧。",
            path,
            // /songs/all/ は詳細ページを孤立させないためだけのハブなので index させない。
            if matches!(kind, SongListKind::All) { Robots::NoindexFollow } else { Robots::IndexFollow },
            &[("ホーム", "/")],
        ),
    }
}

fn birth_month_path(month: u32) -> String {
    format!("/idols/birth-month/{month}/")
}

fn idol_list_page(path: &str, title: &str, kind: IdolListKind, empty: bool) -> IdolListPage {
    IdolListPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        title: title.to_string(),
        kind,
        brand: if matches!(kind, IdolListKind::Brand) { Some(brand_ml()) } else { None },
        birth_month: if matches!(kind, IdolListKind::BirthMonth) {
            // path から月を読み戻す (代表値では 1〜12 のページを全部出す)。
            path.trim_end_matches('/').rsplit('/').next().and_then(|m| m.parse().ok())
        } else {
            None
        },
        items: if empty {
            vec![]
        } else {
            vec![
                IdolListItem {
                    reference: idol_mirai(),
                    brand: Some(brand_ml()),
                    current_voice_actor: Some("山崎はるか".to_string()),
                    birthday_display: Some("4月3日".to_string()),
                },
                IdolListItem {
                    reference: idol_shizuka(),
                    brand: Some(brand_ml()),
                    current_voice_actor: Some("田所あずさ".to_string()),
                    birthday_display: Some("6月26日".to_string()),
                },
            ]
        },
        brand_links: vec![
            nav("すべて", "/idols/", path == "/idols/", None, Some(394)),
            nav("ミリオンライブ!", "/idols/brand/ml/", path == "/idols/brand/ml/", Some("brand:ml"), Some(52)),
        ],
        birth_month_links: (1..=12)
            .map(|m| nav(&format!("{m}月"), &birth_month_path(m), path == birth_month_path(m), None, None))
            .collect(),
        total: if empty { 0 } else { 2 },
        seo: seo(title, "アイドルの一覧。", path, Robots::IndexFollow, &[("ホーム", "/")]),
    }
}

fn unit_list_page(path: &str, title: &str) -> UnitListPage {
    UnitListPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        title: title.to_string(),
        brand: if path.contains("/brand/") { Some(brand_ml()) } else { None },
        items: vec![
            UnitListItem {
                reference: unit_sample(),
                brand: Some(brand_ml()),
                is_permanent: true,
                member_count: 2,
                song_count: 1,
            },
            UnitListItem {
                reference: unit_empty(),
                brand: None,
                is_permanent: false,
                member_count: 0,
                song_count: 0,
            },
        ],
        brand_links: vec![
            nav("すべて", "/units/", path == "/units/", None, Some(1539)),
            nav("ミリオンライブ!", "/units/brand/ml/", path == "/units/brand/ml/", Some("brand:ml"), Some(300)),
        ],
        total: 2,
        seo: seo(title, "ユニットの一覧。", path, Robots::IndexFollow, &[("ホーム", "/")]),
    }
}

/// 都道府県が空の会場をまとめる 1 ページ (実データで 35 件ある)。
const UNCLASSIFIED_PREFECTURE: &str = "未分類";

fn pref_path(prefecture: &str) -> String {
    format!("/venues/pref/{}/", super::url::url_segment(prefecture))
}

fn venue_list_page(path: &str, title: &str, prefecture: Option<&str>) -> VenueListPage {
    VenueListPage {
        schema_version: SCHEMA_VERSION,
        path: path.to_string(),
        title: title.to_string(),
        prefecture: prefecture.map(str::to_string),
        items: vec![
            VenueListItem {
                reference: venue_sample(),
                prefecture: Some("千葉県".to_string()),
                city: Some("千葉市美浜区".to_string()),
                location_display: Some("千葉県 千葉市美浜区".to_string()),
                capacity: Some(9000),
                show_count: 24,
            },
            VenueListItem {
                reference: venue_broken_id(),
                prefecture: None,
                city: None,
                location_display: None,
                capacity: None,
                show_count: 1,
            },
        ],
        prefecture_links: vec![
            nav("すべて", "/venues/", path == "/venues/", None, Some(234)),
            nav("東京都", &pref_path("東京都"), path == pref_path("東京都"), None, Some(105)),
            nav(
                UNCLASSIFIED_PREFECTURE,
                &pref_path(UNCLASSIFIED_PREFECTURE),
                path == pref_path(UNCLASSIFIED_PREFECTURE),
                None,
                Some(35),
            ),
        ],
        total: 2,
        seo: seo(title, "会場の一覧。", path, Robots::IndexFollow, &[("ホーム", "/")]),
    }
}

fn brand_list_item(reference: &Ref) -> BrandListItem {
    BrandListItem {
        glyph: reference.sub.as_deref().unwrap_or(&reference.name).chars().take(2).collect(),
        reference: reference.clone(),
        short_name: reference.sub.clone(),
        counts: counts(),
    }
}

fn brand_list_page() -> BrandListPage {
    BrandListPage {
        schema_version: SCHEMA_VERSION,
        path: "/brands/".to_string(),
        title: "ブランド".to_string(),
        items: vec![brand_list_item(&brand_ml()), brand_list_item(&brand_cg()), brand_list_item(&brand_other())],
        seo: seo("ブランド", "ブランドの一覧。", "/brands/", Robots::IndexFollow, &[("ホーム", "/")]),
    }
}

fn home_page() -> HomePage {
    HomePage {
        schema_version: SCHEMA_VERSION,
        path: "/".to_string(),
        tagline: content::SITE_TAGLINE.to_string(),
        disclaimer: content::SITE_DISCLAIMER.to_string(),
        upcoming: vec![event_list_item(&event_sample(), "live")],
        recent_shows: vec![show_summary()],
        counts: counts(),
        brands: vec![brand_list_item(&brand_ml()), brand_list_item(&brand_cg())],
        app: content::app_links(),
        section_links: vec![
            nav("今後のライブ", "/events/upcoming/", false, None, Some(24)),
            nav("開催済み", "/events/past/", false, None, Some(827)),
            nav("楽曲", "/songs/", false, None, Some(2040)),
            nav("アイドル", "/idols/", false, None, Some(394)),
            nav("ユニット", "/units/", false, None, Some(1539)),
            nav("会場", "/venues/", false, None, Some(234)),
            nav("検索", "/search/", false, None, None),
        ],
        seo: seo(content::SITE_NAME, content::SITE_TAGLINE, "/", Robots::IndexFollow, &[]),
    }
}

fn about_page() -> AboutPage {
    AboutPage {
        schema_version: SCHEMA_VERSION,
        path: "/about/".to_string(),
        counts: counts(),
        data_version: Some("2026090401".to_string()),
        content_hash: Some("6c41f0e2b9d4a7c8".to_string()),
        generated_at: GENERATED_AT.to_string(),
        today_jst: TODAY.to_string(),
        app: content::app_links(),
        // About の文面はコアが正。フィクスチャで書き直すと実物とずれる。
        sections: content::about_sections(),
        seo: seo("このサイトについて", "非公式・版権・ライセンス・アプリ。", "/about/", Robots::IndexFollow, &[("ホーム", "/")]),
    }
}

// --- 検索 / パリティ ---------------------------------------------------------

fn search_shard(kind: RefKind, prefix: &str, rows: Vec<SearchRow>) -> SearchShard {
    SearchShard {
        schema_version: SCHEMA_VERSION,
        kind,
        sep: "\u{0001}".to_string(),
        path_prefix: prefix.to_string(),
        rows,
    }
}

fn search_row(name: &str, sub: Option<&str>, key: &str, folded: &[&str]) -> SearchRow {
    SearchRow {
        n: name.to_string(),
        s: sub.map(str::to_string),
        k: key.to_string(),
        f: folded.join("\u{0001}"),
    }
}

fn fold_parity() -> FoldParity {
    // 代表値では手で書いた期待値を置く (実データ版は C3 が
    // `text_search_index::prepare_needle` の出力から生成する)。
    let cases = [
        ("Thank You!", "thank you!"),
        ("オネガイ！シンデレラ", "おねがい！しんでれら"),
        ("ハルカ", "はるか"),
        ("HARUKA", "haruka"),
        ("か\u{3099}っこう", "がっこう"),
        ("ヴィジョン", "ゔぃじょん"),
        ("ラ・ラ・ラ", "ら・ら・ら"),
        ("ー", "ー"),
        ("ΑΣ", "ασ"),
        ("", ""),
    ];
    FoldParity {
        schema_version: SCHEMA_VERSION,
        cases: cases
            .iter()
            .map(|(i, o)| FoldCase { input: (*i).to_string(), output: (*o).to_string() })
            .collect(),
    }
}

// ---------------------------------------------------------------------------
// 書き出し
// ---------------------------------------------------------------------------

/// 代表値を `dir` に書き出す。実データは読まない。
pub fn emit(dir: &Path, pretty: bool) -> Result<Stats> {
    // フィクスチャは人が読んで直すものなので、`--pretty` の指定に関わらず常に整形する。
    let _ = pretty;
    let mut w = Writer::create(dir, true)?;

    let ev_sample = event_sample();
    let ev_weird = event_weird_id();
    let ev_empty = make_ref(RefKind::Event, "ev_empty", "公演未定のライブ", None, "neutral");
    let venue_broken = venue_broken_id();
    let broken_key = path_key(&venue_broken.id, reserved_for("venues"), "venues");

    w.write_json("meta.json", &site_meta())?;
    w.write_json("themes.json", &theme_table())?;

    // --- 詳細 ---
    for (rel, page) in [
        (format!("events/{}.json", path_key(&ev_sample.id, reserved_for("events"), "events")), event_page(&ev_sample, false)),
        (format!("events/{}.json", path_key(&ev_weird.id, reserved_for("events"), "events")), event_page(&ev_weird, false)),
        (format!("events/{}.json", path_key(&ev_empty.id, reserved_for("events"), "events")), event_page(&ev_empty, true)),
    ] {
        w.write_json(&rel, &page)?;
    }
    w.write_json("shows/sh_sample_1.json", &show_page())?;
    w.write_json("songs/ml_sample.json", &song_page(&song_sample(), false))?;
    w.write_json("songs/ml_sample_variant.json", &song_variant_page())?;
    w.write_json("songs/ml_no_artwork.json", &song_page(&song_no_artwork(), true))?;
    w.write_json("idols/ml_kasuga_mirai.json", &idol_page(&idol_mirai()))?;
    w.write_json("idols/ml_mogami_shizuka.json", &idol_page(&idol_shizuka()))?;
    w.write_json("units/unit_sample.json", &unit_page(&unit_sample(), false))?;
    w.write_json("units/unit_empty.json", &unit_page(&unit_empty(), true))?;
    w.write_json("venues/venue_makuhari.json", &venue_page(&venue_sample(), false))?;
    w.write_json(&format!("venues/{broken_key}.json"), &venue_page(&venue_broken, true))?;
    w.count_fallback_slug();
    w.write_json("brands/ml.json", &brand_page(&brand_ml(), false))?;
    w.write_json("brands/cg.json", &brand_page(&brand_cg(), false))?;
    w.write_json("brands/other.json", &brand_page(&brand_other(), true))?;

    // --- 一覧 ---
    w.write_json("index/home.json", &home_page())?;
    w.write_json("index/about.json", &about_page())?;
    w.write_json("index/events.json", &event_list_page("/events/", "ライブ", EventListKind::Index, false))?;
    w.write_json("index/events-upcoming.json", &event_list_page("/events/upcoming/", "今後のライブ", EventListKind::Upcoming, false))?;
    w.write_json("index/events-past.json", &event_list_page("/events/past/", "開催済みのライブ", EventListKind::Past, false))?;
    w.write_json("index/events-past-2026.json", &event_list_page("/events/past/2026/", "2026年のライブ", EventListKind::PastYear, false))?;
    // 空の一覧 (EmptyState の確認用)。
    w.write_json("index/events-brand-ml.json", &event_list_page("/events/brand/ml/", "ミリオンライブ! のライブ", EventListKind::Brand, true))?;
    w.write_json("index/events-brand-cg.json", &event_list_page("/events/brand/cg/", "シンデレラガールズ のライブ", EventListKind::Brand, false))?;
    w.write_json("index/events-past-2025.json", &event_list_page("/events/past/2025/", "2025年のライブ", EventListKind::PastYear, false))?;
    w.write_json("index/songs.json", &song_list_page("/songs/", "楽曲", SongListKind::Index))?;
    w.write_json("index/songs-brand-ml.json", &song_list_page("/songs/brand/ml/", "ミリオンライブ! の楽曲", SongListKind::Brand))?;
    w.write_json("index/songs-brand-cg.json", &song_list_page("/songs/brand/cg/", "シンデレラガールズ の楽曲", SongListKind::Brand))?;
    w.write_json("index/songs-all.json", &song_list_page("/songs/all/", "楽曲 (全件)", SongListKind::All))?;
    w.write_json("index/idols.json", &idol_list_page("/idols/", "アイドル", IdolListKind::Index, false))?;
    w.write_json("index/idols-brand-ml.json", &idol_list_page("/idols/brand/ml/", "ミリオンライブ! のアイドル", IdolListKind::Brand, false))?;
    w.write_json("index/idols-brand-cg.json", &idol_list_page("/idols/brand/cg/", "シンデレラガールズ のアイドル", IdolListKind::Brand, false))?;
    // `other` 配下は noindex にする (非公式サイトが他フランチャイズ名で流入を取らない)。
    let mut other_idols = idol_list_page("/idols/brand/other/", "その他のアイドル", IdolListKind::Brand, false);
    other_idols.brand = Some(brand_other());
    other_idols.seo.robots = Robots::NoindexFollow;
    w.write_json("index/idols-brand-other.json", &other_idols)?;
    // 誕生月は 12 ページ全部出す。1 枚だけだと月ナビのリンク切れを web 側で踏む。
    // 4 月だけ空にしてあるのは EmptyState の確認用。
    for month in 1..=12u32 {
        w.write_json(
            &format!("index/idols-birth-month-{month}.json"),
            &idol_list_page(
                &birth_month_path(month),
                &format!("{month}月生まれのアイドル"),
                IdolListKind::BirthMonth,
                month == 4,
            ),
        )?;
    }
    w.write_json("index/units.json", &unit_list_page("/units/", "ユニット"))?;
    w.write_json("index/units-brand-ml.json", &unit_list_page("/units/brand/ml/", "ミリオンライブ! のユニット"))?;
    w.write_json("index/units-brand-cg.json", &unit_list_page("/units/brand/cg/", "シンデレラガールズ のユニット"))?;
    w.write_json("index/venues.json", &venue_list_page("/venues/", "会場", None))?;
    for pref in ["東京都", UNCLASSIFIED_PREFECTURE] {
        w.write_json(
            &format!("index/venues-pref-{pref}.json"),
            &venue_list_page(&pref_path(pref), &format!("{pref}の会場"), Some(pref)),
        )?;
    }
    w.write_json("index/brands.json", &brand_list_page())?;

    // --- 検索 ---
    let shards = [
        (RefKind::Song, "楽曲", "/songs/", "songs"),
        (RefKind::Idol, "アイドル", "/idols/", "idols"),
        (RefKind::Event, "ライブ", "/events/", "events"),
        (RefKind::Venue, "会場", "/venues/", "venues"),
    ];
    let mut shard_metas = Vec::new();
    for (kind, label, prefix, file) in shards {
        let rows = match kind {
            RefKind::Song => vec![
                search_row("Thank You!", Some("765MILLION ALLSTARS"), "ml_sample", &["thank you!", "さんきゅー"]),
                search_row("ジャケットの無い曲", None, "ml_no_artwork", &["じゃけっとの無い曲"]),
            ],
            RefKind::Idol => vec![
                search_row("春日未来", Some("ミリオンライブ!"), "ml_kasuga_mirai", &["春日未来", "かすがみらい"]),
                search_row("最上静香", Some("ミリオンライブ!"), "ml_mogami_shizuka", &["最上静香", "もがみしずか"]),
            ],
            RefKind::Event => vec![
                search_row(LONG_NAME, Some("2026"), "ev_sample", &["the idolm@ster million live! 10thlive tour act-4 road to memories 幕張"]),
                search_row("THE IDOLM@STER × ふたご星", Some("2025"), "ev_the_idolm@ster_×_ふたご", &["the idolm@ster × ふたご星"]),
            ],
            RefKind::Venue => vec![
                search_row("幕張メッセ", Some("千葉県"), "venue_makuhari", &["幕張めっせ", "まくはりめっせ"]),
                search_row("Donald E. Stephens Convention Center", None, &broken_key, &["donald e. stephens convention center"]),
            ],
            _ => vec![],
        };
        let shard = search_shard(kind, prefix, rows);
        let rel = format!("search/{file}.json");
        let bytes = serde_json::to_string(&shard)?.len() as u32;
        shard_metas.push(SearchShardMeta {
            kind,
            url: format!("/search/{file}.json"),
            label: label.to_string(),
            count: shard.rows.len() as u32,
            bytes,
        });
        w.write_json(&rel, &shard)?;
    }
    w.write_json("search/manifest.json", &SearchManifest { schema_version: SCHEMA_VERSION, shards: shard_metas })?;
    w.write_json("parity/fold.json", &fold_parity())?;

    // --- ルート台帳 ---
    let routes = routes(&broken_key);
    for _ in 0..routes.routes.len() {
        w.count_page();
    }
    w.write_json("routes.json", &routes)?;

    let mut stats = w.into_stats();
    // 代表値のフォールバックは「危険な文字を含む会場 id」1 件だけ (長さ超過は入れていない)。
    stats.fallback_unsafe = stats.fallback_slugs;
    Ok(stats)
}

/// 代表値ぶんのルート台帳。
fn routes(broken_key: &str) -> RoutesFile {
    fn detail(kind: RouteKind, collection: &str, id: &str, key: &str, in_sitemap: bool) -> RouteEntry {
        RouteEntry {
            path: detail_path(collection, key),
            kind,
            key: Some(key.to_string()),
            id: Some(id.to_string()),
            data: format!("{collection}/{key}.json"),
            in_sitemap,
        }
    }
    /// params を取らない一覧 (`/events/` など)。
    fn listing(kind: RouteKind, path: &str, data: &str, in_sitemap: bool) -> RouteEntry {
        RouteEntry { path: path.to_string(), kind, key: None, id: None, data: data.to_string(), in_sitemap }
    }
    /// params を取る一覧 (`/events/past/[year]/` など)。`key` に param の生値を入れる。
    fn param_listing(kind: RouteKind, path: &str, key: &str, data: &str, in_sitemap: bool) -> RouteEntry {
        RouteEntry {
            path: path.to_string(),
            kind,
            key: Some(key.to_string()),
            id: None,
            data: data.to_string(),
            in_sitemap,
        }
    }

    let mut routes = vec![
        listing(RouteKind::Home, "/", "index/home.json", true),
        listing(RouteKind::About, "/about/", "index/about.json", true),
        listing(RouteKind::Search, "/search/", "search/manifest.json", true),
        listing(RouteKind::EventListIndex, "/events/", "index/events.json", true),
        listing(RouteKind::EventListUpcoming, "/events/upcoming/", "index/events-upcoming.json", true),
        listing(RouteKind::EventListPast, "/events/past/", "index/events-past.json", true),
        param_listing(RouteKind::EventListPastYear, "/events/past/2026/", "2026", "index/events-past-2026.json", true),
        param_listing(RouteKind::EventListPastYear, "/events/past/2025/", "2025", "index/events-past-2025.json", true),
        param_listing(RouteKind::EventListBrand, "/events/brand/ml/", "ml", "index/events-brand-ml.json", true),
        param_listing(RouteKind::EventListBrand, "/events/brand/cg/", "cg", "index/events-brand-cg.json", true),
        listing(RouteKind::SongListIndex, "/songs/", "index/songs.json", true),
        param_listing(RouteKind::SongListBrand, "/songs/brand/ml/", "ml", "index/songs-brand-ml.json", true),
        param_listing(RouteKind::SongListBrand, "/songs/brand/cg/", "cg", "index/songs-brand-cg.json", true),
        listing(RouteKind::SongListAll, "/songs/all/", "index/songs-all.json", false),
        listing(RouteKind::IdolListIndex, "/idols/", "index/idols.json", true),
        param_listing(RouteKind::IdolListBrand, "/idols/brand/ml/", "ml", "index/idols-brand-ml.json", true),
        param_listing(RouteKind::IdolListBrand, "/idols/brand/cg/", "cg", "index/idols-brand-cg.json", true),
        // `other` 配下は掲載するが index させない。
        param_listing(RouteKind::IdolListBrand, "/idols/brand/other/", "other", "index/idols-brand-other.json", false),
        listing(RouteKind::UnitListIndex, "/units/", "index/units.json", true),
        param_listing(RouteKind::UnitListBrand, "/units/brand/ml/", "ml", "index/units-brand-ml.json", true),
        param_listing(RouteKind::UnitListBrand, "/units/brand/cg/", "cg", "index/units-brand-cg.json", true),
        listing(RouteKind::VenueListIndex, "/venues/", "index/venues.json", true),
        listing(RouteKind::BrandList, "/brands/", "index/brands.json", true),
        detail(RouteKind::Event, "events", "ev_sample", "ev_sample", true),
        detail(RouteKind::Event, "events", "ev_the_idolm@ster_×_ふたご", "ev_the_idolm@ster_×_ふたご", true),
        detail(RouteKind::Event, "events", "ev_empty", "ev_empty", true),
        detail(RouteKind::Show, "shows", "sh_sample_1", "sh_sample_1", true),
        detail(RouteKind::Song, "songs", "ml_sample", "ml_sample", true),
        detail(RouteKind::Song, "songs", "ml_sample_variant", "ml_sample_variant", true),
        detail(RouteKind::Song, "songs", "ml_no_artwork", "ml_no_artwork", true),
        detail(RouteKind::Idol, "idols", "ml_kasuga_mirai", "ml_kasuga_mirai", true),
        detail(RouteKind::Idol, "idols", "ml_mogami_shizuka", "ml_mogami_shizuka", true),
        detail(RouteKind::Unit, "units", "unit_sample", "unit_sample", true),
        detail(RouteKind::Unit, "units", "unit_empty", "unit_empty", true),
        detail(RouteKind::Venue, "venues", "venue_makuhari", "venue_makuhari", true),
        detail(
            RouteKind::Venue,
            "venues",
            "venue_donalde.stephensconventioncenter/hyattregencyo'hare",
            broken_key,
            true,
        ),
        detail(RouteKind::Brand, "brands", "ml", "ml", true),
        detail(RouteKind::Brand, "brands", "cg", "cg", true),
        detail(RouteKind::Brand, "brands", "other", "other", false),
    ];
    routes.extend((1..=12u32).map(|month| {
        param_listing(
            RouteKind::IdolListBirthMonth,
            &birth_month_path(month),
            &month.to_string(),
            &format!("index/idols-birth-month-{month}.json"),
            true,
        )
    }));
    routes.extend(["東京都", UNCLASSIFIED_PREFECTURE].iter().map(|pref| {
        param_listing(
            RouteKind::VenueListPref,
            &pref_path(pref),
            pref,
            &format!("index/venues-pref-{pref}.json"),
            true,
        )
    }));
    let noindex_paths = routes.iter().filter(|r| !r.in_sitemap).map(|r| r.path.clone()).collect();
    RoutesFile { schema_version: SCHEMA_VERSION, routes, noindex_paths }
}

// ---------------------------------------------------------------------------
// 検証
// ---------------------------------------------------------------------------

/// `dir` 以下の JSON が、対応する DTO でデシリアライズできるかを確かめる。
///
/// 手書きのフィクスチャを使い続ける場合の安全網。認識のズレはここで必ず露見する。
pub fn check(dir: &Path) -> Result<Stats> {
    let mut stats = Stats::default();
    let mut files = Vec::new();
    collect_json(dir, dir, &mut files)?;
    files.sort();
    for rel in &files {
        let path = dir.join(rel);
        let text = std::fs::read_to_string(&path)?;
        verify(rel, &text).map_err(|e| {
            WebExportError::Invariant(format!("{rel} が DTO と一致しない: {e}"))
        })?;
        stats.files += 1;
        stats.bytes += text.len() as u64;
    }
    if stats.files == 0 {
        return Err(WebExportError::Invariant(format!(
            "{} に JSON が 1 本も無い",
            dir.display()
        )));
    }
    Ok(stats)
}

/// 相対パスから型を決めてデシリアライズする。
fn verify(rel: &str, text: &str) -> std::result::Result<(), serde_json::Error> {
    fn as_<T: serde::de::DeserializeOwned>(text: &str) -> std::result::Result<(), serde_json::Error> {
        serde_json::from_str::<T>(text).map(|_| ())
    }
    let name = rel.rsplit('/').next().unwrap_or(rel);
    match rel.split('/').next().unwrap_or("") {
        _ if rel == "meta.json" => as_::<SiteMeta>(text),
        _ if rel == "themes.json" => as_::<ThemeTable>(text),
        _ if rel == "routes.json" => as_::<RoutesFile>(text),
        "index" if name == "home.json" => as_::<HomePage>(text),
        "index" if name == "about.json" => as_::<AboutPage>(text),
        "index" if name == "brands.json" => as_::<BrandListPage>(text),
        "index" if name.starts_with("events") => as_::<EventListPage>(text),
        "index" if name.starts_with("songs") => as_::<SongListPage>(text),
        "index" if name.starts_with("idols") => as_::<IdolListPage>(text),
        "index" if name.starts_with("units") => as_::<UnitListPage>(text),
        "index" if name.starts_with("venues") => as_::<VenueListPage>(text),
        "events" => as_::<EventPage>(text),
        "shows" => as_::<ShowPage>(text),
        "songs" => as_::<SongPage>(text),
        "idols" => as_::<IdolPage>(text),
        "units" => as_::<UnitPage>(text),
        "venues" => as_::<VenuePage>(text),
        "brands" => as_::<BrandPage>(text),
        "search" if name == "manifest.json" => as_::<SearchManifest>(text),
        "search" => as_::<SearchShard>(text),
        "parity" => as_::<FoldParity>(text),
        // 未知のファイルは JSON として妥当なことだけ確かめる。
        _ => as_::<serde_json::Value>(text),
    }
}

/// `.json` を再帰的に集める (返すのは `root` からの相対パス)。
fn collect_json(root: &Path, dir: &Path, out: &mut Vec<String>) -> Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_json(root, &path, out)?;
        } else if path.extension().is_some_and(|e| e == "json") {
            let rel = path.strip_prefix(root).unwrap_or(&path).to_string_lossy().replace('\\', "/");
            out.push(rel);
        }
    }
    Ok(())
}
