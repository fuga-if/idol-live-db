package com.fugaif.imaslivedb.data.applink

import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** アプリの外から開かれた公演・イベントのリンク (iOS `Deeplink.event` / `.show` と対)。 */
sealed interface DetailLink {
    data class Event(val eventId: String) : DetailLink
    data class Show(val showId: String) : DetailLink
}

/**
 * Intent から公演・イベントのリンクを拾う。iOS `DeeplinkRouter.parse` と同じ形を受ける
 * (AndroidManifest の intent-filter と対):
 * - `imaslivedb://events/{id}` / `imaslivedb://shows/{id}` (公開サイト・着地ページの「アプリで開く」)
 * - `https://imas-live-api.tokata3011.workers.dev/app/{events,shows}/{id}` (アプリの共有リンク。App Links)
 *
 * `Uri.pathSegments` は percent-decode 済みなので、`sh_…` などの TEXT の id がそのまま得られる。
 */
object DetailLinks {
    private const val SCHEME = "imaslivedb"
    private const val API_HOST = "imas-live-api.tokata3011.workers.dev"

    fun parse(intent: Intent?): DetailLink? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        val (kind, id) = when {
            data.scheme == SCHEME -> {
                val segments = data.pathSegments
                if (segments.size != 1) return null
                (data.host ?: return null) to segments[0]
            }
            data.scheme == "https" && data.host == API_HOST -> {
                val segments = data.pathSegments
                if (segments.size != 3 || segments[0] != "app") return null
                segments[1] to segments[2]
            }
            else -> return null
        }
        if (id.isEmpty()) return null
        return when (kind) {
            "events" -> DetailLink.Event(id)
            "shows" -> DetailLink.Show(id)
            else -> null
        }
    }
}

/**
 * 外から届いた公演・イベントのリンクの受け渡し口。MainActivity が置き、アプリのナビゲーションが
 * 画面を開いたら [consume] する ([PollLinkIncoming] と同じ)。
 */
object DetailLinkIncoming {
    var pending by mutableStateOf<DetailLink?>(null)
        private set

    fun present(link: DetailLink) {
        pending = link
    }

    fun consume() {
        pending = null
    }
}
