package com.fugaif.imaslivedb.data.games

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

// =============================================================================
// ティアー表の保存。曲とアイドルで 1 枚ずつ。iOS TierListBoard.swift の移植。
//
// 並べるのは利用者の手 (好みの判断を機械に任せない)。コアが持つのは段の並びと色、
// ソートメーカーの順位からのたたき台 (`tierListAssignFromRanking`) だけ。
// =============================================================================

data class TierListBoard(
    val subject: SortMakerSubject,
    /** 対象の id 列 (未分類の並び順にも使う)。 */
    val itemIds: List<String>,
    /** id → 段の添字 (0 = S)。載っていない id は未分類。 */
    val placements: Map<String, Int> = emptyMap(),
    val scopeLabel: String,
    /** ソートメーカーの結果から作ったときのたたき台 (「たたき台に戻す」用)。 */
    val suggested: Map<String, Int>? = null,
    /** 利用者が付けた表の名前 (null = 「好きな曲ティアー表」等の既定)。 */
    val title: String? = null,
    /** 段ごとの名前の上書き (添字は段。null / 範囲外 / 要素が null = S〜D の既定名)。 */
    val tierLabels: List<String?>? = null,
    val savedAt: Long = System.currentTimeMillis()
) {
    val unplacedIds: List<String> get() = itemIds.filter { placements[it] == null }

    fun idsInTier(tier: Int): List<String> = itemIds.filter { placements[it] == tier }

    /** 見出し・共有に出す表の名前。 */
    val displayTitle: String get() = displayTitle(ignoringCustom = false)

    /** [ignoringCustom] なら利用者の名前を無視した既定の名前 (入力欄の見本用)。 */
    fun displayTitle(ignoringCustom: Boolean): String {
        if (!ignoringCustom && title != null) return title
        return if (subject == SortMakerSubject.SONG) "好きな曲ティアー表" else "好きなアイドルティアー表"
    }

    /** 段の名前 (上書きがあればそれ、無ければコアの既定名)。 */
    fun label(ofTier: Int, default: String): String {
        val custom = tierLabels?.getOrNull(ofTier)
        return custom ?: default
    }
}

/**
 * ローカル保存 (SharedPreferences の JSON)。保存の形は [SortMakerStore] と同じ流儀。
 * iOS は UserDefaults の `tier_list_boards_v1`。
 */
class TierListStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _boards = MutableStateFlow(load())
    val boards: StateFlow<Map<SortMakerSubject, TierListBoard>> = _boards.asStateFlow()

    fun board(subject: SortMakerSubject): TierListBoard? = _boards.value[subject]

    fun save(b: TierListBoard) {
        _boards.value = _boards.value + (b.subject to b)
        persist()
    }

    fun clear(subject: SortMakerSubject) {
        if (!_boards.value.containsKey(subject)) return
        _boards.value = _boards.value - subject
        persist()
    }

    private fun persist() {
        val array = JSONArray()
        _boards.value.values.forEach { array.put(encode(it)) }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    private fun load(): Map<SortMakerSubject, TierListBoard> {
        val raw = prefs.getString(KEY, null) ?: return emptyMap()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { decode(array.getJSONObject(it)) }
                .associateBy { it.subject }
        } catch (e: Exception) {
            // 壊れた保存は捨てる (「つくりかけ」が出せないだけで、遊ぶのには困らない)。
            emptyMap()
        }
    }

    companion object {
        private const val PREFS_NAME = "tier_list_store"
        private const val KEY = "tier_list_boards_v1"

        internal fun encode(b: TierListBoard): JSONObject = JSONObject().apply {
            put("subject", b.subject.key)
            put("itemIds", JSONArray(b.itemIds))
            put("placements", JSONObject().apply { b.placements.forEach { (id, tier) -> put(id, tier) } })
            put("scopeLabel", b.scopeLabel)
            b.suggested?.let { suggested ->
                put("suggested", JSONObject().apply { suggested.forEach { (id, tier) -> put(id, tier) } })
            }
            b.title?.let { put("title", it) }
            b.tierLabels?.let { labels ->
                put("tierLabels", JSONArray().apply { labels.forEach { put(it ?: JSONObject.NULL) } })
            }
            put("savedAt", b.savedAt)
        }

        internal fun decode(o: JSONObject): TierListBoard? {
            val subject = SortMakerSubject.fromKey(o.optString("subject")) ?: return null
            val itemIds = o.optJSONArray("itemIds") ?: JSONArray()
            val placementsJson = o.optJSONObject("placements")
            val placements = mutableMapOf<String, Int>()
            placementsJson?.keys()?.forEach { id -> placements[id] = placementsJson.optInt(id) }
            val suggestedJson = o.optJSONObject("suggested")
            val suggested = if (suggestedJson != null) {
                val map = mutableMapOf<String, Int>()
                suggestedJson.keys().forEach { id -> map[id] = suggestedJson.optInt(id) }
                map
            } else null
            // 古い保存 (title/tierLabels 追加前) を読んでも欠けたキーは null 扱いになるだけで壊れない。
            val title = if (o.has("title")) o.optString("title").takeIf { it.isNotEmpty() } else null
            val tierLabelsJson = o.optJSONArray("tierLabels")
            val tierLabels = tierLabelsJson?.let { arr ->
                (0 until arr.length()).map { i -> if (arr.isNull(i)) null else arr.getString(i) }
            }
            return TierListBoard(
                subject = subject,
                itemIds = (0 until itemIds.length()).map { itemIds.getString(it) },
                placements = placements,
                scopeLabel = o.optString("scopeLabel"),
                suggested = suggested,
                title = title,
                tierLabels = tierLabels,
                savedAt = o.optLong("savedAt")
            )
        }
    }
}
