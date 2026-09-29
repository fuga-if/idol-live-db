//! 音楽カードゲーム「KAMISABI」の収録と、所持コンプの分母。
//!
//! # なぜ分母の規則をここに置くか
//!
//! **KAMISABI はブランドごとの別商品**で、アルバムセットは
//! ミリオン 50 曲 / SideM 50 曲 / シャニマス 50 曲。3 つ合わせて 150 曲だが、
//! それは「1 つの商品に 150 曲入っている」という意味ではない。
//! SideM しか買っていない人に「150 曲中 7 曲所持」と出すのは実態と合わない。
//!
//! 分母は「その商品の収録曲数」。この規則を各 OS の画面に書くと必ず食い違う
//! (実際、最初の実装では iOS が画面の絞り込み結果を、Android が 3 商品の合算を、
//! Web が DOM の行数を分母にしていて、同じ機能で 3 通りの数が出ていた)。
//!
//! # 数えるのは「曲」であって「枚」ではない
//!
//! シングルパックは同じ 50 曲それぞれにノーマル版とレア版があり、1 商品 100 種になる。
//! 収録は曲の単位でしか決まらないので、数え方も曲で言い切る。

use crate::domain::snapshot::Snapshot;

/// 所持コンプの状態。`total` が分母 (= その商品の収録曲数)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct KamisabiCompletion {
    pub owned: u32,
    pub total: u32,
}

/// KAMISABI 収録曲の添字列。`brand_id` を渡すとその商品だけ、`None` なら全商品。
///
/// 見るのは曲の**主ブランド** (`brand_id`) だけ。合同曲の参加ブランド
/// (`joint_brand_ids`) では広げない — カードはどれか 1 つの商品に入っているもので、
/// 参加していることと収録されていることは別だから。
///
/// 並びは添字の昇順 (呼び出し側が自分の一覧の並べ替えに渡す前提)。
pub fn song_indexes(snap: &Snapshot, brand_id: Option<&str>) -> Vec<u32> {
    snap.songs
        .iter()
        .enumerate()
        .filter(|(_, s)| s.has_kamisabi_card)
        .filter(|(_, s)| brand_id.is_none_or(|b| s.brand_id.as_deref() == Some(b)))
        .map(|(i, _)| i as u32)
        .collect()
}

/// 収録曲のある商品 (ブランド id)。ブランドの表示順 (`brands.sort_order`) で返す。
pub fn brand_ids(snap: &Snapshot) -> Vec<String> {
    snap.brand_order
        .iter()
        .map(|&b| snap.brands[b as usize].id.as_str())
        .filter(|b| !song_indexes(snap, Some(b)).is_empty())
        .map(str::to_string)
        .collect()
}

/// 所持コンプ。`owned_song_ids` は端末の所持マーク (user_marks の `owned`) を
/// プラットフォーム側で解決した song_id 集合。
///
/// **分母に数えるのは収録曲だけ。** 所持マークが付いていても収録曲でない id は
/// 分子にも数えない (古いマークが残っていてもコンプ率が 100% を超えない)。
pub fn completion(
    snap: &Snapshot,
    brand_id: Option<&str>,
    owned_song_ids: &[String],
) -> KamisabiCompletion {
    let owned: std::collections::HashSet<&str> =
        owned_song_ids.iter().map(String::as_str).collect();
    let indexes = song_indexes(snap, brand_id);
    let have = indexes
        .iter()
        .filter(|&&i| owned.contains(snap.songs[i as usize].id.as_str()))
        .count();
    KamisabiCompletion { owned: have as u32, total: indexes.len() as u32 }
}

/// 収録の札。曲一覧の行にも曲詳細にも、どの OS でもこの語を出す。
pub const CARD_LABEL: &str = "KAMISABI 収録";

/// 「7 / 50 曲所持」。コンプ率の言い回しも 1 箇所で決める。
pub fn completion_label(c: &KamisabiCompletion) -> String {
    format!("{} / {} 曲所持", c.owned, c.total)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::{Brand, Song};

    fn song(id: &str, brand: &str, flagged: bool) -> Song {
        Song {
            id: id.into(),
            title: id.into(),
            brand_id: Some(brand.into()),
            has_kamisabi_card: flagged,
            ..Song::default()
        }
    }

    fn brand(id: &str, order: i64) -> Brand {
        Brand {
            id: id.into(),
            name: id.into(),
            short_name: id.into(),
            color: None,
            sort_order: order,
            icon_url: None,
        }
    }

    fn snap() -> Snapshot {
        Snapshot {
            // 配列の並びは表示順 (sort_order) とわざと違えてある。
            brands: vec![brand("sidem", 2), brand("ml", 1), brand("cg", 3)],
            brand_order: vec![1, 0, 2],
            songs: vec![
                song("ml1", "ml", true),
                song("ml2", "ml", true),
                song("sidem1", "sidem", true),
                song("ml3", "ml", false),
                song("cg1", "cg", false),
            ],
            ..Snapshot::default()
        }
    }

    #[test]
    fn owned_counts_only_songs_in_that_product() {
        let s = snap();
        let owned = vec!["ml1".to_string(), "sidem1".to_string(), "ml3".to_string()];
        // ml の商品: 収録 2 曲のうち ml1 だけ所持。sidem1 も ml3 も数えない
        // (ml3 は所持マークがあっても収録曲ではない)。
        assert_eq!(completion(&s, Some("ml"), &owned), KamisabiCompletion { owned: 1, total: 2 });
        assert_eq!(completion(&s, None, &owned), KamisabiCompletion { owned: 2, total: 3 });
    }

    #[test]
    fn brand_ids_lists_only_products_that_exist() {
        // cg は収録曲が無いので商品として出さない。並びはブランドの表示順 (sort_order)。
        assert_eq!(brand_ids(&snap()), vec!["ml".to_string(), "sidem".to_string()]);
    }

    /// 実データの見張り。`db/master.sql` の再ダンプや `fill_apple_music_ids` 系の
    /// 誤爆で札が落ちても、3,000 行動く差分を目視では拾えない。
    ///
    /// **新しいセットが出たらここを更新すること** (それが唯一の更新理由)。
    #[test]
    fn bundle_has_every_kamisabi_card() {
        let snap = crate::test_support::bundle_snapshot();

        // 商品は 3 つ。アルバムセットはそれぞれ 50 曲。
        let products = brand_ids(snap);
        assert_eq!(products, vec!["ml".to_string(), "sidem".to_string(), "sc".to_string()]);
        for p in &products {
            assert_eq!(
                completion(snap, Some(p), &[]).total,
                50,
                "{p} の KAMISABI 収録曲が 50 曲でない"
            );
        }
        assert_eq!(completion(snap, None, &[]).total, 150);
    }

    #[test]
    fn completion_label_says_songs_not_cards() {
        // 1 曲にノーマルとレアの 2 枚があるので、数えているのは枚ではなく曲。
        let c = KamisabiCompletion { owned: 7, total: 50 };
        assert_eq!(completion_label(&c), "7 / 50 曲所持");
    }
}
