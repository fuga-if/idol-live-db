package com.fugaif.imaslivedb.data.games

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import uniffi.imas_core.tierListTiers
import java.util.UUID

// =============================================================================
// ティアー表の保存。端末の中に何枚でも持てる (曲・アイドルごとに一覧から開き直す)。
// iOS TierListBoard.swift の移植。
//
// 並べるのは利用者の手 (好みの判断を機械に任せない)。コアが持つのは段の既定 (名前と色)、
// 段の数の上限、色の候補、名前の整え方、ソートメーカーの順位からのたたき台だけ。
// =============================================================================

/** 段 1 つ。並び替え・削除しても振り分けが崩れないように、振り分けは段の id で持つ。 */
data class TierDef(
    val id: String = UUID.randomUUID().toString(),
    val label: String,
    val colorSeed: String
) {
    companion object {
        /** コアの既定の S〜D。 */
        fun defaults(): List<TierDef> = tierListTiers().map { TierDef(label = it.label, colorSeed = it.colorSeed) }
    }
}

data class TierListBoard(
    val id: String = UUID.randomUUID().toString(),
    val subject: SortMakerSubject,
    /** 対象の id 列 (未分類の並び順にも使う)。 */
    val itemIds: List<String>,
    /** 段 (上から)。 */
    val tiers: List<TierDef> = TierDef.defaults(),
    /** 項目 id → 段の id。載っていない項目は未分類。 */
    val placements: Map<String, String> = emptyMap(),
    val scopeLabel: String,
    /** ソートメーカーの結果から作ったときのたたき台 (「たたき台に戻す」用)。 */
    val suggested: Map<String, String>? = null,
    /** 利用者が付けた表の名前 (null = 「好きな曲ティアー表」等の既定)。 */
    val title: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val savedAt: Long = System.currentTimeMillis()
) {
    val unplacedIds: List<String> get() = itemIds.filter { tierIndexOf(it) == null }
    val placedCount: Int get() = itemIds.size - unplacedIds.size

    fun idsInTier(tierId: String): List<String> = itemIds.filter { placements[it] == tierId }

    /** 項目が今いる段の添字 (未分類・消えた段なら null)。 */
    fun tierIndexOf(itemId: String): Int? {
        val tierId = placements[itemId] ?: return null
        val idx = tiers.indexOfFirst { it.id == tierId }
        return if (idx >= 0) idx else null
    }

    /** 見出し・共有に出す表の名前。 */
    val displayTitle: String get() = title ?: defaultTitle

    val defaultTitle: String
        get() = if (subject == SortMakerSubject.SONG) "好きな曲ティアー表" else "好きなアイドルティアー表"

    companion object {
        fun create(subject: SortMakerSubject, itemIds: List<String>, scopeLabel: String): TierListBoard =
            TierListBoard(subject = subject, itemIds = itemIds, scopeLabel = scopeLabel)
    }
}

/**
 * ローカル保存 (SharedPreferences の JSON)。端末に何枚でも持てる (新しく触ったものが先)。
 * iOS は UserDefaults の `tier_list_boards_v2` (旧 `tier_list_boards_v1` は読み替えて捨てる)。
 */
class TierListStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _boards = MutableStateFlow(loadAndMigrate())
    val boards: StateFlow<List<TierListBoard>> = _boards.asStateFlow()

    fun boardsFor(subject: SortMakerSubject): List<TierListBoard> = _boards.value.filter { it.subject == subject }

    fun find(id: String): TierListBoard? = _boards.value.firstOrNull { it.id == id }

    fun save(b: TierListBoard) {
        val list = _boards.value.toMutableList()
        val i = list.indexOfFirst { it.id == b.id }
        if (i >= 0) list[i] = b else list.add(b)
        list.sortByDescending { it.savedAt }
        _boards.value = list
        persist()
    }

    fun delete(id: String) {
        if (_boards.value.none { it.id == id }) return
        _boards.value = _boards.value.filterNot { it.id == id }
        persist()
    }

    private fun persist() {
        val array = JSONArray()
        _boards.value.forEach { array.put(encode(it)) }
        prefs.edit().putString(KEY_V2, array.toString()).apply()
    }

    private fun loadAndMigrate(): List<TierListBoard> {
        val v2 = prefs.getString(KEY_V2, null)
        if (v2 != null) {
            return try {
                val array = JSONArray(v2)
                (0 until array.length()).mapNotNull { decode(array.getJSONObject(it)) }
                    .sortedByDescending { it.savedAt }
            } catch (e: Exception) {
                emptyList()
            }
        }
        val v1 = prefs.getString(KEY_V1_LEGACY, null) ?: return emptyList()
        val migrated = try {
            val array = JSONArray(v1)
            (0 until array.length()).mapNotNull { decodeLegacyV1(array.getJSONObject(it)) }
        } catch (e: Exception) {
            emptyList()
        }
        if (migrated.isNotEmpty()) {
            val array = JSONArray()
            migrated.forEach { array.put(encode(it)) }
            prefs.edit().putString(KEY_V2, array.toString()).remove(KEY_V1_LEGACY).apply()
        } else {
            prefs.edit().remove(KEY_V1_LEGACY).apply()
        }
        return migrated.sortedByDescending { it.savedAt }
    }

    companion object {
        private const val PREFS_NAME = "tier_list_store"
        private const val KEY_V2 = "tier_list_boards_v2"

        /** 1 種類 1 枚・段は添字で持っていた頃の保存 (2026-10-01 の一時期だけ)。読み替えて捨てる。 */
        private const val KEY_V1_LEGACY = "tier_list_boards_v1"

        internal fun encode(b: TierListBoard): JSONObject = JSONObject().apply {
            put("id", b.id)
            put("subject", b.subject.key)
            put("itemIds", JSONArray(b.itemIds))
            put("tiers", JSONArray().apply {
                b.tiers.forEach { t ->
                    put(JSONObject().apply { put("id", t.id); put("label", t.label); put("colorSeed", t.colorSeed) })
                }
            })
            put("placements", JSONObject().apply { b.placements.forEach { (id, tierId) -> put(id, tierId) } })
            put("scopeLabel", b.scopeLabel)
            b.suggested?.let { suggested ->
                put("suggested", JSONObject().apply { suggested.forEach { (id, tierId) -> put(id, tierId) } })
            }
            b.title?.let { put("title", it) }
            put("createdAt", b.createdAt)
            put("savedAt", b.savedAt)
        }

        internal fun decode(o: JSONObject): TierListBoard? {
            val subject = SortMakerSubject.fromKey(o.optString("subject")) ?: return null
            val itemIdsJson = o.optJSONArray("itemIds") ?: JSONArray()
            val tiersJson = o.optJSONArray("tiers")
            val tiers = if (tiersJson != null && tiersJson.length() > 0) {
                (0 until tiersJson.length()).map { i ->
                    val t = tiersJson.getJSONObject(i)
                    TierDef(id = t.optString("id"), label = t.optString("label"), colorSeed = t.optString("colorSeed"))
                }
            } else {
                TierDef.defaults()
            }
            val placementsJson = o.optJSONObject("placements")
            val placements = mutableMapOf<String, String>()
            placementsJson?.keys()?.forEach { id -> placements[id] = placementsJson.optString(id) }
            val suggestedJson = o.optJSONObject("suggested")
            val suggested = if (suggestedJson != null) {
                val map = mutableMapOf<String, String>()
                suggestedJson.keys().forEach { id -> map[id] = suggestedJson.optString(id) }
                map
            } else null
            val title = if (o.has("title")) o.optString("title").takeIf { it.isNotEmpty() } else null
            val id = o.optString("id").takeIf { it.isNotEmpty() } ?: UUID.randomUUID().toString()
            val savedAt = o.optLong("savedAt")
            return TierListBoard(
                id = id,
                subject = subject,
                itemIds = (0 until itemIdsJson.length()).map { itemIdsJson.getString(it) },
                tiers = tiers,
                placements = placements,
                scopeLabel = o.optString("scopeLabel"),
                suggested = suggested,
                title = title,
                createdAt = if (o.has("createdAt")) o.optLong("createdAt") else savedAt,
                savedAt = savedAt
            )
        }

        /** 旧形式 (添字の振り分け・段名の上書きのみ) を読み替える。 */
        private fun decodeLegacyV1(o: JSONObject): TierListBoard? {
            val subject = SortMakerSubject.fromKey(o.optString("subject")) ?: return null
            val itemIdsJson = o.optJSONArray("itemIds") ?: JSONArray()
            var tiers = TierDef.defaults()
            val tierLabelsJson = o.optJSONArray("tierLabels")
            if (tierLabelsJson != null) {
                tiers = tiers.mapIndexed { i, t ->
                    if (i < tierLabelsJson.length() && !tierLabelsJson.isNull(i)) t.copy(label = tierLabelsJson.getString(i)) else t
                }
            }
            fun convert(m: JSONObject?): Map<String, String> {
                if (m == null) return emptyMap()
                val out = mutableMapOf<String, String>()
                m.keys().forEach { id -> tiers.getOrNull(m.optInt(id))?.let { out[id] = it.id } }
                return out
            }
            val placements = convert(o.optJSONObject("placements"))
            val suggestedJson = o.optJSONObject("suggested")
            val suggested = if (suggestedJson != null) convert(suggestedJson) else null
            val title = if (o.has("title")) o.optString("title").takeIf { it.isNotEmpty() } else null
            val savedAt = o.optLong("savedAt")
            return TierListBoard(
                subject = subject,
                itemIds = (0 until itemIdsJson.length()).map { itemIdsJson.getString(it) },
                tiers = tiers,
                placements = placements,
                scopeLabel = o.optString("scopeLabel"),
                suggested = suggested,
                title = title,
                createdAt = savedAt,
                savedAt = savedAt
            )
        }
    }
}
