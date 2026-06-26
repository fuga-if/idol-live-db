package com.fugaif.imaslivedb.ui.produce

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ProduceUiState(
    val pickedIdols: List<Idol> = emptyList(),
    val favoriteIdols: List<Idol> = emptyList(),
    val favoriteSongs: List<Song> = emptyList(),
    val isLoading: Boolean = true
)

class ProduceViewModel(app: Application) : AndroidViewModel(app) {

    private val marks = AppModule.from(app).userMarkRepository

    private val _uiState = MutableStateFlow(ProduceUiState())
    val uiState: StateFlow<ProduceUiState> = _uiState.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            _uiState.value = ProduceUiState(
                pickedIdols = marks.pickedIdols(),
                favoriteIdols = marks.favoriteIdols(),
                favoriteSongs = marks.favoriteSongs(),
                isLoading = false
            )
        }
    }
}
