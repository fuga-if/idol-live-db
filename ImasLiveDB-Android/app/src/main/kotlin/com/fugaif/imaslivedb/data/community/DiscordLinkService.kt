package com.fugaif.imaslivedb.data.community

import android.util.Log
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Discord のロール受け取り (「データ協力」ロール) の入口。iOS `DiscordLinkService` の移植。
 *
 * Worker に `POST /discord/link` で 1 回限り (10 分) の Discord 認可 URL を発行してもらい、
 * それをブラウザで開くだけ。Discord でログインした後の結果 (サーバー参加・ロール付与・
 * 「あとN件」) は Worker 自身のページが出すので、アプリはコールバックを受けない。
 */
class DiscordLinkService(private val http: WorkerHttpClient) {

    /** 発行に失敗したことを表す。[message] はそのまま画面に出せる短い文言。 */
    class LinkException(message: String) : Exception(message)

    /** 認可 URL を発行してもらう。ログイン中のセッションで送る (未ログインは 401)。 */
    suspend fun authorizeUrl(): String = withContext(Dispatchers.IO) {
        val response = try {
            http.request("POST", "/discord/link", JSONObject())
        } catch (e: Exception) {
            Log.w(TAG, "POST /discord/link failed: ${e.message}")
            throw LinkException(GENERIC_MESSAGE)
        }
        if (response.code == 503) throw LinkException(NOT_CONFIGURED_MESSAGE)
        val url = response.body
            ?.takeIf { response.isSuccess }
            ?.let { runCatching { JSONObject(it).optString("url") }.getOrNull() }
            ?.takeIf { it.startsWith("https://") }
        url ?: throw LinkException(GENERIC_MESSAGE)
    }

    companion object {
        private const val TAG = "DiscordLink"
        /** 503 = サーバー側で連携を止めている (未設定)。 */
        const val NOT_CONFIGURED_MESSAGE = "いまは受け付けていません"
        const val GENERIC_MESSAGE = "Discordのページを開けませんでした。時間をおいて再試行してください。"
    }
}
