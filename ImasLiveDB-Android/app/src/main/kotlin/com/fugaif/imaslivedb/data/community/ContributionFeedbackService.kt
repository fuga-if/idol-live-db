package com.fugaif.imaslivedb.data.community

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.auth.AuthService
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import uniffi.imas_core.ShowCreditInput
import uniffi.imas_core.ShowCreditLine
import uniffi.imas_core.showCreditLines
import uniffi.imas_core.showViewDecision
import java.net.URLEncoder

/**
 * データを入れた人への手応え (自分の編集に付いた Good・自分が入れたセトリの先週の閲覧数) と、
 * 公演ページの奥付。iOS `ContributionFeedbackStore` + `ContributionFeedbackAPI` の移植。
 *
 * 対象はアプリからの編集だけ。歌詞の投稿はサーバの別の表に入るので、どれにも出ない。
 * - Good の新着: 最後に見た Good の時刻より後を新着として数える。「マイ投稿」を閉じたら既読。
 * - 公演の閲覧: 1 端末 1 週 1 公演 1 回だけ送る (判定はコア `showViewDecision`)。
 * - 奥付に名前を載せるか: サーバの設定。写しは [AuthService] の状態に持つ。
 */
class ContributionFeedbackService(
    context: Context,
    private val http: WorkerHttpClient,
    private val authService: AuthService
) {
    data class ReceivedGood(
        val batchId: Int,
        val summary: String?,
        val recordType: String?,
        val goodCount: Int,
        val newGoodCount: Int,
        /** 最後に Good が付いた時刻 (epoch ミリ秒)。 */
        val latestGoodAt: Long
    )

    data class SetlistReach(val week: String, val viewers: Int, val shows: Int)

    data class Feedback(val goods: List<ReceivedGood>, val newGoodTotal: Int, val setlistReach: SetlistReach)

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _feedback = MutableStateFlow<Feedback?>(null)
    /** 最新の手応え。未ログイン・未取得は null。 */
    val feedback: StateFlow<Feedback?> = _feedback.asStateFlow()

    @Volatile private var lastFetchedMs = 0L
    /** 公演ごとの奥付 (取った時刻つき)。サーバ側のエッジと同じ 10 分で取り直す。 */
    private val creditsCache = HashMap<String, Pair<List<ShowCreditLine>, Long>>()
    /** 閲覧の記録の読み書きを 1 本にする (続けて開いた公演の記録で上書きしないため)。 */
    private val viewMutex = Mutex()

    init {
        authService.addSignOutListener { resetForSignOut() }
    }

    /** 手応えを取り直す。`force` でなければ 10 分以内の再取得はしない。 */
    suspend fun refresh(force: Boolean = false) = withContext(Dispatchers.IO) {
        if (!authService.state.value.isSignedIn) {
            _feedback.value = null
            return@withContext
        }
        val now = System.currentTimeMillis()
        if (!force && lastFetchedMs != 0L && now - lastFetchedMs < REFRESH_INTERVAL_MS) return@withContext
        try {
            val since = prefs.getLong(KEY_SEEN_GOOD_AT, 0L)
            val res = http.request("GET", "/me/feedback?since=$since")
            if (!res.isSuccess || res.body.isNullOrEmpty()) {
                Log.w(TAG, "feedback -> HTTP ${res.code}")
                return@withContext
            }
            _feedback.value = parseFeedback(JSONObject(res.body))
            lastFetchedMs = now
        } catch (e: Exception) {
            Log.w(TAG, "feedback failed: ${e.message}")
        }
    }

    /** 届いた Good を見た (「マイ投稿」を閉じた)。いまの新着を既読にし、手元の新着の数も 0 にする。 */
    fun markGoodsSeen() {
        val current = _feedback.value ?: return
        val latest = current.goods.maxOfOrNull { it.latestGoodAt } ?: return
        if (latest <= prefs.getLong(KEY_SEEN_GOOD_AT, 0L)) return
        prefs.edit().putLong(KEY_SEEN_GOOD_AT, latest).apply()
        _feedback.value = current.copy(goods = current.goods.map { it.copy(newGoodCount = 0) }, newGoodTotal = 0)
    }

    /** 公演ページを開いた。今週まだ送っていなければ送る。失敗したら記録から外し、次に開いたとき送り直す。 */
    suspend fun reportShowView(showId: String) = withContext(Dispatchers.IO) {
        val decision = viewMutex.withLock {
            val d = showViewDecision(
                storedWeek = prefs.getString(KEY_VIEW_WEEK, "") ?: "",
                reported = readReported(),
                showId = showId,
                nowEpochSeconds = System.currentTimeMillis() / 1000
            )
            prefs.edit()
                .putString(KEY_VIEW_WEEK, d.week)
                .putString(KEY_VIEW_REPORTED, JSONArray(d.reportedAfter).toString())
                .apply()
            d
        }
        if (!decision.report) return@withContext
        val ok = try {
            http.request("POST", "/shows/views", JSONObject().put("show_ids", JSONArray(listOf(showId))),
                authorized = false).isSuccess
        } catch (e: Exception) {
            false
        }
        if (!ok) viewMutex.withLock {
            prefs.edit().putString(KEY_VIEW_REPORTED, JSONArray(readReported().filter { it != showId }).toString()).apply()
        }
    }

    private fun readReported(): List<String> =
        prefs.getString(KEY_VIEW_REPORTED, null)?.let { raw ->
            runCatching { JSONArray(raw).let { a -> (0 until a.length()).map { a.getString(it) } } }.getOrNull()
        } ?: emptyList()

    /** サインアウト。アカウントごとの値 (既読の位置・手応え) を捨てる。閲覧の記録は端末の値なので残す。 */
    private fun resetForSignOut() {
        _feedback.value = null
        lastFetchedMs = 0L
        prefs.edit().remove(KEY_SEEN_GOOD_AT).apply()
    }

    /** 公演の奥付の行 (並びと「ほか N 人」はコア `showCreditLines`)。取れなければ空。 */
    suspend fun creditLines(showId: String): List<ShowCreditLine> = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        synchronized(creditsCache) { creditsCache[showId] }
            ?.takeIf { now - it.second < CREDITS_TTL_MS }?.let { return@withContext it.first }
        try {
            val res = http.request("GET", "/shows/${enc(showId)}/credits", authorized = false)
            if (!res.isSuccess || res.body.isNullOrEmpty()) return@withContext emptyList()
            val json = JSONObject(res.body)
            val lines = showCreditLines(role(json.optJSONObject("setlist")), role(json.optJSONObject("performers")))
            synchronized(creditsCache) { creditsCache[showId] = lines to now }
            lines
        } catch (e: Exception) {
            Log.w(TAG, "credits failed: ${e.message}")
            emptyList()
        }
    }

    /** 奥付に名前を載せるかを切り替える。サーバが受け付けた値を写す。失敗は例外。 */
    suspend fun setCreditOptIn(isOn: Boolean) = withContext(Dispatchers.IO) {
        val res = http.request("POST", "/users/me/credit", JSONObject().put("credit_opt_in", isOn))
        if (!res.isSuccess || res.body.isNullOrEmpty()) throw IllegalStateException("設定を保存できませんでした (HTTP ${res.code})")
        authService.adoptCreditOptIn(JSONObject(res.body).optBoolean("creditOptIn", isOn))
        synchronized(creditsCache) { creditsCache.clear() }
    }

    private fun role(o: JSONObject?): ShowCreditInput {
        val names = o?.optJSONArray("names")?.let { a -> (0 until a.length()).map { a.optString(it) } } ?: emptyList()
        return ShowCreditInput(names = names, total = (o?.optInt("total") ?: 0).coerceAtLeast(0).toUInt())
    }

    private fun parseFeedback(json: JSONObject): Feedback {
        val arr = json.optJSONArray("goods") ?: JSONArray()
        val goods = (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            ReceivedGood(
                batchId = o.optInt("batchId"),
                summary = if (o.isNull("summary")) null else o.optString("summary"),
                recordType = if (o.isNull("recordType")) null else o.optString("recordType"),
                goodCount = o.optInt("goodCount"),
                newGoodCount = o.optInt("newGoodCount"),
                latestGoodAt = o.optLong("latestGoodAt")
            )
        }
        val reach = json.optJSONObject("setlistReach")
        return Feedback(
            goods = goods,
            newGoodTotal = json.optInt("newGoodTotal"),
            setlistReach = SetlistReach(
                week = reach?.optString("week") ?: "",
                viewers = reach?.optInt("viewers") ?: 0,
                shows = reach?.optInt("shows") ?: 0
            )
        )
    }

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private companion object {
        const val TAG = "ContributionFeedback"
        const val PREFS_NAME = "contribution_feedback"
        const val KEY_SEEN_GOOD_AT = "seen_good_at"
        const val KEY_VIEW_WEEK = "show_view_week"
        const val KEY_VIEW_REPORTED = "show_view_reported"
        const val REFRESH_INTERVAL_MS = 10 * 60 * 1000L
        const val CREDITS_TTL_MS = 10 * 60 * 1000L
    }
}
