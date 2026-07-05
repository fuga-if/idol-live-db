package com.fugaif.imaslivedb.data.community

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

/**
 * 自分が投稿した貢献の累計をローカル (SharedPreferences) に記録する。iOS LocalContributionLog の移植。
 * サーバの badges API に内訳が無いため、クライアントで投稿成功時に record() で +1 する。
 * 再インストールすると消える (端末ローカル記録の割り切り)。
 */
class LocalContributionLog(context: Context) {

    enum class Kind(val label: String) {
        SETLIST_EDIT("セトリ編集"),
        CALL_RESPONSE("コーレス"),
        VIDEO("動画"),
        TAG("タグ"),
    }

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _counts = MutableStateFlow(load())
    val counts: StateFlow<Map<Kind, Int>> = _counts.asStateFlow()

    val total: Int get() = _counts.value.values.sum()

    fun count(of: Kind): Int = _counts.value[of] ?: 0

    fun record(kind: Kind) {
        val updated = _counts.value.toMutableMap()
        updated[kind] = (updated[kind] ?: 0) + 1
        _counts.value = updated
        save(updated)
    }

    private fun load(): Map<Kind, Int> {
        val raw = prefs.getString(KEY, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            Kind.entries.mapNotNull { kind -> if (json.has(kind.name)) kind to json.getInt(kind.name) else null }.toMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun save(counts: Map<Kind, Int>) {
        val json = JSONObject()
        counts.forEach { (kind, n) -> json.put(kind.name, n) }
        prefs.edit().putString(KEY, json.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "local_contribution_log"
        private const val KEY = "counts_v1"
    }
}
