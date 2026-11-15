package com.fugaif.imaslivedb.data.chatgpt

import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import uniffi.imas_core.chatgptCallbackIsError

/** 待ち受けの失敗。文言は iOS `LoopbackCallbackServer.ServerError` と同じ。 */
sealed class LoopbackServerException(message: String) : Exception(message) {
    class ListenerFailed(detail: String) : LoopbackServerException("127.0.0.1 で待ち受けできませんでした: $detail")
    class Cancelled : LoopbackServerException("待ち受けを止めました")
}

/**
 * OAuth のリダイレクトを `http://127.0.0.1:<port>/auth/callback` で受ける最小の HTTP サーバ。iOS `LoopbackCallbackServer`。
 *
 * Sign in with ChatGPT はリダイレクト先をループバックに固定している (カスタムスキームも `localhost` も不可)。
 * ブラウザ (Custom Tabs) は別プロセスだが同じ端末なので、アプリのプロセスが生きている間はここで受けられる。
 *
 * 1 回の認可で 1 回だけ使う。待っている callback 以外 (favicon・古い試行など) には 404 を返して待ち続ける。
 * どれが待っている callback かの判定はコア (`chatgptIsExpectedCallback`: パスと state)。
 */
class LoopbackCallbackServer(
    val port: Int = 1455,
    /** リクエスト行の 2 語目 (`/auth/callback?...`) が待っている callback か。待ち受けは端末内の誰でも叩けるので必ず渡す。 */
    private val isExpected: (String) -> Boolean,
) {
    private var server: ServerSocket? = null
    private val stopped = AtomicBoolean(false)

    /** 待ち受けを開始する。ブラウザを開くのはこの後。 */
    fun start() {
        try {
            val socket = ServerSocket(port, 50, InetAddress.getByName("127.0.0.1"))
            server = socket
        } catch (e: IOException) {
            throw LoopbackServerException.ListenerFailed(e.message ?: e.javaClass.simpleName)
        }
    }

    /** 待っている callback が来るまで待ち、そのリクエスト行の 2 語目を返す。 */
    suspend fun waitForCallback(): String = suspendCancellableCoroutine { cont ->
        val socket = server
        if (socket == null || stopped.get()) {
            cont.resumeWithException(LoopbackServerException.Cancelled())
            return@suspendCancellableCoroutine
        }
        cont.invokeOnCancellation { stop() }
        val received = AtomicBoolean(false)
        thread(name = "chatgpt-plan-loopback", isDaemon = true) {
            try {
                while (!stopped.get()) {
                    val client = socket.accept()
                    // ブラウザは何も送らない先行接続を張ることがあるので、接続ごとに別の線で読む。
                    thread(name = "chatgpt-plan-loopback-conn", isDaemon = true) {
                        val target = handle(client)
                        if (target != null && received.compareAndSet(false, true)) {
                            if (cont.isActive) cont.resume(target)
                            stop()
                        }
                    }
                }
                if (cont.isActive) cont.resumeWithException(LoopbackServerException.Cancelled())
            } catch (e: SocketException) {
                if (cont.isActive && !received.get()) {
                    cont.resumeWithException(
                        if (stopped.get()) LoopbackServerException.Cancelled()
                        else LoopbackServerException.ListenerFailed(e.message ?: e.javaClass.simpleName)
                    )
                }
            } catch (e: IOException) {
                if (cont.isActive && !received.get()) {
                    cont.resumeWithException(LoopbackServerException.ListenerFailed(e.message ?: e.javaClass.simpleName))
                }
            }
        }
    }

    fun stop() {
        stopped.set(true)
        runCatching { server?.close() }
        server = null
    }

    /** 1 接続を読んで答える。待っている callback ならその target を返す。 */
    private fun handle(client: Socket): String? = client.use { socket ->
        try {
            socket.soTimeout = 5000
            val input = socket.getInputStream()
            val buffer = java.io.ByteArrayOutputStream()
            val chunk = ByteArray(2048)
            // ヘッダの終わり (空行) まで。64KB を超えたら打ち切る。
            while (buffer.size() < 64 * 1024) {
                val n = input.read(chunk)
                if (n < 0) break
                buffer.write(chunk, 0, n)
                if (indexOfHeaderEnd(buffer.toByteArray()) >= 0) break
            }
            val text = String(buffer.toByteArray(), Charsets.UTF_8)
            // リクエスト行: "GET /auth/callback?code=...&state=... HTTP/1.1"
            val firstLine = text.lineSequence().firstOrNull().orEmpty()
            val parts = firstLine.split(" ").filter { it.isNotEmpty() }
            val target = if (parts.size >= 2) parts[1] else ""
            val out = socket.getOutputStream()
            if (parts.firstOrNull() != "GET" || !isExpected(target)) {
                send(out, "404 Not Found", "Not Found", "text/plain; charset=utf-8")
                return@use null
            }
            val isError = chatgptCallbackIsError(target)
            send(out, "200 OK", completionHtml(isError), "text/html; charset=utf-8")
            target
        } catch (_: IOException) {
            null
        }
    }

    private fun indexOfHeaderEnd(bytes: ByteArray): Int {
        for (i in 0..bytes.size - 4) {
            if (bytes[i] == 13.toByte() && bytes[i + 1] == 10.toByte() && bytes[i + 2] == 13.toByte() && bytes[i + 3] == 10.toByte()) return i
        }
        return -1
    }

    private fun send(out: java.io.OutputStream, status: String, body: String, contentType: String) {
        val bodyBytes = body.toByteArray(Charsets.UTF_8)
        val head = "HTTP/1.1 $status\r\nContent-Type: $contentType\r\nContent-Length: ${bodyBytes.size}\r\n" +
            "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        out.write(head.toByteArray(Charsets.UTF_8))
        out.write(bodyBytes)
        out.flush()
    }

    /** 文言は iOS と同じ。 */
    private fun completionHtml(isError: Boolean): String = """
        <!doctype html><html lang="ja"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>アイドルライブDB</title>
        <style>body{font-family:system-ui,sans-serif;display:flex;min-height:90vh;align-items:center;justify-content:center;text-align:center;color:#1c1c1e}
        @media (prefers-color-scheme:dark){body{background:#000;color:#fff}}</style></head>
        <body><div><p style="font-size:20px;font-weight:600">${if (isError) "連携は完了しませんでした" else "ChatGPT との連携を受け取りました"}</p>
        <p>アプリに戻ります。この画面は閉じて大丈夫です。</p></div></body></html>
    """.trimIndent()
}
