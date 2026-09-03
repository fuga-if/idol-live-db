//! 歌詞行を「語のまとまり」に切る FFI 口。コールのアンカー選択に使う。

use crate::domain::lyric_chunks::{chunk_at as at, chunks as split, LyricChunk};

/// 行を語のまとまりに切る。位置は Unicode スカラー単位。
///
/// 編集モードで「どこで切れるか」を下敷きに出したいときに使う。
/// 1 タップの選択だけなら [`lyric_chunk_at`] で足りる。
#[uniffi::export]
pub fn lyric_chunks(line: String) -> Vec<LyricChunk> {
    split(&line)
}

/// 触れた位置 (スカラー添字) を含むまとまりを返す。
///
/// 指で 1 文字を狙わせないための入口。行末より後ろを触っても最後のまとまりを返すので、
/// 行の右端の余白をタップしても空振りしない。
#[uniffi::export]
pub fn lyric_chunk_at(line: String, scalar: u32) -> Option<LyricChunk> {
    at(&line, scalar)
}
