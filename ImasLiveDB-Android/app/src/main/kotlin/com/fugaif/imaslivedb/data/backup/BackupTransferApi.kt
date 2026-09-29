package com.fugaif.imaslivedb.data.backup

import android.util.Log
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** 引き継ぎコード API (`/transfer`) の呼び出しで発生したエラー。呼び出し元でそのまま日本語メッセージとして表示できる。 */
class BackupTransferException(message: String) : Exception(message)

data class TransferCodeResult(val code: String, val expiresAt: String)

/** 引き継ぎコード方式のバックアップ転送 (サーバー経由)。iOS BackupTransferService の移植。 */
class BackupTransferApi(private val http: WorkerHttpClient) {

    /** POST /transfer — payload (envelope JSON文字列) をサーバーに保管し、ワンタイムコードを発行する。 */
    suspend fun createTransferCode(payloadJson: String): TransferCodeResult = withContext(Dispatchers.IO) {
        try {
            val response = http.request("POST", "/transfer", JSONObject().put("payload", payloadJson))
            if (!response.isSuccess) {
                Log.w(TAG, "POST /transfer -> HTTP ${response.code} body=${response.body}")
                throw statusException(response.code)
            }
            val json = JSONObject(response.body ?: throw BackupTransferException("サーバーからの応答が不正です"))
            TransferCodeResult(json.getString("code"), json.getString("expiresAt"))
        } catch (e: BackupTransferException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "POST /transfer failed: ${e.message}")
            throw BackupTransferException("通信に失敗しました")
        }
    }

    /** GET /transfer/:code — コードでペイロード文字列を取得する (ワンタイム消費、成功すればサーバー側では即座に削除される)。 */
    suspend fun fetchTransferCode(code: String): String = withContext(Dispatchers.IO) {
        try {
            val response = http.request("GET", "/transfer/${enc(code.trim().uppercase())}")
            if (!response.isSuccess) {
                Log.w(TAG, "GET /transfer/:code -> HTTP ${response.code} body=${response.body}")
                throw statusException(response.code)
            }
            val json = JSONObject(response.body ?: throw BackupTransferException("サーバーからの応答が不正です"))
            json.getString("payload")
        } catch (e: BackupTransferException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "GET /transfer/:code failed: ${e.message}")
            throw BackupTransferException("通信に失敗しました")
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

    companion object {
        private const val TAG = "BackupTransferApi"
    }
}
