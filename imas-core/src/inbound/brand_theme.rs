//! ブランド ID からテーマを導く FFI 面。ロジックは [`crate::domain::brand_theme`]。
//!
//! ブランドの色はマスタの `brands.color` から引くので、スナップショットのメソッドにしてある。
//! アプリはブランド ID をそのまま渡す (ID → hex の表を持たない)。一覧は
//! [`SnapshotStore::theme_derive_batch_for_brand_ids`] で 1 回に畳む。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::brand_theme::{self as domain, ThemeBrandSeedRequest};
use crate::domain::color_engine::ImasThemeColors;

#[uniffi::export]
impl SnapshotStore {
    /// アイドル色 → ブランド ID の色 (`brands.color`) → ニュートラル の順でテーマを導く。
    /// `brand_id` は ID (`"876"` / `"cg"`)。hex を渡す既存の [`crate::inbound::color_engine::theme_derive`]
    /// に ID を渡すと、`"876"` が #887766 に、`"cg"` がグレーになる。
    pub fn theme_derive_for_brand_id(
        &self,
        seed: Option<String>,
        brand_id: Option<String>,
        dark: bool,
    ) -> Result<ImasThemeColors, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::derive_for_brand_id(&snap, seed.as_deref(), brand_id.as_deref(), dark))
    }

    /// 一覧 1 画面ぶん (入力と同じ順)。行ごとに呼ばないための入口。
    pub fn theme_derive_batch_for_brand_ids(
        &self,
        requests: Vec<ThemeBrandSeedRequest>,
        dark: bool,
    ) -> Result<Vec<ImasThemeColors>, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::derive_batch_for_brand_ids(&snap, &requests, dark))
    }
}
