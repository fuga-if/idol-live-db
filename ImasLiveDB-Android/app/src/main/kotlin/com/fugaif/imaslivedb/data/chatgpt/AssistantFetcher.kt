package com.fugaif.imaslivedb.data.chatgpt

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import uniffi.imas_core.AssistantFetch
import uniffi.imas_core.AssistantFetched

/**
 * チャットのモデルが読みたいと言ったもの (X のポスト) を、端末が取りに行く。iOS `AssistantFetcher`。
 *
 * どこへ行くか ([AssistantFetch.url]) はコアが組む。ここは GET して、状態と本文をそのまま返すだけ
 * (本文をモデルに渡す形に削るのもコアの `assistantFetched`)。
 */
object AssistantFetcher {
    /** 本文の上限 (バイト)。一覧 1 ページぶんには十分で、これを越えるものは読まない。 */
    private const val MAX_BYTES = 600_000
    private const val TIMEOUT_MS = 15_000

    suspend fun fetch(fetches: List<AssistantFetch>): List<AssistantFetched> = coroutineScope {
        fetches.map { async(Dispatchers.IO) { get(it) } }.awaitAll()
    }

    private suspend fun get(fetch: AssistantFetch): AssistantFetched = withContext(Dispatchers.IO) {
        // 通信できなかったときは状態 0 (文言はコアが決める)。
        val failed = AssistantFetched(fetch.callId, 0u, "")
        val conn = try {
            URL(fetch.url).openConnection() as HttpURLConnection
        } catch (e: Exception) {
            return@withContext failed
        }
        try {
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout = TIMEOUT_MS
            conn.setRequestProperty("Accept", "application/json")
            // 利用者や端末を識別できるものは付けない。
            conn.setRequestProperty("User-Agent", "idol-live-db-app")
            val status = conn.responseCode
            val stream = (if (status in 200..399) conn.inputStream else conn.errorStream) ?: return@withContext failed
            val out = ByteArrayOutputStream()
            stream.use { input ->
                val buf = ByteArray(8192)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    if (out.size() > MAX_BYTES) return@withContext failed
                }
            }
            AssistantFetched(fetch.callId, status.toUShort(), out.toString(Charsets.UTF_8.name()))
        } catch (e: Exception) {
            failed
        } finally {
            conn.disconnect()
        }
    }
}
