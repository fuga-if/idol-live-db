//! 再生中バーの FFI 面。判断は domain::now_playing。
//!
//! `song_id` を 1 つ渡して 1 枚受け取る。曲と原唱者はコアが snapshot から引くので、
//! OS 側が 2 回引いて射影に詰め替える必要は無い。

use crate::domain::now_playing::{NowPlayingBar, NowPlayingKind};
use crate::domain::performer_label::PerformerNaming;
use crate::inbound::snapshot_store::{SnapshotError, SnapshotStore};

#[uniffi::export]
impl SnapshotStore {
    /// 鳴っている曲を再生中バー 1 枚にする。鳴らす曲を知らなければ `None`。
    pub fn now_playing_bar(
        &self,
        song_id: String,
        kind: NowPlayingKind,
        is_playing: bool,
    ) -> Result<Option<NowPlayingBar>, SnapshotError> {
        let snap = self.current()?;
        Ok(crate::domain::now_playing::now_playing_bar(
            &snap, &song_id, kind, is_playing,
        ))
    }
}

/// 曲一覧など、バー以外で名義だけ要るときの口。
///
/// 規則を画面ごとに書き直させないために出している
/// (iOS の `SongRowView` とコアで食い違っていた)。
#[uniffi::export]
pub fn performer_label(naming: PerformerNaming) -> Option<String> {
    crate::domain::performer_label::performer_label(&naming)
}
