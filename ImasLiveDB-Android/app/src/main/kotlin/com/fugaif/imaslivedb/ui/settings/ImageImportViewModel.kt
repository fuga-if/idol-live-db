package com.fugaif.imaslivedb.ui.settings

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import com.fugaif.imaslivedb.data.image.BulkImageImporter
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 一括インポート/型紙の対象。UI 文言・ファイル名・呼ぶ API がこれで決まる。 */
enum class ImageImportTarget(
    val label: String,
    val templateFileName: String,
) {
    IDOL("アイドル", "idol_images_template.json"),
    BRAND("ブランド", "brand_images_template.json"),
    UNIT("ユニット", "unit_images_template.json"),
}

/**
 * キャラクター画像の一括インポート・型紙の書き出し・全削除。
 *
 * 実行はアプリのスコープで行い、進捗は取り込み器 (アプリで 1 つ) が持つ。画面のスコープで
 * 走らせていたので、画面を離れると取り込みが途中で止まっていた。戻ってくれば進捗が見える。
 */
class ImageImportViewModel(app: Application) : AndroidViewModel(app) {

    private val module = AppModule.from(app)
    private val importer: BulkImageImporter = module.bulkImageImporter

    val state: StateFlow<BulkImageImporter.State> = importer.state

    fun import(target: ImageImportTarget, url: String) {
        module.appScope.launch {
            when (target) {
                ImageImportTarget.IDOL -> importer.importIdolImages(url)
                ImageImportTarget.BRAND -> importer.importBrandImages(url)
                ImageImportTarget.UNIT -> importer.importUnitImages(url)
            }
        }
    }

    /** 型紙 JSON (組み立てはコアが唯一の正) を SAF で選ばれた [uri] に書き出す。 */
    fun saveTemplate(target: ImageImportTarget, uri: Uri) {
        module.appScope.launch {
            val json = when (target) {
                ImageImportTarget.IDOL -> importer.idolTemplateJson()
                ImageImportTarget.BRAND -> importer.brandTemplateJson()
                ImageImportTarget.UNIT -> importer.unitTemplateJson()
            }
            withContext(Dispatchers.IO) {
                getApplication<Application>().contentResolver.openOutputStream(uri)?.use {
                    it.write(json.toByteArray(Charsets.UTF_8))
                }
            }
        }
    }

    fun clearAll() {
        module.appScope.launch { importer.clearAllImages() }
    }
}
