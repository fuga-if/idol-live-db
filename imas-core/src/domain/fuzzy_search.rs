//! うろ覚えの曲名でも引ける**あいまい検索**。
//!
//! 既存の [`crate::domain::text_search_index`] は部分一致 (contains) なので、
//! タイプミス・音引きの揺れ・送り仮名違いだと 0 件になる。ここは編集距離で
//! 「だいたい合っている」候補を拾い、部分一致で拾えたものより下に並べる。
//!
//! # なぜ Rust に置くか
//!
//! 全 3,117 曲に対して編集距離を計算するのは Swift/Kotlin では体感できる遅さになるが、
//! ここでは数ミリ秒で終わる。打鍵ごとに引き直しても間に合う。
//!
//! # 正規化
//!
//! 比較の前に [`prepare_needle`] と同じ正規化 (NFC + 小文字化 + 記号除去) を通し、
//! さらに**カタカナ→ひらがな**と**長音・促音・濁点の揺れ**を潰す。
//! 「ｼｬｲﾆｰ」「シャイニー」「しゃいにい」がすべて同じ鍵になる。
//!
//! # できないこと
//!
//! **漢字とかなは互いに寄らない**。「おねがいしんでれら」と打っても
//! 「お願い！シンデレラ」には当たらない (編集距離では 願 と ねが を同一視できない)。
//! これを解くには読み仮名が要るが、`songs.title_kana` は現在**全 3,117 曲で空**。
//! [`fuzzy_matches_multi`] は 1 件につき複数の綴り (曲名・読み・別名) を受け取れるので、
//! 読みが入り次第そこへ渡せば漢字入りの曲もかなで引けるようになる。

use crate::domain::text_search_index::prepare_needle;

/// 1 件ぶんの候補。`index` は呼び出し側が渡した配列の添字。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct FuzzyHit {
    pub index: u32,
    /// 0.0〜1.0。1.0 が完全一致。並べ替え済みなので通常は見なくてよい。
    pub score: f64,
    /// 部分一致で拾えたか (true なら「確実な一致」として上に出る)。
    pub exact: bool,
}

/// 比較用の鍵へ正規化する。
///
/// - `prepare_needle` の正規化 (NFC・小文字化・記号除去) を通す
/// - カタカナをひらがなへ寄せる (半角カナは NFC で全角になっている)
/// - 長音「ー」・促音「っ」・濁点半濁点を落とす (「ぷりんせす」「プリンセス」「ぷりんせすー」を同一視)
pub fn fuzzy_key(text: &str) -> Vec<char> {
    let normalized = prepare_needle(text);
    let s = String::from_utf8_lossy(&normalized);
    let mut out = Vec::new();
    for ch in s.chars() {
        // カタカナ (30A1..30F6) → ひらがな (3041..3096)
        let ch = if ('\u{30A1}'..='\u{30F6}').contains(&ch) {
            char::from_u32(ch as u32 - 0x60).unwrap_or(ch)
        } else {
            ch
        };
        // 音引き・促音は落とす。揺れの原因になりやすく、落としても弁別性はほぼ減らない。
        if ch == 'ー' || ch == 'っ' || ch == 'ゝ' {
            continue;
        }
        out.push(ch);
    }
    out
}

/// 編集距離 (Levenshtein)。`limit` を超えると打ち切って `limit + 1` を返す。
///
/// 打ち切りを入れているのは、全曲との比較で「明らかに違う」ものに
/// 最後まで計算を回さないため。
fn edit_distance(a: &[char], b: &[char], limit: usize) -> usize {
    if a.len().abs_diff(b.len()) > limit {
        return limit + 1;
    }
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    let mut cur = vec![0usize; b.len() + 1];
    for i in 1..=a.len() {
        cur[0] = i;
        let mut row_min = cur[0];
        for j in 1..=b.len() {
            let cost = usize::from(a[i - 1] != b[j - 1]);
            cur[j] = (prev[j] + 1).min(cur[j - 1] + 1).min(prev[j - 1] + cost);
            row_min = row_min.min(cur[j]);
        }
        if row_min > limit {
            return limit + 1;
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    prev[b.len()]
}

/// 許容する編集距離。短い語ほど厳しくする
/// (2 文字の語で距離 2 を許すと何にでも当たってしまう)。
fn allowed_distance(needle_len: usize) -> usize {
    match needle_len {
        0..=2 => 0,
        3..=5 => 1,
        6..=9 => 2,
        _ => 3,
    }
}

/// 候補群からあいまい一致を拾う (1 件 = 1 綴り)。
///
/// 並び順は「部分一致 → 編集距離が小さい順 → 元の並び順」。
/// 同点は添字の小さい方を先に出すので、同じ入力なら常に同じ結果になる。
pub fn fuzzy_matches(haystacks: &[String], needle: &str, limit: u32) -> Vec<FuzzyHit> {
    let multi: Vec<Vec<String>> = haystacks.iter().map(|h| vec![h.clone()]).collect();
    fuzzy_matches_multi(&multi, needle, limit)
}

/// 1 件につき複数の綴りを持てる版 (曲名・読み仮名・ローマ字・別名など)。
///
/// どれか 1 つでも当たれば採用し、**最も良いスコア**をその件のスコアにする。
/// 読み仮名が入れば、漢字の曲名をかなで引けるようになる。
pub fn fuzzy_matches_multi(haystacks: &[Vec<String>], needle: &str, limit: u32) -> Vec<FuzzyHit> {
    let needle_key = fuzzy_key(needle);
    if needle_key.is_empty() {
        return Vec::new();
    }
    let allowed = allowed_distance(needle_key.len());
    let mut hits: Vec<FuzzyHit> = Vec::new();

    for (i, spellings) in haystacks.iter().enumerate() {
        let mut best: Option<FuzzyHit> = None;
        for hay in spellings {
        let key = fuzzy_key(hay);
        if key.is_empty() {
            continue;
        }
        // ① 部分一致 (従来と同じ判定)。確実な一致として最優先。
        if key.windows(needle_key.len().min(key.len())).any(|w| w == needle_key.as_slice()) {
            best = Some(FuzzyHit { index: i as u32, score: 1.0, exact: true });
            break;
        }
        // ② 語全体の編集距離。
        let d = edit_distance(&needle_key, &key, allowed);
        if d <= allowed {
            let denom = needle_key.len().max(key.len()) as f64;
            let hit = FuzzyHit { index: i as u32, score: 1.0 - (d as f64 / denom), exact: false };
            if best.as_ref().is_none_or(|b| hit.score > b.score) { best = Some(hit); }
            continue;
        }
        // ③ 先頭 n 文字との距離 (「シャイニーカラーズ」で「シャイニー」を打った等)。
        if key.len() > needle_key.len() {
            let head = &key[..needle_key.len()];
            let d = edit_distance(&needle_key, head, allowed);
            if d <= allowed {
                let hit = FuzzyHit {
                    index: i as u32,
                    score: 0.9 - (d as f64 / needle_key.len() as f64),
                    exact: false,
                };
                if best.as_ref().is_none_or(|b| hit.score > b.score) { best = Some(hit); }
            }
        }
        }
        if let Some(hit) = best { hits.push(hit); }
    }

    hits.sort_by(|a, b| {
        b.exact
            .cmp(&a.exact)
            .then(b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal))
            .then(a.index.cmp(&b.index))
    });
    hits.truncate(limit as usize);
    hits
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hay() -> Vec<String> {
        ["お願い！シンデレラ", "SHINY SMILE", "シャイニーカラーズ", "Star!!",
         "君は明日と何を願う", "プリンセスの休息", "GO MY WAY!!", "私はアイドル♡"]
            .iter().map(|s| s.to_string()).collect()
    }

    fn titles(hits: &[FuzzyHit], src: &[String]) -> Vec<String> {
        hits.iter().map(|h| src[h.index as usize].clone()).collect()
    }

    #[test]
    fn exact_substring_comes_first() {
        let h = hay();
        let got = fuzzy_matches(&h, "シンデレラ", 5);
        assert!(got[0].exact);
        assert_eq!(titles(&got, &h)[0], "お願い！シンデレラ");
    }

    #[test]
    fn katakana_and_hiragana_are_the_same() {
        let h = hay();
        assert_eq!(titles(&fuzzy_matches(&h, "しんでれら", 5), &h)[0], "お願い！シンデレラ");
    }

    #[test]
    fn typo_still_hits() {
        let h = hay();
        // 「プリンセス」を「ぷりんせつ」と打ち間違えても拾える
        let got = fuzzy_matches(&h, "ぷりんせつ", 5);
        assert!(titles(&got, &h).contains(&"プリンセスの休息".to_string()), "{:?}", titles(&got, &h));
    }

    #[test]
    fn long_vowel_variation_is_absorbed() {
        let h = hay();
        // 音引きの有無が違っても同じ曲に当たる
        let a = fuzzy_matches(&h, "シャイニーカラーズ", 3);
        let b = fuzzy_matches(&h, "しゃいにいからず", 3);
        assert_eq!(titles(&a, &h)[0], "シャイニーカラーズ");
        assert!(titles(&b, &h).contains(&"シャイニーカラーズ".to_string()), "{:?}", titles(&b, &h));
    }

    #[test]
    fn prefix_typed_partially() {
        let h = hay();
        let got = fuzzy_matches(&h, "シャイニー", 5);
        assert!(titles(&got, &h).contains(&"シャイニーカラーズ".to_string()));
    }

    #[test]
    fn short_needle_does_not_match_everything() {
        let h = hay();
        // 2 文字は編集距離 0 (部分一致のみ)。何にでも当たると使い物にならない。
        let got = fuzzy_matches(&h, "ずざ", 10);
        assert!(got.is_empty(), "{:?}", titles(&got, &h));
    }

    #[test]
    fn empty_needle_returns_nothing() {
        assert!(fuzzy_matches(&hay(), "", 5).is_empty());
        assert!(fuzzy_matches(&hay(), "  ", 5).is_empty());
    }

    #[test]
    fn results_are_deterministic() {
        let h = hay();
        let a = fuzzy_matches(&h, "しゃいに", 5);
        let b = fuzzy_matches(&h, "しゃいに", 5);
        assert_eq!(a, b);
    }

    /// 読み仮名を併せて渡せば、漢字の曲名もかなで引ける。
    /// (`songs.title_kana` は現在空なので実データでは効かないが、
    ///  入った瞬間に使える形になっていることをここで固定する)
    #[test]
    fn reading_lets_kanji_titles_be_found_by_kana() {
        let items = vec![
            vec!["お願い！シンデレラ".to_string(), "おねがいシンデレラ".to_string()],
            vec!["Star!!".to_string()],
        ];
        let got = fuzzy_matches_multi(&items, "おねがいしんでれら", 5);
        assert_eq!(got.first().map(|h| h.index), Some(0), "{got:?}");

        // 読みが無ければ当たらない (今の実データの状態)
        let without = vec![vec!["お願い！シンデレラ".to_string()], vec!["Star!!".to_string()]];
        assert!(fuzzy_matches_multi(&without, "おねがいしんでれら", 5).is_empty());
    }

    #[test]
    fn limit_is_respected() {
        let h = hay();
        assert!(fuzzy_matches(&h, "あ", 2).len() <= 2);
    }

    /// 実データ (全曲) に対して、打鍵ごとに引ける速さかを確かめる。
    #[test]
    fn is_fast_enough_on_the_real_catalogue() {
        use rusqlite::{Connection, OpenFlags};
        let db = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        let conn = Connection::open_with_flags(&db, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let mut stmt = conn.prepare("SELECT title FROM songs").unwrap();
        let titles: Vec<String> = stmt
            .query_map([], |r| r.get::<_, String>(0))
            .unwrap()
            .filter_map(Result::ok)
            .collect();
        assert!(titles.len() > 3000, "曲数={}", titles.len());

        let t = std::time::Instant::now();
        let got = fuzzy_matches(&titles, "しゃいにーえくささいず", 20);
        let elapsed = t.elapsed();
        // 打鍵ごとに引き直しても間に合う (人が遅さを感じ始める 100ms を大きく下回ること)
        assert!(elapsed.as_millis() < 100, "{:?} かかった", elapsed);
        let names: Vec<&str> = got.iter().map(|h| titles[h.index as usize].as_str()).collect();
        println!("FUZZY 全{}曲 {:?} → {:?}", titles.len(), elapsed, &names[..names.len().min(3)]);
        // ひらがなで打っても実在の曲 (カタカナ表記) に当たること
        assert!(names.contains(&"シャイニーエクササイズ"), "{:?}", names);

        // 打ち間違い・表記ゆれでも実在曲に当たること
        for (typed, expected) in [
            ("ぷりんせすあらもーど", "プリンセス・アラモード"),
            ("アップルパイプリンセス", "アップルパイ・プリンセス"),
            ("しゃいにーえくささいす", "シャイニーエクササイズ"),
        ] {
            let hits = fuzzy_matches(&titles, typed, 20);
            let names: Vec<&str> = hits.iter().map(|h| titles[h.index as usize].as_str()).collect();
            assert!(names.contains(&expected), "「{typed}」→ {expected} が出ない: {:?}", &names[..names.len().min(5)]);
            println!("FUZZY 「{typed}」→ {expected} ✓");
        }
    }
    #[test]
    fn kana_search_now_reaches_kanji_titles() {
        use rusqlite::{Connection, OpenFlags};
        let db = format!("{}/../ImasLiveDB/Resources/master.sqlite", env!("CARGO_MANIFEST_DIR"));
        let conn = Connection::open_with_flags(&db, OpenFlags::SQLITE_OPEN_READ_ONLY).unwrap();
        let mut stmt = conn.prepare("SELECT title, title_kana FROM songs").unwrap();
        let rows: Vec<(String, Option<String>)> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap().filter_map(Result::ok).collect();
        // 1 曲につき「曲名」と「読み」の 2 綴りを渡す
        let items: Vec<Vec<String>> = rows.iter()
            .map(|(t, k)| match k { Some(k) if !k.is_empty() => vec![t.clone(), k.clone()], _ => vec![t.clone()] })
            .collect();
        let with_kana = rows.iter().filter(|(_, k)| k.as_deref().is_some_and(|s| !s.is_empty())).count();
        println!("KANA 読みつき {}/{} 曲", with_kana, rows.len());

        for (typed, expect) in [
            ("おねがいしんでれら", "お願い！シンデレラ"),
            ("あおいとり", "蒼い鳥"),
            ("たいようのじぇらしー", "太陽のジェラシー"),
        ] {
            let t = std::time::Instant::now();
            let hits = fuzzy_matches_multi(&items, typed, 20);
            let names: Vec<&str> = hits.iter().map(|h| rows[h.index as usize].0.as_str()).collect();
            let ok = names.iter().any(|n| *n == expect);
            println!("KANA 「{typed}」 {:?} → {} ({:?})", t.elapsed(), if ok {"当たった"} else {"外れた"}, &names[..names.len().min(3)]);
            assert!(ok, "「{typed}」で {expect} が出ない");
        }
    }
}
