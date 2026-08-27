package com.fugaif.imaslivedb.data.image

import android.util.Log
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.repository.IdolRepository
import com.fugaif.imaslivedb.data.repository.StatsRepository
import com.fugaif.imaslivedb.data.repository.UnitRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONObject
import uniffi.imas_core.ImageTemplatePair
import uniffi.imas_core.imageTemplateJson
import java.net.HttpURLConnection
import java.net.URL
import java.text.Normalizer

/**
 * 「名前 → 画像 URL」の JSON を指定して、アイドル/ブランド/ユニットのカスタム画像を
 * まとめて取り込む。iOS `ImasLiveDB/Services/BulkImageImporter.swift` の 1:1 移植。
 *
 * JSON 形式は 1 階層のオブジェクト 1 個だけ:
 * ```json
 * { "天海春香": "https://example.com/haruka.png", "如月千早": "https://…" }
 * ```
 * キーは名前 (別名・よみ・ID でも引ける)、値が画像 URL。値が空文字の行は
 * 「型紙をそのまま埋めずに上げた」ケースなので失敗ではなく skip する。
 *
 * 取得した画像は [CustomImageStore] 経由で端末内にだけ保存する。
 * **サーバにも CloudKit にも送らない** (iOS も同じ)。
 */
class BulkImageImporter(
    private val store: CustomImageStore,
    private val idolRepository: IdolRepository,
    private val statsRepository: StatsRepository,
    private val unitRepository: UnitRepository,
    private val snapshots: SnapshotStoreProvider?,
) {

    /** 失敗内訳 1 件 (キー名, 理由)。最後のインポート分のみ保持する。 */
    data class Failure(val key: String, val reason: String)

    data class State(
        val isImporting: Boolean = false,
        /** 0.0〜1.0。プログレスバーにそのまま渡せる。 */
        val progress: Float = 0f,
        val statusMessage: String = "",
        val importedCount: Int = 0,
        val failedCount: Int = 0,
        val failures: List<Failure> = emptyList(),
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    // MARK: - インポート

    /**
     * アイドル画像 JSON を取得して一括ダウンロード。既存画像は上書きする。
     * JSON のキーは 名前 / よみ / ニックネーム / 別名 / idol_id のいずれかで引ける。
     */
    suspend fun importIdolImages(urlString: String) = runImport(urlString, "アイドル") {
        val nameToId = mutableMapOf<String, String>()
        idolRepository.fetchIdols().forEach { idol ->
            register(nameToId, idol.id, idol.id)
            register(nameToId, idol.name, idol.id)
            idol.nameKana?.let { register(nameToId, it, idol.id) }
            idol.nickname?.let { register(nameToId, it, idol.id) }
            idol.aliases?.split(',')?.map(String::trim)?.filter(String::isNotEmpty)
                ?.forEach { register(nameToId, it, idol.id) }
        }
        Resolution(nameToId) { id, bytes ->
            // アイドルはギャラリー方式。一括インポートは「アイコンを設定」なので既存を
            // 消して 1 枚にする (再実行で同じ絵が積み上がらない)。
            val bitmap = store.decodeBitmap(bytes) ?: return@Resolution false
            store.saveImage(bitmap, id, GalleryKind.IDOL)
            true
        }
    }

    /** ブランド画像 JSON を取得。キーは ブランド名 / 略称 / brand_id。 */
    suspend fun importBrandImages(urlString: String) = runImport(urlString, "ブランド") {
        val nameToId = mutableMapOf<String, String>()
        statsRepository.fetchBrands().forEach { brand ->
            register(nameToId, brand.id, brand.id)
            register(nameToId, brand.name, brand.id)
            register(nameToId, brand.shortName, brand.id)
        }
        Resolution(nameToId) { id, bytes ->
            val bitmap = store.decodeBitmap(bytes) ?: return@Resolution false
            store.saveBrandImage(bitmap, id)
            true
        }
    }

    /**
     * ユニット画像 JSON を取得。キーは ユニット名 / name_alt / unit_id。
     *
     * 同名ユニットが複数ある (315 STARS / Café Parade の表記ゆれ等) 場合、名前で引くと
     * どちらに入るか不定になる。常設ユニット (is_permanent) を優先して登録し、
     * 非常設の重複エントリで上書きされないようにする。
     */
    suspend fun importUnitImages(urlString: String) = runImport(urlString, "ユニット") {
        val nameToId = mutableMapOf<String, String>()
        val units = fetchAllUnits()
        // 非常設 → 常設 の順に入れ、常設が最後に勝つようにする。
        units.filterNot { it.isPermanent }.forEach { registerUnit(nameToId, it, overwrite = false) }
        units.filter { it.isPermanent }.forEach { registerUnit(nameToId, it, overwrite = true) }
        Resolution(nameToId) { id, bytes ->
            val bitmap = store.decodeBitmap(bytes) ?: return@Resolution false
            store.saveImage(bitmap, id, GalleryKind.UNIT)
            true
        }
    }

    /** アイドル/ユニット/ブランドのカスタム画像をすべて削除する。 */
    suspend fun clearAllImages() {
        store.clearAllIdolImages()
        store.clearAllUnitImages()
        store.clearAllBrandImages()
        _state.value = State(statusMessage = "カスタム画像を全削除しました")
    }

    // MARK: - 型紙 JSON

    /**
     * 画像一括インポート用の型紙 JSON。組み立て (キー順の保持・エスケープ) は
     * **共有コア (imas-core) の `image_template_json` が唯一の正**。iOS と 1 バイトも
     * 違わない出力にするため、Kotlin 側で JSON を組み立て直さない。
     *
     * 名前一覧を 1 回の FFI 呼び出しで渡し、完成した JSON 文字列を 1 回で受け取る
     * (1 ユーザー操作 = 1 FFI 呼び出しの規約)。
     */
    suspend fun idolTemplateJson(): String = templateJson(
        idolRepository.fetchIdols().map { it.name }
    )

    suspend fun brandTemplateJson(): String = templateJson(
        statsRepository.fetchBrands().map { it.shortName }
    )

    /**
     * ユニットの型紙は常設のみ。公演ごとの臨時ユニット (「〇〇 + 〇〇」等) まで並べると
     * 型紙が数百行になり、アイコンを用意したい常設ユニットが埋もれる。
     */
    suspend fun unitTemplateJson(): String = templateJson(
        fetchAllUnits().filter { it.isPermanent }.map { it.name }
    )

    private suspend fun templateJson(names: List<String>): String = withContext(Dispatchers.Default) {
        imageTemplateJson(names.map { ImageTemplatePair(key = it, value = "") })
    }

    // MARK: - 内部

    /** 名前解決表と、解決済み ID に画像バイト列を保存する手続き。 */
    private class Resolution(
        val nameToId: Map<String, String>,
        val save: suspend (id: String, bytes: ByteArray) -> Boolean,
    )

    private fun register(map: MutableMap<String, String>, key: String, id: String) {
        if (key.isEmpty()) return
        map[key] = id
        map[normalizeName(key)] = id
    }

    private fun registerUnit(map: MutableMap<String, String>, unit: ImasUnit, overwrite: Boolean) {
        listOfNotNull(unit.id, unit.name, unit.nameAlt).forEach { key ->
            listOf(key, normalizeName(key)).forEach { k ->
                if (overwrite || !map.containsKey(k)) map[k] = unit.id
            }
        }
    }

    /**
     * 全ユニット (臨時含む)。名前解決表は臨時ユニットも引けたほうが良いので全件必要。
     * `UnitRepository` の公開口は「曲ありユニット」しか返さないため、全件を持っている
     * 共有コアのスナップショットを先に見て、使えないときだけそちらへ落とす。
     */
    private suspend fun fetchAllUnits(): List<ImasUnit> =
        snapshots?.query { snapshot ->
            snapshot.unitIndexRecord().units.map {
                ImasUnit(
                    id = it.id, brandId = it.brandId, name = it.name,
                    isPermanent = it.isPermanent, nameAlt = it.nameAlt,
                )
            }
        } ?: unitRepository.fetchUnitsForList()

    private suspend fun runImport(
        urlString: String,
        label: String,
        resolve: suspend () -> Resolution,
    ) {
        val url = runCatching { URL(urlString.trim()) }.getOrNull()
        if (url == null) {
            _state.value = State(statusMessage = "無効なURLです")
            return
        }

        _state.value = State(isImporting = true, statusMessage = "データ取得中...")

        val mapping = runCatching { parseMapping(fetchBytes(url)) }.getOrNull()
        if (mapping == null) {
            _state.value = State(statusMessage = "JSONの形式が正しくありません")
            return
        }

        val resolution = runCatching { resolve() }.getOrElse {
            Log.w(TAG, "名前解決に失敗", it)
            _state.value = State(statusMessage = "エラー: ${it.message ?: "名前の解決に失敗しました"}")
            return
        }

        val total = mapping.size
        var current = 0
        var imported = 0
        val failures = mutableListOf<Failure>()

        for ((key, rawUrl) in mapping) {
            current += 1
            val trimmed = rawUrl.trim()
            // 空 URL はスキップ (型紙をそのまま埋めずに上げたケース) — failure 扱いにしない。
            if (trimmed.isNotEmpty()) {
                val id = resolution.nameToId[key] ?: resolution.nameToId[normalizeName(key)]
                val imageUrl = runCatching { URL(trimmed) }.getOrNull()
                when {
                    id == null -> failures += Failure(key, "$label ID が見つからない")
                    imageUrl == null -> failures += Failure(key, "URL が不正")
                    else -> {
                        val result = runCatching { fetchBytes(imageUrl) }
                        val bytes = result.getOrNull()
                        when {
                            bytes == null ->
                                failures += Failure(key, result.exceptionOrNull()?.message ?: "取得失敗")
                            !resolution.save(id, bytes) -> failures += Failure(key, "画像デコード失敗")
                            else -> imported += 1
                        }
                    }
                }
            }
            _state.value = _state.value.copy(
                progress = current.toFloat() / total,
                importedCount = imported,
                failedCount = failures.size,
                statusMessage = "$imported/$total ダウンロード中...",
            )
            // 配布元 (GitHub 等) を叩き過ぎないよう間隔を空ける (iOS と同じ 100ms)。
            delay(REQUEST_INTERVAL_MS)
        }

        _state.value = State(
            isImporting = false,
            progress = 1f,
            statusMessage = "完了: ${imported}件成功, ${failures.size}件失敗",
            importedCount = imported,
            failedCount = failures.size,
            failures = failures,
        )
    }

    private suspend fun fetchBytes(url: URL): ByteArray = withContext(Dispatchers.IO) {
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            instanceFollowRedirects = true
        }
        try {
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException("HTTP $code")
            connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    /** `{"名前": "URL"}` のフラットなオブジェクトだけ受け付ける (iOS の `[String: String]` と同じ)。 */
    private fun parseMapping(bytes: ByteArray): Map<String, String> {
        val json = JSONObject(bytes.toString(Charsets.UTF_8))
        return json.keys().asSequence().associateWith { json.optString(it) }
    }

    companion object {
        private const val TAG = "BulkImageImporter"
        private const val TIMEOUT_MS = 15_000
        private const val REQUEST_INTERVAL_MS = 100L

        /** 名前マッチングのゆらぎを吸収した比較用キーを作る。iOS `normalizeName` と同じ規則。 */
        fun normalizeName(source: String): String {
            // NFKC で全角/半角・互換等価字 (＝→= Ⅱ→II 等) を畳んでから、
            // 区切り類 (空白・中黒・スラッシュ・イコール) を落として小文字化する。
            val nfkc = Normalizer.normalize(source, Normalizer.Form.NFKC)
            return nfkc.filterNot { it in SEPARATORS }.lowercase()
        }

        private val SEPARATORS = setOf(' ', '　', '・', '/', '／', '=', '＝')
    }
}
