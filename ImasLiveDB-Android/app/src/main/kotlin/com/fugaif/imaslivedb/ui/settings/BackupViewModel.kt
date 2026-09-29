package com.fugaif.imaslivedb.ui.settings

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import com.fugaif.imaslivedb.data.backup.BackupExportImportService
import com.fugaif.imaslivedb.data.backup.BackupFormatException
import com.fugaif.imaslivedb.data.backup.BackupImportResult
import com.fugaif.imaslivedb.data.backup.BackupTransferException
import com.fugaif.imaslivedb.data.backup.TransferCodeResult
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.backupImportSummary

data class BackupUiState(
    val isCreatingCode: Boolean = false,
    val transferCode: TransferCodeResult? = null,
    val transferError: String? = null,
    val codeInput: String = "",
    val isRestoringCode: Boolean = false,
    val isExporting: Boolean = false,
    val isImportingFile: Boolean = false,
    /** 復元の結果の文面 (何がどれだけ入ったか。組み立てはコア)。null = 出していない。 */
    val importSummary: String? = null,
    val importError: String? = null
)

/**
 * バックアップ (引き継ぎコード・ファイル) の書き出しと取り込み。
 *
 * 実行はアプリのスコープで行う。画面のスコープで走らせていたので、画面を離れたり
 * 回したりすると取り込みが途中で止まり、一部だけ入っていた。結果の表示はこの画面が
 * 居る間だけ (居なくなっても取り込みは最後まで走る)。
 */
class BackupViewModel(app: Application) : AndroidViewModel(app) {

    private val module = AppModule.from(app)
    private val scope = module.appScope

    private val _uiState = MutableStateFlow(BackupUiState())
    val uiState: StateFlow<BackupUiState> = _uiState.asStateFlow()

    fun setCodeInput(value: String) = _uiState.update { it.copy(codeInput = value.uppercase()) }

    /** 現在のバックアップを envelope 化してサーバーに送り、引き継ぎコードを発行する。 */
    fun createTransferCode() {
        _uiState.update { it.copy(isCreatingCode = true, transferError = null) }
        scope.launch {
            try {
                val code = module.backupTransferApi.createTransferCode(exportJson())
                _uiState.update { it.copy(transferCode = code) }
            } catch (e: BackupTransferException) {
                _uiState.update { it.copy(transferError = e.message) }
            } catch (e: Exception) {
                _uiState.update { it.copy(transferError = "発行に失敗しました") }
            } finally {
                _uiState.update { it.copy(isCreatingCode = false) }
            }
        }
    }

    /** 引き継ぎコードでサーバーから envelope を取得し、非破壊マージで取り込む。 */
    fun restoreFromTransferCode(restoreDeviceId: Boolean) {
        val code = _uiState.value.codeInput.trim()
        _uiState.update { it.copy(isRestoringCode = true) }
        scope.launch {
            try {
                val envelope = module.backupTransferApi.fetchTransferCode(code)
                val result = importJson(envelope, restoreDeviceId)
                _uiState.update { it.copy(importSummary = summaryOf(result), codeInput = "") }
            } catch (e: Exception) {
                reportImportFailure(e)
            } finally {
                _uiState.update { it.copy(isRestoringCode = false) }
            }
        }
    }

    /** バックアップをファイル (SAF で選ばれた [uri]) に書き出す。 */
    fun exportTo(uri: Uri) {
        _uiState.update { it.copy(isExporting = true) }
        scope.launch {
            try {
                val json = exportJson()
                withContext(Dispatchers.IO) {
                    getApplication<Application>().contentResolver.openOutputStream(uri)?.use {
                        it.write(json.toByteArray(Charsets.UTF_8))
                    }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(importError = "書き出しに失敗しました") }
            } finally {
                _uiState.update { it.copy(isExporting = false) }
            }
        }
    }

    /** ファイル (SAF で選ばれた [uri]) から非破壊マージで取り込む。 */
    fun importFrom(uri: Uri, restoreDeviceId: Boolean) {
        _uiState.update { it.copy(isImportingFile = true) }
        scope.launch {
            try {
                val json = withContext(Dispatchers.IO) {
                    getApplication<Application>().contentResolver.openInputStream(uri)
                        ?.bufferedReader()?.use { it.readText() }
                } ?: throw BackupFormatException("ファイルを読み込めませんでした")
                val result = importJson(json, restoreDeviceId)
                _uiState.update { it.copy(importSummary = summaryOf(result)) }
            } catch (e: Exception) {
                reportImportFailure(e)
            } finally {
                _uiState.update { it.copy(isImportingFile = false) }
            }
        }
    }

    fun dismissTransferError() = _uiState.update { it.copy(transferError = null) }

    fun dismissImportResult() = _uiState.update { it.copy(importSummary = null) }

    fun dismissImportError() = _uiState.update { it.copy(importError = null) }

    private fun reportImportFailure(e: Exception) {
        val message = when (e) {
            is BackupFormatException -> e.message
            is BackupTransferException -> e.message
            else -> null
        } ?: "読み込みに失敗しました"
        _uiState.update { it.copy(importError = message) }
    }

    /** 復元の結果の文面 (iOS と同じ。入ったものだけを並べる規則はコアの backupImportSummary)。 */
    private fun summaryOf(result: BackupImportResult): String = backupImportSummary(
        addedMarks = result.addedMarks.toLong(),
        addedVotes = result.addedVotes.toLong(),
        addedPersonalTags = result.addedPersonalTags.toLong(),
        addedExpenses = result.addedExpenses.toLong(),
        skippedMarks = result.skippedMarks.toLong(),
        deviceIdRestored = result.deviceIdRestored
    )

    private suspend fun exportJson(): String =
        BackupExportImportService.buildEnvelopeJson(
            getApplication(), module.userMarkRepository, module.localPollVoteLog,
            module.personalTagRepository, module.expenseRepository
        )

    private suspend fun importJson(json: String, restoreDeviceId: Boolean): BackupImportResult =
        BackupExportImportService.importEnvelopeJson(
            getApplication(), json, module.database, module.userMarkRepository, module.localPollVoteLog,
            module.personalTagRepository, module.expenseRepository, restoreDeviceId
        )
}
