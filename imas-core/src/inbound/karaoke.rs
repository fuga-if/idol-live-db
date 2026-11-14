//! カラオケモードの時計と「次に自分が歌うまで」の FFI 口。規則は domain::karaoke。

use crate::domain::karaoke as d;
pub use crate::domain::karaoke::{
    KaraokeAnchor, KaraokeClock, KaraokeHeard, KaraokeHeardChange, KaraokeHeardOutcome, KaraokeLaneSpan,
    KaraokeTapOutcome, KaraokeTurn,
};

/// 今の曲の位置 (ms、手のずらし込み)。`now_ms` は端末の単調時計。
#[uniffi::export]
pub fn karaoke_position(clock: KaraokeClock, now_ms: i64) -> i64 {
    d::position(&clock, now_ms)
}

/// 今の位置を `song_ms` として合わせ直す (止めて再開したとき)。速さとずらしは残す。
#[uniffi::export]
pub fn karaoke_rebase(clock: KaraokeClock, song_ms: i64, now_ms: i64) -> KaraokeClock {
    d::rebase(&clock, song_ms, now_ms)
}

/// 手のずらしを足す (左右スワイプ、±5 秒で頭打ち)。
#[uniffi::export]
pub fn karaoke_nudge(clock: KaraokeClock, delta_ms: i64) -> KaraokeClock {
    d::nudge(&clock, delta_ms)
}

/// 「この行が今始まった」とタップしたときの時計 (2 点目からは速さも直す)。
#[uniffi::export]
pub fn karaoke_tap(previous: Option<KaraokeClock>, previous_anchor: Option<KaraokeAnchor>,
                   line_start_ms: i64, now_ms: i64) -> KaraokeTapOutcome {
    d::tap(previous, previous_anchor, line_start_ms, now_ms)
}

/// 耳で聞いた曲の位置で時計を直す (小さな差は半分寄せ、大きな差は 2 回続いたら採る)。
#[uniffi::export]
pub fn karaoke_heard(clock: Option<KaraokeClock>, pending: Option<KaraokeHeard>,
                     heard_song_ms: i64, now_ms: i64) -> KaraokeHeardOutcome {
    d::heard(clock, pending, heard_song_ms, now_ms)
}

/// 行を歌う人に自分のパートが入っているか。
#[uniffi::export]
pub fn karaoke_is_mine(singers: Vec<String>, mine: Vec<String>) -> bool {
    d::is_mine(&singers, &mine)
}

/// 次に自分が歌い出す行と残り時間 (残り 8 秒から)。
#[uniffi::export]
pub fn karaoke_next_turn(starts: Vec<Option<i64>>, singers: Vec<Vec<String>>, mine: Vec<String>,
                         position_ms: i64) -> Option<KaraokeTurn> {
    d::next_turn(&starts, &singers, &mine, position_ms)
}

/// この先 `window_ms` に誰が歌うかの帯。
#[uniffi::export]
pub fn karaoke_lane(starts: Vec<Option<i64>>, singers: Vec<Vec<String>>, mine: Vec<String>,
                    position_ms: i64, window_ms: i64) -> Vec<KaraokeLaneSpan> {
    d::lane(&starts, &singers, &mine, position_ms, window_ms)
}

/// 耳で当たった曲が、開いている曲と同じか (id・ISRC・カラオケ版の札を外した曲名)。
#[uniffi::export]
pub fn karaoke_heard_same_song(song_title: String, song_apple_music_id: Option<String>, song_isrc: Option<String>,
                               heard_title: Option<String>, heard_apple_music_id: Option<String>,
                               heard_isrc: Option<String>) -> bool {
    d::heard_same_song(&song_title, song_apple_music_id.as_deref(), song_isrc.as_deref(),
                       heard_title.as_deref(), heard_apple_music_id.as_deref(), heard_isrc.as_deref())
}
