package com.fugaif.imaslivedb.data.sync

import android.util.Log
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import uniffi.imas_core.syncDigestUrl

/**
 * 同期の目録 (Worker `GET /sync/manifest` = レコードタイプごとの最新 modifiedAt) を取る。
 *
 * 返すのは本文そのまま。読んで「どの型を省くか」を決めるのは共有コア
 * (`sync_planning::manifest_plan`) で、ここは通信だけ。
 *
 * 誰が呼んでも同じ値なので、ログインの有無に関わらず認証ヘッダも端末 ID も付けない
 * ([WorkerHttpClient] を通さないのはそのため)。待つのは短く切る: 目録は往復を省くための
 * もので、遅いなら無いものとして進めた方が速い。
 */
object SyncManifestClient {
    private const val TAG = "SyncManifest"
    private const val TIMEOUT_MS = 4_000

    /** 目録の本文。取れなければ null (同期は従来どおり全部の型を問い合わせる)。 */
    suspend fun fetch(): String? = get("${WorkerHttpClient.BASE_URL}/sync/manifest")

    /**
     * ID 一覧のダイジェスト (公開データ API) の本文。取れなければ null
     * (フル同期は従来どおり単一 PK の型を全件取り直す)。URL はコアが持つ。
     */
    suspend fun fetchDigests(): String? = get(syncDigestUrl())

    private suspend fun get(url: String): String? = withContext(Dispatchers.IO) {
        try {
            val conn = URL(url).openConnection() as HttpURLConnection
            try {
                conn.connectTimeout = TIMEOUT_MS
                conn.readTimeout = TIMEOUT_MS
                if (conn.responseCode != 200) return@withContext null
                conn.inputStream.bufferedReader().use { it.readText() }
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            Log.i(TAG, "$url unavailable: ${e.message}")
            null
        }
    }
}
