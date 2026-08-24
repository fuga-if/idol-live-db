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

#[cfg(test)]
mod tests {
    use super::*;

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
}
