package com.fugaif.imaslivedb.data.edit

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.auth.AuthService
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * オープン編集 (マスタの create/update/delete) + 編集フィードの Worker API クライアント。
 * iOS `EditService` / `EditFeedService` の移植。
 *
 * 契約 (imas-live-api/src/edits.ts, edit_requests.ts, feed.ts, edit_good.ts を実ソースで確認済み):
 * - `POST /edits` はマスタ型 (Event/Show/Song/Idol/SetlistItem/SetlistPerformer/SongArtist/ShowCast) の
 *   create/update/delete を admin のみ受け付ける。一般ユーザーがマスタ op を送ると 422 になる
 *   (コミュニティ型 SongCall/SongVideo だけは一般ユーザーも `/edits` で即時反映)。
 * - 一般ユーザーのマスタ編集は `POST /edit-requests` (GitHub issue 化。CloudKit 未反映・ローカル反映不可)。
 * - [submitMaster] が `AuthService.isAdmin` で自動的にどちらを呼ぶか振り分ける
 *   (iOS `EditService.submitMaster` と同じ分岐)。
 */
class EditApi(private val appContext: Context, private val authService: AuthService) {

    enum class EditOp(val raw: String) { CREATE("create"), UPDATE("update"), DELETE("delete") }

    /** 1 マスタ操作。`before` はクライアントから送らない (サーバが権威取得する契約)。 */
    data class EditOperation(
        val op: EditOp,
        val recordType: String,
        val recordName: String? = null,
        val fields: Map<String, Any?>? = null
    ) {
        fun toJson(): JSONObject {
            val o = JSONObject()
            o.put("op", op.raw)
            o.put("recordType", recordType)
            if (recordName != null) o.put("recordName", recordName)
            if (fields != null) {
                val f = JSONObject()
                for ((k, v) in fields) f.put(k, v ?: JSONObject.NULL)
                o.put("fields", f)
            }
            return o
        }
    }

    data class EditResult(val recordType: String?, val recordName: String, val op: String, val ok: Boolean)
    data class EditResponse(val ok: Boolean, val batchId: Int?, val results: List<EditResult>)
    data class EditRequestResponse(val ok: Boolean, val issueNumber: Int?, val issueUrl: String?)

    /** マスタ編集の結末。admin は直接反映、一般ユーザーは修正リクエスト (issue) 送信。 */
    sealed class MasterEditOutcome {
        data class Applied(val response: EditResponse) : MasterEditOutcome()
        data class Requested(val response: EditRequestResponse) : MasterEditOutcome()
    }

    /** 「最近の編集」フィード 1 行 (= edit_batch 1 件)。契約: 素の camelCase 直返し。 */
    data class EditFeedEntry(
        val batchId: Int,
        val editorDisplayName: String?,
        val isOwnEdit: Boolean,
        /** 'create' | 'update' | 'delete' | 'revert' | 'snapshot' | 'replace' */
        val op: String,
        val recordType: String,
        val recordName: String,
        val summary: String?,
        /** ミリ秒 epoch。 */
        val createdAt: Long,
        val goodCount: Int,
        val hasUserGood: Boolean,
        val reverted: Boolean,
        val source: String?
    ) {
        /** 投稿者表示名。privaterelay 系 / メール形式は「名無しのプロデューサー」へマスク。 */
        val editorDisplayLabel: String
            get() {
                val name = editorDisplayName
                if (name.isNullOrEmpty()) return "名無しのプロデューサー"
                if (name.contains("@")) return "名無しのプロデューサー"
                return name
            }
    }

    data class EditFeedPage(val items: List<EditFeedEntry>, val total: Int, val page: Int, val limit: Int)
    data class GoodResult(val batchId: Int, val goodCount: Int, val gooded: Boolean)

    data class RecordHistoryEntry(
        val id: Int,
        val batchId: Int,
        val op: String,
        val changedFields: List<String>,
        val editorName: String?,
        val createdAt: Long,
        val reverted: Boolean
    )

    sealed class ApiException(message: String) : Exception(message) {
        object NotAuthorized : ApiException("unauthorized")
        object Banned : ApiException("banned")
        data class RateLimited(val retryAfter: Int? = null) : ApiException("rate_limited")
        data class Server(val status: Int, val body: String) : ApiException("server_error($status)")
        data class Transport(override val message: String) : ApiException(message)
    }

    // MARK: - POST /edits (admin 直接反映)

    suspend fun submit(ops: List<EditOperation>, summary: String? = null): EditResponse {
        if (ops.isEmpty()) return EditResponse(true, null, emptyList())
        val body = JSONObject().apply {
            put("ops", JSONArray(ops.map { it.toJson() }))
            if (summary != null) put("summary", summary)
        }
        return parseEditResponse(request("POST", "/edits", body))
    }

    // MARK: - POST /edit-requests (一般ユーザーの修正リクエスト、GitHub issue 化)

    suspend fun submitRequest(ops: List<EditOperation>, summary: String? = null): EditRequestResponse {
        if (ops.isEmpty()) return EditRequestResponse(true, null, null)
        val body = JSONObject().apply {
            put("ops", JSONArray(ops.map { it.toJson() }))
            if (summary != null) put("summary", summary)
        }
        val json = request("POST", "/edit-requests", body)
        return EditRequestResponse(
            ok = json.optBoolean("ok", true),
            issueNumber = if (json.has("issueNumber") && !json.isNull("issueNumber")) json.optInt("issueNumber") else null,
            issueUrl = json.optString("issueUrl").ifEmpty { null }
        )
    }

    /** admin なら直接反映、一般ユーザーは修正リクエストへ回す (iOS EditService.submitMaster と同じ分岐)。 */
    suspend fun submitMaster(ops: List<EditOperation>, summary: String? = null): MasterEditOutcome {
        return if (authService.state.value.isAdmin) {
            MasterEditOutcome.Applied(submit(ops, summary))
        } else {
            MasterEditOutcome.Requested(submitRequest(ops, summary))
        }
    }

    // MARK: - Feed

    suspend fun fetchEdits(
        page: Int = 1,
        limit: Int = 20,
        recordType: String? = null,
        brandId: String? = null,
        mine: Boolean = false
    ): EditFeedPage {
        val path = if (mine) "/me/edits" else "/edits"
        val params = mutableListOf("page=$page", "limit=$limit")
        if (!recordType.isNullOrEmpty()) params.add("record_type=${enc(recordType)}")
        if (!brandId.isNullOrEmpty()) params.add("brand_id=${enc(brandId)}")
        val json = request("GET", "$path?${params.joinToString("&")}", null)
        val itemsArr = json.optJSONArray("items") ?: JSONArray()
        val items = (0 until itemsArr.length()).map { i -> parseFeedEntry(itemsArr.getJSONObject(i)) }
        return EditFeedPage(items, json.optInt("total"), json.optInt("page", page), json.optInt("limit", limit))
    }

    suspend fun good(batchId: Int): GoodResult {
        val json = request("POST", "/edits/$batchId/good", null)
        return GoodResult(json.optInt("batchId", batchId), json.optInt("goodCount"), json.optBoolean("gooded"))
    }

    suspend fun ungood(batchId: Int): GoodResult {
        val json = request("DELETE", "/edits/$batchId/good", null)
        return GoodResult(json.optInt("batchId", batchId), json.optInt("goodCount"), json.optBoolean("gooded"))
    }

    /** `GET /master/:recordType/:recordName/history` — あるレコードの変更履歴 (差分の主要キーのみ)。 */
    suspend fun recordHistory(recordType: String, recordName: String, limit: Int = 30): List<RecordHistoryEntry> {
        val path = "/master/${enc(recordType)}/${enc(recordName)}/history?limit=$limit"
        val json = request("GET", path, null)
        val arr = json.optJSONArray("history") ?: JSONArray()
        return (0 until arr.length()).map { i ->
            val h = arr.getJSONObject(i)
            val changed = h.optJSONArray("changedFields") ?: JSONArray()
            RecordHistoryEntry(
                id = h.optInt("id"),
                batchId = h.optInt("batchId"),
                op = h.optString("op"),
                changedFields = (0 until changed.length()).map { changed.getString(it) },
                editorName = h.optString("editorName").ifEmpty { null },
                createdAt = h.optLong("createdAt"),
                reverted = h.optBoolean("reverted", false)
            )
        }
    }

    // MARK: - parsing

    private fun parseEditResponse(json: JSONObject): EditResponse {
        val resultsArr = json.optJSONArray("results") ?: JSONArray()
        val results = (0 until resultsArr.length()).map { i ->
            val r = resultsArr.getJSONObject(i)
            EditResult(
                recordType = r.optString("recordType").ifEmpty { null },
                recordName = r.optString("recordName"),
                op = r.optString("op"),
                ok = r.optBoolean("ok", true)
            )
        }
        val batchId = if (json.has("batchId") && !json.isNull("batchId")) json.optInt("batchId") else null
        return EditResponse(json.optBoolean("ok", true), batchId, results)
    }

    private fun parseFeedEntry(o: JSONObject): EditFeedEntry {
        return EditFeedEntry(
            batchId = o.optInt("batchId"),
            editorDisplayName = o.optString("editorDisplayName").ifEmpty { null },
            isOwnEdit = o.optBoolean("isOwnEdit", false),
            op = o.optString("op"),
            recordType = o.optString("recordType"),
            recordName = o.optString("recordName"),
            summary = o.optString("summary").ifEmpty { null },
            createdAt = o.optLong("createdAt"),
            goodCount = o.optInt("goodCount"),
            hasUserGood = o.optBoolean("hasUserGood", false),
            reverted = o.optBoolean("reverted", false),
            source = o.optString("source").ifEmpty { null }
        )
    }

    // MARK: - HTTP

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    /** 成功時は JSON を返し、失敗時は契約に沿った [ApiException] を投げる (CommunityApi と違い、
     *  呼び出し側が 401/403/429 を UI 分岐 [ログイン誘導 / BAN / レート制限] できるようにする)。 */
    private suspend fun request(method: String, path: String, body: JSONObject?): JSONObject = withContext(Dispatchers.IO) {
        val conn = try {
            (URL(BASE + path).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = 15_000
                readTimeout = 15_000
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("X-Device-Id", DeviceIdentity.get(appContext))
                authService.sessionToken?.let { setRequestProperty("Authorization", "Bearer $it") }
            }
        } catch (e: Exception) {
            throw ApiException.Transport(e.message ?: "connection failed")
        }
        try {
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() }
            if (code !in 200..299) {
                Log.w(TAG, "$method $path -> HTTP $code body=$text")
                throw when (code) {
                    401 -> ApiException.NotAuthorized
                    403 -> ApiException.Banned
                    429 -> ApiException.RateLimited()
                    else -> ApiException.Server(code, text ?: "")
                }
            }
            if (text.isNullOrEmpty()) JSONObject() else JSONObject(text)
        } catch (e: ApiException) {
            throw e
        } catch (e: Exception) {
            throw ApiException.Transport(e.message ?: "request failed")
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        private const val TAG = "EditApi"
        private const val BASE = "https://imas-live-api.tokata3011.workers.dev"
    }
}

/** [EditApi.ApiException] をユーザー向け文言に変換する共通ヘルパー。 */
fun EditApi.ApiException.friendlyMessage(): String = when (this) {
    is EditApi.ApiException.NotAuthorized -> "認証の有効期限が切れています。再度サインインしてください。"
    is EditApi.ApiException.Banned -> "この操作は制限されています。"
    is EditApi.ApiException.RateLimited -> "投稿が多すぎます。しばらく待ってからお試しください。"
    is EditApi.ApiException.Server -> "保存に失敗しました (${status})"
    is EditApi.ApiException.Transport -> "通信に失敗しました: ${message}"
}
