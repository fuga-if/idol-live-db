package com.fugaif.imaslivedb.ui.filtered

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

data class FilteredIdolsUiState(
    val title: String = "",
    val idols: List<Idol> = emptyList(),
    val isLoading: Boolean = true
)

/**
 * 絞り込んだアイドル一覧 (iOS `FilteredIdolsView`)。
 *
 * ブランドだけは一覧画面と同じ母集団 (外部ゲスト演者を除く) を使う。
 * 星座・出身地・血液型はプロフィールの属性から辿る一覧なので、
 * 「同じ属性の人を全員出す」ためにゲストも落とさない (母集団の違いはリポジトリ側の KDoc に書いた)。
 */
class FilteredIdolsViewModel(
    app: Application,
    private val kind: String,
    private val value: String
) : AndroidViewModel(app) {

    private val idols = AppModule.from(app).idolRepository

    private val _uiState = MutableStateFlow(FilteredIdolsUiState(title = value))
    val uiState: StateFlow<FilteredIdolsUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        when (kind) {
            IdolFilterKind.BRAND -> {
                // 表示名が引けないブランド (同期前・未知 id) でも一覧そのものは出す。
                val label = idols.fetchBrand(value)?.shortName ?: value
                emit("${label}のアイドル", idols.fetchIdolsForList(value))
            }
            IdolFilterKind.CONSTELLATION ->
                emit("${value}のアイドル", idols.fetchIdolsByConstellation(value))
            IdolFilterKind.BIRTH_PLACE ->
                emit("${value}出身のアイドル", idols.fetchIdolsByBirthPlace(value))
            IdolFilterKind.BLOOD_TYPE ->
                emit("${value}型のアイドル", idols.fetchIdolsByBloodType(value))
            else -> emit(value, emptyList())
        }
    }

    private fun emit(title: String, idols: List<Idol>) {
        _uiState.value = FilteredIdolsUiState(title = title, idols = idols, isLoading = false)
    }

    class Factory(
        private val app: Application,
        private val kind: String,
        private val value: String
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            FilteredIdolsViewModel(app, kind, value) as T
    }
}
