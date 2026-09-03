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
#[derive(Debug, Default, Clone)]
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

    /// 畳み済みのフィールド列。
    ///
    /// Web 出面がブラウザに配る検索索引の中身がこれ。**索引そのものの写しを配る**ので、
    /// 「どのフィールドが検索対象か」「どう畳むか」の判断が Web 側に染み出さない
    /// (`title` と `title_kana` を web が選び直すと、規則が二重になる)。
    pub fn folded_fields(&self) -> &[Vec<u8>] {
        &self.fields
    }

    /// [`Self::folded_fields`] を `&str` として見たもの。
    ///
    /// 畳み込みは `String` 上で行って `into_bytes()` しただけなので、各要素は常に
    /// 妥当な UTF-8。万一そうでなくなったら、その要素だけ落とす (JSON に載せられない)。
    pub fn folded_str_fields(&self) -> Vec<&str> {
        self.fields.iter().filter_map(|f| std::str::from_utf8(f).ok()).collect()
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

/// 一覧クエリ側 (索引を組まずに 1 行ずつ判定する経路) 用の、畳み済み検索語。
///
/// ## なぜこれが要るのか
///
/// 検索の当たり方は長らく **2 つの規則に割れていた**。
/// 一覧を手元で絞る経路 (`TextSearchIndex` = iOS の `TextSearchCatalog`) は
/// 大文字小文字と ひらがな↔カタカナを畳むのに、コアのクエリ関数側は SQL の
/// `LIKE` を忠実に写した「ASCII の大文字小文字だけ」の判定だった。
/// 同じ検索欄に同じ語を打っても、**iOS では当たって Android では当たらない**
/// (Android の一覧はクエリ関数を通るため)。移植の忠実さのつもりで残していた差が、
/// そのまま使う人にとっての不具合になっていた。
///
/// 判定はこちらに寄せる。`LIKE` が当てるものは全部当てる (真の上位集合) ので、
/// 従来出ていた行が消えることはない。
///
/// ## 使い分け (ここを間違えると遅い)
///
/// [`matches`](Self::matches) は**行ごとに畳む**。畳み込みは 1 文字ごとに
/// `char::to_lowercase` を通すので安くない。3,154 曲を舐める曲名検索の実測で:
///
/// ```text
///   元の SQL (LIKE)                    0.29ms
///   畳まない byte 走査                  1.8ms
///   matches() で行ごとに畳む            7.4ms
///   読み込み時に畳んだ索引と突き合わせ    0.6ms
/// ```
///
/// **全行を舐める経路では [`TextSearchIndex`] を使うこと** (スナップショットが
/// 読み込み時に組んである。`Snapshot::song_search` など)。`matches` は
/// 「条件が指定されたときだけ見る列」(作詞作曲・CD シリーズ等) 向け。
/// 検索語の方は `new` で 1 度だけ畳んで使い回す。
pub struct FoldedNeedle {
    folded: String,
}

impl FoldedNeedle {
    pub fn new(needle: &str) -> Self {
        Self { folded: fold_lowercase(needle) }
    }

    /// 畳み済みのバイト列。読み込み時に畳んである索引
    /// ([`TextSearchIndex`]) と突き合わせるときに使う。
    pub fn as_bytes(&self) -> &[u8] {
        self.folded.as_bytes()
    }

    /// 空の検索語 (= 絞り込まない)。
    pub fn is_empty(&self) -> bool {
        self.folded.is_empty()
    }

    /// `haystack` が検索語を含むか。空の検索語は `LIKE '%%'` と同じく true。
    pub fn matches(&self, haystack: &str) -> bool {
        if self.folded.is_empty() {
            return true;
        }
        fold_lowercase(haystack).contains(&self.folded)
    }

    /// NULL 許容の列。SQL の `col LIKE ?` は NULL に対して NULL (= 偽) なので、
    /// **空の検索語でも None は false**。`matches` と非対称なのは元の SQL がそうだから。
    pub fn matches_opt(&self, value: Option<&str>) -> bool {
        value.is_some_and(|v| self.matches(v))
    }
}

// ---------------------------------------------------------------------------
// 畳み込みの実体
// ---------------------------------------------------------------------------
//
// 実体は `imas-text-fold` crate にある。切り出したのは、**ブラウザ (wasm) でも
// 同じ規則を使う**ため。Web の検索欄が独自に畳むと、iOS / Android / Web で
// 当たり方が 3 通りになる (かつて iOS と Android で 2 通りに割れていたのと同じ壊れ方)。
//
// `imas-core` 全体を wasm に持っていく案は取らない。rusqlite (wasm では
// sqlite-wasm-rs) と uniffi の scaffolding が丸ごと乗り、`fold` 1 関数のために
// SQLite の実体を配ることになる (実測: sqlite-wasm-rs は Xcode 同梱の clang に
// WebAssembly バックエンドが無いためビルドすら通らない)。

/// 畳み済みバイト列の部分列探索。
///
/// UTF-8 は先頭バイトと継続バイトの範囲が重ならないので、バイト列としての一致が
/// そのまま文字列としての一致になる (途中のバイトから始まる偽の一致が起きない)。
///
/// `imas-text-fold` の実体をそのまま再公開している。呼び出し側で
/// `String::contains` を使うと畳み込みを外れるので、必ずこちらを通すこと。
pub use imas_text_fold::contains;

/// 索引と検索語に共通の畳み込み。規則の実体は `imas_text_fold::fold`。
///
/// 名前を変えずに残してあるのは、この関数を参照している doc コメントと
/// 呼び出し側 (`TextSearchIndex::new` / `prepare_needle` / `FoldedNeedle`) が
/// 「畳むのはここ」という 1 点を指し続けられるようにするため。
#[inline]
fn fold_lowercase(text: &str) -> String {
    imas_text_fold::fold(text)
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
    let (bytes, starts, ends) = imas_text_fold::fold_with_offsets(haystack);
    let at = imas_text_fold::find(&bytes, &needle)?;
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
