package com.fugaif.imaslivedb.data.community

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.imas_core.PendingFavorite
import uniffi.imas_core.SendOutcome
import uniffi.imas_core.pendingFavoriteIsStillQueued
import uniffi.imas_core.pendingFavoriteRetryDelaySeconds
import uniffi.imas_core.pendingFavoritesAfterAttempt
import uniffi.imas_core.pendingFavoritesDecode
import uniffi.imas_core.pendingFavoritesDiscard
import uniffi.imas_core.pendingFavoritesEncode
import uniffi.imas_core.pendingFavoritesEnqueue

/**
 * 曲のお気に入りを、みんなの集計 (`POST /favorites/toggle`、端末単位で重複を除く) に送る。
 * iOS `UserMarkService.setBool` + `PendingCommunityActions` と同じ振る舞い:
 * 付け外しのたびに背景で送り、失敗したら端末に積んでおき、あとで送り直す。
 * 積む・置き換える・待つ・諦めるの規則と保存形式は imas-core (`pending_favorites`)。
 * ここは保存と送信だけ。
 *
 * @param send 1 件送る。失敗したら例外を投げる。
 * @param sleep 送り直す前に待つ (テストでは待たない)。
 */
class FavoriteAggregation(
    context: Context,
    private val scope: CoroutineScope,
    private val sleep: suspend (seconds: Double) -> Unit = { delay((it * 1000).toLong()) },
    private val send: suspend (songId: String, value: Boolean) -> Unit
) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    /** 列の読み書きの排他。送信や待ちの間は持たない (その間の付け外しを止めない)。 */
    private val lock = Mutex()
    /** 送り直しを重ねない。 */
    private val flushing = Mutex()

    /** お気に入りを付け外しした直後に呼ぶ。送るのは背景で、画面は待たない。 */
    fun report(songId: String, value: Boolean) {
        scope.launch {
            try {
                send(songId, value)
                // 送れたら、同じ曲の積み残し (前に送れなかった古い値) は捨てる。残すと前面に
                // 出たときに古い値を送り直して、集計が戻る。
                update { pendingFavoritesDiscard(it, songId) }
            } catch (e: Exception) {
                Log.w(TAG, "favorite toggle failed, enqueue: $songId", e)
                update { pendingFavoritesEnqueue(it, songId, value, System.currentTimeMillis() / 1000.0) }
            }
        }
    }

    /**
     * 積んである未送信を送り直す (アプリが前面に出たとき)。始めた時点の列を 1 件ずつ回し、
     * 結果はそのつど今の列に反映する (待つ間に積み直された曲の結果は捨てられる)。
     */
    suspend fun flushPending() {
        if (!flushing.tryLock()) return
        try {
            for (action in lock.withLock { load() }) {
                if (!isStillQueued(action)) continue
                val wait = pendingFavoriteRetryDelaySeconds(action.retryCount)
                if (wait > 0) {
                    sleep(wait)
                    if (!isStillQueued(action)) continue
                }
                val outcome = try {
                    send(action.songId, action.value)
                    SendOutcome.SENT
                } catch (e: Exception) {
                    Log.w(TAG, "favorite retry failed: ${action.songId} (${action.retryCount})", e)
                    SendOutcome.FAILED
                }
                update { pendingFavoritesAfterAttempt(it, action, outcome) }
            }
        } finally {
            flushing.unlock()
        }
    }

    private suspend fun isStillQueued(action: PendingFavorite): Boolean =
        lock.withLock { pendingFavoriteIsStillQueued(load(), action) }

    private suspend fun update(change: (List<PendingFavorite>) -> List<PendingFavorite>) = lock.withLock {
        val before = load()
        val after = change(before)
        if (after != before) save(after)
    }

    private fun load(): List<PendingFavorite> =
        pendingFavoritesDecode(prefs.getString(KEY_ACTIONS, null) ?: "[]")

    private fun save(actions: List<PendingFavorite>) {
        prefs.edit().putString(KEY_ACTIONS, pendingFavoritesEncode(actions)).apply()
    }

    private companion object {
        const val TAG = "FavoriteAggregation"
        const val PREFS_NAME = "pending_favorite_actions"
        const val KEY_ACTIONS = "actions"
    }
}
