package com.fugaif.imaslivedb.player

import com.fugaif.imaslivedb.data.lyrics.LyricPartCast
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.model.Song
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * いま鳴っている曲の歌詞を、再生中バー (ミニプレイヤー) から引けるように預かる所。iOS `LyricsSession` と対。
 *
 * 歌詞タブがその曲のフル再生中に歌詞を読んだとき、ここへ 1 曲分だけ置く。
 * バーはこれを見て今の行を出し、タップで歌詞プレイヤーを開く。
 *
 * ⚠️ 歌詞の本文を持つので、置き場は**プロセスのメモリだけ** (`data/lyrics/Lyrics.kt` 冒頭の許諾条件)。
 * Room/SharedPreferences/DataStore/ファイル/通知/ウィジェットへ書き出さないこと。
 * 鳴っている曲が変わったら (止めたら) すぐ手放す。
 */
object LyricsSession {
    data class Entry(
        val song: Song,
        val seed: String?,
        val artistLine: String?,
        val artworkUrl: String?,
        val lyrics: Lyrics,
        val cast: LyricPartCast
    )

    private val _state = MutableStateFlow<Entry?>(null)
    val state: StateFlow<Entry?> = _state.asStateFlow()

    /** その曲がフル再生で鳴っているときだけ預かる (呼び出し側が loadedSongId == song.id を確かめてから呼ぶ)。 */
    fun register(entry: Entry) {
        _state.value = entry
    }

    /** 鳴っている曲の歌詞。鳴っていなければ null。 */
    fun entry(forSongId: String?): Entry? = _state.value?.takeIf { it.song.id == forSongId }

    /** 鳴っている曲が変わったら手放す。 */
    fun release(unlessSongId: String?) {
        if (_state.value?.song?.id != unlessSongId) _state.value = null
    }
}
