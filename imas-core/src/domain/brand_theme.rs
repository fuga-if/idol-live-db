//! ブランド ID からテーマを導く (ブランドの色はマスタの `brands.color`)。
//!
//! 画面の多くは「アイドル色 → 所属ブランドの色 → ニュートラル」でテーマを決める
//! ([`color_engine::derive`])。ところがブランドは ID (`"876"` / `"cg"`) で手元にあることが
//! 多く、その ID を hex のつもりで `derive` の `brand` に渡すと、`"876"` は 3 桁 hex として
//! `#887766` に、`"cg"` は無効な hex としてグレーになる。両 OS はそれを避けるために
//! ブランド ID → hex の表 (`BrandPalette`) を写経していたが、ID のまま渡している箇所も残っていた。
//!
//! 色の正本はマスタ (`brands.color`) にあるので、ID から色を引く段もコアに置く。
//! アプリは ID を渡すだけにして、表を持たない。

use crate::domain::color_engine::{self, ImasThemeColors};
use crate::domain::snapshot::Snapshot;

/// 一覧の 1 行ぶんの入力 (アイドル色とブランド ID の組)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ThemeBrandSeedRequest {
    /// アイドル等のイメージカラー hex。無効・未設定ならブランドの色へ落ちる。
    pub seed: Option<String>,
    /// ブランド ID (`"876"` / `"cg"` 等)。hex ではない。
    pub brand_id: Option<String>,
}

/// ブランドの色 (`brands.color`)。未知の ID・色の無いブランドは `None`。
pub fn brand_color_hex<'a>(snap: &'a Snapshot, brand_id: Option<&str>) -> Option<&'a str> {
    snap.brand(brand_id?)?.color.as_deref()
}

/// アイドル色 → ブランド ID の色 → ニュートラル の順でテーマを導く。
pub fn derive_for_brand_id(
    snap: &Snapshot,
    seed: Option<&str>,
    brand_id: Option<&str>,
    dark: bool,
) -> ImasThemeColors {
    color_engine::derive(seed, brand_color_hex(snap, brand_id), dark)
}

/// 一覧 1 画面ぶんを 1 回で (入力と同じ順)。
pub fn derive_batch_for_brand_ids(
    snap: &Snapshot,
    requests: &[ThemeBrandSeedRequest],
    dark: bool,
) -> Vec<ImasThemeColors> {
    requests
        .iter()
        .map(|r| derive_for_brand_id(snap, r.seed.as_deref(), r.brand_id.as_deref(), dark))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::bundle_snapshot;
    use crate::domain::color_engine::{derive, theme_hex};

    /// 両 OS の BrandPalette に写経されていた値と、マスタの色が同じであること。
    /// ここが崩れたら、BrandPalette を消したときに色が変わる。
    #[test]
    fn brand_colors_come_from_the_master() {
        let color = |id: &str| brand_color_hex(bundle_snapshot(), Some(id)).map(str::to_ascii_lowercase);
        assert_eq!(color("876").as_deref(), Some("#656a75"));
        assert_eq!(color("961").as_deref(), Some("#520000"));
        assert_eq!(color("cg").as_deref(), Some("#2681c8"));
        assert_eq!(color("ml").as_deref(), Some("#ffc30b"));
        assert_eq!(color("765as").as_deref(), Some("#fe0000"));
        assert_eq!(color("sidem").as_deref(), Some("#0fbe94"));
        assert_eq!(color("sc").as_deref(), Some("#6bb6b9"));
        assert_eq!(color("gakuen").as_deref(), Some("#f39800"));
        assert_eq!(brand_color_hex(bundle_snapshot(), Some("存在しない")), None);
        assert_eq!(brand_color_hex(bundle_snapshot(), None), None);
    }

    /// ID を hex として渡していた経路 (`derive(None, Some("876"))`) と違う色になること。
    /// `"876"` は 3 桁 hex の #887766 に、`"cg"` は無効でグレーになっていた。
    #[test]
    fn brand_id_is_not_read_as_a_hex() {
        for id in ["876", "961", "cg", "ml"] {
            let by_id = derive_for_brand_id(bundle_snapshot(), None, Some(id), false);
            let hex = brand_color_hex(bundle_snapshot(), Some(id)).unwrap();
            assert_eq!(by_id, derive(None, Some(hex), false), "{id}");
            assert_ne!(by_id, derive(None, Some(id), false), "{id} を hex として読んでいる");
        }
        assert!(derive(None, Some("cg"), false).is_neutral, "旧経路の cg はグレー");
        assert!(!derive_for_brand_id(bundle_snapshot(), None, Some("cg"), false).is_neutral);
    }

    /// 導いた accent の値そのものを固定する (876 / 961 / cg / ml)。
    #[test]
    fn accents_for_the_brands_that_were_broken() {
        let accent = |id: &str, dark: bool| {
            theme_hex(derive_for_brand_id(bundle_snapshot(), None, Some(id), dark).accent)
        };
        let light: Vec<String> = ["876", "961", "cg", "ml"].iter().map(|id| accent(id, false)).collect();
        let dark: Vec<String> = ["876", "961", "cg", "ml"].iter().map(|id| accent(id, true)).collect();
        assert_eq!(light, ["#656a75", "#930606", "#2681c8", "#f5be15"]);
        assert_eq!(dark, ["#878c97", "#f22c2c", "#4298db", "#f2c12c"]);
    }

    /// アイドル色があればブランドより優先。未知のブランドはニュートラルへ落ちる。
    #[test]
    fn seed_wins_and_unknown_brand_falls_back_to_neutral() {
        let s = bundle_snapshot();
        assert_eq!(
            derive_for_brand_id(s, Some("#E22B30"), Some("cg"), true),
            derive(Some("#E22B30"), None, true)
        );
        assert_eq!(derive_for_brand_id(s, None, Some("存在しない"), false), derive(None, None, false));
        let batch = derive_batch_for_brand_ids(
            s,
            &[
                ThemeBrandSeedRequest { seed: None, brand_id: Some("ml".into()) },
                ThemeBrandSeedRequest { seed: Some("#E22B30".into()), brand_id: None },
            ],
            false,
        );
        assert_eq!(batch[0], derive_for_brand_id(s, None, Some("ml"), false));
        assert_eq!(batch[1], derive(Some("#E22B30"), None, false));
    }
}
