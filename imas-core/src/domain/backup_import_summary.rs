//! バックアップ復元 (引き継ぎコード / ファイル) の結果をユーザー向け文面にする。
//!
//! 復元は「担当・お気に入り・マイタグ・投票履歴」という**クラウドに無い端末ローカル唯一
//! データ**を戻す操作で、何がどれだけ入ったかを黙っていると成功したのか分からない。
//! 一方で 0 件の項目まで並べるとノイズになるので、**入ったものだけ**を足していく。
//!
//! 行の並びは固定 (基本行 → マイタグ → スキップ → 端末ID)。同じ入力からは常に
//! 同じ文面が出る決定的な純関数なので、アラート表示のスナップショット的な検証が
//! しやすい。

/// 復元結果の文面を組み立てる。
///
/// - `added_marks`: 追加された担当/お気に入り/メモ/参加済みの件数。
/// - `added_votes`: 追加された投票履歴の件数。
/// - `added_personal_tags`: 追加されたマイタグの件数 (0 なら文面に出さない)。
/// - `skipped_marks`: 形式不正で取り込めなかった件数 (0 なら出さない)。
/// - `device_id_restored`: 端末 ID まで復元したか。
///
/// 件数を i64 で受けるのは Swift の `Int` / Kotlin の `Int` をロス無く受けるため
/// (実データは非負だが、境界で変換エラーを起こさないことを優先する)。
pub fn backup_import_summary(
    added_marks: i64,
    added_votes: i64,
    added_personal_tags: i64,
    skipped_marks: i64,
    device_id_restored: bool,
) -> String {
    // 担当/お気に入りと投票履歴は復元の主目的なので 0 件でも必ず出す
    // (「0 件だった」ことにも意味がある: 全部重複していた等)。
    let mut message = format!(
        "担当/お気に入り等を {added_marks} 件、投票履歴を {added_votes} 件 追加しました。"
    );
    if added_personal_tags > 0 {
        message.push_str(&format!("\nマイタグを {added_personal_tags} 件 追加しました。"));
    }
    if skipped_marks > 0 {
        message.push_str(&format!("\n({skipped_marks} 件は形式不正のためスキップされました)"));
    }
    if device_id_restored {
        message.push_str("\n端末IDも復元しました。");
    }
    message
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 全部 0 件・端末ID無し: 主目的の 1 行だけが出て、オプション行は一切付かない。
    #[test]
    fn all_zero_shows_only_base_line() {
        assert_eq!(
            backup_import_summary(0, 0, 0, 0, false),
            "担当/お気に入り等を 0 件、投票履歴を 0 件 追加しました。"
        );
    }

    /// 0 件の項目は文面に出さない (ノイズを増やさない)。
    /// iOS `MyPageRulesTests.testSummaryOmitsZeroSections` の移植。
    #[test]
    fn omits_zero_sections_with_nonzero_base() {
        assert_eq!(
            backup_import_summary(3, 2, 0, 0, false),
            "担当/お気に入り等を 3 件、投票履歴を 2 件 追加しました。"
        );
    }

    /// マイタグだけが入ったケース: マイタグ行のみ追記される。
    #[test]
    fn personal_tags_line_appears_only_when_positive() {
        assert_eq!(
            backup_import_summary(0, 0, 3, 0, false),
            "担当/お気に入り等を 0 件、投票履歴を 0 件 追加しました。\nマイタグを 3 件 追加しました。"
        );
    }

    /// スキップだけが起きたケース: 括弧書きのスキップ行のみ追記される。
    #[test]
    fn skipped_line_appears_only_when_positive() {
        assert_eq!(
            backup_import_summary(0, 0, 0, 2, false),
            "担当/お気に入り等を 0 件、投票履歴を 0 件 追加しました。\n(2 件は形式不正のためスキップされました)"
        );
    }

    /// 端末 ID だけ復元したケース: 端末 ID 行のみ追記される。
    #[test]
    fn device_id_line_appears_only_when_restored() {
        assert_eq!(
            backup_import_summary(0, 0, 0, 0, true),
            "担当/お気に入り等を 0 件、投票履歴を 0 件 追加しました。\n端末IDも復元しました。"
        );
    }

    /// 全条件が揃ったとき、行の並びが「基本 → マイタグ → スキップ → 端末ID」で
    /// 安定していること (同じ入力からは常に同じ文面)。
    #[test]
    fn full_message_keeps_stable_line_order() {
        let expected = "担当/お気に入り等を 12 件、投票履歴を 34 件 追加しました。\n\
                        マイタグを 5 件 追加しました。\n\
                        (6 件は形式不正のためスキップされました)\n\
                        端末IDも復元しました。";
        assert_eq!(backup_import_summary(12, 34, 5, 6, true), expected);
        // 決定性: 同値入力の再呼び出しで文面が揺れない。
        assert_eq!(
            backup_import_summary(12, 34, 5, 6, true),
            backup_import_summary(12, 34, 5, 6, true)
        );
    }

    /// マルチバイト (日本語) と ASCII 数字の混在文面が改行区切りで壊れないこと。
    #[test]
    fn unicode_lines_split_cleanly() {
        let message = backup_import_summary(1, 2, 3, 4, true);
        let lines: Vec<&str> = message.lines().collect();
        assert_eq!(lines.len(), 4);
        assert!(lines[0].contains("担当/お気に入り等を 1 件"));
        assert!(lines[1].starts_with("マイタグを 3 件"));
        assert!(lines[2].starts_with('('));
        assert_eq!(lines[3], "端末IDも復元しました。");
    }
}
