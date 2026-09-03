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
fn run_rejects_ambiguous_or_incomplete_arguments() {
    // 引数の取り違えは「黙って空を書く」ではなく、引数エラー (exit 1) で落とす。
    let cases = [
        // 入力がない。
        Args { out: Some(PathBuf::from("y")), ..Args::default() },
        // --sql と --db の両方。どちらを正とすべきか決められない。
        Args {
            sql: Some(PathBuf::from("x")),
            db: Some(PathBuf::from("z")),
            out: Some(PathBuf::from("y")),
            ..Args::default()
        },
        // 出力先がない。
        Args { db: Some(PathBuf::from("z")), ..Args::default() },
    ];
    for args in cases {
        let err = imas_core::web_export::run(&args).unwrap_err();
        assert_eq!(err.exit_code(), 1, "{err}");
    }
}

// ===========================================================================
// 実データ (同梱 master.sqlite) を通した検査
//
// ここだけ重い (フル出力に 1 分強)。既定の `cargo test --locked` には feature が
// 付かないので走らず、`--features web-export` のときだけ走る。
// ===========================================================================

mod real {
    use super::*;
    use imas_core::domain::snapshot::Snapshot;
    use imas_core::domain::text_search_index::prepare_needle;
    use imas_core::outbound::sqlite_loader::load_snapshot;
    use imas_core::web_export::emit::context::Ctx;
    use imas_core::web_export::emit::search;
    use imas_core::web_export::url::{
        fallback_reason, path_key, reserved_for, FallbackReason, MAX_SEGMENT_BYTES,
    };
    use std::collections::{BTreeMap, BTreeSet, HashSet};
    use std::sync::OnceLock;

    /// 出力を固定するための「今日」。実時刻を使うと結果が日ごとに変わる。
    const TODAY: &str = "2026-09-04";

    fn db_path() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    /// スナップショットは全テストで共有する (不変なので安全・ロードを 1 回にする)。
    fn snap() -> &'static Snapshot {
        static SNAP: OnceLock<Snapshot> = OnceLock::new();
        SNAP.get_or_init(|| {
            load_snapshot(&db_path()).expect(
                "同梱 master.sqlite が読めない。`bash tools/build_db.sh` で生成すること",
            )
        })
    }

    fn ctx() -> Ctx<'static> {
        Ctx::new(snap(), TODAY.to_string(), format!("{TODAY}T00:00:00Z"), None)
    }

    /// フル出力を 1 回だけ作り、複数のテストで共有する (毎回作ると 1 分 × テスト数になる)。
    fn exported() -> &'static TempDir {
        static DIR: OnceLock<TempDir> = OnceLock::new();
        DIR.get_or_init(|| {
            let dir = TempDir::new("real");
            let args = Args {
                db: Some(PathBuf::from(db_path())),
                out: Some(dir.path().to_path_buf()),
                today: Some(TODAY.to_string()),
                ..Args::default()
            };
            imas_core::web_export::run(&args).expect("実データの export が失敗した");
            dir
        })
    }

    // -----------------------------------------------------------------------
    // T2: URL の安全化
    // -----------------------------------------------------------------------

    #[test]
    fn t2_fallback_slugs_stay_at_the_two_ids_we_know_about() {
        let ctx = ctx();
        let mut by_reason: BTreeMap<&str, Vec<String>> = BTreeMap::new();
        let collections: [(&str, Vec<String>); 7] = [
            ("events", snap().events.iter().map(|e| e.id.clone()).collect()),
            ("shows", snap().shows.iter().map(|s| s.id.clone()).collect()),
            ("songs", snap().songs.iter().map(|s| s.id.clone()).collect()),
            ("idols", snap().idols.iter().map(|i| i.id.clone()).collect()),
            ("units", snap().units.iter().map(|u| u.id.clone()).collect()),
            ("venues", snap().venues.iter().map(|v| v.id.clone()).collect()),
            ("brands", snap().brands.iter().map(|b| b.id.clone()).collect()),
        ];
        for (collection, ids) in &collections {
            for id in ids {
                if let Some(reason) = fallback_reason(id, reserved_for(collection)) {
                    let key = match reason {
                        FallbackReason::Unsafe => "unsafe",
                        FallbackReason::TooLong => "tooLong",
                    };
                    by_reason.entry(key).or_default().push(format!("{collection}: {id}"));
                }
            }
        }
        let unsafe_ids = by_reason.get("unsafe").map(Vec::len).unwrap_or(0);
        let too_long = by_reason.get("tooLong").map(Vec::len).unwrap_or(0);

        // 内訳まで固定する。合計だけ見ていると、危険 id が 1 件消えて長い id が
        // 1 件増えたときに気付けない (前者はデータ修正、後者は放置でよい別の話)。
        assert_eq!(
            (unsafe_ids, too_long),
            (2, 0),
            "フォールバック slug の内訳が変わった:\n{by_reason:#?}\n\
             危険 id が増えたならデータ側 (db/master.sql) を直す。\
             長い id が増えただけなら MAX_SEGMENT_BYTES と期待値を見直してよい。"
        );
        assert_eq!(ctx.fallback_unsafe + ctx.fallback_too_long, 2);

        // 実データの最長 id が上限に収まっていること。上限を割ると、その id を持つ
        // ページの URL だけが静かにハッシュに変わる (ビルドは通ってしまう)。
        let longest = collections
            .iter()
            .flat_map(|(_, ids)| ids.iter())
            .map(|id| id.len())
            .max()
            .unwrap_or(0);
        assert!(
            longest <= MAX_SEGMENT_BYTES,
            "最長 id ({longest} バイト) が MAX_SEGMENT_BYTES ({MAX_SEGMENT_BYTES}) を超えた"
        );
    }

    #[test]
    fn t2b_path_keys_are_unique_within_every_collection() {
        // フォールバック名は fnv1a64 の**上位 32bit しか使っていない**ので、
        // 衝突は理論上ありうる。実データで起きていないことを固定する
        // (起きたら URL が 1 本消えるが、ビルドは通ってしまう)。
        for (collection, ids) in [
            ("events", snap().events.iter().map(|e| e.id.clone()).collect::<Vec<_>>()),
            ("shows", snap().shows.iter().map(|s| s.id.clone()).collect()),
            ("songs", snap().songs.iter().map(|s| s.id.clone()).collect()),
            ("idols", snap().idols.iter().map(|i| i.id.clone()).collect()),
            ("units", snap().units.iter().map(|u| u.id.clone()).collect()),
            ("venues", snap().venues.iter().map(|v| v.id.clone()).collect()),
            ("brands", snap().brands.iter().map(|b| b.id.clone()).collect()),
        ] {
            let mut seen: BTreeMap<String, String> = BTreeMap::new();
            for id in ids {
                let key = path_key(&id, reserved_for(collection), collection);
                if let Some(other) = seen.insert(key.clone(), id.clone()) {
                    panic!("{collection} で path_key が衝突: {other:?} と {id:?} → {key:?}");
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // T5 / T6: 検索
    // -----------------------------------------------------------------------

    #[test]
    fn t5_folded_fields_are_exactly_what_prepare_needle_produces() {
        // 索引の accessor が「畳み済みの中身」をそのまま返していること。
        // ここがずれると、配った索引とアプリの索引が別物になる。
        let mut checked = 0;
        for (i, song) in snap().songs.iter().enumerate().take(100) {
            let sources: Vec<&str> = [Some(song.title.as_str()), song.title_kana.as_deref()]
                .into_iter()
                .flatten()
                .filter(|s| !s.is_empty())
                .collect();
            let folded = snap().song_search[i].folded_fields();
            assert_eq!(folded.len(), sources.len(), "曲 {} のフィールド数", song.id);
            for (actual, source) in folded.iter().zip(&sources) {
                assert_eq!(actual, &prepare_needle(source), "曲 {} の {source:?}", song.id);
                checked += 1;
            }
        }
        assert!(checked > 100, "確かめたフィールドが少なすぎる: {checked}");
    }

    #[test]
    fn t6_browser_side_matching_agrees_with_the_core_index() {
        // ブラウザは `row.f.includes(fold(q))` の 1 行しか実行しない。
        // それがコアの `TextSearchIndex::matches` と同じ集合を返すことを、
        // 実データ全件 × 代表クエリで確かめる。
        let ctx = ctx();
        let shards = search::shards(&ctx);
        let songs = shards.iter().find(|s| s.file == "songs").expect("曲シャードが無い");
        assert_eq!(songs.shard.rows.len(), snap().songs.len());

        let queries = [
            "はるか", "ハルカ", "HARUKA", "haruka", "Thank", "THANK", "thank you",
            "おねがい", "オネガイ", "しんでれら", "ラ", "ら", "が", "か\u{3099}",
            "ミライ", "みらい", "@", "!", "M@STER", "m@ster", "ー", "・", "★",
            "ΑΣ", "σ", "", " ", "9", "live", "ゆめ", "夢",
        ];
        for query in queries {
            let needle = prepare_needle(query);
            let expected: BTreeSet<usize> = snap()
                .song_search
                .iter()
                .enumerate()
                .filter(|(_, index)| index.matches(&needle))
                .map(|(i, _)| i)
                .collect();

            // ブラウザ側の式をそのまま書く (畳んだ検索語の部分一致 1 本)。
            let folded_query = String::from_utf8(needle.clone()).unwrap();
            let actual: BTreeSet<usize> = songs
                .shard
                .rows
                .iter()
                .enumerate()
                .filter(|(_, row)| folded_query.is_empty() || row.f.contains(&folded_query))
                .map(|(i, _)| i)
                .collect();

            assert_eq!(
                actual, expected,
                "検索語 {query:?} で、ブラウザ側の照合とコアの索引が食い違った"
            );
        }
    }

    #[test]
    fn t6b_the_field_separator_never_leaks_into_the_index_text() {
        // 区切り (U+0001) が本文に混ざると、フィールド境界をまたぐ偽陽性を防ぐ仕掛けが
        // 無効になる (`f.includes(q)` が別フィールドをまたいで当たる)。
        //
        // 「連結を解いたら索引のフィールド列に戻る」ことを実データ全件で見る。
        // これが成り立つ限り、本文に区切りは 1 つも混ざっていない。
        let ctx = ctx();
        let mut checked = 0usize;
        for shard in search::shards(&ctx) {
            let indexes = match shard.shard.kind {
                RefKind::Song => &snap().song_search,
                RefKind::Idol => &snap().idol_search,
                RefKind::Event => &snap().event_search,
                RefKind::Venue => &snap().venue_search,
                other => panic!("知らないシャード: {other:?}"),
            };
            assert_eq!(shard.shard.rows.len(), indexes.len(), "{} の行数", shard.file);
            for (row, index) in shard.shard.rows.iter().zip(indexes) {
                let fields: Vec<&str> = if row.f.is_empty() {
                    // 索引が空 (曲名もよみも空) の行。split は [""] を返すので特別扱い。
                    Vec::new()
                } else {
                    row.f.split(search::SEP).collect()
                };
                assert_eq!(
                    fields,
                    index.folded_str_fields(),
                    "{}: 連結を解いても索引のフィールド列に戻らない ({:?})",
                    shard.file,
                    row.n
                );
                assert!(
                    !row.n.contains(search::SEP),
                    "{}: 表示名に区切り文字が入っている ({:?})",
                    shard.file,
                    row.n
                );
                checked += 1;
            }
        }
        assert!(checked > 4_000, "確かめた行が少なすぎる: {checked}");
    }

    // -----------------------------------------------------------------------
    // L-7: マスタの分類値
    // -----------------------------------------------------------------------

    #[test]
    fn l7_event_kinds_and_release_types_stay_within_the_known_set() {
        // 未知の値が入ると、表示名の写像 (content::kind_label) が黙って
        // 「その他」「リリース」に落ちる。ラベルが消えたことは画面を見ないと
        // 気付けないので、値の集合の方をここで固定する。
        let kinds: BTreeSet<&str> = snap().events.iter().map(|e| e.kind.as_str()).collect();
        let known: BTreeSet<&str> =
            ["live", "festival", "release_event", "other", "radio", "stream"].into_iter().collect();
        assert!(
            kinds.is_subset(&known),
            "知らない events.kind がある: {:?}\n\
             content::kind_label と lists::all_event_kinds の両方に足すこと \
             (all_event_kinds に足し忘れると一覧から静かに消える)。",
            kinds.difference(&known).collect::<Vec<_>>()
        );

        let types: BTreeSet<&str> =
            snap().event_releases.iter().map(|r| r.product_type.as_str()).collect();
        let known_types: BTreeSet<&str> =
            ["bluray", "dvd", "cd", "digital"].into_iter().collect();
        assert!(
            types.is_subset(&known_types),
            "知らない event_releases.product_type がある: {:?}\n\
             emit::events::release_kind_label に足すこと。",
            types.difference(&known_types).collect::<Vec<_>>()
        );
    }

    #[test]
    fn l1_kana_index_places_every_listed_song_in_a_real_row() {
        // かな目次で「その他」に落ちる曲が増えていないか。`ゔ` や小書きの `ゕゖ` は
        // ひらがなの並びの末尾にあるので、範囲を素直に書くと取りこぼす。
        let dir = exported();
        let songs: SongListPage = serde_json::from_str(
            &std::fs::read_to_string(dir.path().join("index/songs.json")).unwrap(),
        )
        .unwrap();
        let other: u32 = songs
            .kana_sections
            .iter()
            .filter(|s| s.label == "その他")
            .map(|s| s.count)
            .sum();
        let total: u32 = songs.kana_sections.iter().map(|s| s.count).sum();
        assert_eq!(total, songs.items.len() as u32, "目次が全行を覆っていない");
        // 記号始まりの曲名は実在するので 0 にはならないが、行の取りこぼしがあると跳ね上がる。
        assert!(
            f64::from(other) / f64::from(total) < 0.15,
            "「その他」が多すぎる ({other}/{total})。かなの範囲に抜けがある可能性"
        );
        // 区画は items の並び順に沿って連続していること。
        let mut expected_start = 0u32;
        for section in &songs.kana_sections {
            assert_eq!(section.start_index, expected_start, "区画 {} の開始位置", section.label);
            expected_start += section.count;
        }
    }

    // -----------------------------------------------------------------------
    // T8 / T11 / T12: 出力全体
    // -----------------------------------------------------------------------

    /// JSON を舐めて、リンクとして書かれている `path` を全部集める。
    fn collect_paths(value: &serde_json::Value, out: &mut Vec<String>) {
        match value {
            serde_json::Value::Object(map) => {
                for (k, v) in map {
                    if k == "path" {
                        if let Some(s) = v.as_str() {
                            out.push(s.to_string());
                        }
                    }
                    collect_paths(v, out);
                }
            }
            serde_json::Value::Array(items) => items.iter().for_each(|v| collect_paths(v, out)),
            _ => {}
        }
    }

    #[test]
    fn t8_every_page_is_reachable_from_the_top_and_no_link_dangles() {
        let dir = exported();
        let root = dir.path();
        let routes: RoutesFile =
            serde_json::from_str(&std::fs::read_to_string(root.join("routes.json")).unwrap())
                .unwrap();
        let known: BTreeMap<&str, &RouteEntry> =
            routes.routes.iter().map(|r| (r.path.as_str(), r)).collect();
        assert!(routes.routes.len() > 7_000, "ルートが少なすぎる: {}", routes.routes.len());

        // 1) すべてのリンクがルート台帳に載っていること (リンク切れゼロ)。
        let mut links: BTreeMap<String, Vec<String>> = BTreeMap::new();
        let mut dangling: Vec<String> = Vec::new();
        for entry in &routes.routes {
            let data = root.join(&entry.data);
            let text = std::fs::read_to_string(&data)
                .unwrap_or_else(|e| panic!("{} が読めない: {e}", entry.data));
            let mut paths = Vec::new();
            collect_paths(&serde_json::from_str(&text).unwrap(), &mut paths);
            for p in &paths {
                if !known.contains_key(p.as_str()) {
                    dangling.push(format!("{} → {p}", entry.path));
                }
            }
            links.insert(entry.path.clone(), paths);
        }
        assert!(
            dangling.is_empty(),
            "ルート台帳に無いリンクが {} 本ある (先頭 10 件):\n{}",
            dangling.len(),
            dangling.iter().take(10).cloned().collect::<Vec<_>>().join("\n")
        );

        // 2) `/` から全ページに辿り着けること。
        //    辿り着けないページは、検索エンジンにも人にも見つけられない。
        let mut seen: HashSet<&str> = HashSet::new();
        let mut stack = vec!["/"];
        seen.insert("/");
        while let Some(current) = stack.pop() {
            for next in links.get(current).into_iter().flatten() {
                if let Some((path, _)) = known.get_key_value(next.as_str()) {
                    if seen.insert(path) {
                        stack.push(path);
                    }
                }
            }
        }
        let unreachable: Vec<&str> =
            known.keys().filter(|p| !seen.contains(*p)).copied().take(10).collect();
        assert!(
            unreachable.is_empty(),
            "`/` から辿り着けないページがある (先頭 10 件): {unreachable:?}"
        );
    }

    #[test]
    fn sibling_show_chips_are_short_and_absent_on_single_show_events() {
        // 「このライブの他の公演」は 2 本以上あるときだけ出す。単日公演で出すと
        // 自分 1 本しか並ばず、選べないものの見出しだけが残る。
        //
        // チップの名前はライブ名との重なりを落とした短い形。ページ見出しが既に
        // ライブ名なので、フルの公演名を並べると同じ文字列が繰り返されて
        // 肝心の見分け (DAY1 / 昼公演 / ステージ１回目) が読めなくなる。
        let dir = exported();
        let routes: RoutesFile =
            serde_json::from_str(&std::fs::read_to_string(dir.path().join("routes.json")).unwrap())
                .unwrap();

        let mut with_siblings = 0usize;
        let mut single_show = 0usize;
        let mut repeated_event_name: Vec<String> = Vec::new();
        for entry in routes.routes.iter().filter(|r| r.kind == RouteKind::Show) {
            let page: ShowPage = serde_json::from_str(
                &std::fs::read_to_string(dir.path().join(&entry.data)).unwrap(),
            )
            .unwrap();
            if page.sibling_shows.is_empty() {
                single_show += 1;
                continue;
            }
            with_siblings += 1;
            assert!(
                page.sibling_shows.len() >= 2,
                "{}: 兄弟公演が 1 件だけ出ている",
                page.path
            );
            for sibling in &page.sibling_shows {
                if sibling.name.starts_with(page.event.name.as_str()) {
                    repeated_event_name.push(format!("{} → {:?}", page.path, sibling.name));
                }
                // 日付はチップだけで分かること。公演名がライブ名と丸ごと同じで
                // 名前が日付になっている公演は、それ自体が日付なので sub は要らない。
                let name_is_a_date = sibling.name.len() == 10
                    && sibling.name.bytes().filter(|b| *b == b'-').count() == 2;
                assert!(
                    sibling.sub.is_some() || name_is_a_date,
                    "{}: 兄弟公演 {:?} から日付が分からない",
                    page.path,
                    sibling.name
                );
            }
        }

        assert!(
            repeated_event_name.is_empty(),
            "兄弟公演の名前がライブ名で始まっている {} 件 (先頭 10 件):\n{}",
            repeated_event_name.len(),
            repeated_event_name.iter().take(10).cloned().collect::<Vec<_>>().join("\n")
        );
        // 実データには単日公演も複数公演も両方ある。片方だけになっていたら
        // この検査が空回りしているので、両方を踏んでいることを確かめる。
        assert!(single_show > 100, "単日公演が少なすぎる: {single_show}");
        assert!(with_siblings > 100, "複数公演のライブが少なすぎる: {with_siblings}");
    }

    #[test]
    fn about_credits_the_display_font_and_ships_its_licence() {
        // OFL はライセンス文の同梱を求める。About から辿れて、実体が配布物にあること。
        let dir = exported();
        let about: AboutPage = serde_json::from_str(
            &std::fs::read_to_string(dir.path().join("index/about.json")).unwrap(),
        )
        .unwrap();
        let section = about
            .sections
            .iter()
            .find(|s| s.heading == "書体")
            .expect("About に「書体」の節が無い");
        assert!(
            section.paragraphs.iter().any(|p| p.contains("SIL Open Font License")),
            "ライセンス名が本文に無い"
        );
        let link = section
            .links
            .iter()
            .find(|l| l.href == "/fonts/OFL.txt")
            .expect("OFL 全文へのリンクが無い");
        assert!(!link.external, "同梱物なので外部リンクにしない");

        // 配布物にライセンス文が実在すること (リンク切れは OFL 違反になる)。
        let ofl = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../web/public/fonts/OFL.txt");
        let text = std::fs::read_to_string(&ofl)
            .unwrap_or_else(|e| panic!("{} が読めない: {e}", ofl.display()));
        assert!(text.contains("SIL OPEN FONT LICENSE"), "OFL.txt の中身がライセンス文でない");
    }

    #[test]
    fn t11_output_stays_inside_the_cloudflare_limits() {
        let dir = exported();
        let mut files = 0usize;
        let mut largest = (0u64, String::new());
        fn walk(dir: &Path, files: &mut usize, largest: &mut (u64, String)) {
            for entry in std::fs::read_dir(dir).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    walk(&path, files, largest);
                } else {
                    *files += 1;
                    let size = path.metadata().unwrap().len();
                    if size > largest.0 {
                        *largest = (size, path.display().to_string());
                    }
                }
            }
        }
        walk(dir.path(), &mut files, &mut largest);

        // Cloudflare Workers Static Assets は 20,000 ファイル / 1 ファイル 25MiB。
        // 手前で落として、上限に触れる前に気付けるようにする。
        assert!(files < 18_000, "ファイルが多すぎる: {files}");
        assert!(
            largest.0 < 8 * 1024 * 1024,
            "1 ファイルが大きすぎる: {} ({} バイト)",
            largest.1,
            largest.0
        );
    }

    #[test]
    fn t9_two_runs_of_the_real_export_are_byte_identical() {
        // 差分レビューが成立する条件。HashMap をそのまま serde していたり、
        // 生成時刻を実時刻から取っていたりすると、ここで落ちる。
        let a = exported();
        let b = TempDir::new("real-again");
        let args = Args {
            db: Some(PathBuf::from(db_path())),
            out: Some(b.path().to_path_buf()),
            today: Some(TODAY.to_string()),
            ..Args::default()
        };
        imas_core::web_export::run(&args).unwrap();

        // 代表的な 1 枚ずつではなく、全ファイルのハッシュで比べる。
        fn digest(root: &Path) -> BTreeMap<String, u64> {
            fn walk(root: &Path, dir: &Path, out: &mut BTreeMap<String, u64>) {
                for entry in std::fs::read_dir(dir).unwrap() {
                    let path = entry.unwrap().path();
                    if path.is_dir() {
                        walk(root, &path, out);
                    } else {
                        let rel = path.strip_prefix(root).unwrap().display().to_string();
                        let bytes = std::fs::read(&path).unwrap();
                        out.insert(rel, imas_core::web_export::url::fnv1a64(&String::from_utf8_lossy(&bytes)));
                    }
                }
            }
            let mut out = BTreeMap::new();
            walk(root, root, &mut out);
            out
        }
        let (x, y) = (digest(a.path()), digest(b.path()));
        assert_eq!(x.keys().collect::<Vec<_>>(), y.keys().collect::<Vec<_>>(), "顔ぶれが違う");
        let diff: Vec<&String> = x.iter().filter(|(k, v)| y.get(*k) != Some(v)).map(|(k, _)| k).collect();
        assert!(diff.is_empty(), "2 回の実行で内容が違うファイル: {:?}", &diff[..diff.len().min(10)]);
    }

    #[test]
    fn t12_the_real_output_carries_no_lyrics_or_preview_audio() {
        let dir = exported();
        let mut checked = 0;
        fn walk(dir: &Path, checked: &mut usize) {
            for entry in std::fs::read_dir(dir).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    walk(&path, checked);
                    continue;
                }
                if path.extension().is_some_and(|e| e == "json") {
                    let text = std::fs::read_to_string(&path).unwrap();
                    // キー名で見る (値に "lyrics" を含む曲名がありうるため)。
                    for forbidden in ["\"previewUrl\"", "\"lyricsUrl\"", "\"lyrics\""] {
                        assert!(
                            !text.contains(forbidden),
                            "{}: {forbidden} を出してはいけない",
                            path.display()
                        );
                    }
                    assert!(
                        !text.contains("audio-ssl.itunes.apple.com"),
                        "{}: プレビュー音源の URL を出してはいけない",
                        path.display()
                    );
                    *checked += 1;
                }
            }
        }
        walk(dir.path(), &mut checked);
        assert!(checked > 7_000, "検査したファイルが少なすぎる: {checked}");
    }

    #[test]
    fn themes_css_covers_every_idol_brand_and_neutral() {
        let dir = exported();
        let css = std::fs::read_to_string(dir.path().join("themes.css")).unwrap();
        // アイドル 394 + ブランド 9 + neutral = 404 テーマ × ライト/ダーク。
        let expected = snap().idols.len() + snap().brands.len() + 1;
        assert_eq!(
            css.matches("[data-theme=").count(),
            expected * 2,
            "テーマ数がアイドル + ブランド + neutral と合わない"
        );
        assert!(css.contains("@media (prefers-color-scheme: dark)"));
        // 変数名は web 側の tokens.css と噛み合っている必要がある。
        for name in ["--accent:", "--on-accent:", "--tint-strong:", "--hero-surface:"] {
            assert!(css.contains(name), "{name} が出ていない");
        }
    }

    #[test]
    fn meta_carries_the_content_fingerprint_and_the_frozen_today() {
        let dir = exported();
        let meta: SiteMeta =
            serde_json::from_str(&std::fs::read_to_string(dir.path().join("meta.json")).unwrap())
                .unwrap();
        assert_eq!(meta.today_jst, TODAY);
        // 生成時刻は today から作る (実時刻だと 2 回の実行でバイト一致しない)。
        assert_eq!(meta.generated_at, format!("{TODAY}T00:00:00Z"));
        assert!(meta.data_version.is_some(), "data_version が meta に無い");
        assert_eq!(meta.counts.songs, snap().songs.len() as u32);
    }

    #[test]
    fn fold_parity_fixture_covers_real_data_and_the_known_traps() {
        let dir = exported();
        let parity: FoldParity =
            serde_json::from_str(&std::fs::read_to_string(dir.path().join("parity/fold.json")).unwrap())
                .unwrap();
        assert!(parity.cases.len() > 2_000, "パリティケースが少なすぎる: {}", parity.cases.len());
        // 期待値はコアの畳み込みそのものであること。
        for case in parity.cases.iter().take(500) {
            assert_eq!(
                case.output,
                String::from_utf8(prepare_needle(&case.input)).unwrap(),
                "{:?} の期待値がコアの畳み込みと違う",
                case.input
            );
        }
        // JS の toLowerCase() が落ちる語末 Σ は必ず入れておく。
        let sigma = parity.cases.iter().find(|c| c.input == "ΑΣ").expect("ΑΣ が入っていない");
        assert_eq!(sigma.output, "ασ");
    }
}
