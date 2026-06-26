package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class IdolDetailUiState(
    val idol: Idol? = null,
    val originalSongs: List<Song> = emptyList(),
    val performedSongs: List<Song> = emptyList(),
    val units: List<ImasUnit> = emptyList(),
    val castShows: List<CastShowRow> = emptyList(),
    val isLoading: Boolean = true
)

class IdolDetailViewModel(app: Application, private val idolId: String) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).idolRepository
    private val songRepo = AppModule.from(app).songRepository

    private val _uiState = MutableStateFlow(IdolDetailUiState())
    val uiState: StateFlow<IdolDetailUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val idol = repo.fetchIdol(idolId) ?: return@launch
            val originalSongs = songRepo.fetchIdolSongs(idolId, "original")
            val performedSongs = songRepo.fetchIdolSongs(idolId, "performer")
            val units = repo.fetchIdolUnits(idolId)
            val castShows = repo.fetchIdolShows(idolId)

            _uiState.value = IdolDetailUiState(
                idol = idol,
                originalSongs = originalSongs,
                performedSongs = performedSongs,
                units = units,
                castShows = castShows,
                isLoading = false
            )
        }
    }

    class Factory(private val app: Application, private val idolId: String) :
        ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IdolDetailViewModel(app, idolId) as T
    }
}
