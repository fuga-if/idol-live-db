package com.fugaif.imaslivedb.ui.produce

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** 最近見た項目の種別。 */
enum class RecentKind(val raw: String) {
    EVENT("event"),
    SONG("song"),
    IDOL("idol");

    companion object {
        fun from(raw: String?): RecentKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** 最近見た項目 1 件。**名前は持たない** — 表示時にローカルのカタログから引き直す。 */
data class RecentItem(val kind: RecentKind, val entityId: String) {
    val key: String get() = "${kind.raw}:$entityId"
}

/**
 * 最近見たイベント / 曲 / アイドルを端末ローカル (SharedPreferences) に記録する。
 * iOS `RecentsService` の移植。サーバ非依存で、新しい順・同一項目は先頭へ繰り上げ・上限件数で打ち切り。
 *
 * iOS は名前も一緒に保存しているが、ここは id だけにしている。名前を焼くと改名 (ライブの
 * 正式名称の訂正など) がいつまでも履歴に残るし、どのみち表示のたびにカタログを引いて
 * 実体を解決するので、保存しておく利点が無い。
 */
class RecentsStore private constructor(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 新しい順。 */
    fun items(): List<RecentItem> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.getJSONObject(i)
                val kind = RecentKind.from(o.optString("kind")) ?: return@mapNotNull null
                val id = o.optString("id").ifEmpty { return@mapNotNull null }
                RecentItem(kind, id)
            }
        }.getOrDefault(emptyList())
    }

    /** 記録する。既存の同一項目は取り除いて先頭へ積み直す。 */
    fun record(kind: RecentKind, entityId: String) {
        if (entityId.isEmpty()) return
        val item = RecentItem(kind, entityId)
        val updated = (listOf(item) + items().filter { it.key != item.key }).take(MAX_COUNT)
        val arr = JSONArray()
        updated.forEach { arr.put(JSONObject().put("kind", it.kind.raw).put("id", it.entityId)) }
        prefs.edit().putString(KEY, arr.toString()).apply()
    }

    fun clear() = prefs.edit().remove(KEY).apply()

    companion object {
        private const val PREFS_NAME = "recent_items"
        private const val KEY = "items_v1"
        private const val MAX_COUNT = 20

        @Volatile
        private var instance: RecentsStore? = null

        fun get(context: Context): RecentsStore =
            instance ?: synchronized(this) {
                instance ?: RecentsStore(context).also { instance = it }
            }

        /**
         * ナビゲーションの行き先 (ルートテンプレート + 引数) から「最近見た」を記録する。
         *
         * 記録の口をここ 1 箇所にまとめているのは、詳細画面はどのタブからも積めるので、
         * 遷移のコールバック側に record() を撒くと必ずどこかで漏れるため。
         * ルート名と引数名は [com.fugaif.imaslivedb.ui.navigation.NavRoutes] の定義に従う。
         */
        fun recordRoute(context: Context, route: String?, arg: (String) -> String?) {
            val (kind, argName) = when (route) {
                "event_detail/{eventId}" -> RecentKind.EVENT to "eventId"
                "song_detail/{songId}" -> RecentKind.SONG to "songId"
                "idol_detail/{idolId}" -> RecentKind.IDOL to "idolId"
                else -> return
            }
            arg(argName)?.let { get(context).record(kind, it) }
        }
    }
}
