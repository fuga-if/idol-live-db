//! 衣装クエリ (FFI 面)。`domain::costume_queries` への委譲だけ。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::costume_queries::{
    self as queries, CostumeRecord, CostumeShowRecord, SetlistCostumeRecord, ShowCostumeRecord,
};

#[uniffi::export]
impl SnapshotStore {
    /// 衣装の一覧 (表示順)。`brand_id` を渡すとそのブランドの衣装だけ。
    pub fn costume_records(
        &self,
        brand_id: Option<String>,
    ) -> Result<Vec<CostumeRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::costume_list(&snap, brand_id))
    }

    /// 単一の衣装。未知 id は nil。
    pub fn costume_record(&self, id: String) -> Result<Option<CostumeRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::costume_record_by_id(&snap, &id))
    }

    /// その公演で着られた衣装 (進行順)。
    pub fn show_costume_records(
        &self,
        show_id: String,
    ) -> Result<Vec<ShowCostumeRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::show_costumes(&snap, &show_id))
    }

    /// その披露 (セトリ 1 行) で着ていた衣装。
    pub fn setlist_item_costume_records(
        &self,
        setlist_item_id: String,
    ) -> Result<Vec<SetlistCostumeRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::setlist_item_costumes(&snap, &setlist_item_id))
    }

    /// その衣装が着られた公演 (新しい順)。
    pub fn costume_show_records(
        &self,
        costume_id: String,
    ) -> Result<Vec<CostumeShowRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(queries::costume_shows(&snap, &costume_id))
    }
}
