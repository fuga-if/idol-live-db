package com.fugaif.imaslivedb.ui.search

import android.content.Context
import com.fugaif.imaslivedb.data.repository.SearchScope

/**
 * 検索履歴の保管 (iOS `SearchHistoryManager` の移植)。
 *
 * スコープごとに別キーで持ち、新しい順に最大 [MAX_ITEMS] 件。「すべて」スコープは
 * 3 スコープをラウンドロビンでマージして見せる (単純連結だと1スコープが先頭を独占するため)。
 */
class SearchHistoryStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 保存対象のスコープ (ALL は保存先を持たず、3スコープの合成で表示する)。 */
    private fun storageScopes(scope: SearchScope): List<SearchScope> = when (scope) {
        SearchScope.ALL -> listOf(SearchScope.EVENTS, SearchScope.SONGS, SearchScope.IDOLS)
        else -> listOf(scope)
    }

    private fun key(scope: SearchScope) = "search_history_${scope.name.lowercase()}"

    private fun rawHistory(scope: SearchScope): List<String> =
        prefs.getString(key(scope), null)
            ?.split(SEPARATOR)
            ?.filter { it.isNotBlank() }
            ?: emptyList()

    private fun store(scope: SearchScope, items: List<String>) {
        prefs.edit().putString(key(scope), items.joinToString(SEPARATOR)).apply()
    }

    /** 表示用の履歴。ALL は各スコープの新しい方から順に取り出して偏りを均す。 */
    fun history(scope: SearchScope): List<String> {
        val lists = storageScopes(scope).map { rawHistory(it) }
        if (lists.size == 1) return lists.first().take(MAX_ITEMS)

        val seen = LinkedHashSet<String>()
        val maxCount = lists.maxOfOrNull { it.size } ?: 0
        for (index in 0 until maxCount) {
            for (list in lists) {
                list.getOrNull(index)?.let { seen.add(it) }
            }
        }
        return seen.toList().take(MAX_ITEMS)
    }

    /**
     * 検索語を記録する。ALL スコープでは、実際にヒットしたスコープにだけ記録する
     * (常に固定スコープへ記録すると、曲に関係ない語が楽曲の履歴を汚染する)。
     */
    fun record(query: String, scopes: List<SearchScope>) {
        val trimmed = query.trim().take(MAX_QUERY_LENGTH)
        if (trimmed.isEmpty()) return
        for (scope in scopes) {
            if (scope == SearchScope.ALL) continue
            val items = (listOf(trimmed) + rawHistory(scope).filter { it != trimmed }).take(MAX_ITEMS)
            store(scope, items)
        }
    }

    /** 履歴1件だけを削除する。 */
    fun remove(query: String, scope: SearchScope) {
        for (s in storageScopes(scope)) {
            store(s, rawHistory(s).filter { it != query })
        }
    }

    /** 表示中スコープの履歴をまとめて消す。 */
    fun clear(scope: SearchScope) {
        for (s in storageScopes(scope)) {
            prefs.edit().remove(key(s)).apply()
        }
    }

    private companion object {
        const val PREFS_NAME = "search_history"
        // 検索語に現れない制御文字を区切りにする (曲名に「,」「/」等は普通に出るため)。
        const val SEPARATOR = ""
        const val MAX_ITEMS = 15
        const val MAX_QUERY_LENGTH = 100
    }
}
