//! セトリ編集の差分判定 — 「実際に送る必要があるもの」だけを選ぶ。
//!
//! iOS `SetlistDiff` の一次実装。DB にも UI にも依存しない純粋ロジック。
//!
//! ## なぜ差分にするか
//!
//! 以前は 1 曲直すだけでも全曲・全出演者を送っていた。本番マスタ実測でセトリ登録済み
//! 1252 公演のうち 403 件 (32.2%) が 50 ops 超、最大 606 ops。これが
//! - 一般ユーザーの修正リクエストが op 上限で送れない
//! - admin の直接編集も上限 1000 に迫る
//! - GitHub issue が肥大してコメント分割が必要になる
//! の共通原因だった。
//!
//! ## 送らないもの
//!
//! - **値が変わっていない item**: 同じ値で update しても結果は変わらない。
//! - **既存の出演者すべて**: 出演者は `(setlistItemId, idolId)` の 2 つしか持たず、
//!   recordName がその 2 つから決まる。つまり既存出演者の update は
//!   「recordName に入っている値を同じ値で書く」だけで、変化しようがない。
//!   出演者は新規追加 (create) と削除 (delete) しか意味を持たない。
//!
//! 送らないぶん、ローカルとサーバがずれていても「全部送り直して直す」効果は失われる。
//! ずれの修復は CloudKit 同期の役目で、編集リクエストの役目ではない。
//!
//! ## FFI 境界
//!
//! エンティティ全体は渡さず、サーバに送る field だけの射影 [`SetlistItemDiffRow`] を
//! 渡して「送るべき index の列」を返す (1 ユーザー操作 = 1 呼び出し。呼び出し側が
//! 自国の配列を index で引き直す)。表示用の曲名やジャケ URL は編集対象ではないので
//! 比較に入れない。

use std::collections::{HashMap, HashSet};

/// セトリ行 1 件の射影。サーバに送る field (`song_id` / `position` / `section`) と、
/// 編集前後の突き合わせに使う `id` だけを持つ。
///
/// 編集後の行にも編集前のスナップショットにも同じ型を使う (比較対象が同じ field 集合
/// である事実を型で固定する)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SetlistItemDiffRow {
    /// 行の同一性 (編集前後の対応付けキー)。差分比較そのものには使わない。
    pub id: String,
    pub song_id: String,
    pub position: i64,
    /// アンコール等のセクション名。`None` = 本編。
    pub section: Option<String>,
}

/// 送る必要のある item の index だけ返す (新規 + 値が変わったもの)。順序は入力のまま
/// (position 順に並べた呼び出し側の意図を壊さない)。
///
/// - `items`: 編集後の全 item。
/// - `original`: 編集前のスナップショット。順不同でよい (Swift の Dictionary 由来で
///   順序が不定なため、ここで id 索引を作る)。ここに無い id は新規なので必ず送る。
///
/// 落としやすいケースとして section のクリア (非 None → None = 「本編」に戻す) も
/// 差分になる。これを取りこぼすとアンコール表記が消えないまま残る。
pub fn item_indexes_needing_sync(
    items: &[SetlistItemDiffRow],
    original: &[SetlistItemDiffRow],
) -> Vec<u32> {
    let before: HashMap<&str, &SetlistItemDiffRow> =
        original.iter().map(|row| (row.id.as_str(), row)).collect();
    items
        .iter()
        .enumerate()
        .filter(|(_, item)| match before.get(item.id.as_str()) {
            None => true, // 新規
            Some(b) => {
                item.song_id != b.song_id
                    || item.position != b.position
                    || item.section != b.section
            }
        })
        .map(|(i, _)| i as u32)
        .collect()
}

/// 送る必要のある出演者の index だけ返す (新規追加のみ)。順序は入力のまま。
///
/// recordName の生成規則は呼び出し側の所有物なので、ここでは規則適用済みの文字列列
/// (`record_names`) を受け取り、編集前に存在した集合 (`initial_record_names`) に
/// 無いものだけを選ぶ。既存の出演者は上記の理由 (update に意味がない) で 1 件も返さない。
pub fn performer_indexes_needing_sync(
    record_names: &[String],
    initial_record_names: &[String],
) -> Vec<u32> {
    let initial: HashSet<&str> = initial_record_names.iter().map(String::as_str).collect();
    record_names
        .iter()
        .enumerate()
        .filter(|(_, name)| !initial.contains(name.as_str()))
        .map(|(i, _)| i as u32)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// iOS `SetlistDiffTests` の全ケースを移植。
    /// ここが取りこぼすと「直したつもりが直っていない」になる。特に
    /// 削除・section のクリア・並べ替えは落としやすいので個別に固定する。

    fn row(id: &str, song: &str, pos: i64, section: Option<&str>) -> SetlistItemDiffRow {
        SetlistItemDiffRow {
            id: id.to_string(),
            song_id: song.to_string(),
            position: pos,
            section: section.map(str::to_string),
        }
    }

    /// index 列を id 列へ引き直す (iOS テストの `map(\.id)` 相当)。
    fn ids_at<'a>(items: &'a [SetlistItemDiffRow], indexes: &[u32]) -> Vec<&'a str> {
        indexes.iter().map(|&i| items[i as usize].id.as_str()).collect()
    }

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    // --- item: 変わっていないものは送らない ---

    /// 何も編集していなければ 0 件。ここが 0 にならないと差分化の意味がない。
    #[test]
    fn unchanged_setlist_produces_nothing() {
        let items = [row("a", "s1", 1, None), row("b", "s2", 2, None)];
        let original = [row("a", "s1", 1, None), row("b", "s2", 2, None)];
        assert!(item_indexes_needing_sync(&items, &original).is_empty());
    }

    /// 1 曲だけ差し替えたら 1 件だけ送る。
    #[test]
    fn only_changed_song_is_sent() {
        let items = [row("a", "s1", 1, None), row("b", "CHANGED", 2, None)];
        let original = [row("a", "s1", 1, None), row("b", "s2", 2, None)];
        let picked = item_indexes_needing_sync(&items, &original);
        assert_eq!(ids_at(&items, &picked), ["b"]);
    }

    /// 新規追加 (スナップショットに無い id) は必ず送る。
    #[test]
    fn new_item_is_always_sent() {
        let items = [row("a", "s1", 1, None), row("new", "s9", 2, None)];
        let original = [row("a", "s1", 1, None)];
        let picked = item_indexes_needing_sync(&items, &original);
        assert_eq!(ids_at(&items, &picked), ["new"]);
    }

    // --- item: 落としやすいケース ---

    /// section を付けた / 変えた。
    #[test]
    fn section_change_is_sent() {
        let items = [row("a", "s1", 1, Some("アンコール"))];
        let original = [row("a", "s1", 1, None)];
        let picked = item_indexes_needing_sync(&items, &original);
        assert_eq!(ids_at(&items, &picked), ["a"]);
    }

    /// section を「本編」に戻した (非 None → None)。
    /// これを取りこぼすとアンコール表記が消えないまま残る。
    #[test]
    fn section_clear_is_sent() {
        let items = [row("a", "s1", 1, None)];
        let original = [row("a", "s1", 1, Some("アンコール"))];
        let picked = item_indexes_needing_sync(&items, &original);
        assert_eq!(ids_at(&items, &picked), ["a"]);
    }

    /// 並べ替えは position が動いた曲すべてを送る (動いていない曲は送らない)。
    #[test]
    fn reorder_sends_only_moved_items() {
        // a(1) b(2) c(3) → b と c を入れ替え
        let items = [row("a", "s1", 1, None), row("c", "s3", 2, None), row("b", "s2", 3, None)];
        let original = [row("a", "s1", 1, None), row("b", "s2", 2, None), row("c", "s3", 3, None)];
        let picked = item_indexes_needing_sync(&items, &original);
        let mut got = ids_at(&items, &picked);
        got.sort();
        assert_eq!(got, ["b", "c"]);
    }

    /// 曲は同じでも位置が変わっていれば送る。
    #[test]
    fn position_only_change_is_sent() {
        let items = [row("a", "s1", 5, None)];
        let original = [row("a", "s1", 1, None)];
        let picked = item_indexes_needing_sync(&items, &original);
        assert_eq!(ids_at(&items, &picked), ["a"]);
    }

    /// 出力順は入力のまま (position 順に並べた呼び出し側の意図を壊さない)。
    #[test]
    fn keeps_input_order() {
        let items: Vec<_> = (1..=5)
            .map(|i| row(&format!("i{i}"), &format!("changed{i}"), i, None))
            .collect();
        let original: Vec<_> = (1..=5)
            .map(|i| row(&format!("i{i}"), &format!("s{i}"), i, None))
            .collect();
        let picked = item_indexes_needing_sync(&items, &original);
        assert_eq!(ids_at(&items, &picked), ["i1", "i2", "i3", "i4", "i5"]);
    }

    /// スナップショットの並び順は結果に影響しない
    /// (iOS 側は Dictionary 由来で順序不定のまま渡してくるため、ここで保証する)。
    #[test]
    fn original_order_does_not_matter() {
        let items = [row("a", "s1", 1, None), row("b", "CHANGED", 2, None)];
        let original_reversed = [row("b", "s2", 2, None), row("a", "s1", 1, None)];
        let picked = item_indexes_needing_sync(&items, &original_reversed);
        assert_eq!(ids_at(&items, &picked), ["b"]);
    }

    // --- 出演者 ---

    /// 既存の出演者は 1 件も送らない。
    ///
    /// 出演者は (setlistItemId, idolId) しか持たず recordName がその 2 つから
    /// 決まるので、update しても変化しようがない。ここが差分化でいちばん効く。
    #[test]
    fn existing_performers_are_never_sent() {
        let performers = names(&["a_i1", "a_i2", "b_i1"]);
        let initial = names(&["a_i1", "a_i2", "b_i1"]);
        assert!(performer_indexes_needing_sync(&performers, &initial).is_empty());
    }

    /// 追加された出演者だけ送る。
    #[test]
    fn only_added_performers_are_sent() {
        let performers = names(&["a_i1", "a_NEW"]);
        let initial = names(&["a_i1"]);
        assert_eq!(performer_indexes_needing_sync(&performers, &initial), [1]);
    }

    /// 出演者ゼロから付け直したケース (全員新規)。
    #[test]
    fn all_performers_new_when_nothing_existed() {
        let performers = names(&["a_i1", "a_i2"]);
        assert_eq!(performer_indexes_needing_sync(&performers, &[]).len(), 2);
    }

    // --- 実データ相当での削減幅 ---

    /// 実測最大級のセトリ (86曲 × 出演者6) で 1 曲だけ直したとき、
    /// 606 ops 相当が 1 件まで落ちること。
    #[test]
    fn large_setlist_with_single_edit_collapses_to_one_op() {
        let mut items = Vec::new();
        let mut original = Vec::new();
        let mut performers = Vec::new();
        let mut initial_names = Vec::new();
        for i in 1..=86 {
            let id = format!("i{i}");
            items.push(row(&id, &format!("song{i}"), i, None));
            original.push(row(&id, &format!("song{i}"), i, None));
            for p in 1..=6 {
                performers.push(format!("{id}_idol{p}"));
                initial_names.push(format!("{id}_idol{p}"));
            }
        }
        assert_eq!(items.len() + performers.len(), 602, "前提: 600 ops 規模");

        // 42曲目だけ曲を差し替える
        items[41].song_id = "CORRECTED".to_string();

        let changed_items = item_indexes_needing_sync(&items, &original);
        let changed_performers = performer_indexes_needing_sync(&performers, &initial_names);

        assert_eq!(ids_at(&items, &changed_items), ["i42"]);
        assert!(changed_performers.is_empty());
        assert_eq!(changed_items.len() + changed_performers.len(), 1);
    }
}
