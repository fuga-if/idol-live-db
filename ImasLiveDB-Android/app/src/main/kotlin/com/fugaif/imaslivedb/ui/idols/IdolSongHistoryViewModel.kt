package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class IdolSongHistoryUiState(
    val idol: Idol? = null,
    val song: Song? = null,
    val history: List<CastShowRow> = emptyList(),
    val isLoading: Boolean = true
)

/**
 * アイドル × 曲 の披露履歴 (iOS `IdolSongHistoryView`)。
 *
 * 履歴そのものは 1 回の取得で揃う。アイドルと曲を別に読むのは、遷移元 (アイドル詳細) から
 * ルートに載せられるのが id だけで、画面タイトル (「◯◯ × ◯◯」) と配色シードに実体が要るため。
 */
class IdolSongHistoryViewModel(
    app: Application,
    private val idolId: String,
    private val songId: String
) : AndroidViewModel(app) {

    private val idols = AppModule.from(app).idolRepository
    private val songs = AppModule.from(app).songRepository

    private val _uiState = MutableStateFlow(IdolSongHistoryUiState())
    val uiState: StateFlow<IdolSongHistoryUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            _uiState.value = IdolSongHistoryUiState(
                idol = idols.fetchIdol(idolId),
                song = songs.fetchSong(songId),
                history = idols.fetchIdolSongHistory(idolId, songId),
                isLoading = false
            )
        }
    }

    class Factory(
        private val app: Application,
        private val idolId: String,
        private val songId: String
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IdolSongHistoryViewModel(app, idolId, songId) as T
    }
}
