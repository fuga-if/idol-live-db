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
 */
class CloudKitClient {

    private val queryUrl: String
        get() = "${CloudKitConfig.BASE}/database/1/${CloudKitConfig.CONTAINER}/" +
            "${CloudKitConfig.ENV}/public/records/query?ckAPIToken=${CloudKitConfig.API_TOKEN}"

    /** 指定 recordType を modifiedSinceMs より後の変更だけ全ページ取得する。 */
    suspend fun query(recordType: String, modifiedSinceMs: Long): List<CkRecord> =
        withContext(Dispatchers.IO) {
            val out = ArrayList<CkRecord>()
            var cursor: String? = null
            do {
                val page = queryPage(recordType, modifiedSinceMs, cursor)
                out.addAll(page.records)
                cursor = page.continuationMarker
            } while (cursor != null)
            out
        }

    private data class Page(val records: List<CkRecord>, val continuationMarker: String?)

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
            throw RuntimeException("CloudKit query $recordType HTTP $code: ${text.take(300)}")
        }

        val json = JSONObject(text)
        val recordsJson = json.optJSONArray("records") ?: JSONArray()
        val records = ArrayList<CkRecord>(recordsJson.length())
        for (i in 0 until recordsJson.length()) {
            val rec = recordsJson.getJSONObject(i)
            if (rec.has("serverErrorCode")) {
                Log.w(TAG, "record error: ${rec.optString("serverErrorCode")}")
                continue
            }
            val name = rec.optString("recordName")
            val fieldsJson = rec.optJSONObject("fields") ?: JSONObject()
            val fields = HashMap<String, Any?>(fieldsJson.length())
            val keys = fieldsJson.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                fields[k] = fieldsJson.getJSONObject(k).opt("value")
            }
            records.add(CkRecord(name, fields))
        }
        return Page(records, json.optString("continuationMarker").takeIf { it.isNotEmpty() })
    }

    companion object {
        private const val TAG = "CloudKitClient"
    }
}
