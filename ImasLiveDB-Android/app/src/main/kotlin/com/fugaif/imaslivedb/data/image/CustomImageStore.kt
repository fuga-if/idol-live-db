package com.fugaif.imaslivedb.data.image

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * ギャラリー画像 1 枚分のメタ。`manifest.json` に順序付きで保存する (先頭=プライマリ)。
 *
 * iOS `CustomImageService.GalleryImageMeta` と **フィールド名まで一致** させてある。
 * 端末をまたいで manifest をコピーしても読めるようにするためと、Android のホーム画面
 * ウィジェット (別プロセス) が同じパーサを持てるようにするため。
 */
data class GalleryImageMeta(
    val name: String,
    /** ホーム画面ウィジェットのスライドショー対象に含めるか (既定 true)。 */
    val inSlideshow: Boolean = true,
)

/**
 * 複数画像ギャラリーの対象種別。ディレクトリ分離のみが違いで、内部ロジックは共通。
 * ディレクトリ名は iOS (`GalleryKind.directoryName`) と同じ。
 */
enum class GalleryKind(val directoryName: String) {
    IDOL("custom_images"),
    UNIT("custom_images_units"),
}

/**
 * アイドル / ユニット / ブランドごとのカスタム画像を端末ローカルに保存・管理する層。
 * iOS `ImasLiveDB/Services/CustomImageService.swift` の 1:1 移植。
 *
 * ## 保存場所と命名 (ウィジェット担当への契約 — 勝手に変えないこと)
 *
 * ルートは **`context.filesDir`**。外部ストレージ権限を増やさないためで、同じ UID の
 * ホーム画面ウィジェット (AppWidgetProvider / Glance) からは
 * `context.applicationContext.filesDir` で **同じ実ファイルがそのまま読める**
 * (iOS のような App Group ミラーは不要)。
 *
 * ```
 * filesDir/custom_images/{idolId}/{uuid}.jpg|png   … アイドルのギャラリー画像
 * filesDir/custom_images/{idolId}/manifest.json    … 並び順 + スライドショー対象フラグ
 * filesDir/custom_images_units/{unitId}/…          … ユニット (同じ構造)
 * filesDir/custom_images_brands/{brandId}.jpg|png  … ブランドは 1 件 1 ファイル
 * ```
 *
 * `manifest.json` は **順序付きの配列**。先頭がプライマリ (= アプリ内アバターに出る 1 枚)。
 *
 * ```json
 * [{"name":"9f0c…-….jpg","inSlideshow":true},{"name":"…png","inSlideshow":false}]
 * ```
 *
 * 旧形式のファイル名だけの配列 (`["a.jpg","b.jpg"]`) も読める (全件スライドショー対象として移行)。
 * ウィジェット側は [slideshowFiles] と同じ規則 —「`inSlideshow=true` のものだけ。
 * 1 枚も無ければ全件にフォールバック」— で選ぶこと。空表示を避けるためのフォールバックなので、
 * ここを素直に filter するだけにすると「全部外した」ユーザーのウィジェットが空になる。
 *
 * ## 画像はこの端末から出ない
 * サーバにも CloudKit にも上げない (iOS も同じ)。バックアップ/引き継ぎの対象外。
 *
 * ## スレッド
 * 書き込み系は `suspend` で IO ディスパッチャへ逃がす。読み取り系 ([primaryImageFile] 等) は
 * Compose から毎フレーム呼ばれるので、**manifest をメモリにキャッシュ**して同期関数にしてある。
 * 書くのはこのアプリだけなので、変更時にキャッシュを差し替えれば整合は保てる。
 */
class CustomImageStore(context: Context) {

    private val appContext: Context = context.applicationContext

    private val idolDirectory = File(appContext.filesDir, GalleryKind.IDOL.directoryName)
    private val unitDirectory = File(appContext.filesDir, GalleryKind.UNIT.directoryName)
    private val brandDirectory = File(appContext.filesDir, BRAND_DIRECTORY_NAME)

    /** 画像を 1 枚以上持つアイドル ID 集合 (アバター有無判定用)。 */
    private val _idolsWithImages = MutableStateFlow<Set<String>>(emptySet())
    val idolsWithImages: StateFlow<Set<String>> = _idolsWithImages.asStateFlow()

    /** 画像を 1 枚以上持つユニット ID 集合。 */
    private val _unitsWithImages = MutableStateFlow<Set<String>>(emptySet())
    val unitsWithImages: StateFlow<Set<String>> = _unitsWithImages.asStateFlow()

    private val _brandsWithImages = MutableStateFlow<Set<String>>(emptySet())
    val brandsWithImages: StateFlow<Set<String>> = _brandsWithImages.asStateFlow()

    /**
     * ギャラリーの変更通知 (再描画トリガ、idol/unit/brand 共通)。
     * iOS の `galleryVersion` と同じ役割 — 「同じ id のまま中身が変わった」を Compose に伝える。
     */
    private val _galleryVersion = MutableStateFlow(0)
    val galleryVersion: StateFlow<Int> = _galleryVersion.asStateFlow()

    /**
     * manifest のメモリキャッシュ。キーは `"{directoryName}/{entityId}"`。
     * Compose の描画中にディスクを読まないための物で、書くのはこのアプリだけなので
     * 変更のたびにここを差し替えれば正しさは保てる。
     */
    private val manifestCache = ConcurrentHashMap<String, List<GalleryImageMeta>>()

    // Application と同寿命のシングルトン想定なので cancel 経路は持たない。
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        // 初回スキャンはディスク走査なので起動をブロックしない。終わると StateFlow が
        // 更新され、購読しているアバターが自然に差し替わる。
        scope.launch {
            listOf(idolDirectory, unitDirectory, brandDirectory).forEach { it.mkdirs() }
            _idolsWithImages.value = scanGalleryIds(GalleryKind.IDOL)
            _unitsWithImages.value = scanGalleryIds(GalleryKind.UNIT)
            _brandsWithImages.value = scanBrandIds()
            bumpVersion()
        }
    }

    // MARK: - ギャラリー (複数画像、idol/unit 共通)

    private fun directory(kind: GalleryKind): File = when (kind) {
        GalleryKind.IDOL -> idolDirectory
        GalleryKind.UNIT -> unitDirectory
    }

    /** 1 エンティティ = 1 フォルダ。ウィジェットもこの組み立て規則で辿ること。 */
    fun entityFolder(entityId: String, kind: GalleryKind = GalleryKind.IDOL): File =
        File(directory(kind), entityId)

    private fun manifestFile(entityId: String, kind: GalleryKind): File =
        File(entityFolder(entityId, kind), MANIFEST_FILE_NAME)

    private fun cacheKey(entityId: String, kind: GalleryKind) = "${kind.directoryName}/$entityId"

    /**
     * プライマリを含む順序付きエントリ (先頭=プライマリ)。
     * キャッシュが無ければディスクの実体と突き合わせて健全化してから載せる。
     */
    private fun manifest(entityId: String, kind: GalleryKind): List<GalleryImageMeta> =
        manifestCache.getOrPut(cacheKey(entityId, kind)) { readManifest(entityId, kind) }

    /**
     * ディスクから manifest を読み、フォルダの実体と突き合わせる。
     * - 消えたファイルのエントリは落とす
     * - 同名の重複エントリは畳む (過去の不正 manifest 対策)
     * - manifest に無いがディスクにある画像は末尾に足す (取りこぼし防止)
     */
    private fun readManifest(entityId: String, kind: GalleryKind): List<GalleryImageMeta> {
        val folder = entityFolder(entityId, kind)
        // 画像を 1 枚も持たないのが大多数。無いフォルダを毎回開きに行かないよう先に切る。
        if (!folder.isDirectory) return emptyList()
        val onDisk = (folder.list() ?: emptyArray()).filter(::isImageFile).toSet()
        val saved = runCatching { manifestFile(entityId, kind).readText() }
            .getOrNull()
            ?.let(::parseManifest)
            .orEmpty()
        val order = dedupedByName(saved.filter { it.name in onDisk }).toMutableList()
        val known = order.mapTo(mutableSetOf()) { it.name }
        onDisk.sorted().filterNot { it in known }.forEach { order.add(GalleryImageMeta(it)) }
        return order
    }

    private fun writeManifest(entries: List<GalleryImageMeta>, entityId: String, kind: GalleryKind) {
        val folder = entityFolder(entityId, kind)
        folder.mkdirs()
        runCatching { manifestFile(entityId, kind).writeText(encodeManifest(entries)) }
            .onFailure { Log.w(TAG, "manifest 書き込み失敗: $entityId", it) }
        manifestCache[cacheKey(entityId, kind)] = entries
    }

    /** 代表 (プライマリ) 画像。アプリ内アバター・ウィジェットの単枚表示はこれを使う。 */
    fun primaryImageFile(entityId: String, kind: GalleryKind = GalleryKind.IDOL): File? {
        // 画像を持たない大多数のために、まず集合で弾いてディスクアクセスを避ける
        // (一覧の全行から毎フレーム呼ばれる)。
        if (entityId !in idsWithImages(kind).value) return null
        val first = manifest(entityId, kind).firstOrNull() ?: return null
        return File(entityFolder(entityId, kind), first.name)
    }

    /** ギャラリー全画像 (順序付き、先頭=プライマリ)。 */
    fun imageFiles(entityId: String, kind: GalleryKind = GalleryKind.IDOL): List<File> {
        val folder = entityFolder(entityId, kind)
        return manifest(entityId, kind).map { File(folder, it.name) }
    }

    fun imageCount(entityId: String, kind: GalleryKind = GalleryKind.IDOL): Int =
        manifest(entityId, kind).size

    fun hasCustomImage(entityId: String, kind: GalleryKind = GalleryKind.IDOL): Boolean =
        entityId in idsWithImages(kind).value

    // MARK: - スライドショー対象選択 (ウィジェット)

    /**
     * スライドショー対象 (inSlideshow=true) の画像 (順序付き)。
     * 1 枚も選ばれていなければ全件にフォールバックし、ウィジェットが空にならないようにする。
     */
    fun slideshowFiles(entityId: String, kind: GalleryKind = GalleryKind.IDOL): List<File> {
        val folder = entityFolder(entityId, kind)
        return slideshowFiltered(manifest(entityId, kind)).map { File(folder, it.name) }
    }

    /** 指定画像がスライドショー対象か (manifest に無ければ既定 true)。 */
    fun isInSlideshow(file: File, entityId: String, kind: GalleryKind = GalleryKind.IDOL): Boolean =
        manifest(entityId, kind).firstOrNull { it.name == file.name }?.inSlideshow ?: true

    /** 指定画像のスライドショー対象フラグを設定する。 */
    suspend fun setInSlideshow(
        included: Boolean,
        file: File,
        entityId: String,
        kind: GalleryKind = GalleryKind.IDOL,
    ) {
        val order = manifest(entityId, kind)
        if (order.none { it.name == file.name }) return
        val updated = order.map { if (it.name == file.name) it.copy(inSlideshow = included) else it }
        withContext(Dispatchers.IO) { writeManifest(updated, entityId, kind) }
        bumpVersion()
    }

    /** 指定画像をプライマリ (先頭) にする。 */
    suspend fun setPrimary(file: File, entityId: String, kind: GalleryKind = GalleryKind.IDOL) {
        val order = manifest(entityId, kind)
        val idx = order.indexOfFirst { it.name == file.name }
        if (idx <= 0) return
        val reordered = order.toMutableList().apply { add(0, removeAt(idx)) }
        withContext(Dispatchers.IO) { writeManifest(reordered, entityId, kind) }
        bumpVersion()
    }

    // MARK: - 追加・削除

    /**
     * 端末のフォトピッカーで選ばれた [uri] を 1 枚追加する (末尾)。
     * 元画像は `contentResolver` 経由でしか読めないので、デコードもここで行う。
     */
    suspend fun addImage(
        uri: Uri,
        entityId: String,
        kind: GalleryKind = GalleryKind.IDOL,
    ): File? = withContext(Dispatchers.IO) {
        val bitmap = decodeBitmap(uri) ?: return@withContext null
        addImage(bitmap, entityId, kind)
    }

    /** ギャラリーに 1 枚追加する (末尾)。返り値は追加した画像ファイル。 */
    suspend fun addImage(
        bitmap: Bitmap,
        entityId: String,
        kind: GalleryKind = GalleryKind.IDOL,
    ): File? = withContext(Dispatchers.IO) {
        val folder = entityFolder(entityId, kind)
        folder.mkdirs()
        val name = "${UUID.randomUUID()}.${fileExtension(bitmap)}"
        val file = File(folder, name)
        // manifest を「書き込み前」に読む。先に画像を書くと readManifest の突き合わせが
        // 新ファイルを拾い、続く append と二重登録になる (同じ画像が 2 枚並ぶ)。
        val order = manifest(entityId, kind) + GalleryImageMeta(name)
        if (!writeDownsampled(bitmap, file)) return@withContext null
        writeManifest(order, entityId, kind)
        insertHasImage(entityId, kind)
        bumpVersion()
        file
    }

    /**
     * 単一画像として設定する (既存を全消去して 1 枚に)。
     * 一括インポートの「アイコンを設定」用途 — 再実行で同じ絵が積み上がらないようにするため。
     */
    suspend fun saveImage(bitmap: Bitmap, entityId: String, kind: GalleryKind = GalleryKind.IDOL) {
        deleteAllImages(entityId, kind)
        addImage(bitmap, entityId, kind)
    }

    /** 指定 1 枚を削除する。 */
    suspend fun deleteImage(file: File, entityId: String, kind: GalleryKind = GalleryKind.IDOL) {
        withContext(Dispatchers.IO) { file.delete() }
        val order = manifest(entityId, kind).filterNot { it.name == file.name }
        writeManifest(order, entityId, kind)
        if (order.isEmpty()) removeHasImage(entityId, kind)
        bumpVersion()
    }

    /** このアイドル/ユニットの全画像を削除する。 */
    suspend fun deleteAllImages(entityId: String, kind: GalleryKind = GalleryKind.IDOL) {
        withContext(Dispatchers.IO) { entityFolder(entityId, kind).deleteRecursively() }
        manifestCache.remove(cacheKey(entityId, kind))
        removeHasImage(entityId, kind)
        bumpVersion()
    }

    // MARK: - ブランド (単一画像)

    /**
     * ブランドは 1 ブランド 1 ファイル。拡張子は中身次第 (透過ロゴ=png / 写真=jpg) なので、
     * 決め打ちせず実在するものを探す。
     */
    private fun brandFile(brandId: String): File? =
        IMAGE_EXTENSIONS.map { File(brandDirectory, "$brandId.$it") }.firstOrNull { it.exists() }

    fun brandImageFile(brandId: String): File? =
        if (brandId in _brandsWithImages.value) brandFile(brandId) else null

    fun hasBrandImage(brandId: String): Boolean = brandId in _brandsWithImages.value

    suspend fun saveBrandImage(bitmap: Bitmap, brandId: String) {
        withContext(Dispatchers.IO) {
            brandDirectory.mkdirs()
            // 形式が変わると別名になるので、先に旧ファイルを消さないと jpg と png が併存し、
            // brandFile が古い方を拾い続ける。
            IMAGE_EXTENSIONS.forEach { File(brandDirectory, "$brandId.$it").delete() }
            writeDownsampled(bitmap, File(brandDirectory, "$brandId.${fileExtension(bitmap)}"))
        }
        _brandsWithImages.value = _brandsWithImages.value + brandId
        bumpVersion()
    }

    suspend fun deleteBrandImage(brandId: String) {
        withContext(Dispatchers.IO) {
            IMAGE_EXTENSIONS.forEach { File(brandDirectory, "$brandId.$it").delete() }
        }
        _brandsWithImages.value = _brandsWithImages.value - brandId
        bumpVersion()
    }

    // MARK: - 一括削除

    suspend fun clearAllIdolImages() = clearGallery(GalleryKind.IDOL)

    suspend fun clearAllUnitImages() = clearGallery(GalleryKind.UNIT)

    private suspend fun clearGallery(kind: GalleryKind) {
        val dir = directory(kind)
        withContext(Dispatchers.IO) {
            dir.listFiles()?.forEach { it.deleteRecursively() }
            dir.mkdirs()
        }
        manifestCache.keys.removeAll { it.startsWith("${kind.directoryName}/") }
        idsWithImages(kind).value = emptySet()
        bumpVersion()
    }

    suspend fun clearAllBrandImages() {
        withContext(Dispatchers.IO) {
            brandDirectory.listFiles()?.filter { isImageFile(it.name) }?.forEach { it.delete() }
        }
        _brandsWithImages.value = emptySet()
        bumpVersion()
    }

    // MARK: - 内部

    private fun idsWithImages(kind: GalleryKind): MutableStateFlow<Set<String>> = when (kind) {
        GalleryKind.IDOL -> _idolsWithImages
        GalleryKind.UNIT -> _unitsWithImages
    }

    private fun insertHasImage(entityId: String, kind: GalleryKind) {
        val flow = idsWithImages(kind)
        flow.value = flow.value + entityId
    }

    private fun removeHasImage(entityId: String, kind: GalleryKind) {
        val flow = idsWithImages(kind)
        flow.value = flow.value - entityId
    }

    private fun bumpVersion() {
        _galleryVersion.value = _galleryVersion.value + 1
    }

    /** 画像を 1 枚以上持つエンティティ ID (= manifest が空でないフォルダ)。 */
    private fun scanGalleryIds(kind: GalleryKind): Set<String> {
        val dir = directory(kind)
        val folders = dir.listFiles()?.filter { it.isDirectory } ?: return emptySet()
        return folders.filter { folder ->
            // 起動時の走査でキャッシュも温めておく (最初の一覧描画でディスクを読まないため)。
            val entries = readManifest(folder.name, kind)
            manifestCache[cacheKey(folder.name, kind)] = entries
            entries.isNotEmpty()
        }.mapTo(mutableSetOf()) { it.name }
    }

    private fun scanBrandIds(): Set<String> =
        (brandDirectory.list() ?: emptyArray())
            .filter(::isImageFile)
            .mapTo(mutableSetOf(), ::stem)

    /**
     * 元のアスペクト比を保ったまま最長辺 1024px へ縮小して書き出す。
     *
     * **透過があれば PNG、無ければ JPEG。** JPEG はアルファチャンネルを持てないので、
     * 透過ロゴ (ユニット/ブランド) を JPEG 固定にすると背景が黒く潰れる。逆に写真まで
     * PNG にすると 1024px で数 MB になるので、形式は画像ごとに選ぶ (iOS と同じ判断)。
     */
    private fun writeDownsampled(bitmap: Bitmap, destination: File): Boolean {
        val scaled = downsample(bitmap, MAX_PIXELS)
        val alpha = scaled.hasAlpha()
        return runCatching {
            destination.outputStream().use { out ->
                val format = if (alpha) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
                if (!scaled.compress(format, JPEG_QUALITY, out)) error("compress failed")
            }
        }.onFailure {
            Log.w(TAG, "画像の書き出しに失敗: ${destination.name}", it)
            destination.delete()
        }.isSuccess
    }

    private fun downsample(bitmap: Bitmap, maxPixels: Int): Bitmap {
        val longSide = maxOf(bitmap.width, bitmap.height)
        if (longSide <= maxPixels) return bitmap
        val scale = maxPixels.toFloat() / longSide
        val width = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }

    /** この画像を保存するときの拡張子 (透過があれば png)。ファイル名を決める側で使う。 */
    private fun fileExtension(bitmap: Bitmap): String = if (bitmap.hasAlpha()) "png" else "jpg"

    /**
     * フォトピッカーの content:// を Bitmap にする。
     * 巨大な原本 (最近のスマホは 4000px 超) をそのまま載せると OOM になるので、
     * まず境界だけ読んで `inSampleSize` で 2 の冪の粗デコードに落とす。
     */
    private fun decodeBitmap(uri: Uri): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        appContext.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, bounds)
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(maxOf(bounds.outWidth, bounds.outHeight))
        }
        appContext.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, options)
        }
    }.onFailure { Log.w(TAG, "画像のデコードに失敗: $uri", it) }.getOrNull()

    /** ダウンロードした画像バイト列を Bitmap にする (一括インポート用)。 */
    fun decodeBitmap(bytes: ByteArray): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(maxOf(bounds.outWidth, bounds.outHeight))
        }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }.getOrNull()

    private fun sampleSizeFor(longSide: Int): Int {
        var sample = 1
        while (longSide / sample > MAX_PIXELS * 2) sample *= 2
        return sample
    }

    companion object {
        private const val TAG = "CustomImageStore"

        /** ブランド画像のディレクトリ名 (iOS と同じ)。 */
        const val BRAND_DIRECTORY_NAME = "custom_images_brands"

        /** 並び順とスライドショー対象フラグを保存するファイル名 (iOS と同じ)。 */
        const val MANIFEST_FILE_NAME = "manifest.json"

        /**
         * 保存に使う拡張子。透過ロゴは PNG、写真は JPEG なので両方を読み書きの対象にする。
         * ウィジェット側で画像ファイルを見分けるときも同じ判定にすること。
         */
        val IMAGE_EXTENSIONS = listOf("jpg", "png")

        private const val MAX_PIXELS = 1024
        private const val JPEG_QUALITY = 82

        fun isImageFile(name: String): Boolean = IMAGE_EXTENSIONS.any { name.endsWith(".$it") }

        /** 拡張子を除いたファイル名。[isImageFile] を通ったものにだけ使う。 */
        fun stem(name: String): String = name.substringBeforeLast('.')

        /**
         * 同一ファイル名の重複エントリを除去する (最初の出現 = プライマリ寄りを残す)。
         * 不正な manifest に同名が複数入っていると、同じ画像が複数セルに描画され、
         * 片方を消すと両方消える不具合になる。その対策。
         */
        fun dedupedByName(entries: List<GalleryImageMeta>): List<GalleryImageMeta> {
            val seen = mutableSetOf<String>()
            return entries.filter { seen.add(it.name) }
        }

        /**
         * スライドショーに出すエントリを選ぶ。`inSlideshow=true` のものだけ。
         * 1 枚も選ばれていなければ全件にフォールバックし、ウィジェットが空にならないようにする。
         * **ウィジェット側もこの規則をそのまま使うこと。**
         */
        fun slideshowFiltered(entries: List<GalleryImageMeta>): List<GalleryImageMeta> {
            val included = entries.filter { it.inSlideshow }
            return included.ifEmpty { entries }
        }

        /**
         * `manifest.json` の中身を [GalleryImageMeta] 列に解釈する。
         * 新形式 (オブジェクト配列) を優先し、旧形式 (ファイル名だけの配列) は
         * 全件スライドショー対象として移行する。
         */
        fun parseManifest(text: String): List<GalleryImageMeta> = runCatching {
            val array = JSONArray(text)
            (0 until array.length()).mapNotNull { i ->
                when (val element = array.get(i)) {
                    is JSONObject -> element.optString("name")
                        .takeIf { it.isNotEmpty() }
                        ?.let { GalleryImageMeta(it, element.optBoolean("inSlideshow", true)) }
                    is String -> element.takeIf { it.isNotEmpty() }?.let { GalleryImageMeta(it) }
                    else -> null
                }
            }
        }.getOrElse { emptyList() }

        /** [parseManifest] の逆。キー名と順序は iOS の `JSONEncoder` 出力に合わせてある。 */
        fun encodeManifest(entries: List<GalleryImageMeta>): String {
            val array = JSONArray()
            entries.forEach { entry ->
                array.put(
                    JSONObject()
                        .put("name", entry.name)
                        .put("inSlideshow", entry.inSlideshow)
                )
            }
            return array.toString()
        }
    }
}
