package com.fugaif.imaslivedb.ui.filtered

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.data.repository.SongWithRoles
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.songs.songTypeLabel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class FilteredSongsUiState(
    val title: String = "",
    val songs: List<SongWithArtists> = emptyList(),
    /**
     * クリエイター絞り込みのときだけ埋まる「その曲での役割」。song_id → "作曲・編曲"。
     * 曲そのものは [songs] に入っているので、行の描画は 1 系統で済む。
     */
    val rolesBySongId: Map<String, String> = emptyMap(),
    val isLoading: Boolean = true
)

/**
 * 絞り込んだ楽曲一覧 (iOS `FilteredSongsView`)。
 *
 * 母集団と並びは kind ごとに違うが、どれも「1 画面 = 1 回の取得」に収める。
 * ブランド名の解決だけは追加の 1 回が要る (ルートに載るのは brand_id で、
 * 画面タイトルに出したいのは表示名なので)。
 */
class FilteredSongsViewModel(
    app: Application,
    private val kind: String,
    private val value: String
) : AndroidViewModel(app) {

    private val songs = AppModule.from(app).songRepository
    private val idols = AppModule.from(app).idolRepository

    private val _uiState = MutableStateFlow(FilteredSongsUiState(title = fallbackTitle()))
    val uiState: StateFlow<FilteredSongsUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        when (kind) {
            SongFilterKind.CREATOR -> {
                val withRoles = songs.fetchSongsByCreator(value)
                emit(
                    title = "${value}が関わった楽曲",
                    songs = withRoles.map { SongWithArtists(it.song, it.song.singerLabel ?: "") },
                    roles = withRoles.associate { it.song.id to it.rolesLabel }
                )
            }
            SongFilterKind.BRAND -> {
                // 表示名が引けないブランド (同期前・未知 id) でも一覧そのものは出す。
                val label = idols.fetchBrand(value)?.shortName ?: value
                emit(title = "${label}の楽曲", songs = songs.fetchSongs(brandCriterionFilter()))
            }
            SongFilterKind.SONG_TYPE -> {
                emit(
                    title = "${songTypeLabel(value)}の楽曲",
                    songs = songs.fetchSongs(SongSearchFilter(songType = value, excludeLiveOnly = false))
                )
            }
            SongFilterKind.CD_SERIES -> emit(title = value, songs = songs.fetchSongsByCdSeries(value))
            SongFilterKind.SERIES_GROUP -> emit(title = value, songs = songs.fetchSongsBySeriesGroup(value))
            SongFilterKind.RELEASE_YEAR ->
                emit(title = "${value}年リリースの楽曲", songs = songs.fetchSongsByReleaseYear(value))
            // 未知の kind は空一覧。落とさないのは、ルートを増やした側の取りこぼしが
            // クラッシュではなく「0曲」として見えた方が直しやすいため。
            else -> emit(title = fallbackTitle(), songs = emptyList())
        }
    }

    /**
     * ブランド絞り込みの母集団。曲一覧ブラウズと違い `excludeLiveOnly` を寝かせる —
     * iOS の `SongFilterCriterion.brand` は既定の SongSearchFilter (excludeLiveOnly=false) を
     * 使っており、ライブ履歴にしかない曲もこの一覧には出るのが正。
     */
    private fun brandCriterionFilter() = SongSearchFilter(brandIds = setOf(value), excludeLiveOnly = false)

    private fun emit(title: String, songs: List<SongWithArtists>, roles: Map<String, String> = emptyMap()) {
        _uiState.value = FilteredSongsUiState(
            title = title, songs = songs, rolesBySongId = roles, isLoading = false
        )
    }

    /** 取得前・未知 kind のタイトル。値そのものは必ず意味のある文字列なのでそれを出す。 */
    private fun fallbackTitle(): String = value

    class Factory(
        private val app: Application,
        private val kind: String,
        private val value: String
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            FilteredSongsViewModel(app, kind, value) as T
    }
}
