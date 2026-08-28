package com.fugaif.imaslivedb.ui.settings

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.backup.BackupExportImportService
import com.fugaif.imaslivedb.data.backup.BackupImportResult
import com.fugaif.imaslivedb.data.backup.TransferCodeResult
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import uniffi.imas_core.OshiThemePickIdol
import uniffi.imas_core.resolveOshiTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SettingsUiState(
    val schemaVersion: String = "...",
    val dataVersion: String = "...",
    val databaseStats: DatabaseStats? = null,
    val brands: List<Brand> = emptyList(),
    /** iOS `@AppStorage("defaultBrandId")` に相当。空文字は「すべて」。 */
    val defaultBrandId: String = "",
    /** 担当 (推し) マークの付いたアイドル。テーマ色に使う 1 人をここから選ばせる。 */
    val pickIdols: List<Idol> = emptyList(),
    val isLoading: Boolean = true
)

class SettingsViewModel(app: Application) : AndroidViewModel(app) {

    private val module = AppModule.from(app)
    private val statsRepo = module.statsRepository
    private val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(SettingsUiState(defaultBrandId = prefs.getString(KEY_DEFAULT_BRAND, "") ?: ""))
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val schemaVersion = statsRepo.fetchMetaValue("schema_version") ?: "不明"
            val dataVersion = statsRepo.fetchMetaValue("data_version") ?: "不明"
            val databaseStats = statsRepo.fetchDatabaseStats()
            val brands = statsRepo.fetchBrands()
            val pickIdols = module.userMarkRepository.pickedIdols()

            _uiState.value = _uiState.value.copy(
                schemaVersion = schemaVersion,
                dataVersion = dataVersion,
                databaseStats = databaseStats,
                brands = brands,
                pickIdols = pickIdols,
                isLoading = false
            )
            // 担当が増減している可能性があるので、開くたびにテーマ色を解決し直す
            // (担当を外したアイドルの色がテーマに残り続けるのを防ぐ)。
            syncOshiTheme()
        }
    }

    /**
     * 担当テーマ色を現在の選択から再計算して保存する。
     *
     * 解決規則そのもの (OFF のときは色だけ消して選択 ID は残す / 選択中の担当が外れていたら
     * 先頭へ黙って寄せる) は共有コアの `resolveOshiTheme` が正本。iOS と同じ関数を呼ぶので、
     * 同じ状態からは必ず同じ結果になる。
     */
    fun syncOshiTheme() {
        val resolved = resolveOshiTheme(
            isEnabled = AppPreferences.useOshiColor,
            currentIdolId = AppPreferences.oshiIdolId,
            pickIdols = _uiState.value.pickIdols.map { OshiThemePickIdol(it.id, it.color) }
        )
        resolved.idolId?.let { AppPreferences.setOshiIdolId(it) }
        AppPreferences.setOshiColorHex(resolved.colorHex)
    }

    /** デフォルトブランドを永続化する。iOS `MyPageView` の `defaultBrandId` と同じキー意味。 */
    fun setDefaultBrand(brandId: String?) {
        val value = brandId ?: ""
        prefs.edit().putString(KEY_DEFAULT_BRAND, value).apply()
        _uiState.value = _uiState.value.copy(defaultBrandId = value)
    }

    /** バックアップをファイルエクスポート/引き継ぎコード発行用の envelope JSON 文字列にまとめる。 */
    suspend fun exportBackupJson(): String =
        BackupExportImportService.buildEnvelopeJson(
            getApplication(), module.userMarkRepository, module.localPollVoteLog, module.personalTagRepository
        )

    /** ファイル/引き継ぎコードから取得した envelope JSON を非破壊マージで取り込む。 */
    suspend fun importBackup(json: String, restoreDeviceId: Boolean): BackupImportResult =
        BackupExportImportService.importEnvelopeJson(
            getApplication(), json, module.userMarkRepository, module.localPollVoteLog,
            module.personalTagRepository, restoreDeviceId
        )

    /** 現在のバックアップを envelope 化してサーバーに送り、引き継ぎコードを発行する。 */
    suspend fun createTransferCode(): TransferCodeResult {
        val envelope = exportBackupJson()
        return module.backupTransferApi.createTransferCode(envelope)
    }

    /** 引き継ぎコードでサーバーから envelope を取得し、非破壊マージで取り込む。 */
    suspend fun restoreFromTransferCode(code: String, restoreDeviceId: Boolean): BackupImportResult {
        val envelope = module.backupTransferApi.fetchTransferCode(code)
        return importBackup(envelope, restoreDeviceId)
    }

    companion object {
        private const val PREFS_NAME = "imas_settings"
        private const val KEY_DEFAULT_BRAND = "default_brand_id"
    }
}
