//! KAMISABI の収録と所持コンプ (FFI 面・impl 分割)。domain::kamisabi_cards への委譲だけ。
//!
//! 所持マーク (user_marks の `owned`) はスナップショットに無いので、
//! 解決済みの song_id 集合をプラットフォーム側が渡す (回収系と同じ流儀)。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::kamisabi_cards::{self as cards, KamisabiCompletion};

#[uniffi::export]
impl SnapshotStore {
    /// 所持コンプ。**分母はその商品の収録曲数**で、`brand_id` を省くと全商品の合算。
    ///
    /// 合算を出してよいのは、**画面が 3 商品ぶんを一度に並べているとき**だけ
    /// (曲一覧をブランド無指定で KAMISABI に絞った場合)。曲詳細のように 1 商品の話を
    /// しているところで合算を出すと、SideM しか買っていない人に「150 曲中 7 曲」と
    /// 見せることになる。
    pub fn kamisabi_completion(
        &self,
        brand_id: Option<String>,
        owned_song_ids: Vec<String>,
    ) -> Result<KamisabiCompletion, SnapshotError> {
        let snap = self.current()?;
        Ok(cards::completion(&snap, brand_id.as_deref(), &owned_song_ids))
    }
}

/// 収録の札 (`KAMISABI 収録`)。どの OS も同じ語を出すためにコアから配る。
#[uniffi::export]
pub fn kamisabi_card_label() -> String {
    cards::CARD_LABEL.to_string()
}

/// 「7 / 50 曲所持」。言い回しもコアが決める。
#[uniffi::export]
pub fn kamisabi_completion_label(completion: KamisabiCompletion) -> String {
    cards::completion_label(&completion)
}
