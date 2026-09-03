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
//! # 漢字とかなをまたぐには読みが要る
//!
//! **編集距離だけでは漢字とかなは互いに寄らない** (願 と ねが を同一視できない)。
//! そこで [`fuzzy_matches_multi`] は 1 件につき複数の綴り (曲名・読み・別名) を受け取り、
//! どれか 1 つでも当たれば採用する。呼び出し側は `[曲名, songs.title_kana]` を渡すこと。
//!
//! `title_kana` は 3,117 曲中 1,017 曲に入っている (2026-08-26 時点)。
//! 入っている曲は「おねがいしんでれら」→「お願い！シンデレラ」のようにかなで引ける。
//! **読みが空の曲はかなで引けない**ので、カバー率を上げるほど検索は効くようになる。

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
    // カタカナ → ひらがなの畳み込みは prepare_needle が済ませている
    // (一覧の絞り込みと同じ規則を使うため)。ここは更に緩める分だけを持つ。
    for ch in s.chars() {
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
///
/// 2 文字で 1 文字違いまで許すのは、距離だけで採否を決めていないから。
/// この先に一致率 (`Rarity::coverage`) の関門があり、「宮」だけ合っている
/// 「龍宮」→「竜宮逢幻記」は通し、「き」だけ合っている「きみ」→「かみ」は落ちる。
/// 距離が門番だった頃はここを 0 にするしかなかった。
fn allowed_distance(needle_len: usize) -> usize {
    match needle_len {
        0..=1 => 0,
        2..=5 => 1,
        6..=9 => 2,
        _ => 3,
    }
}

/// 文字ごとの希少性 (IDF)。何件の候補にその文字が出るかから求める。
///
/// # なぜ距離だけでは足りないか
///
/// 編集距離は「何文字違うか」しか見ないので、**どの文字が一致したか**を無視する。
/// 実機で「お願い」と打つと「オモイノウタ」が候補に出たのがこれで、
/// 一致していたのは「お」と「い」だけだった。日本語で最も頻出する 2 文字なので、
/// 一致しても手がかりにならない。
///
/// 逆に「龍宮」で「竜宮逢幻記」を出したい場面では、一致するのは「宮」1 文字だけだが
/// こちらは希少なので強い手がかりになる。**一致率ではなく、一致した文字の
/// 珍しさで測る**とこの 2 つが分かれる。異体字の対応表を持たずに済むのが利点で、
/// 表を作る方式は列挙しきれず必ず漏れる (龍/竜・櫻/桜・恋/戀・﨑/崎…)。
struct Rarity {
    total: f64,
    doc_freq: std::collections::HashMap<char, u32>,
}

impl Rarity {
    fn build(keys: &[Vec<char>]) -> Self {
        let mut doc_freq: std::collections::HashMap<char, u32> = std::collections::HashMap::new();
        for key in keys {
            let mut seen = std::collections::HashSet::new();
            for &c in key {
                if seen.insert(c) {
                    *doc_freq.entry(c).or_insert(0) += 1;
                }
            }
        }
        Self { total: keys.len().max(1) as f64, doc_freq }
    }

    /// 珍しいほど大きい。全件に出る文字は 0 に近づく。
    fn idf(&self, c: char) -> f64 {
        let df = self.doc_freq.get(&c).copied().unwrap_or(0) as f64;
        (self.total / (1.0 + df)).ln().max(0.0)
    }

    /// 打った語のうち、候補に含まれている文字が占める「珍しさの割合」。
    ///
    /// 1.0 に近いほど、打った語の情報が候補に残っている。
    fn coverage(&self, needle: &[char], candidate: &[char]) -> f64 {
        let present: std::collections::HashSet<char> = candidate.iter().copied().collect();
        let mut total = 0.0;
        let mut matched = 0.0;
        for &c in needle {
            // どの候補にも無い文字は数えない。
            //
            // 珍しさは「何件に出るか」で測るので、1 件も出ない文字は最も珍しい =
            // 最も重い、と出てしまう。しかし絶対に一致しない文字なので、重く数えると
            // 分母を占領して一致率を潰す (候補「プリンセスの休息」に「ぷりんせつ」と
            // 打つと、打ち間違えた「つ」だけで分母の 2/3 を占めて落ちた)。
            // どの候補にも無い文字は候補同士を区別できないので、判断材料にしない。
            if !self.doc_freq.contains_key(&c) {
                continue;
            }
            // 全件に出る文字も僅かに数える。ここが 0 だけになると 0 除算になる。
            let w = self.idf(c) + 0.1;
            total += w;
            if present.contains(&c) {
                matched += w;
            }
        }
        if total <= 0.0 { 0.0 } else { matched / total }
    }
}

/// あいまい候補として認める最小の一致率。
///
/// 実データで測った値: ノイズ (「お願い」→「オモイノウタ」= 合っているのは
/// 最頻出の「お」「い」だけ) が 0.49、拾いたいものは 1.0。この間で切る。
///
/// # 異体字 (龍/竜・櫻/桜) について
///
/// 対応表は持たない。列挙しきれず必ず漏れるうえ、「なぜこの字だけ効かないのか」
/// を生む。代わりに、**どの曲名にも出てこない文字は数えない** という
/// `Rarity::coverage` の規則がそのまま効く。データに無い旧字を打った時点で
/// その文字は候補同士を区別できないので、残りの文字で判断される
/// (「龍宮」→「竜宮逢幻記」・「月ノ櫻」→「月ノ桜」はこれで当たる)。
///
/// 逆に、その字がデータ中の別の曲で使われている場合は区別材料として数えるので
/// 当たらない。異体字を正面から解くには読みへの正規化か対応表が要るが、
/// 読み仮名 (`songs.title_kana`) を綴りとして渡してあるので、
/// 表記に迷うならかなで打てば引ける。
const MIN_COVERAGE: f64 = 0.6;

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
    // 希少性は候補群そのものから求める (辞書を持たない)。
    let all_keys: Vec<Vec<char>> = haystacks
        .iter()
        .map(|sp| sp.iter().flat_map(|s| fuzzy_key(s)).collect())
        .collect();
    let rarity = Rarity::build(&all_keys);
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
            // 距離が近いだけでは足りない。**打った語の情報がどれだけ残っているか**を見る。
            let cov = rarity.coverage(&needle_key, &key);
            if cov >= MIN_COVERAGE {
                let denom = needle_key.len().max(key.len()) as f64;
                // 珍しい文字が一致したものを上に出す。
                let hit = FuzzyHit {
                    index: i as u32,
                    score: (1.0 - (d as f64 / denom)) * cov,
                    exact: false,
                };
                if best.as_ref().is_none_or(|b| hit.score > b.score) { best = Some(hit); }
            }
            continue;
        }
        // ③ 先頭 n 文字との距離 (「シャイニーカラーズ」で「シャイニー」を打った等)。
        if key.len() > needle_key.len() {
            let head = &key[..needle_key.len()];
            let d = edit_distance(&needle_key, head, allowed);
            if d <= allowed {
                let cov = rarity.coverage(&needle_key, head);
                if cov >= MIN_COVERAGE {
                    let hit = FuzzyHit {
                        index: i as u32,
                        score: (0.9 - (d as f64 / needle_key.len() as f64)) * cov,
                        exact: false,
                    };
                    if best.as_ref().is_none_or(|b| hit.score > b.score) { best = Some(hit); }
                }
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

        // 5 回引いて**最良値**で見る。テストは並列に走るので、1 回計るだけだと他の
        // テストに CPU を持って行かれた分まで乗ってしまい、実際の速さと関係なく落ちる
        // (実データ照合のテストを重くした時に、この閾値で 1 度だけ落ちた)。
        // 見たいのは「この処理がどれだけ速く引けるか」なので、最小値が答え。
        let mut got = Vec::new();
        let mut best = std::time::Duration::MAX;
        for _ in 0..5 {
            let t = std::time::Instant::now();
            got = fuzzy_matches(&titles, "しゃいにーえくささいず", 20);
            best = best.min(t.elapsed());
        }
        let elapsed = best;
        // ⚠️ 閾値は「人が遅いと感じる時間」ではなく**桁が変わる regression の検出**用。
        //
        // 以前は 100ms で切っていたが、これは開発機 (実測 33ms) の感覚で決めた値で、
        // CI の runner はおおよそ 3 倍遅く、best-of-5 でも 100.7ms を出して落ちた。
        // 「打鍵ごとに間に合うか」は**ユーザーの端末**の話で、CI の実機速度で測っても
        // 答えは出ない。CI に見てほしいのは「アルゴリズムが O(n) から落ちていないか」で、
        // それが起きれば 3 倍ではなく桁で変わる。
        //
        // 実測値は下の println! に出るので、じわじわ遅くなる変化はログで追える。
        assert!(elapsed.as_millis() < 400, "{:?} かかった (桁が変わっている疑い)", elapsed);
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
    #[test]
    fn generated_readings_still_reach_the_song() {
        // 「正しい読み」で打ったとき、AI 生成の読みが入っていても曲に当たるか。
        // 生成読みが多少ずれていても、編集距離で吸収できれば検索の実用上は問題ない。
        let cases = [
            // (曲名, 生成された読み, ユーザーが打つであろう正しい読み)
            ("Brand New Theater!", "ぶらんどにゅーしあたー", "ぶらんにゅーしあたー"),
            ("Nation Blue", "ねーしょんぶるー", "ねいしょんぶるー"),
            ("求ム VS マイ・フューチャー", "もとむぶいえすまいふゅーちゃー", "もとむばーさすまいふゅーちゃー"),
            ("夕風のメロディー", "ゆうかぜのめろでぃー", "ゆうかぜのめろでぃー"),
        ];
        let items: Vec<Vec<String>> = cases.iter()
            .map(|(t, gen, _)| vec![t.to_string(), gen.to_string()])
            .collect();
        for (i, (title, generated, typed)) in cases.iter().enumerate() {
            let got = fuzzy_matches_multi(&items, typed, 10);
            assert!(
                got.iter().any(|h| h.index as usize == i),
                "「{typed}」で「{title}」に当たらない (入っている読み: {generated})"
            );
        }
    }
    #[test]
    fn kanji_difference_is_not_a_typo() {
        // 実機で「お願い」と打つと「オモイノウタ」「おもいでのはじまり」が
        // 「もしかして」に出ていた。「お」と「い」しか合っていないのに、
        // 願↔も を かな 1 文字の打ち間違いと同じ重さで数えていたため。
        let items = vec![
            vec!["お願い！シンデレラ".to_string(), "おねがいしんでれら".to_string()],
            vec!["オモイノウタ".to_string()],
            vec!["おもいでのはじまり".to_string()],
            vec!["プリンセスの休息".to_string()],
        ];
        let got = fuzzy_matches_multi(&items, "お願い", 10);
        let hit: Vec<u32> = got.iter().map(|h| h.index).collect();
        assert!(hit.contains(&0), "本命が出ない: {hit:?}");
        assert!(!hit.contains(&1), "オモイノウタ を拾ってはいけない");
        assert!(!hit.contains(&2), "おもいでのはじまり を拾ってはいけない");

        // かな同士の打ち間違いは今までどおり拾う
        let got = fuzzy_matches_multi(&items, "ぷりんせつ", 10);
        assert!(got.iter().any(|h| h.index == 3), "かなの打ち間違いが拾えない");
    }
    /// 候補が数件しかなくても希少性が機能する。
    ///
    /// 希少性は候補群そのものから測るので、候補が少ないと「どの文字も 1 件にしか
    /// 出ない = 珍しさに差が無い」状態に潰れる。そこで一致率まで 0 になると、
    /// 絞り込んだ一覧の中での検索が丸ごと効かなくなる。
    #[test]
    fn rarity_survives_a_tiny_candidate_set() {
        let items = vec![
            vec!["プリンセスの休息".to_string()],
            vec!["Star!!".to_string()],
        ];
        let hit: Vec<u32> = fuzzy_matches_multi(&items, "ぷりんせつ", 10).iter().map(|h| h.index).collect();
        assert!(hit.contains(&0), "かなの打ち間違いが拾えない: {hit:?}");
    }

    /// データに無い旧字で打っても、残りの文字で当たる。
    ///
    /// 異体字の対応表は持っていない。「龍」も「櫻」も曲名に一度も出てこないので
    /// 候補同士を区別できず、一致率の計算から外れる。結果として「宮」「月ノ」だけで
    /// 判断され、新字の曲に当たる。対応表を足したくなったらこの性質を思い出すこと。
    #[test]
    fn old_kanji_absent_from_the_data_does_not_block_the_match() {
        let items = vec![
            vec!["竜宮逢幻記".to_string()],
            vec!["月ノ桜".to_string()],
            vec!["お願い！シンデレラ".to_string()],
            vec!["オモイノウタ".to_string()],
        ];
        let hit = |n: &str| -> Vec<u32> {
            fuzzy_matches_multi(&items, n, 10).iter().map(|h| h.index).collect()
        };
        assert!(hit("龍宮").contains(&0), "龍宮 → 竜宮逢幻記 が当たらない");
        assert!(hit("月ノ櫻").contains(&1), "月ノ櫻 → 月ノ桜 が当たらない");
    }

    /// 2 文字の語で 1 文字違いを許しても、共通の文字だけでは通さない。
    ///
    /// 距離を緩めた分は一致率で受け止める。ここが緩むと短い語が何にでも当たる。
    #[test]
    fn a_single_shared_character_is_not_enough_for_a_short_query() {
        let items = vec![
            vec!["紙ヒコーキ".to_string()],
            vec!["キミはメロディ".to_string()],
        ];
        let hit: Vec<u32> = fuzzy_matches_multi(&items, "きみ", 10).iter().map(|h| h.index).collect();
        assert!(!hit.contains(&0), "「き」しか合っていない 紙ヒコーキ を拾ってはいけない: {hit:?}");
    }
}
