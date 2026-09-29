package com.fugaif.imaslivedb.ui.settings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import uniffi.imas_core.InputField
import uniffi.imas_core.inputClamp

data class AccountUiState(
    /** 表示名の変更ダイアログ。null = 閉じている。 */
    val editingName: String? = null,
    val isSavingName: Boolean = false,
    val nameError: String? = null,
    val isDeleting: Boolean = false,
    val deleteError: String? = null
)

/**
 * 設定のアカウント欄 (表示名の変更・アカウントの削除)。
 *
 * サーバへの書き込みはアプリのスコープで行う (画面を離れても途中で止まらない)。
 * サインインそのものは Credential Manager が画面にアカウント選択を出すので、画面の側で行う。
 */
class AccountViewModel(app: Application) : AndroidViewModel(app) {

    private val module = AppModule.from(app)
    private val authService = module.authService

    val authState = authService.state

    private val _uiState = MutableStateFlow(AccountUiState())
    val uiState: StateFlow<AccountUiState> = _uiState.asStateFlow()

    fun signOut() = authService.signOut()

    fun startEditingName() = _uiState.update { it.copy(editingName = authState.value.displayName ?: "") }

    /** 40 文字までだけ受け付ける。 */
    fun setEditingName(value: String) {
        // 上限と数え方 (コードポイント。サーバと同じ) はコアが決める。超えた分は切る。
        _uiState.update { it.copy(editingName = inputClamp(InputField.DISPLAY_NAME, value)) }
    }

    fun cancelEditingName() = _uiState.update { if (it.isSavingName) it else it.copy(editingName = null) }

    fun saveName() {
        val name = _uiState.value.editingName?.trim() ?: return
        _uiState.update { it.copy(isSavingName = true) }
        module.appScope.launch {
            val result = authService.updateDisplayName(name)
            _uiState.update { state ->
                result.fold(
                    onSuccess = { state.copy(isSavingName = false, editingName = null) },
                    onFailure = { state.copy(isSavingName = false, nameError = "表示名の保存に失敗しました") }
                )
            }
        }
    }

    fun dismissNameError() = _uiState.update { it.copy(nameError = null) }

    fun deleteAccount() {
        _uiState.update { it.copy(isDeleting = true) }
        module.appScope.launch {
            val result = authService.deleteAccount()
            _uiState.update { state ->
                state.copy(isDeleting = false, deleteError = if (result.isFailure) "削除に失敗しました" else null)
            }
        }
    }

    fun dismissDeleteError() = _uiState.update { it.copy(deleteError = null) }

    private companion object {
    }
}
