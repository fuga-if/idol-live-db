package com.fugaif.imaslivedb.data.chatgpt

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.ChatGptFailure
import uniffi.imas_core.ChatGptHttpErrorAction
import uniffi.imas_core.ChatGptModel
import uniffi.imas_core.ChatGptStreamEvent
import uniffi.imas_core.chatgptEndpoints
import uniffi.imas_core.chatgptHttpFailure
import uniffi.imas_core.chatgptReadModels
import uniffi.imas_core.chatgptReadStreamLine
import uniffi.imas_core.chatgptHttpErrorAction
import uniffi.imas_core.chatgptStreamCutOff

/** 推論の失敗。文言はコアが決めたもの。iOS `ChatGPTPlanClient.Failure`。 */
class ChatGptFailureException(val failure: ChatGptFailure) : Exception(failure.message)

/** 推論の暗号化返却を受けない経路だった。それ無しでやり直す。 */
class RetryWithoutReasoning : Exception()

/** Web 検索のツールを受けない経路だった。それを外してやり直す (外したものが無い仕事なら失敗)。 */
class RetryWithoutWebSearch : Exception()

sealed interface ChatGptStreamItem {
    data class Delta(val text: String) : ChatGptStreamItem

    /** 関数呼び出しが始まった (進行表示用)。 */
    data class ToolCallStarted(val name: String) : ChatGptStreamItem

    /** 出力項目 1 件が確定した (JSON)。 */
    data class OutputItem(val json: String) : ChatGptStreamItem
}

/**
 * ChatGPT プランの経路の HTTP。iOS `ChatGPTPlanClient`。
 *
 * 何を送るか (フォーム・リクエスト本文) と、返ってきたものの読み方 (ストリームの行の意味・失敗の言い方・
 * モデル一覧) は全部コア (`chatgpt_plan.rs`)。ここは運ぶだけ。HTTP は他の連携と同じ `HttpURLConnection`。
 */
object ChatGptPlanClient {
    private const val CONNECT_TIMEOUT_MS = 30_000
    private const val READ_TIMEOUT_MS = 60_000

    /** ストリームは考えている間は黙るので、読みの待ちは長めに取る。 */
    private const val STREAM_READ_TIMEOUT_MS = 300_000

    suspend fun get(url: String): String = withContext(Dispatchers.IO) {
        val conn = open(url, READ_TIMEOUT_MS)
        try {
            val status = conn.responseCode
            readBody(conn, status)
        } finally {
            conn.disconnect()
        }
    }

    suspend fun postForm(url: String, body: String): Pair<Int, String> = withContext(Dispatchers.IO) {
        val conn = open(url, READ_TIMEOUT_MS)
        try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            conn.setRequestProperty("Accept", "application/json")
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val status = conn.responseCode
            status to readBody(conn, status)
        } finally {
            conn.disconnect()
        }
    }

    suspend fun listModels(accessToken: String): List<ChatGptModel> = withContext(Dispatchers.IO) {
        val conn = open(chatgptEndpoints().modelsUrl, READ_TIMEOUT_MS)
        try {
            conn.setRequestProperty("Authorization", "Bearer $accessToken")
            val status = conn.responseCode
            val body = readBody(conn, status)
            if (status !in 200..299) throw ChatGptFailureException(chatgptHttpFailure(status.toUShort(), body))
            chatgptReadModels(body)
        } finally {
            conn.disconnect()
        }
    }

    /**
     * Responses API を 1 回呼び、ストリームを読む。正常に終われば完了、失敗は [ChatGptFailureException] を流す。
     * 受け手が止まったら接続を切る。
     *
     * @param includesReasoning このリクエストに暗号化返却を付けたか (失敗時のやり直しの判断はコア)。
     * @param body コアが組んだリクエスト本文 (`chatgptResponsesBody`)。
     */
    fun stream(body: String, accessToken: String, includesReasoning: Boolean): Flow<ChatGptStreamItem> = callbackFlow {
        val conn = open(chatgptEndpoints().responsesUrl, STREAM_READ_TIMEOUT_MS)
        val job = launch(Dispatchers.IO) {
            try {
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Authorization", "Bearer $accessToken")
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Accept", "text/event-stream")
                conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

                val status = conn.responseCode
                if (status !in 200..299) {
                    val text = (conn.errorStream ?: conn.inputStream).bufferedReader(Charsets.UTF_8).use { reader ->
                        val buf = CharArray(4000)
                        val n = reader.read(buf)
                        if (n > 0) String(buf, 0, n) else ""
                    }
                    when (val action = chatgptHttpErrorAction(status.toUShort(), text, includesReasoning)) {
                        is ChatGptHttpErrorAction.RetryWithoutReasoning -> throw RetryWithoutReasoning()
                        is ChatGptHttpErrorAction.RetryWithoutWebSearch -> throw RetryWithoutWebSearch()
                        is ChatGptHttpErrorAction.Fail -> throw ChatGptFailureException(action.failure)
                    }
                }

                var completed = false
                conn.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                    while (isActive) {
                        val line = reader.readLine() ?: break
                        when (val event = chatgptReadStreamLine(line)) {
                            is ChatGptStreamEvent.Ignored -> Unit
                            is ChatGptStreamEvent.Delta -> send(ChatGptStreamItem.Delta(event.text))
                            is ChatGptStreamEvent.ToolCallStarted -> send(ChatGptStreamItem.ToolCallStarted(event.name))
                            is ChatGptStreamEvent.OutputItem -> send(ChatGptStreamItem.OutputItem(event.json))
                            is ChatGptStreamEvent.Completed -> completed = true
                            is ChatGptStreamEvent.Failed -> throw ChatGptFailureException(event.failure)
                        }
                    }
                }
                if (!isActive) return@launch
                if (!completed) throw ChatGptFailureException(chatgptStreamCutOff())
                close()
            } catch (e: Throwable) {
                // 受け手が止めて接続を切ったときの読み損ねは、エラーとして流さない。
                if (isActive) close(e) else close()
            }
        }
        awaitClose {
            job.cancel()
            conn.disconnect()
        }
    }

    private fun open(url: String, readTimeoutMs: Int): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = readTimeoutMs
        }

    private fun readBody(conn: HttpURLConnection, status: Int): String {
        val stream = if (status in 200..399) conn.inputStream else (conn.errorStream ?: return "")
        return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }
}
