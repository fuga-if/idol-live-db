package com.fugaif.imaslivedb.data.applink

import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import uniffi.imas_core.sharePollIdFromUrl

/** アプリの外から開かれたお題のリンク (iOS `Deeplink.poll` と対)。 */
sealed interface PollLink {
    /** 1 つのお題 (共有 URL `https://idollivedb.fugaapp.site/polls/#poll-{id}` など)。 */
    data class Detail(val pollId: String) : PollLink

    /** お題の一覧 (`/polls/` を、どのお題も指さずに開いたとき)。 */
    data object List : PollLink
}

/**
 * Intent からお題のリンクを拾う。どの URL をお題と読むかはコア (`sharePollIdFromUrl`) 一本。
 *
 * 受ける形 (AndroidManifest の intent-filter と対):
 * - 公開サイトの共有 URL `https://idollivedb.fugaapp.site/polls/#poll-{id}` (App Links)
 * - API の着地ページ `https://imas-live-api.tokata3011.workers.dev/app/polls/{id}` (旧い共有 URL。App Links)
 * - `imaslivedb://polls/{id}` (公開サイトの「アプリで投票する」・着地ページの「アプリで開く」)
 */
object PollLinks {
    private const val WEB_HOST = "idollivedb.fugaapp.site"

    fun parse(intent: Intent?): PollLink? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        sharePollIdFromUrl(data.toString())?.let { return PollLink.Detail(it) }
        // `/polls/` だけ (節を指さない) はお題の一覧へ。
        val isPollList = data.scheme == "https" && data.host == WEB_HOST &&
            (data.path == "/polls" || data.path == "/polls/")
        return if (isPollList) PollLink.List else null
    }
}

/**
 * 外から届いたお題のリンクの受け渡し口。MainActivity が置き、アプリのナビゲーションが
 * 画面を開いたら [consume] する (開く前に届いても、データの準備が済むまで取っておく)。
 */
object PollLinkIncoming {
    private val _pending = MutableStateFlow<PollLink?>(null)
    val pending: StateFlow<PollLink?> = _pending.asStateFlow()

    fun present(link: PollLink) {
        _pending.value = link
    }

    fun consume() {
        _pending.value = null
    }
}
