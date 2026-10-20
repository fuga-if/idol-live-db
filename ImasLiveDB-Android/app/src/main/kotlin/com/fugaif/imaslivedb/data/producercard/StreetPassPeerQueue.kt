package com.fugaif.imaslivedb.data.producercard

import uniffi.imas_core.StreetpassTuning

/**
 * すれちがいで繋ぐ相手の待ち行列 (iOS `StreetPassService` の待ち行列と同じ決まり)。数字はコアの `streetpassTuning`。
 *
 * - 端末の識別子ごとに「次に繋いでよい時刻」を持つ。読めた (既に読んだ人も) なら `reconnectAfterReadSeconds`、
 *   失敗なら `reconnectAfterFailureSeconds` 後まで繋がない。
 * - 行列の要素は見つけた時刻を持ち、取り出すときに `queueStaleSeconds` より古いものは捨てる
 *   (もう近くにいない)。長さが `queueMax` を超えたら古いものから捨てる。同じ識別子は 1 つだけ
 *   (見つけ直したら時刻を新しくして後ろへ)。
 *
 * スキャンの知らせ (Binder のスレッド) と読み手 (Main) の両方から触るので、全部を 1 つの鍵で守る。
 * 時刻は呼ぶ側が渡す (ミリ秒。端末では elapsedRealtime)。
 */
class StreetPassPeerQueue<T>(private val tuning: StreetpassTuning) {
    private class Entry<T>(val item: T, val foundAt: Long)

    private val waiting = LinkedHashMap<String, Entry<T>>()
    private val nextAllowed = HashMap<String, Long>()

    /** 今この相手に繋いでよいか (次に繋いでよい時刻を過ぎた)。 */
    @Synchronized
    fun mayConnect(id: String, nowMs: Long): Boolean {
        val at = nextAllowed[id] ?: return true
        if (nowMs >= at) {
            nextAllowed.remove(id)
            return true
        }
        return false
    }

    /**
     * 見つけた相手を行列に入れる。新しく入ったときだけ true (見つけ直し・まだ繋がない相手は false)。
     * スキャンの結果はこれで弾いてから Main に移る。
     */
    @Synchronized
    fun offer(id: String, item: T, nowMs: Long): Boolean {
        if (!mayConnect(id, nowMs)) return false
        val again = waiting.remove(id) != null
        waiting[id] = Entry(item, nowMs)
        while (waiting.size > tuning.queueMax.toInt()) {
            waiting.remove(waiting.keys.first())
        }
        return !again
    }

    /** 次に繋ぐ相手 (古すぎるものは捨てる)。いなければ null。 */
    @Synchronized
    fun take(nowMs: Long): Pair<String, T>? {
        val stale = tuning.queueStaleSeconds.toLong() * 1000
        while (waiting.isNotEmpty()) {
            val id = waiting.keys.first()
            val entry = waiting.remove(id) ?: continue
            if (nowMs - entry.foundAt <= stale) return id to entry.item
        }
        return null
    }

    /** 繋ぎ終えた。[read] は読めた (または既に読んだ人だった)。 */
    @Synchronized
    fun finished(id: String, read: Boolean, nowMs: Long) {
        val seconds = if (read) tuning.reconnectAfterReadSeconds else tuning.reconnectAfterFailureSeconds
        nextAllowed[id] = nowMs + seconds.toLong() * 1000
    }

    @Synchronized
    fun contains(id: String): Boolean = id in waiting

    @Synchronized
    fun size(): Int = waiting.size

    /** 止めたときは行列だけ捨てる (次に繋いでよい時刻は [reset] まで覚えておく)。 */
    @Synchronized
    fun clearWaiting() = waiting.clear()

    @Synchronized
    fun reset() {
        waiting.clear()
        nextAllowed.clear()
    }
}
