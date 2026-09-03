//! 「日替わり」ものの共通ルール。日付キーと、日付から曲を 1 つ選ぶ決定論的な種。
//!
//! ## なぜ端末ローカル日で、なぜ `jst_day` と分けるか
//!
//! `jst_day` は **公演日 (`shows.date`) との比較**に使う。公演日は日本のライブの開催日なので
//! 端末がどこにあっても JST で判定しないと 1 日ずれる。
//!
//! こちらは **「そのユーザーの 1 日」**が単位。連続クリア日数や日替わりピックは、
//! 使っている人の深夜 0 時で切り替わるのが自然なので端末ローカルのまま。
//! 意味が違うので統合しない。
//!
//! ## なぜ epoch 秒ではなく「暦法解決済みの日付成分」を受け取るか
//!
//! 原本 Swift は `Calendar.current.dateComponents([.year, .month, .day], from:)`、つまり
//! **端末の暦法設定** (iOS 設定 > 一般 > 言語と地域 > 暦法) に従う。和暦の端末では
//! era 年の `"0008-07-26"`、タイ仏暦では `"2569-07-26"` が出るのが出荷済みの挙動で、
//! この文字列が `GameProgressStore` の連続記録や「今日の1曲」の種としてユーザーの
//! 端末に保存されている。[`stable_index`] の offset basis と同じく、**日付キーの表記も
//! 出荷済みの値のまま**が契約 (変えると和暦/仏暦端末で「今日の1曲」が入れ替わり、
//! 保存済みキーと突き合う連続記録が黙って切れる)。
//!
//! chrono はグレゴリオ暦固定なので、epoch 秒 + UTC オフセットからはこの値を再構成
//! できない (移植初版はそうしていて、上記の互換が黙って破れていた)。端末の暦法は
//! OS からしか分からないため、暦法を解決した後のローカル日付成分を各プラットフォームの
//! 薄いラッパが注入する (iOS: `Calendar.current.dateComponents([.year, .month, .day], from:)`)。
//!
//! 「前日」の算出も同じ理由でラッパ側のカレンダー任せ
//! (iOS: `Calendar.current.date(byAdding: .day, value: -1, to:)`)。夏時間で 1 日が
//! 24 時間ちょうどとは限らず (epoch から 86400 秒引く方式は不可)、暦によっては
//! era 跨ぎ・うるう規則がグレゴリオ暦と違うため (例: 和暦の era 年 10 = 2028 は
//! うるう年だがグレゴリオ演算では 10 年は平年)、core での日付演算はどの方式でも
//! 正しくならない。core が持つのは **表記とハッシュの契約** だけ。
//!
//! ## なぜ 1 か所に置くか
//!
//! 「今日の 1 曲」はアプリ内 (`DailySongVoteSheet`) とウィジェット用スナップショット
//! (`InfoWidgetBridge`) の両方が **同じ曲を選ばないといけない**。
//! 以前は日付キー・FNV-1a・種文字列の組み立てが両方にコピーされていて
//! (コメントに「同一実装」と書いてあるだけ)、片方を直すとウィジェットとアプリが
//! 黙って違う曲を出す状態だった。契約なのでここに集約してテストで固定する。

use crate::domain::snapshot::Snapshot;

/// 端末ローカルの `"yyyy-MM-dd"`。端末の暦法設定で解決済みの年月日成分から組む
/// (和暦端末なら `local_year` は era 年で来る。モジュールコメント参照)。
///
/// 原本 Swift の `String(format: "%04d-%02d-%02d", ...)` と同じゼロ詰め表記
/// (符号つきゼロ詰めも printf と一致)。`chrono::format` ではなく手組みなのは、
/// 負の年など異常系でも桁が揺れないようにするため。欠損・破損した成分が FFI 越しに
/// 来てもパニックせずそのまま整形する (Swift 側の `c.year ?? 0` フォールバックと対)。
pub fn day_key(local_year: i32, local_month: i32, local_day: i32) -> String {
    format!("{local_year:04}-{local_month:02}-{local_day:02}")
}

/// 文字列 → `[0, modulo)` の安定インデックス (FNV-1a 系)。
///
/// プロセス・OS をまたいでも同じ値になる必要があるので、言語標準のハッシュは使えない
/// (Swift の `Hasher` は起動ごとに seed が変わる)。
///
/// # 重要: offset basis は出荷済みの値のまま
///
/// offset basis が標準 FNV-1a の `14695981039346656037` ではなく
/// 1 桁欠けた `1469598103934665603` のまま出荷されている。分布に実害はないので
/// **直さない**。直すと全ユーザーの「今日の1曲」が一斉に入れ替わる。
/// `stable_index_matches_shipped_values` テストで固定している。
pub fn stable_index(seed: &str, modulo: i64) -> i64 {
    // 候補 0 件 (や負数) でも落ちない (剰余のゼロ除算を踏まない)。呼び出し側で空判定する前提。
    if modulo <= 0 {
        return 0;
    }
    let mut h: u64 = 1469598103934665603;
    for b in seed.as_bytes() {
        h = (h ^ u64::from(*b)).wrapping_mul(1099511628211);
    }
    (h % modulo as u64) as i64
}

/// その日そのブランドの「今日の 1 曲」を、曲 ID 一覧の何番目にするか。
///
/// アプリ本体とウィジェットのスナップショット生成が同じ答えを出すための唯一の入口。
/// 種文字列の組み立て (`"日付|ブランドID"`) までここに含める。
/// `count` はそのブランドの候補曲数。0 なら 0 を返す (呼び出し側で空判定する前提)。
pub fn song_index(day_key: &str, brand_id: &str, count: i64) -> i64 {
    stable_index(&format!("{day_key}|{brand_id}"), count)
}

/// その日そのブランドの「今日のアイドル」を、アイドル ID 一覧の何番目にするか。
///
/// 種を `"日付|idol|ブランドID"` と曲側 (`"日付|ブランドID"`) で分けている。
/// 分けないと、候補数がたまたま一致するブランドで曲とアイドルが同じ番号を引き、
/// 「1 番目の曲と 1 番目のアイドル」が毎日そろって出る。番号の意味が別物なので
/// 種の名前空間も分ける。
pub fn idol_index(day_key: &str, brand_id: &str, count: i64) -> i64 {
    stable_index(&format!("{day_key}|idol|{brand_id}"), count)
}

/// 一括版 [`song_index`] の入力射影。ブランド ID と候補曲数だけを渡す
/// (エンティティ全体を FFI 越しに運ばないための Record)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct DailyPickBrandCandidates {
    pub brand_id: String,
    /// そのブランドの候補曲数。0 は 0 番を返す (呼び出し側で空判定する前提)。
    pub count: u32,
}

/// 全ブランド分の「今日の 1 曲」インデックスをまとめて解決する
/// (1 ユーザー操作 = 1 FFI 呼び出しにするための一括版)。
///
/// 返り値は `brands` と同順。呼び出し側は自国の曲 ID 配列を index で引く。
/// 1 件ずつの答えは [`song_index`] と必ず一致する (アプリ ↔ ウィジェットの契約)。
pub fn song_indices(day_key: &str, brands: &[DailyPickBrandCandidates]) -> Vec<u32> {
    brands
        .iter()
        // song_index の結果は常に [0, count) なので u32 に収まる。
        .map(|b| song_index(day_key, &b.brand_id, i64::from(b.count)) as u32)
        .collect()
}

/// 一括版 [`idol_index`] ([`song_indices`] と同じ規約)。
pub fn idol_indices(day_key: &str, brands: &[DailyPickBrandCandidates]) -> Vec<u32> {
    brands
        .iter()
        // idol_index の結果は常に [0, count) なので u32 に収まる。
        .map(|b| idol_index(day_key, &b.brand_id, i64::from(b.count)) as u32)
        .collect()
}

/// 起動時の日替わりシートが、その日どちらを出すか。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum DailyPickKind {
    /// 各ブランドの「今日の 1 曲」に曲タグを付けてもらう。
    Song,
    /// 各ブランドの「今日のアイドル」にアイドルタグを付けてもらう。
    Idol,
}

/// その日に出すシートの種別。**日で交互**に入れ替える (偶数日=曲 / 奇数日=アイドル)。
///
/// # なぜ日付キーのハッシュではなく日の偶奇か
///
/// [`stable_index`] で 2 を法に取ると長い目では半々になるが、同じ側が 3 日 4 日と
/// 続くことがある。毎日開く画面なので「昨日と違う方が出る」ことに意味があり、
/// 交互になる規則を選んでいる。
///
/// # なぜ日付キー文字列ではなく日の成分を受け取るか
///
/// 日付キーは端末の暦法で解決済みの表記で、和暦端末では `"0008-07-26"` のように
/// 年の桁が変わる (モジュールコメント参照)。文字列から日を切り出す規則を足すと
/// 暦法ごとの表記に依存してしまう。日の成分はどの暦法でも同じ「その月の何日目か」
/// なので、そのまま受け取る。
///
/// 月末で偶奇が続くこと (31 日 → 翌月 1 日 はどちらも奇数) は許容している。
/// 厳密に途切れなく交互にするには暦の日数計算が要り、それは core が持たない責務
/// (モジュールコメントの「前日」と同じ理由)。年に数回、同じ側が 2 日続くだけ。
pub fn sheet_kind(local_day: i32) -> DailyPickKind {
    // 負の成分 (欠損時のフォールバック 0 や異常値) でも panic せず定義通りに返す。
    if local_day.rem_euclid(2) == 0 {
        DailyPickKind::Song
    } else {
        DailyPickKind::Idol
    }
}

/// 「今日の 1 曲」の候補列 (そのブランドの曲 id を id 昇順で)。
///
/// 番号を引く [`song_index`] と**対**の契約なのでここに置く。番号だけ共有しても
/// 候補列がずれれば同じ日に別の曲が出るので、母集団の作り方も 1 か所に固定する
/// (モジュールコメントの「1 か所に置く理由」がそのまま候補列にも当てはまる)。
///
/// 元 SQL (iOS `AppDatabase.fetchSongIdsQuery` / Android `SongDao.fetchDailyPickSongIds`):
///
/// ```sql
/// SELECT id FROM songs WHERE brand_id=?
///   -- include_covers=false のときだけ
///   AND song_type<>'cover'
///   -- exclude_remixes=true のときだけ
///   AND (parent_song_id IS NULL OR parent_song_id='')
///  ORDER BY id
/// ```
///
/// SQL の非自明な挙動をそのまま写す:
/// - `song_type<>'cover'` は三値論理。`song_type` が NULL の行は比較結果が NULL =
///   偽になって**落ちる**。同梱スキーマは `song_type TEXT NOT NULL` なので実データで
///   差は出ないが、NULL を通す実装にすると DB 次第で候補数が変わり、番号が同じでも
///   別の曲が出てしまう。落とす側で固定する。
/// - `parent_song_id=''` を NULL と同列に扱うのは、空文字が入った行を「派生ではない」と
///   見る運用のため (id の無い派生は表現できない)。空文字を派生扱いにすると
///   その曲が候補から消える。
/// - `ORDER BY id` は BINARY 照合 (バイト列比較) で、Rust の `str` の `Ord` と一致する。
///   id は PRIMARY KEY なのでタイは無く、並びは完全に決まる。
///
/// スナップショットの添字順 (rowid 順) に**依存しない**のがこの候補列の要点:
/// Android の rowid は同期で届いた順で iOS の同梱ファイルとは別物なので、
/// id 昇順に並べ直して初めて両 OS が同じ列を見る。
pub fn candidate_song_ids(
    snap: &Snapshot,
    brand_id: &str,
    include_covers: bool,
    exclude_remixes: bool,
) -> Vec<String> {
    let mut ids: Vec<&str> = snap
        .songs
        .iter()
        .filter(|s| s.brand_id.as_deref() == Some(brand_id))
        .filter(|s| include_covers || !Snapshot::is_cover(s))
        .filter(|s| !exclude_remixes || s.parent_song_id.as_deref().is_none_or(str::is_empty))
        .map(|s| s.id.as_str())
        .collect();
    ids.sort_unstable();
    ids.into_iter().map(str::to_owned).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outbound::sqlite_loader::load_snapshot;
    use rusqlite::{Connection, OpenFlags};
    use std::sync::OnceLock;

    fn db_path() -> String {
        format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"))
    }

    /// スナップショットは全テストで共有 (不変なので安全・ロードを 1 回にする)。
    fn snap() -> &'static Snapshot {
        static SNAP: OnceLock<Snapshot> = OnceLock::new();
        SNAP.get_or_init(|| load_snapshot(&db_path()).expect("bundle DB はロードできる"))
    }

    fn conn() -> Connection {
        Connection::open_with_flags(
            db_path(),
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .expect("bundle DB を開ける")
    }

    // MARK: idol_index / sheet_kind

    /// 曲とアイドルは種の名前空間が違う。候補数が同じでも同じ番号にはならない。
    #[test]
    fn the_idol_pick_does_not_track_the_song_pick() {
        let day = "2026-08-28";
        // 同じ日・同じブランド・同じ候補数でも別の番号を引く。
        let same_count = 190;
        assert_ne!(
            song_index(day, "cg", same_count),
            idol_index(day, "cg", same_count),
            "種を分けていないと曲とアイドルが連動する"
        );
    }

    /// 日が変われば選ばれるアイドルも変わる (同じ日なら何度呼んでも同じ)。
    #[test]
    fn the_idol_pick_is_stable_within_a_day_and_moves_across_days() {
        assert_eq!(idol_index("2026-08-28", "ml", 52), idol_index("2026-08-28", "ml", 52));
        assert_ne!(idol_index("2026-08-28", "ml", 52), idol_index("2026-08-29", "ml", 52));
    }

    /// 候補 0 人 (そのブランドにアイドルが居ない) でもゼロ除算で落ちない。
    #[test]
    fn the_idol_pick_survives_an_empty_brand() {
        assert_eq!(idol_index("2026-08-28", "other", 0), 0);
    }

    /// 一括版は 1 件ずつの答えと必ず一致する (曲側と同じ契約)。
    #[test]
    fn bulk_idol_indices_match_the_single_answers() {
        let brands = vec![
            DailyPickBrandCandidates { brand_id: "cg".into(), count: 190 },
            DailyPickBrandCandidates { brand_id: "ml".into(), count: 52 },
            DailyPickBrandCandidates { brand_id: "sc".into(), count: 28 },
        ];
        let bulk = idol_indices("2026-08-28", &brands);
        for (b, got) in brands.iter().zip(bulk) {
            assert_eq!(u32::from(got), idol_index("2026-08-28", &b.brand_id, i64::from(b.count)) as u32);
        }
    }

    /// 起動シートは日で交互 (偶数日=曲 / 奇数日=アイドル)。
    #[test]
    fn the_launch_sheet_alternates_day_by_day() {
        assert_eq!(sheet_kind(28), DailyPickKind::Song);
        assert_eq!(sheet_kind(29), DailyPickKind::Idol);
        assert_eq!(sheet_kind(30), DailyPickKind::Song);
        assert_eq!(sheet_kind(31), DailyPickKind::Idol);
    }

    /// 欠損時のフォールバック 0 や負の成分でも panic しない。
    #[test]
    fn the_launch_sheet_kind_survives_degenerate_components() {
        assert_eq!(sheet_kind(0), DailyPickKind::Song);
        assert_eq!(sheet_kind(-1), DailyPickKind::Idol);
        assert_eq!(sheet_kind(i32::MIN), DailyPickKind::Song);
    }

    // MARK: day_key

    #[test]
    fn day_key_is_zero_padded() {
        assert_eq!(day_key(2026, 1, 9), "2026-01-09");
    }

    /// 回帰 (レビュー指摘): 端末の暦法設定を尊重する。
    ///
    /// 移植初版は epoch 秒 + UTC オフセットを受けて chrono (グレゴリオ暦固定) で
    /// 日付を出していたため、2026-07-26T12:00+09:00 に対し原本 Swift が
    /// 和暦端末で `"0008-07-26"`、タイ仏暦端末で `"2569-07-26"` を出すところを
    /// 常に `"2026-07-26"` にしてしまい、保存済みキーと食い違って「今日の1曲」の
    /// 入れ替わりと連続記録リセットを起こした。core は暦法解決済みの成分を
    /// 受け取って整形するだけにし、暦の解決は各プラットフォームのラッパに置く。
    #[test]
    fn day_key_preserves_device_calendar_components() {
        // 和暦端末: Calendar(identifier: .japanese) の year 成分は era 年 (令和 8)。
        assert_eq!(day_key(8, 7, 26), "0008-07-26");
        // タイ仏暦端末: 仏暦 2569 年。
        assert_eq!(day_key(2569, 7, 26), "2569-07-26");
        // グレゴリオ暦端末 (大多数): 従来どおり。
        assert_eq!(day_key(2026, 7, 26), "2026-07-26");
    }

    /// 欠損・破損した成分でもパニックせず、原本 Swift の `%04d-%02d-%02d` と
    /// 同じ表記になる (Rust の `{:04}` も printf と同じ符号つきゼロ詰め)。
    #[test]
    fn day_key_with_degenerate_components_matches_printf() {
        // Swift 側の `c.year ?? 0` フォールバック相当。
        assert_eq!(day_key(0, 0, 0), "0000-00-00");
        // printf("%04d-%02d-%02d", -1, -2, -3) と同一 (机上確認値)。
        assert_eq!(day_key(-1, -2, -3), "-001--2--3");
        // 桁あふれは最小幅扱いでそのまま伸びる。
        assert_eq!(day_key(12026, 1, 9), "12026-01-09");
    }

    // NOTE: 「前日」のテストはここには無い。前日算出は端末カレンダーの演算
    // (夏時間・era 跨ぎ・暦ごとのうるう規則) が必要でラッパ側の責務のため、
    // ImasLiveDBTests/DailyPickTests.swift (testPreviousDayKey*) が固定している。

    // MARK: stable_index

    /// 同じ入力なら常に同じ値 (プロセスをまたいでも同じである必要がある)。
    #[test]
    fn stable_index_is_deterministic() {
        assert_eq!(
            stable_index("2026-07-26|cg", 100),
            stable_index("2026-07-26|cg", 100)
        );
    }

    /// 出荷済みの実装が出す既知値を固定する。
    ///
    /// ここが変わると全ユーザーの「今日の1曲」が一斉に入れ替わる。特に offset basis は
    /// 標準 FNV-1a (14695981039346656037) から 1 桁欠けた値のまま出荷されているので、
    /// 「定数が間違っている」と気づいた人が直したくなる。直すとこのテストが落ちる。
    /// 落ちたら実装ではなくこのテストの意図 (モジュールコメント) を先に読むこと。
    #[test]
    fn stable_index_matches_shipped_values() {
        assert_eq!(stable_index("a", 500), 366);
        assert_eq!(stable_index("", 7), 3);
        assert_eq!(stable_index("2026-07-26|cg", 500), 362);
    }

    #[test]
    fn stable_index_is_within_range() {
        for i in 0..200 {
            let idx = stable_index(&format!("2026-07-26|brand{i}"), 13);
            assert!((0..13).contains(&idx), "範囲外: {idx}");
        }
    }

    /// 候補 0 件でも落ちない (剰余のゼロ除算を踏まない)。
    #[test]
    fn stable_index_with_zero_modulo_is_safe() {
        assert_eq!(stable_index("x", 0), 0);
        assert_eq!(stable_index("x", -3), 0);
    }

    // MARK: song_index (アプリ ↔ ウィジェットの契約)

    /// 種文字列は `"日付|ブランドID"`。
    /// アプリ側とウィジェット側がこの組み立てを別々に持っていたのが元のバグ要因。
    #[test]
    fn song_index_uses_day_pipe_brand_seed() {
        assert_eq!(
            song_index("2026-07-26", "cg", 50),
            stable_index("2026-07-26|cg", 50)
        );
    }

    /// 日が変われば (基本的に) 選ぶ曲も変わる。日替わりとして機能していることの確認。
    #[test]
    fn song_index_varies_by_day() {
        let a = song_index("2026-07-26", "cg", 500);
        let b = song_index("2026-07-27", "cg", 500);
        assert_ne!(a, b);
    }

    /// 同じ日でもブランドが違えば別の曲を選ぶ (全ブランド同じ番号にならない)。
    #[test]
    fn song_index_varies_by_brand() {
        let cg = song_index("2026-07-26", "cg", 500);
        let ml = song_index("2026-07-26", "ml", 500);
        assert_ne!(cg, ml);
    }

    /// 候補が空でも 0 を返して落ちない。
    #[test]
    fn song_index_with_no_candidates() {
        assert_eq!(song_index("2026-07-26", "cg", 0), 0);
    }

    // MARK: song_indices (一括版)

    /// 一括版はスカラー版と必ず同じ答えを出す (アプリの一括解決とウィジェットの
    /// 単発解決が同じ曲を選ぶための契約)。順序も入力と同じ。
    #[test]
    fn song_indices_match_scalar_song_index() {
        let brands = vec![
            DailyPickBrandCandidates { brand_id: "cg".into(), count: 500 },
            DailyPickBrandCandidates { brand_id: "ml".into(), count: 321 },
            DailyPickBrandCandidates { brand_id: "sc".into(), count: 1 },
            DailyPickBrandCandidates { brand_id: "empty".into(), count: 0 },
        ];
        let got = song_indices("2026-07-26", &brands);
        let want: Vec<u32> = brands
            .iter()
            .map(|b| song_index("2026-07-26", &b.brand_id, i64::from(b.count)) as u32)
            .collect();
        assert_eq!(got, want);
    }

    #[test]
    fn song_indices_with_empty_input() {
        assert!(song_indices("2026-07-26", &[]).is_empty());
    }

    // MARK: candidate_song_ids (元 SQL との等価性)

    /// 元 SQL (iOS fetchSongIdsQuery / Android fetchDailyPickSongIds) の写経を
    /// 同梱 DB に対して直接実行する。候補列は**順序込み**で一致しないといけない
    /// (番号は共有しているので、列がずれれば同じ日に別の曲が出る)。
    fn run_original_sql(brand_id: &str, include_covers: bool, exclude_remixes: bool) -> Vec<String> {
        let mut sql = String::from("SELECT id FROM songs WHERE brand_id=?");
        if !include_covers {
            sql.push_str(" AND song_type<>'cover'");
        }
        if exclude_remixes {
            sql.push_str(" AND (parent_song_id IS NULL OR parent_song_id='')");
        }
        sql.push_str(" ORDER BY id");
        let db = conn();
        let mut stmt = db.prepare(&sql).expect("元 SQL は妥当");
        stmt.query_map([brand_id], |r| r.get::<_, String>(0))
            .expect("元 SQL を実行できる")
            .collect::<Result<Vec<_>, _>>()
            .expect("行を読める")
    }

    /// 実在ブランド全部 × フラグ 4 通りで元 SQL と順序込みで一致する。
    #[test]
    fn candidate_song_ids_match_sql_for_every_brand() {
        let brand_ids: Vec<String> = snap().brands.iter().map(|b| b.id.clone()).collect();
        assert!(brand_ids.len() > 5, "ブランドが載っている前提: {}", brand_ids.len());
        let mut non_empty = 0usize;
        for brand in &brand_ids {
            for include_covers in [false, true] {
                for exclude_remixes in [false, true] {
                    let want = run_original_sql(brand, include_covers, exclude_remixes);
                    let got = candidate_song_ids(snap(), brand, include_covers, exclude_remixes);
                    assert_eq!(
                        got, want,
                        "brand={brand} include_covers={include_covers} exclude_remixes={exclude_remixes}"
                    );
                    non_empty += usize::from(!want.is_empty());
                }
            }
        }
        assert!(non_empty > 20, "候補が空の組み合わせばかりでは検証にならない: {non_empty}");
    }

    /// 除外の 2 条件が実データで効いていること。全ブランド一致だけだと
    /// 「両方の条件を無視する実装」でも (カバーも派生も持たないブランドが多いので)
    /// たまたま通り得るため、条件ごとに「そのブランドで実際に減る」ことを見る。
    #[test]
    fn candidate_song_ids_actually_drop_covers_and_variants() {
        // カバーを一番多く持つブランド / 派生を一番多く持つブランドは別々なので分けて選ぶ。
        let dropped_by = |include_covers: bool, exclude_remixes: bool| {
            snap()
                .brands
                .iter()
                .map(|b| {
                    let all = candidate_song_ids(snap(), &b.id, true, false).len();
                    let kept = candidate_song_ids(snap(), &b.id, include_covers, exclude_remixes).len();
                    (b.id.clone(), all - kept)
                })
                .max_by_key(|(_, dropped)| *dropped)
                .expect("ブランドが 1 つはある")
        };

        let (cover_brand, covers_dropped) = dropped_by(false, false);
        assert!(covers_dropped > 0, "カバー曲を持つブランドがある前提 (brand={cover_brand})");

        let (variant_brand, variants_dropped) = dropped_by(true, true);
        assert!(variants_dropped > 0, "派生曲を持つブランドがある前提 (brand={variant_brand})");

        // 実際に使う組み合わせは両方の除外が同時に効く (どちらの単独より多くは残らない)。
        for brand in [&cover_brand, &variant_brand] {
            let used = candidate_song_ids(snap(), brand, false, true).len();
            let no_cover = candidate_song_ids(snap(), brand, false, false).len();
            let no_variant = candidate_song_ids(snap(), brand, true, true).len();
            assert!(used <= no_cover.min(no_variant), "brand={brand}");
        }
    }

    /// 未知ブランドは空 (呼び出し側が空判定してスキップする前提)。
    #[test]
    fn candidate_song_ids_for_unknown_brand_is_empty() {
        assert!(candidate_song_ids(snap(), "存在しないブランド", false, true).is_empty());
        assert_eq!(run_original_sql("存在しないブランド", false, true), Vec::<String>::new());
    }

    /// 並びは id 昇順 (BINARY) で、スナップショットの添字順ではない。
    /// ここが崩れると Android (rowid = 同期到着順) と iOS で候補列がずれる。
    #[test]
    fn candidate_song_ids_are_sorted_by_id_not_by_snapshot_order() {
        let brand = snap()
            .brands
            .iter()
            .map(|b| b.id.as_str())
            .max_by_key(|b| candidate_song_ids(snap(), b, false, true).len())
            .expect("ブランドが 1 つはある");
        let ids = candidate_song_ids(snap(), brand, false, true);
        assert!(ids.len() > 50, "検証に足る件数がある前提: {}", ids.len());
        assert!(ids.windows(2).all(|w| w[0] < w[1]), "id 昇順・重複なし");

        // 添字順とは実際に違うこと (同じなら「並べ替えを忘れた実装」でも通ってしまう)
        let in_snapshot_order: Vec<&str> = snap()
            .songs
            .iter()
            .filter(|s| s.brand_id.as_deref() == Some(brand))
            .filter(|s| !Snapshot::is_cover(s))
            .filter(|s| s.parent_song_id.as_deref().is_none_or(str::is_empty))
            .map(|s| s.id.as_str())
            .collect();
        assert_ne!(ids, in_snapshot_order, "添字順と id 昇順が同じ DB では検証にならない");
    }

    /// 共有 CARGO_TARGET_DIR の成果物混入の回帰ガード (search_queries と同型)。
    #[test]
    fn test_binary_was_built_from_this_tree() {
        let baked = include_str!("daily_pick.rs");
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/src/domain/daily_pick.rs");
        let on_disk = std::fs::read_to_string(path).unwrap_or_else(|e| {
            panic!("ビルド元ツリーの {path} を読めない = 陳腐化した成果物で検証している: {e}")
        });
        assert!(baked == on_disk, "ビルド元とディスク上の {path} が不一致 = 陳腐化した成果物で検証している");
    }
}
