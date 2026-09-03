//! Web 出面エクスポータの結合テスト (`--features web-export` でのみ走る)。
//!
//! ここで守りたいのは 3 つ:
//! 1. **スキーマが壊れていない** — 書いた JSON がそのまま DTO に戻せる
//! 2. **出力が再現する** — 同じ入力で 2 回流すとバイト一致する (差分レビューが成立する条件)
//! 3. **載せてはいけないものが載っていない** — 歌詞とプレビュー音源

use imas_core::web_export::dto::*;
use imas_core::web_export::url::{is_safe_segment, path_key, reserved_for, url_segment};
use imas_core::web_export::{fixture, Args};
use std::path::{Path, PathBuf};

/// テスト用の一時ディレクトリ。`Drop` で消す。
struct TempDir(PathBuf);

impl TempDir {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "imas-web-export-{tag}-{}-{:?}",
            std::process::id(),
            std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
        ));
        Self(dir)
    }
    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn emit_fixture(tag: &str) -> TempDir {
    let dir = TempDir::new(tag);
    fixture::emit(dir.path(), true).expect("emit_fixture が失敗した");
    dir
}

/// ディレクトリ以下の JSON を (相対パス, 本文) で集める。
fn read_all(root: &Path) -> Vec<(String, String)> {
    fn walk(root: &Path, dir: &Path, out: &mut Vec<(String, String)>) {
        for entry in std::fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                walk(root, &path, out);
            } else if path.extension().is_some_and(|e| e == "json") {
                let rel = path.strip_prefix(root).unwrap().to_string_lossy().into_owned();
                out.push((rel, std::fs::read_to_string(&path).unwrap()));
            }
        }
    }
    let mut out = Vec::new();
    walk(root, root, &mut out);
    out.sort();
    out
}

// ---------------------------------------------------------------------------
// T1: URL 規約
// ---------------------------------------------------------------------------

#[test]
fn t1_url_rules_survive_the_ids_that_actually_exist() {
    // 実データに居る形をそのまま。日本語・@・×・'・( ) は「安全」で、生のまま置く。
    for id in [
        "ml_kasuga_mirai",
        "ev_the_idolm@ster_×_ふたご",
        "venue_grandpeacepalace(慶熙大学,ソウル)",
        "o'hare",
        "song_9:02pm".trim_end_matches("9:02pm"), // ":" を含む形は下で別途
    ] {
        if id.is_empty() {
            continue;
        }
        assert_eq!(path_key(id, &[], "x"), id, "安全な id は素通しになるはず: {id}");
    }

    // 危険な文字・予約語・`.`・空・長すぎは落とす。
    for id in ["a/b", "a%b", "a?b", "a#b", "a:b", "a\\b", "a\"b", "a<b", "a|b", ".", "..", ""] {
        assert!(!is_safe_segment(id, &[]), "危険な id を安全と判定した: {id:?}");
        assert!(!path_key(id, &[], "x").contains(['/', '%', '?', '#', ':', '\\']));
    }
    assert_ne!(path_key("upcoming", reserved_for("events"), "ev"), "upcoming");
    assert_ne!(path_key("all", reserved_for("songs"), "song"), "all");

    // encode は JS の encodeURIComponent と完全一致 (検索 island が同じ href を組むため)。
    assert_eq!(url_segment("ev_the_idolm@ster_×_ふたご"), "ev_the_idolm%40ster_%C3%97_%E3%81%B5%E3%81%9F%E3%81%94");
    assert_eq!(url_segment("aA0-_.!~*'()"), "aA0-_.!~*'()");
}

// ---------------------------------------------------------------------------
// T7 / T10: スキーマの往復
// ---------------------------------------------------------------------------

#[test]
fn t7_every_emitted_json_deserializes_back_into_its_dto() {
    let dir = emit_fixture("roundtrip");
    let stats = fixture::check(dir.path()).expect("--fixture-check が落ちた");
    assert!(stats.files >= 30, "書き出したファイルが少なすぎる: {}", stats.files);
}

#[test]
fn t7b_pages_survive_a_full_serde_round_trip() {
    let dir = emit_fixture("serde");
    // 代表的な 1 枚ずつを「読む → 書く → 読む」でバイト一致まで確認する。
    macro_rules! round {
        ($rel:expr, $ty:ty) => {{
            let text = std::fs::read_to_string(dir.path().join($rel)).unwrap();
            let value: $ty = serde_json::from_str(&text).expect(concat!($rel, " が読めない"));
            let again = serde_json::to_string_pretty(&value).unwrap();
            let value2: $ty = serde_json::from_str(&again).unwrap();
            assert_eq!(value, value2, concat!($rel, " が往復で変わった"));
        }};
    }
    round!("meta.json", SiteMeta);
    round!("themes.json", ThemeTable);
    round!("routes.json", RoutesFile);
    round!("index/home.json", HomePage);
    round!("index/about.json", AboutPage);
    round!("index/events.json", EventListPage);
    round!("index/songs.json", SongListPage);
    round!("index/idols.json", IdolListPage);
    round!("index/units.json", UnitListPage);
    round!("index/venues.json", VenueListPage);
    round!("index/brands.json", BrandListPage);
    round!("events/ev_sample.json", EventPage);
    round!("shows/sh_sample_1.json", ShowPage);
    round!("songs/ml_sample.json", SongPage);
    round!("idols/ml_kasuga_mirai.json", IdolPage);
    round!("units/unit_sample.json", UnitPage);
    round!("venues/venue_makuhari.json", VenuePage);
    round!("brands/ml.json", BrandPage);
    round!("search/manifest.json", SearchManifest);
    round!("search/songs.json", SearchShard);
    round!("parity/fold.json", FoldParity);
}

// ---------------------------------------------------------------------------
// T9: 再現性
// ---------------------------------------------------------------------------

#[test]
fn t9_two_runs_produce_byte_identical_output() {
    let a = emit_fixture("repeat-a");
    let b = emit_fixture("repeat-b");
    let (fa, fb) = (read_all(a.path()), read_all(b.path()));
    assert_eq!(
        fa.iter().map(|(r, _)| r.as_str()).collect::<Vec<_>>(),
        fb.iter().map(|(r, _)| r.as_str()).collect::<Vec<_>>(),
        "2 回の実行でファイルの顔ぶれが違う"
    );
    for ((rel, x), (_, y)) in fa.iter().zip(&fb) {
        assert_eq!(x, y, "{rel} が 2 回の実行でバイト一致しない (HashMap を serde していないか)");
    }
}

// ---------------------------------------------------------------------------
// T12 (DECISIONS A7): 歌詞とプレビュー音源を出さない
// ---------------------------------------------------------------------------

#[test]
fn t12_no_lyrics_or_preview_audio_anywhere_in_the_output() {
    let dir = emit_fixture("forbidden");

    /// 唯一許すキー。「歌詞はアプリで」の固定文であって歌詞本文ではない。
    const ALLOWED: &str = "lyricsNote";

    fn walk(rel: &str, value: &serde_json::Value) {
        match value {
            serde_json::Value::Object(map) => {
                for (key, child) in map {
                    let lower = key.to_lowercase();
                    if lower.contains("lyric") {
                        assert_eq!(key, ALLOWED, "{rel}: 歌詞まわりのキーは {ALLOWED} 以外を出さない ({key})");
                    }
                    assert!(
                        !lower.contains("preview"),
                        "{rel}: プレビュー音源のキーを出してはいけない ({key})"
                    );
                    walk(rel, child);
                }
            }
            serde_json::Value::Array(items) => items.iter().for_each(|v| walk(rel, v)),
            serde_json::Value::String(s) => {
                assert!(
                    !s.contains("audio-ssl.itunes.apple.com") && !s.contains(".m4a"),
                    "{rel}: プレビュー音源の URL を出してはいけない ({s})"
                );
            }
            _ => {}
        }
    }

    for (rel, text) in read_all(dir.path()) {
        walk(&rel, &serde_json::from_str(&text).unwrap());
    }
}

// ---------------------------------------------------------------------------
// 代表値が「端」を含んでいること (web-coder がここで崩れ方を見る)
// ---------------------------------------------------------------------------

#[test]
fn fixture_covers_the_boundary_cases_the_web_needs() {
    let dir = emit_fixture("boundary");
    let read = |rel: &str| std::fs::read_to_string(dir.path().join(rel)).unwrap();

    // 日本語 + @ + × を含む id → percent-encode された path が出ている。
    let weird: EventPage =
        serde_json::from_str(&read("events/ev_the_idolm@ster_×_ふたご.json")).unwrap();
    assert!(weird.path.contains("%40") && weird.path.contains("%C3%97"), "{}", weird.path);
    assert!(weird.path.ends_with('/'));

    // 危険な id → フォールバック slug に落ち、path に生の "/" が残らない。
    let routes: RoutesFile = serde_json::from_str(&read("routes.json")).unwrap();
    let broken = routes
        .routes
        .iter()
        .find(|r| r.id.as_deref() == Some("venue_donalde.stephensconventioncenter/hyattregencyo'hare"))
        .expect("フォールバック slug の会場が代表値に無い");
    assert_ne!(broken.key.as_deref(), broken.id.as_deref(), "危険な id なのに key が生のまま");
    assert_eq!(broken.path.matches('/').count(), 3, "{}", broken.path); // /venues/<key>/

    // params を取るルートには必ず key が入っている (getStaticPaths がそれだけで書けること)。
    for entry in &routes.routes {
        let takes_param = matches!(
            entry.kind,
            RouteKind::EventListPastYear
                | RouteKind::EventListBrand
                | RouteKind::SongListBrand
                | RouteKind::IdolListBrand
                | RouteKind::IdolListBirthMonth
                | RouteKind::UnitListBrand
                | RouteKind::VenueListPref
                | RouteKind::Event
                | RouteKind::Show
                | RouteKind::Song
                | RouteKind::Idol
                | RouteKind::Unit
                | RouteKind::Venue
                | RouteKind::Brand
        );
        assert_eq!(
            entry.key.is_some(),
            takes_param,
            "{:?} ({}) の key の有無が params の有無と食い違う",
            entry.kind,
            entry.path
        );
        // key は URL に percent-encode して現れる (組み立て規則を TS に持たせないための担保)。
        if let Some(key) = &entry.key {
            assert!(
                entry.path.contains(&url_segment(key)),
                "{} が key {key:?} を含んでいない",
                entry.path
            );
        }
    }

    // noindex の一覧が routes.noindexPaths に出ている (Astro の sitemap filter 用)。
    assert!(routes.noindex_paths.contains(&"/songs/all/".to_string()));
    assert!(routes.noindex_paths.contains(&"/brands/other/".to_string()));
    assert!(routes.noindex_paths.iter().all(|p| p.starts_with('/') && p.ends_with('/')));

    // ジャケ無しの曲。
    let no_art: SongPage = serde_json::from_str(&read("songs/ml_no_artwork.json")).unwrap();
    assert!(no_art.artwork_url.is_none());
    // 曲に deeplink は無い (DeeplinkRouter が受けるのは events / shows / polls だけ)。
    assert!(no_art.app.deeplink.is_none() && no_art.app.deeplink_kind.is_none());
    // 歌詞の断り書きは必ず出る。
    assert!(no_art.lyrics_note.contains("J260943703"));

    // 歌唱メンバーが空のセトリ行。
    let show: ShowPage = serde_json::from_str(&read("shows/sh_sample_1.json")).unwrap();
    assert!(show.setlist.iter().any(|r| r.performers.is_empty()), "performers 空の行が無い");
    // event / show には deeplink がある。
    assert_eq!(show.app.deeplink_kind.as_deref(), Some("show"));

    // 60 文字級の長い名前。
    let long: EventPage = serde_json::from_str(&read("events/ev_sample.json")).unwrap();
    assert!(long.name.chars().count() >= 60, "長い名前の代表値が短い: {}", long.name.chars().count());

    // 空の一覧・空の詳細。
    let empty_list: EventListPage = serde_json::from_str(&read("index/events-brand-ml.json")).unwrap();
    assert!(empty_list.groups.is_empty() && empty_list.total == 0);
    let empty_event: EventPage = serde_json::from_str(&read("events/ev_empty.json")).unwrap();
    assert!(empty_event.shows.is_empty() && empty_event.cast.is_none());
    let empty_unit: UnitPage = serde_json::from_str(&read("units/unit_empty.json")).unwrap();
    assert!(empty_unit.members.is_empty() && empty_unit.songs.is_empty());
}

#[test]
fn every_ref_path_in_the_fixture_is_a_known_route() {
    let dir = emit_fixture("reachable");
    let routes: RoutesFile =
        serde_json::from_str(&std::fs::read_to_string(dir.path().join("routes.json")).unwrap())
            .unwrap();
    let known: std::collections::BTreeSet<&str> =
        routes.routes.iter().map(|r| r.path.as_str()).collect();

    // JSON を機械的に舐めて、あらゆる "path" の値がルート台帳に載っていることを見る。
    // (Ref だけでなく NavLink / Crumb / RouteEntry も同じキー名で持たせてあるので
    //  これ 1 本でリンク切れが拾える。)
    fn collect(value: &serde_json::Value, out: &mut Vec<String>) {
        match value {
            serde_json::Value::Object(map) => {
                for (k, v) in map {
                    if k == "path" {
                        if let Some(s) = v.as_str() {
                            out.push(s.to_string());
                        }
                    }
                    collect(v, out);
                }
            }
            serde_json::Value::Array(items) => items.iter().for_each(|v| collect(v, out)),
            _ => {}
        }
    }

    let mut missing = Vec::new();
    for (rel, text) in read_all(dir.path()) {
        // search/*.json の path はシャードの取得先 (/search/songs.json) でページではない。
        if rel.starts_with("search/") {
            continue;
        }
        let mut paths = Vec::new();
        collect(&serde_json::from_str(&text).unwrap(), &mut paths);
        for p in paths {
            if !known.contains(p.as_str()) {
                missing.push(format!("{rel} → {p}"));
            }
        }
    }
    assert!(missing.is_empty(), "ルート台帳に無いリンクがある:\n{}", missing.join("\n"));
}

#[test]
fn schema_version_is_stamped_on_every_top_level_document() {
    let dir = emit_fixture("schema-version");
    for (rel, text) in read_all(dir.path()) {
        let value: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(
            value.get("schemaVersion").and_then(|v| v.as_u64()),
            Some(SCHEMA_VERSION as u64),
            "{rel} に schemaVersion が無い (TS ローダが版を確かめられない)"
        );
    }
}

#[test]
fn run_rejects_the_data_export_until_c3_lands() {
    // まだ実装していない経路を「黙って空を書く」ではなく明示的に落とす。
    let args = Args { sql: Some(PathBuf::from("x")), out: Some(PathBuf::from("y")), ..Args::default() };
    let err = imas_core::web_export::run(&args).unwrap_err();
    assert_eq!(err.exit_code(), 1, "{err}");
}
