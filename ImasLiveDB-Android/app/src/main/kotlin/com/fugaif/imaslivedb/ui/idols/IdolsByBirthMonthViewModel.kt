package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class IdolsByBirthMonthUiState(
    val idols: List<Idol> = emptyList(),
    val isLoading: Boolean = true
)

/**
 * 誕生月で絞ったアイドル一覧の状態 (iOS `FilteredIdolsView(criterion: .birthMonth)` 相当)。
 *
 * 母集団も並びも共有コアが持つので、ここは 1 画面 = 1 回の取得を投げるだけ。
 * 行ごとに問い合わせない (境界を跨ぐ呼び出しを要素数に比例させない)。
 */
class IdolsByBirthMonthViewModel(app: Application, private val month: Int) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).idolRepository

    private val _uiState = MutableStateFlow(IdolsByBirthMonthUiState())
    val uiState: StateFlow<IdolsByBirthMonthUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            _uiState.value = IdolsByBirthMonthUiState(
                idols = repo.fetchIdolsByBirthMonth(month),
                isLoading = false
            )
        }
    }

    class Factory(private val app: Application, private val month: Int) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IdolsByBirthMonthViewModel(app, month) as T
    }
}
