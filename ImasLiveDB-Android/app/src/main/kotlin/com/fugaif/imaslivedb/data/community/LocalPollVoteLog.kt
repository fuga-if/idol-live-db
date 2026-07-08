package com.fugaif.imaslivedb.data.community

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

/**
 * 自分が「みんなの投票」のお題に投票した履歴をローカル (SharedPreferences) に残す。iOS LocalPollVoteLog の移植。
 * サーバ側に my-votes API が無いため、クライアントで投票成功時に recordVote/removeVote を呼び、
 * マイ投票履歴画面 (MyVotesScreen) のソースにする。1お題で複数エントリ (推し3票) に投票できるため
 * `pollId -> 選んだ entityId の Set` で持つ。
 */
class LocalPollVoteLog(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _votes = MutableStateFlow(load())
    /** pollId -> 自分が投票した entityId のセット。 */
    val votes: StateFlow<Map<String, Set<String>>> = _votes.asStateFlow()

    fun entityIds(pollId: String): Set<String> = _votes.value[pollId] ?: emptySet()

    fun recordVote(pollId: String, entityId: String) {
        val current = _votes.value[pollId] ?: emptySet()
        if (entityId in current) return
        val updated = _votes.value + (pollId to (current + entityId))
        _votes.value = updated
        save(updated)
    }

    fun removeVote(pollId: String, entityId: String) {
        val current = _votes.value[pollId] ?: return
        if (entityId !in current) return
        val remaining = current - entityId
        val updated = _votes.value.toMutableMap()
        if (remaining.isEmpty()) updated.remove(pollId) else updated[pollId] = remaining
        _votes.value = updated
        save(updated)
    }

    private fun load(): Map<String, Set<String>> {
        val raw = prefs.getString(KEY, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            json.keys().asSequence().associateWith { pollId ->
                val arr = json.getJSONArray(pollId)
                (0 until arr.length()).map { arr.getString(it) }.toSet()
            }
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun save(votes: Map<String, Set<String>>) {
        val json = JSONObject()
        votes.forEach { (pollId, entityIds) -> json.put(pollId, JSONArray(entityIds.sorted())) }
        prefs.edit().putString(KEY, json.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "local_poll_vote_log"
        private const val KEY = "votes_v1"
    }
}
