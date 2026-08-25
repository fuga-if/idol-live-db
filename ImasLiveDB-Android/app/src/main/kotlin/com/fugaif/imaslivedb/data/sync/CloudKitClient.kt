package com.fugaif.imaslivedb.data.sync

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * CloudKit Web Services の public DB を read-only で叩く最小クライアント。
 * records/query を modifiedAt > since で投げ、continuationMarker でページングする。
 *
 * 返すのは **レコードの生 JSON 文字列**。値を Kotlin の型に落とすのは共有コアの仕事で、
 * ここで `{"value": X, "type": "TIMESTAMP"}` を value だけに平坦化すると
 * TIMESTAMP / INT64 / DOUBLE が区別できなくなり、soft delete (deletedAt) が伝搬せず
 * 投稿の createdAt も同期のたび現在時刻に化ける。
 * transport (HTTP・ページング・serverErrorCode の除去) だけがこのクラスの責務。
 */
class CloudKitClient {

    private val queryUrl: String
        get() = "${CloudKitConfig.BASE}/database/1/${CloudKitConfig.CONTAINER}/" +
            "${CloudKitConfig.ENV}/public/records/query?ckAPIToken=${CloudKitConfig.API_TOKEN}"

    /** 指定 recordType を modifiedSinceMs より後の変更だけ全ページ取得する (生 JSON のまま)。 */
    suspend fun query(recordType: String, modifiedSinceMs: Long): List<String> =
        withContext(Dispatchers.IO) {
            val out = ArrayList<String>()
            var cursor: String? = null
            do {
                val page = queryPage(recordType, modifiedSinceMs, cursor)
                out.addAll(page.recordJsons)
                cursor = page.continuationMarker
            } while (cursor != null)
            out
        }

    private data class Page(val recordJsons: List<String>, val continuationMarker: String?)

    private fun queryPage(recordType: String, sinceMs: Long, cursor: String?): Page {
        val body = JSONObject().apply {
            put("resultsLimit", 200)
            put("query", JSONObject().apply {
                put("recordType", recordType)
                put("filterBy", JSONArray().put(JSONObject().apply {
                    put("fieldName", "modifiedAt")
                    put("comparator", "GREATER_THAN")
                    put("fieldValue", JSONObject().apply {
                        put("value", sinceMs)
                        put("type", "TIMESTAMP")
                    })
                }))
                put("sortBy", JSONArray().put(JSONObject().apply {
                    put("fieldName", "modifiedAt")
                    put("ascending", true)
                }))
            })
            if (cursor != null) put("continuationMarker", cursor)
        }

        val conn = (URL(queryUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 30_000
            readTimeout = 30_000
            setRequestProperty("Content-Type", "application/json")
        }
        conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }

        val code = conn.responseCode
        val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
            ?.bufferedReader()?.use { it.readText() } ?: ""
        conn.disconnect()
        if (code !in 200..299) {
            // エラー本文も CKWS の JSON ({"serverErrorCode":..,"reason":..})。
            // 呼び出し側が「スキーマ未作成なので飛ばす」と「本物の失敗なので止まる」を
            // 区別できるよう、文字列に潰さず構造のまま渡す。
            val err = runCatching { JSONObject(text) }.getOrNull()
            throw CloudKitQueryException(
                recordType = recordType,
                httpCode = code,
                serverErrorCode = err?.optString("serverErrorCode")?.takeIf { it.isNotEmpty() },
                reason = err?.optString("reason")?.takeIf { it.isNotEmpty() },
                message = "CloudKit query $recordType HTTP $code: ${text.take(300)}"
            )
        }

        val json = JSONObject(text)
        val recordsJson = json.optJSONArray("records") ?: JSONArray()
        val records = ArrayList<String>(recordsJson.length())
        for (i in 0 until recordsJson.length()) {
            val rec = recordsJson.getJSONObject(i)
            if (rec.has("serverErrorCode")) {
                Log.w(TAG, "record error: ${rec.optString("serverErrorCode")}")
                continue
            }
            records.add(rec.toString())
        }
        return Page(records, json.optString("continuationMarker").takeIf { it.isNotEmpty() })
    }

    companion object {
        private const val TAG = "CloudKitClient"
    }
}

/**
 * `records/query` が 2xx 以外を返した。CKWS のエラー本文 (serverErrorCode / reason) を
 * そのまま持たせ、判断は呼び出し側 ([CloudKitSyncEngine]) に委ねる。
 */
class CloudKitQueryException(
    val recordType: String,
    val httpCode: Int,
    val serverErrorCode: String?,
    val reason: String?,
    message: String
) : RuntimeException(message) {

    /**
     * このコンテナ環境のスキーマに [recordType] がまだ無い、という意味のエラーか。
     *
     * 新しいレコードタイプは development へ import してから production へ deploy するので、
     * その間 production だけが未作成になる。iOS は `CKError.unknownItem` を握って
     * そのステップだけ飛ばしており (CloudKitSyncEngine.swift)、Android も揃える。
     *
     * 判定は**狭く**取る。取りこぼしても現状どおり同期が止まるだけ (= 退行しない) だが、
     * 本物の失敗をこれと誤認すると last_sync だけ進んで、そのレコードタイプの変更が
     * 次のフル同期まで永久に欠落する。だから「404 系」+「本文がレコードタイプの不在を
     * 名指ししている」の両方が揃ったときだけ true にする。
     */
    val isUnknownRecordType: Boolean
        get() {
            if (httpCode != 400 && httpCode != 404) return false
            if (serverErrorCode == "NOT_FOUND") return true
            val text = (reason ?: return false).lowercase()
            // **レコードタイプ**を名指ししているものだけ。フィールド側のスキーマ不備
            // ("Field 'modifiedAt' is not marked queryable" 等) は本物の設定漏れで、
            // 飛ばすとそのテーブルが静かに欠落したまま気づけない。
            return "unknown type" in text ||
                ("record type" in text && MISSING_WORDS.any { it in text })
        }

    private companion object {
        /** 「無い」を表す CKWS reason の言い回し。 */
        val MISSING_WORDS = listOf("unknown", "not found", "does not exist", "not defined", "no such")
    }
}
