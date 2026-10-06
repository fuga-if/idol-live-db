package com.fugaif.imaslivedb.data.producercard

import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import uniffi.imas_core.ProfileSongInput

/** お気に入りの曲 1 つと、お気に入りに付けた時刻。載せる曲を選ぶ材料 (規則はコアの `favoriteSongPicks`)。iOS `FavoriteSong`。 */
data class FavoriteSong(
    val song: Song,
    /** お気に入りに付けた時刻 (ISO 8601)。 */
    val favoritedAt: String
) {
    val id: String get() = song.id

    /** コアに渡す形。 */
    val input: ProfileSongInput get() = ProfileSongInput(song.id, song.title, favoritedAt)
}

/**
 * お気に入りの曲を引く (P名刺の画像・P名刺の編集・載せる曲を選ぶ画面で共有する。引けない曲は入れない)。
 * iOS `FavoriteSongSource`。
 */
object FavoriteSongSource {
    suspend fun load(module: AppModule): List<FavoriteSong> {
        val times = runCatching { module.userMarkRepository.favoriteSongTimes() }.getOrDefault(emptyMap())
        if (times.isEmpty()) return emptyList()
        // SQLite の引数の上限 (999) を超えないように分けて引く (お気に入りは何百曲にもなる)。
        val songs = runCatching {
            times.keys.toList().chunked(900).flatMap { module.songRepository.fetchSongsByIds(it) }
        }.getOrDefault(emptyList())
        return songs.map { FavoriteSong(it, times[it.id].orEmpty()) }
    }
}
