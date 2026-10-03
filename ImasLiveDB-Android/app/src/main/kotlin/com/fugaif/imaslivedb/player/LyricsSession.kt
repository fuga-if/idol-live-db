package com.fugaif.imaslivedb.player

import com.fugaif.imaslivedb.data.lyrics.LyricPartCast
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.lyrics.LyricsApi
import com.fugaif.imaslivedb.data.lyrics.LyricsResult
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.repository.SongRepository
import com.fugaif.imaslivedb.ui.theme.BrandColors
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

    /** 取得中の songId (二重リクエストを防ぐ)。 */
    private var loadingSongId: String? = null

    /**
     * 曲送り・プレイリストで曲が替わったとき、その曲の歌詞を自分で取りに行く
     * (歌詞タブを開いていなくても、再生中バー・プレイヤーが付いてくるように)。iOS `LyricsSession.follow` と対。
     *
     * 1 曲 1 リクエスト。取れなければ (未ログイン・歌詞なし) 何も預からない。
     */
    suspend fun follow(songId: String?, songRepository: SongRepository, lyricsApi: LyricsApi) {
        if (songId == null || _state.value?.song?.id == songId || loadingSongId == songId) return
        loadingSongId = songId
        try {
            val song = songRepository.fetchSong(songId) ?: return
            val lyricsResult = lyricsApi.lyrics(songId)
            val lyrics = (lyricsResult as? LyricsResult.Loaded)?.lyrics ?: return
            val artists = songRepository.fetchSongArtists(songId, "original")
            // 曲詳細と同じ差し色: 原唱者が 1 人ならその人の色、他はブランドの色。
            val seed = if (artists.size == 1) artists.first().color else BrandColors.hex(song.brandId)
            val artistLine = when {
                artists.isNotEmpty() -> artists.joinToString(" / ") { it.name }
                !song.singerLabel.isNullOrEmpty() -> song.singerLabel
                !song.unitName.isNullOrEmpty() -> song.unitName
                else -> null
            }
            register(
                Entry(
                    song = song, seed = seed, artistLine = artistLine, artworkUrl = song.artworkUrl,
                    lyrics = lyrics, cast = LyricPartCast(artists)
                )
            )
        } finally {
            if (loadingSongId == songId) loadingSongId = null
        }
    }
}
