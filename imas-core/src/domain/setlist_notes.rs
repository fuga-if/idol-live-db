//! セトリ行の注記 (`setlist_items.notes`) の表示形。
//!
//! 入力は手入力で綴りが揺れる: `M@STER VERSION` / `（M＠STER VERSION）` / `（M@STER VERSION）` /
//! `M＠STER VERSION` が同じ意味で混在していた (2026-09-06 に db/master.sql 側は 651 行を素の形に
//! 揃えた)。投稿で再発しても見た目が割れないよう、**セトリを取り出すところ
//! (`event_detail_queries::setlist`) で 1 つの形へ畳む**。iOS / Android / Web はそこを通るので、
//! 規則はここ 1 箇所。
//!
//! やること (これ以上は踏み込まない — 「Short ver.」と「SHORT Ver.」の大小の統一は
//! どちらが正か決められないので触らない):
//! 1. 前後の空白を落とす。
//! 2. 全体を 1 組の括弧 (全角 `（）` / 半角 `()`) で括ってあれば外す (注記は曲名の脇に
//!    別の色で置くので、括弧は要らない)。
//! 3. 全角 `＠` を `@` に (アイマス表記の `M@STER` は半角が正)。全角→半角を広く畳む
//!    `show_naming::fold_width` は照合用の畳み込みで、表示する文字を決める規則ではないので使わない。

/// 表示用の注記。空 (または空白と括弧だけ) なら None。
pub fn display_notes(raw: Option<&str>) -> Option<String> {
    let s = raw?.trim();
    // 内側にも同じ括弧が残る「(A)(B)」のような形は外さない (対の括弧でない)。
    let unwrapped = [('（', '）'), ('(', ')')].into_iter().find_map(|(open, close)| {
        s.strip_prefix(open)?
            .strip_suffix(close)
            .filter(|inner| !inner.contains(open) && !inner.contains(close))
    });
    let folded = unwrapped.map_or(s, str::trim).replace('＠', "@");
    (!folded.is_empty()).then_some(folded)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn notes(raw: &str) -> Option<String> {
        display_notes(Some(raw))
    }

    #[test]
    fn variants_of_master_version_fold_to_one() {
        for raw in ["M@STER VERSION", "（M＠STER VERSION）", "（M@STER VERSION）", "M＠STER VERSION", " (M@STER VERSION) "] {
            assert_eq!(notes(raw).as_deref(), Some("M@STER VERSION"), "{raw}");
        }
    }

    #[test]
    fn only_a_single_wrapping_pair_is_removed() {
        assert_eq!(notes("（GAME Ver・メドレー）").as_deref(), Some("GAME Ver・メドレー"));
        // 対でない括弧はそのまま。
        assert_eq!(notes("(A)(B)").as_deref(), Some("(A)(B)"));
        assert_eq!(notes("Medley ver[1番のみ]・SPECIALメドレー").as_deref(), Some("Medley ver[1番のみ]・SPECIALメドレー"));
    }

    #[test]
    fn case_is_left_alone_and_blank_is_none() {
        assert_eq!(notes("Short ver.").as_deref(), Some("Short ver."));
        assert_eq!(notes("SHORT Ver.").as_deref(), Some("SHORT Ver."));
        assert_eq!(notes("  "), None);
        assert_eq!(notes("（）"), None);
        assert_eq!(display_notes(None), None);
    }
}
