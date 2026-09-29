package com.fugaif.imaslivedb.data.net

import android.content.Context
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Worker (imas-live-api) へ送る 1 件。 */
data class WorkerRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String>,
    val body: String?
)

/** Worker の応答。本文は 2xx なら応答本文、それ以外ならエラー本文 (どちらも無ければ null)。 */
data class WorkerResponse(val code: Int, val body: String?) {
    val isSuccess: Boolean get() = code in 200..299
}

/** 送信の実体。テストではフェイクに差し替える。 */
fun interface WorkerTransport {
    /** 通信そのものが失敗したら例外を投げる (HTTP のエラー状態は [WorkerResponse] で返す)。 */
    @Throws(IOException::class)
    fun execute(request: WorkerRequest): WorkerResponse
}

/** HttpURLConnection による送信。 */
object UrlConnectionTransport : WorkerTransport {
    private const val TIMEOUT_MS = 15_000

    override fun execute(request: WorkerRequest): WorkerResponse {
        val conn = (URL(request.url).openConnection() as HttpURLConnection).apply {
            requestMethod = request.method
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            request.headers.forEach { (name, value) -> setRequestProperty(name, value) }
        }
        try {
            request.body?.let { body ->
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            // Android の HttpURLConnection は 400 以上で inputStream が投げるので、エラー本文は errorStream から読む。
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() }
            return WorkerResponse(code, text)
        } finally {
            conn.disconnect()
        }
    }
}

/**
 * セッションが 401 で断られたときの再発行口 (AuthService が持つ)。
 *
 * iOS `APIClient` と同じく、401 を受けたら 1 回だけ `/auth/refresh` で再発行を試し、
 * 通れば同じリクエストを送り直す。通らなければセッションを失効させる (ログイン導線に戻す)。
 */
fun interface SessionRenewer {
    /**
     * @param rejectedToken 401 で断られたトークン。待っている間に別のリクエストが再発行を
     *   済ませていれば、もう一度は再発行しない。
     * @return 送り直してよい (新しいセッションがある) なら true。
     */
    fun renewAfterUnauthorized(rejectedToken: String): Boolean
}

/**
 * Worker (imas-live-api) への HTTP の共通部分。ベース URL・タイムアウト・端末 ID と
 * セッションの付け方をここ 1 か所に置く (以前は 5 つのクライアントがそれぞれ書いていた)。
 *
 * 失敗の扱い (null を返す / 例外にする / どの文言を出す) はクライアントごとに違うので、
 * ここは「送って、状態と本文を返す」だけ。通信そのものの失敗は例外のまま投げる。
 * 例外は 401 だけで、セッションの再発行を 1 回試して送り直す ([SessionRenewer])。
 *
 * @param sessionToken セッション JWT。付けるのはリクエストの時点の値。
 */
class WorkerHttpClient(
    private val appContext: Context,
    private val sessionToken: () -> String?,
    private val transport: WorkerTransport = UrlConnectionTransport,
    private val renewer: SessionRenewer? = null
) {
    /**
     * @param authorized false ならセッションを付けない (サインインそのもの)。
     * @param bearer 手元のセッションの代わりに付けるトークン (再発行の要求そのもの)。
     *   付けたときは 401 でも再発行しない。
     */
    @Throws(IOException::class)
    fun request(
        method: String,
        path: String,
        body: JSONObject? = null,
        authorized: Boolean = true,
        bearer: String? = null
    ): WorkerResponse {
        val token = bearer ?: if (authorized) sessionToken() else null
        val response = send(method, path, body, token)
        if (response.code != 401 || bearer != null || token == null || renewer == null) return response
        if (!renewer.renewAfterUnauthorized(token)) return response
        return send(method, path, body, sessionToken())
    }

    /**
     * いまのセッション (無ければ null)。利用者ごとの値を覚えておく側が「誰の値か」を
     * 見分けるのに使う (サインアウト・別アカウントへの切り替えで前の人の値を出さない)。
     */
    fun currentSession(): String? = sessionToken()

    private fun send(method: String, path: String, body: JSONObject?, token: String?): WorkerResponse {
        val headers = buildMap {
            put("Content-Type", "application/json")
            put("X-Device-Id", DeviceIdentity.get(appContext))
            token?.let { put("Authorization", "Bearer $it") }
        }
        return transport.execute(WorkerRequest(method, BASE_URL + path, headers, body?.toString()))
    }

    companion object {
        /** Worker のベース URL。共有リンクの着地ページ (`/app/...`) もこのホストが返す。 */
        const val BASE_URL = "https://imas-live-api.tokata3011.workers.dev"
    }
}
