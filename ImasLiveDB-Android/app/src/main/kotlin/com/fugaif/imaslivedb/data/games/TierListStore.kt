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
    val savedAt: Long = System.currentTimeMillis()
) {
    val unplacedIds: List<String> get() = itemIds.filter { placements[it] == null }

    fun idsInTier(tier: Int): List<String> = itemIds.filter { placements[it] == tier }
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
            return TierListBoard(
                subject = subject,
                itemIds = (0 until itemIds.length()).map { itemIds.getString(it) },
                placements = placements,
                scopeLabel = o.optString("scopeLabel"),
                suggested = suggested,
                savedAt = o.optLong("savedAt")
            )
        }
    }
}
