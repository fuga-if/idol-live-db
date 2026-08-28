package com.fugaif.imaslivedb.widget

import android.content.Context
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.image.CustomImageStore
import com.fugaif.imaslivedb.data.image.GalleryKind
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** ウィジェットに出せるアイドル 1 人分 (= 端末に取り込んだ画像を 1 枚以上持つアイドル)。 */
data class OshiCandidate(
    val idolId: String,
    val name: String,
    /** 検索用の読み。候補は 300 件を超えるので、かなで絞れないと目当てまで届かない。 */
    val nameKana: String?,
    /** アイドル色 (hex)。設定画面のアバターの発色に使う。 */
    val colorHex: String?,
    val brandId: String?,
    /** ブランド略称。同名・大量候補の判別を助ける副題 (iOS のピッカーと同じ役割)。 */
    val brandShortName: String?,
    val brandColorHex: String?
)

/**
 * 担当画像ウィジェットの候補一覧と、表示する画像の解決。
 * iOS の `WidgetImageBridge` (App Group へのカタログ書き出し) に相当する層。
 *
 * ## iOS との違い: カタログ JSON を作らない
 *
 * iOS はウィジェット拡張がアプリの DB も Documents も読めないので、アプリ側が
 * 画像を App Group へコピーしてカタログ JSON を書き出していた。Android の
 * ウィジェットはアプリと同じ UID・同じプロセスで動くので、`filesDir` の実ファイルと
 * Room をそのまま読める。ミラーを作ると「アプリで画像を消したのにウィジェットには
 * 残る」という同期ズレを自前で抱えることになるので、作らない。
 */
object OshiCatalog {

    /**
     * 画像を持つアイドルを、ブランド順 → アイドルの sort_order 順で返す
     * (iOS `WidgetImageBridge` の並びと同じ。ピッカーで探しやすい順)。
     */
    suspend fun candidates(context: Context): List<OshiCandidate> = withContext(Dispatchers.IO) {
        val ids = galleryIdolIds(context)
        if (ids.isEmpty()) return@withContext emptyList()

        val database = AppDatabase.getInstance(context)
        val idols = database.idolDao().fetchIdolsByIds(ids)
        val brands = database.brandDao().fetchBrands().associateBy { it.id }

        idols.sortedWith(
            compareBy(
                { brands[it.brandId]?.sortOrder ?: Int.MAX_VALUE },
                { it.sortOrder },
                { it.id }
            )
        ).map { idol ->
            val brand = brands[idol.brandId]
            OshiCandidate(
                idolId = idol.id,
                name = idol.name,
                nameKana = idol.nameKana,
                colorHex = idol.color,
                brandId = idol.brandId,
                brandShortName = brand?.shortName,
                brandColorHex = brand?.color
            )
        }
    }

    /**
     * ウィジェットが順に送る画像 (順序付き、先頭=プライマリ)。
     *
     * 選択規則は [CustomImageStore.slideshowFiles] に委ねる。
     * 「`inSlideshow=true` のものだけ。1 枚も無ければ全件」という
     * フォールバック込みの規則で、素朴に filter すると全部チェックを外した
     * ユーザーのウィジェットが空になる。
     */
    fun slideshowImages(context: Context, idolId: String): List<File> =
        AppModule.from(context).customImageStore
            .slideshowFiles(idolId, GalleryKind.IDOL)
            .filter { it.isFile }

    /**
     * 画像を持つアイドル ID をディスクから直接列挙する。
     *
     * [CustomImageStore.idolsWithImages] を使わないのは、あれが起動時の非同期スキャンで
     * 埋まる StateFlow だから。ウィジェットの更新はプロセスが起きた直後に 1 回走って
     * 終わるので、スキャンの完走を待てず「画像はあるのに候補ゼロ」になる。
     *
     * 置き場所の契約 (`filesDir/custom_images/{idolId}/<uuid>.jpg|png`) と拡張子の判定は
     * [CustomImageStore] の KDoc / [CustomImageStore.isImageFile] が正本。ここは同じ規則で
     * 列挙するだけで、どの画像を出すかは [slideshowImages] に任せる。
     */
    private fun galleryIdolIds(context: Context): List<String> {
        val root = File(context.applicationContext.filesDir, GalleryKind.IDOL.directoryName)
        val folders = root.listFiles()?.filter { it.isDirectory } ?: return emptyList()
        return folders
            .filter { folder -> folder.list()?.any(CustomImageStore::isImageFile) == true }
            .map { it.name }
    }
}
