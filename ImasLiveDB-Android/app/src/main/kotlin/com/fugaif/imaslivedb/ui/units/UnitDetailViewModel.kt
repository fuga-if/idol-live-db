package com.fugaif.imaslivedb.ui.units

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class UnitDetailUiState(
    val unit: ImasUnit? = null,
    val members: List<Idol> = emptyList(),
    val songs: List<Song> = emptyList(),
    val isLoading: Boolean = true
)

class UnitDetailViewModel(app: Application, private val unitId: String) : AndroidViewModel(app) {

    private val idolRepo = AppModule.from(app).idolRepository
    private val songRepo = AppModule.from(app).songRepository

    private val _uiState = MutableStateFlow(UnitDetailUiState())
    val uiState: StateFlow<UnitDetailUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val unit = idolRepo.fetchUnit(unitId) ?: return@launch
            val members = idolRepo.fetchUnitMembers(unitId)
            val songs = songRepo.fetchUnitSongs(unitId)
            _uiState.value = UnitDetailUiState(
                unit = unit,
                members = members,
                songs = songs,
                isLoading = false
            )
        }
    }

    class Factory(private val app: Application, private val unitId: String) :
        ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            UnitDetailViewModel(app, unitId) as T
    }
}
