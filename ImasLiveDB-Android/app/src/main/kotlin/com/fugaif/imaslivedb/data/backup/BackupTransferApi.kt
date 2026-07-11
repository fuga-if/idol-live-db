package com.fugaif.imaslivedb.data.backup

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.auth.AuthService
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** 引き継ぎコード API (`/transfer`) の呼び出しで発生したエラー。呼び出し元でそのまま日本語メッセージとして表示できる。 */
class BackupTransferException(message: String) : Exception(message)

data class TransferCodeResult(val code: String, val expiresAt: String)

/** 引き継ぎコード方式のバックアップ転送 (サーバー経由)。iOS BackupTransferService の移植。 */
class BackupTransferApi(private val appContext: Context, private val authService: AuthService) {

    /** POST /transfer — payload (envelope JSON文字列) をサーバーに保管し、ワンタイムコードを発行する。 */
    suspend fun createTransferCode(payloadJson: String): TransferCodeResult = withContext(Dispatchers.IO) {
        val conn = open("POST", "/transfer")
        try {
            conn.doOutput = true
            val body = JSONObject().put("payload", payloadJson)
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() }
            if (code !in 200..299) {
                Log.w(TAG, "POST /transfer -> HTTP $code body=$text")
                throw statusException(code)
            }
            val json = JSONObject(text ?: throw BackupTransferException("サーバーからの応答が不正です"))
            TransferCodeResult(json.getString("code"), json.getString("expiresAt"))
        } catch (e: BackupTransferException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "POST /transfer failed: ${e.message}")
            throw BackupTransferException("通信に失敗しました")
        } finally {
            conn.disconnect()
        }
    }

    /** GET /transfer/:code — コードでペイロード文字列を取得する (ワンタイム消費、成功すればサーバー側では即座に削除される)。 */
    suspend fun fetchTransferCode(code: String): String = withContext(Dispatchers.IO) {
        val conn = open("GET", "/transfer/${enc(code.trim().uppercase())}")
        try {
            val httpCode = conn.responseCode
            val text = (if (httpCode in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() }
            if (httpCode !in 200..299) {
                Log.w(TAG, "GET /transfer/:code -> HTTP $httpCode body=$text")
                throw statusException(httpCode)
            }
            val json = JSONObject(text ?: throw BackupTransferException("サーバーからの応答が不正です"))
            json.getString("payload")
        } catch (e: BackupTransferException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "GET /transfer/:code failed: ${e.message}")
            throw BackupTransferException("通信に失敗しました")
        } finally {
            conn.disconnect()
        }
    }

    private fun statusException(httpCode: Int): BackupTransferException = when (httpCode) {
        401 -> BackupTransferException("ログインが必要です")
        404 -> BackupTransferException("コードが無効か期限切れです")
        429 -> BackupTransferException("しばらく待ってから再試行してください")
        400 -> BackupTransferException("データが不正です")
        else -> BackupTransferException("通信に失敗しました (HTTP $httpCode)")
    }

    private fun enc(s: String): String = java.net.URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private fun open(method: String, path: String): HttpURLConnection {
        return (URL(BASE + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("X-Device-Id", DeviceIdentity.get(appContext))
            authService.sessionToken?.let { setRequestProperty("Authorization", "Bearer $it") }
        }
    }

    companion object {
        private const val BASE = "https://imas-live-api.tokata3011.workers.dev"
        private const val TAG = "BackupTransferApi"
    }
}
