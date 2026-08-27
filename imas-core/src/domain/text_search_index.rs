//! 一覧の絞り込み用に前処理したテキスト検索索引。
//!
//! Swift の `String.contains` / Kotlin の `String.contains` を使わないのは、
//! 書記素クラスタ (Swift) やロケール処理を挟む照合が日本語で極端に遅く、
//! 2,000 曲を打鍵ごとに舐める用途では効いてくるから。iOS (Swift) 時代の実測では
//! 「毎回 lowercased + String.contains」の 1 打鍵 1.38 ms が、「事前に小文字化した
//! UTF-8 バイト列 + 部分列探索」で 0.11 ms (対象 4 スコープ) まで落ちた。
//! Rust 化後もこの構造は不変で、1 打鍵 = カタログ全体を 1 回走査する
//! O(総バイト数) のまま (FFI も 1 呼び出しに畳んであるので境界コストも定数)。
//!
//! 下ごしらえ (小文字化 + バイト列化) は読み込み時の 1 回だけ。読み込みは元々
//! DB クエリと出演者マップの解決で数十 ms 掛かっているので誤差に収まる。
//!
//! 畳むのは**大文字小文字**と**ひらがな↔カタカナ**の 2 つだけ。濁点と全角半角は畳まない。
//!
//! かなを畳むのは、日本語の入力では表記の種類まで合わせて打たないから
//! (「おね」と打った人は「オネガイ」も探している)。畳まなかった頃は、読み仮名
//! 経由で一覧には出るのに表記側に一致範囲が無く、ハイライトだけ付かなかった。
//!
//! 緩めるときは `match_range` (ハイライトの範囲) も同じ規則で動くことを確かめること。
//! 判定と表示で規則がズレると、索引が拾わなかった箇所に色が付いたり、
//! 一致しているのに説明が出なかったりする。

/// 1 項目 (曲など) ぶんの、小文字化済み UTF-8 バイト列の索引。
/// 照合したい単位 (フィールド) ごとに 1 本持つ。
///
/// 連結して 1 本にしないのは、境界をまたいだ偽陽性を避けるため
/// (「A」と「B」を繋ぐと "AB" が当たってしまう)。
pub struct TextSearchIndex {
    fields: Vec<Vec<u8>>,
}

impl TextSearchIndex {
    /// フィールド列から前処理する。空文字は索引に載せない
    /// (呼び出し側は nil 相当を除くか空文字のまま渡してよい)。
    pub fn new<I, S>(texts: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        Self {
            fields: texts
                .into_iter()
                .filter(|t| !t.as_ref().is_empty())
                .map(|t| fold_lowercase(t.as_ref()).into_bytes())
                .collect(),
        }
    }

    /// いずれかのフィールドに検索語を含むか。空の検索語は「絞り込まない」= true。
    pub fn matches(&self, needle: &[u8]) -> bool {
        if needle.is_empty() {
            return true;
        }
        self.fields.iter().any(|field| contains(field, needle))
    }
}

/// 検索語の前処理 (小文字化 + UTF-8 バイト列化)。
/// 索引側と同じ畳み込みを通すことが、当たり方を対称に保つ条件。
pub fn prepare_needle(text: &str) -> Vec<u8> {
    fold_lowercase(text).into_bytes()
}

/// 原本 Swift の `String.lowercased()` と同じ「文脈を見ない」小文字化。
///
/// `str::to_lowercase` を使わないのは、Unicode SpecialCasing の Final_Sigma
/// 文脈規則を適用して語末の Σ (U+03A3) を ς に畳んでしまうから。原本 Swift は
/// 無条件写像のみで Σ→σ 固定なので、そのままだと "ΑΣ" が "ας" に畳まれて
/// 検索語 "σ" を外す等、旧アプリと当たり方が非対称になる (移植時の差分ファズで
/// 不一致は全て U+03A3 絡みのこの規則差だった)。`char::to_lowercase` は
/// 無条件の全小文字化写像 (U+0130 → "i\u{307}" の 1:N 展開含む) で Swift と一致する。
fn fold_lowercase(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars().flat_map(char::to_lowercase).map(fold_kana) {
        match out.chars().next_back().and_then(|prev| compose_voiced_mark(prev, ch)) {
            Some(composed) => {
                out.pop();
                out.push(composed);
            }
            None => out.push(ch),
        }
    }
    out
}

/// 単独の濁点・半濁点を直前のかなに合成する (か + ゛ → が)。合成できなければ None。
///
/// 濁点付きのかなには合成済み (NFC: が U+304C) と分解済み (NFD: か + U+3099) の
/// 2 つの表し方がある。バイト列で比べる以上、片方だけでは当たらない。
/// 実データにも 1 曲・1 ライブ紛れていて、**自分の名前で検索できない**状態だった。
/// データを直しても、アプリ内編集や貼り付けで再び入ってくるのでここで吸収する。
///
/// 表を持たずに済むのは、ひらがなが濁点の有無で連続して並んでいるため
/// (か U+304B → が U+304C → 半濁点は は行のみ +2)。`fold_kana` の後に呼ぶ前提。
fn compose_voiced_mark(base: char, mark: char) -> Option<char> {
    const DAKUTEN: char = '\u{3099}';
    const HANDAKUTEN: char = '\u{309A}';
    let voiced = |c: char| char::from_u32(c as u32 + 1);
    let semi = |c: char| char::from_u32(c as u32 + 2);
    match (base, mark) {
        // う゛ = ゔ だけ並びから外れる。
        ('\u{3046}', DAKUTEN) => Some('\u{3094}'),
        // か行 さ行 た行 は行 (清音は 2 つおき / は行は 3 つおきに並ぶ)。
        ('\u{304B}'..='\u{3062}', DAKUTEN) if (base as u32 - 0x304B) % 2 == 0 => voiced(base),
        ('\u{3064}'..='\u{3068}', DAKUTEN) if (base as u32 - 0x3064) % 2 == 0 => voiced(base),
        ('\u{306F}'..='\u{307B}', DAKUTEN) if (base as u32 - 0x306F) % 3 == 0 => voiced(base),
        ('\u{306F}'..='\u{307B}', HANDAKUTEN) if (base as u32 - 0x306F) % 3 == 0 => semi(base),
        _ => None,
    }
}

/// カタカナをひらがなへ畳む (1 文字 → 1 文字、UTF-8 では 3 バイト → 3 バイト)。
///
/// 範囲は U+30A1..=U+30F6 だけ。`ー` (U+30FC) と `・` (U+30FB) は対応するひらがなが
/// 無いうえ、`ー` は表記の一部として弁別に効くので触らない。
/// `ヷヸヹヺ` (U+30F7..=U+30FA) も対応が無いのでそのまま。
pub(crate) fn fold_kana(ch: char) -> char {
    if ('\u{30A1}'..='\u{30F6}').contains(&ch) {
        char::from_u32(ch as u32 - 0x60).unwrap_or(ch)
    } else {
        ch
    }
}

/// 畳んだバイト列と、その各バイトが元の文字列のどこから来たかの対応表。
///
/// ハイライトは**元の文字列**の範囲を必要とするが、照合は畳んだ列で行う。
/// 小文字化には 1 文字が 2 文字に開くもの (U+0130 → "i\u{307}") があるので、
/// 畳んだ位置をそのまま元の位置として使うとずれる。畳みながら対応を記録しておく。
fn fold_with_offsets(text: &str) -> (Vec<u8>, Vec<usize>, Vec<usize>) {
    let mut bytes = Vec::with_capacity(text.len());
    let mut starts = Vec::with_capacity(text.len());
    let mut ends = Vec::with_capacity(text.len());
    let mut buf = [0u8; 4];
    for (offset, ch) in text.char_indices() {
        let end = offset + ch.len_utf8();
        for folded in ch.to_lowercase().map(fold_kana) {
            // 直前の文字と合成できるなら、積んだ 1 文字ぶんを差し替える。
            // 元の 2 文字ぶんを覆うので、始まりは前の文字のまま・終わりだけ伸ばす。
            if let Some(composed) = last_char(&bytes).and_then(|prev| compose_voiced_mark(prev, folded)) {
                let previous = prev_char_len(&bytes);
                let start = starts[bytes.len() - previous];
                bytes.truncate(bytes.len() - previous);
                starts.truncate(bytes.len());
                ends.truncate(bytes.len());
                for _ in composed.encode_utf8(&mut buf).bytes() {
                    starts.push(start);
                    ends.push(end);
                }
                bytes.extend_from_slice(composed.encode_utf8(&mut buf).as_bytes());
                continue;
            }
            for _ in folded.encode_utf8(&mut buf).bytes() {
                starts.push(offset);
                ends.push(end);
            }
            bytes.extend_from_slice(folded.encode_utf8(&mut buf).as_bytes());
        }
    }
    (bytes, starts, ends)
}

/// 積んだバイト列の末尾 1 文字 (合成できるか見るため)。
fn last_char(bytes: &[u8]) -> Option<char> {
    std::str::from_utf8(bytes).ok()?.chars().next_back()
}

/// 積んだバイト列の末尾 1 文字のバイト数。
fn prev_char_len(bytes: &[u8]) -> usize {
    last_char(bytes).map_or(0, char::len_utf8)
}

/// 検索語が `haystack` のどこに当たったかを、**元の文字列のバイト範囲**で返す。
///
/// 一覧に載せるかを決める `matching_indices` と同じ畳み込みを通るので、
/// 「一覧に出ているのに範囲が無い」も「載っていないのに範囲がある」も起きない。
/// ハイライトを描く側がここを呼ぶ前提で、照合規則を二重に持たないこと。
pub fn match_range(haystack: &str, needle: &str) -> Option<(u32, u32)> {
    let needle = prepare_needle(needle);
    if needle.is_empty() {
        return None;
    }
    let (bytes, starts, ends) = fold_with_offsets(haystack);
    let at = find(&bytes, &needle)?;
    Some((starts[at] as u32, ends[at + needle.len() - 1] as u32))
}

/// カタログ (項目の索引列) を 1 パスで照合し、当たった項目の index を昇順で返す。
/// 空の検索語は全項目 (絞り込みを掛けていない状態)。
///
/// 1 打鍵 = この関数 1 回で済ませるのが FFI 境界の規約
/// (項目ごとに matches を FFI 越しに呼ぶと打鍵ごとに 2,000+ 回の境界越えになる)。
pub fn matching_indices(items: &[TextSearchIndex], needle_text: &str) -> Vec<u32> {
    let needle = prepare_needle(needle_text);
    items
        .iter()
        .enumerate()
        .filter(|(_, item)| item.matches(&needle))
        .map(|(i, _)| i as u32)
        .collect()
}

/// 素朴な部分列探索。
///
/// UTF-8 は先頭バイトと継続バイトの範囲が重ならないので、バイト列としての一致が
/// そのまま文字列としての一致になる (途中のバイトから始まる偽の一致が起きない)。
/// 検索語は数文字なので Boyer-Moore 等を持ち込む必要はない。
pub fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    find(haystack, needle).is_some()
}

/// `contains` の位置を返す版。ハイライトの範囲を出すのに要る。
fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    // 空の検索語はここでは None (「絞り込まない」の判定は matches 側の責務)。
    let &first = needle.first()?;
    if haystack.len() < needle.len() {
        return None;
    }
    let last = haystack.len() - needle.len();
    // 先頭バイトで足切りしてから残りを比べる (原本 Swift 実装と同じ形)。
    (0..=last).find(|&i| haystack[i] == first && &haystack[i..i + needle.len()] == needle)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// iOS テストの `index(...)` 相当。nil フィールドは空文字で表す (どちらも索引に載らない)。
    fn index(texts: &[&str]) -> TextSearchIndex {
        TextSearchIndex::new(texts.iter().copied())
    }

    fn hit(index: &TextSearchIndex, query: &str) -> bool {
        index.matches(&prepare_needle(query))
    }

    // --- 基本 ---

    #[test]
    fn matches_substring_anywhere() {
        let i = index(&["夢色ハーモニー"]);
        assert!(hit(&i, "夢")); // 先頭
        assert!(hit(&i, "ハーモ")); // 途中
        assert!(hit(&i, "ニー")); // 末尾
        assert!(hit(&i, "夢色ハーモニー")); // 全体
        assert!(!hit(&i, "夢色ハーモニーズ")); // 検索語の方が長い
        assert!(!hit(&i, "星"));
    }

    #[test]
    fn empty_query_matches_everything() {
        assert!(hit(&index(&["READY!!"]), ""));
        // 中身が無い項目でも空検索なら落とさない (絞り込みを掛けていない状態)
        assert!(hit(&index(&[""]), ""));
    }

    #[test]
    fn empty_index_never_matches_non_empty_query() {
        assert!(!hit(&index(&[""]), "夢"));
    }

    // --- 複数フィールド ---

    #[test]
    fn matches_any_field() {
        let i = index(&["READY!!", "れでぃ"]);
        assert!(hit(&i, "READY"));
        assert!(hit(&i, "れでぃ"));
        assert!(!hit(&i, "GO"));
    }

    /// 連結して 1 本にすると境界をまたいだ偽の一致が起きる。分けて持つ理由。
    #[test]
    fn does_not_match_across_field_boundary() {
        assert!(!hit(&index(&["あい", "うえ"]), "いう"));
    }

    // --- 大文字小文字 ---

    #[test]
    fn case_insensitive_for_ascii() {
        let i = index(&["Crossing!"]);
        assert!(hit(&i, "crossing"));
        assert!(hit(&i, "CROSSING"));
        assert!(hit(&i, "CrOsSiNg"));
    }

    /// 全角半角は畳まない。半角カナはこのデータに現れず、畳むと文字数が変わって
    /// ハイライトの範囲計算まで巻き込むので、境界をここに引く。
    #[test]
    fn does_not_fold_width() {
        assert!(!hit(&index(&["ﾂﾊﾞｻ"]), "ツバサ"));
    }

    // --- バイト列探索の性質 ---

    /// UTF-8 は先頭バイトと継続バイトの範囲が重ならないので、バイト一致が
    /// そのまま文字一致になる。途中のバイトから始まる偽の一致は起きない。
    #[test]
    fn no_false_match_inside_multibyte_character() {
        // 「亜」= E4 BA 9C, 「介」= E4 BB 8B — 先頭バイトを共有する別の文字
        assert!(!hit(&index(&["亜"]), "介"));
        // 継続バイトだけが一致する組み合わせでも当たらない
        assert!(!hit(&index(&["そら"]), "らそ"));
    }

    #[test]
    fn matches_emoji_and_combining_characters() {
        let i = index(&["きらめき✨ 未来"]);
        assert!(hit(&i, "✨"));
        assert!(hit(&i, "✨ 未来"));
    }

    /// 部分一致の途中で外して、その先で当たる場合 (素朴な探索の巻き戻し)。
    #[test]
    fn resumes_after_partial_match() {
        assert!(contains(b"aaab", b"aab"));
        assert!(contains(b"ababab", b"abab"));
        assert!(!contains(b"ababa", b"abb"));
    }

    #[test]
    fn contains_edge_cases() {
        assert!(!contains(&[], &[1]));
        assert!(!contains(&[1], &[])); // 空の検索語はここでは false
        assert!(!contains(&[1, 2], &[1, 2, 3]));
        assert!(contains(&[1, 2, 3], &[1, 2, 3]));
        assert!(contains(&[1, 2, 3], &[3]));
    }

    // --- 置き換え前との同値性 ---

    /// 旧実装 (Swift の `lowercased().contains`) と同じ答えを返すこと。
    /// 参照実装は `str::to_lowercase().contains`。ただし `str::to_lowercase` は
    /// Final_Sigma 文脈規則の分だけ Swift とずれるため、Σ (U+03A3) を含むケースは
    /// ここでは扱わず、専用テスト (folds_final_sigma_unconditionally_like_swift) で
    /// Swift 側の期待値に固定して検証する。
    #[test]
    fn agrees_with_string_contains() {
        let haystacks = [
            "夢色ハーモニー",
            "READY!!",
            "Crossing!",
            "M@STERPIECE",
            "きらめき✨",
            "ｱｲﾄﾞﾙ",
            "あいうえお",
            "1,2,3",
        ];
        let needles = [
            "夢", "ready", "READY", "crossing", "@", "✨", "ｱｲ", "いう", "3", "z", "ハーモニ",
            "M@S",
        ];
        for haystack in haystacks {
            for needle in needles {
                let expected = haystack.to_lowercase().contains(&needle.to_lowercase());
                assert_eq!(
                    hit(&index(&[haystack]), needle),
                    expected,
                    "haystack={haystack} needle={needle}"
                );
            }
        }
    }

    // --- Final_Sigma (原本 Swift との対称性) ---

    /// 原本 Swift の `String.lowercased()` は無条件写像のみで Σ (U+03A3) → σ 固定。
    /// `str::to_lowercase` の Final_Sigma 規則 (語末 Σ → ς) を持ち込むと
    /// 旧アプリと当たり方が黙って変わるので、Swift 側の挙動を期待値として固定する。
    /// (現 master.sqlite では「Σ Desire」の語頭 Σ のみで非可視だが、
    ///  語末 Σ を含む名称が入った時に旧実装との差が顕在化する。)
    #[test]
    fn folds_final_sigma_unconditionally_like_swift() {
        // 語末 Σ も σ に畳む: "ΑΣ" → "ασ"
        assert_eq!(prepare_needle("ΑΣ"), "ασ".as_bytes());
        let i = index(&["ΑΣ"]);
        assert!(hit(&i, "σ")); // 原本 Swift はヒット ("ασ" contains "σ")
        assert!(!hit(&i, "ς")); // 原本 Swift はミス (ς には畳まれない)
        assert!(hit(&i, "Σ")); // 検索語側も同じ無条件写像を通る
        assert!(hit(&i, "ασ"));

        // "ΣΣ" → "σσ" (str::to_lowercase だと "σς")
        let i = index(&["ΣΣ"]);
        assert!(hit(&i, "σσ"));
        assert!(!hit(&i, "σς"));

        // 語頭・単独の Σ は元々どちらの写像でも σ (現データ「Σ Desire」相当)
        assert!(hit(&index(&["Σ Desire"]), "σ desire"));

        // 小文字 ς はどちらの写像でも不変 (ς で入力されたフィールドはそのまま当たる)
        assert!(hit(&index(&["ς"]), "ς"));
        assert!(!hit(&index(&["ς"]), "σ"));
    }

    /// 小文字化が 1 文字 → 複数文字になる写像も Swift の無条件写像と同じ展開になること。
    #[test]
    fn expands_one_to_many_lowercase_mappings() {
        // U+0130 (İ) → "i" + U+0307 (結合ドット)。char 単位でも 1:N 展開は維持される
        assert_eq!(prepare_needle("İ"), "i\u{307}".as_bytes());
        assert!(hit(&index(&["İstanbul"]), "i"));
        // U+1E9E (ẞ) → ß (1:1 だが BMP 外周りの回帰確認として)
        assert_eq!(prepare_needle("ẞ"), "ß".as_bytes());
    }

    // --- カタログ (1 呼び出しで index 列) ---

    fn catalog() -> Vec<TextSearchIndex> {
        vec![
            index(&["夢色ハーモニー"]),
            index(&["READY!!", "れでぃ"]),
            index(&[""]), // メタの無い項目
            index(&["Ready Go!"]),
        ]
    }

    /// 当たった項目の index が入力順 (昇順) で返る。呼び出し側はこの並びで自国の配列を引く。
    #[test]
    fn matching_indices_returns_hits_in_input_order() {
        assert_eq!(matching_indices(&catalog(), "ready"), vec![1, 3]);
        assert_eq!(matching_indices(&catalog(), "夢"), vec![0]);
        assert_eq!(matching_indices(&catalog(), "星"), Vec::<u32>::new());
    }

    /// 空の検索語は全項目 = 絞り込みを掛けていない状態 (メタの無い項目も落とさない)。
    #[test]
    fn matching_indices_with_empty_needle_returns_all() {
        assert_eq!(matching_indices(&catalog(), ""), vec![0, 1, 2, 3]);
    }

    /// 検索語の小文字化はカタログ側で 1 回だけ行う (項目ごとに前処理し直さない)。
    /// 大文字で渡しても索引 (小文字化済み) に当たることで確かめる。
    #[test]
    fn matching_indices_folds_needle_case() {
        assert_eq!(matching_indices(&catalog(), "READY GO"), vec![3]);
    }

    #[test]
    fn matching_indices_on_empty_catalog_is_empty() {
        assert_eq!(matching_indices(&[], "夢"), Vec::<u32>::new());
        assert_eq!(matching_indices(&[], ""), Vec::<u32>::new());
    }

    // --- ひらがな↔カタカナ ---

    /// 打った表記の種類に関係なく当たる。
    ///
    /// 日本語の入力では表記まで合わせて打たない。畳まなかった頃は、読み仮名経由で
    /// 一覧には出るのに表記側に一致範囲が無く、ハイライトだけ付かなかった。
    #[test]
    fn hiragana_and_katakana_match_each_other() {
        assert!(hit(&index(&["オネガイ"]), "おね"));
        assert!(hit(&index(&["おねがい"]), "オネ"));
        assert!(hit(&index(&["ハーモニー"]), "はーもにー"));
    }

    /// 音引きと中黒は畳まない (対応するひらがなが無く、表記の弁別に効く)。
    #[test]
    fn prolonged_sound_mark_is_left_alone() {
        assert!(hit(&index(&["ハーモニー"]), "ー"));
        assert!(!hit(&index(&["ハモニー"]), "はーもにー"));
    }

    // --- ハイライトの範囲 ---

    /// 表記の種類が違っても、元の文字列の当たった位置が返る。
    #[test]
    fn match_range_points_at_the_original_text() {
        let title = "オネガイ！シンデレラ";
        let (start, end) = match_range(title, "おねがい").expect("当たるはず");
        assert_eq!(&title[start as usize..end as usize], "オネガイ");
    }

    /// 先頭以外でも、多バイト文字をまたいでも位置がずれない。
    #[test]
    fn match_range_handles_offsets_inside_the_text() {
        let title = "夢色ハーモニー";
        let (start, end) = match_range(title, "もにー").expect("当たるはず");
        assert_eq!(&title[start as usize..end as usize], "モニー");
    }

    /// 当たらない語と空の語では範囲を返さない (色を敷かない)。
    #[test]
    fn match_range_is_none_without_a_hit() {
        assert_eq!(match_range("夢色ハーモニー", "星空"), None);
        assert_eq!(match_range("夢色ハーモニー", ""), None);
    }

    /// 一覧に載せる判定と範囲の有無が食い違わない。
    ///
    /// ここがズレると、索引が拾わなかった箇所に色が付いたり、
    /// 一覧に出ているのに当たった理由が読めなくなったりする。
    #[test]
    fn the_range_agrees_with_the_list_filter() {
        for (text, needle) in [
            ("オネガイ！シンデレラ", "おね"),
            ("READY!!", "ready"),
            ("夢色ハーモニー", "ハーモ"),
            ("夢色ハーモニー", "星"),
            ("ハーモニー", "はーもにー"),
        ] {
            assert_eq!(
                hit(&index(&[text]), needle),
                match_range(text, needle).is_some(),
                "「{needle}」→「{text}」で判定と範囲が食い違う"
            );
        }
    }

    // --- 濁点の表し方 (合成済み / 分解済み) ---

    /// 分解された濁点でも、合成済みと同じに当たる。
    ///
    /// 実データに「ムケ゛ンタ゛イグロウアップ！」(NFD) が 1 曲あり、
    /// 「ムゲンダイ」(NFC) と打っても**自分の曲名で検索できなかった**。
    #[test]
    fn decomposed_dakuten_matches_the_composed_form() {
        let decomposed = "ムケ\u{3099}ンタ\u{3099}イ";
        assert!(hit(&index(&[decomposed]), "ムゲンダイ"));
        assert!(hit(&index(&["ムゲンダイ"]), decomposed));
        // 半濁点も同じ。
        assert!(hit(&index(&["ハ\u{309A}ステル"]), "パステル"));
    }

    /// 合成しても、ハイライトは元の文字列の 2 文字ぶんを覆う。
    #[test]
    fn a_composed_match_covers_both_original_characters() {
        let title = "ムケ\u{3099}ンタ\u{3099}イ";
        let (start, end) = match_range(title, "ムゲンダイ").expect("当たるはず");
        assert_eq!(&title[start as usize..end as usize], title);
    }

    /// 濁点が付かないかなには合成しない (あ + ゛ は「あ」のままにしない)。
    #[test]
    fn only_kana_that_take_a_dakuten_are_composed() {
        assert!(!hit(&index(&["あ\u{3099}"]), "い"));
        // か行に半濁点は無い。
        assert!(!hit(&index(&["カ\u{309A}"]), "が"));
    }
}
