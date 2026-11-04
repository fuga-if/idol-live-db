package com.fugaif.imaslivedb.ui.designsystem

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import uniffi.imas_core.YouTubeEmbedPlayer
import uniffi.imas_core.YouTubePlayerEvent
import uniffi.imas_core.youtubePlayerEvent

/**
 * 参考動画を再生する YouTube の埋め込みプレーヤー。大きさと角は置く側 (小窓) が決める。iOS `YouTubeInlinePlayer` の移植。
 *
 * ページの中身 (IFrame Player API・開始秒・名乗る origin) はコア (`youtubeEmbedPlayer`) が組む。
 * ここは WebView に読ませて、ページからの知らせ (`youtubePlayerEvent`) を受けるだけ。
 * 埋め込みを止めている動画 (公式 MV に多い) は YouTube の仕様で再生できないので、
 * [onUnplayable] で親に返し、親が「YouTube で開く」案内に替える。
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun YouTubeInlinePlayer(player: YouTubeEmbedPlayer, onUnplayable: () -> Unit, modifier: Modifier = Modifier) {
    var isReady by remember { mutableStateOf(false) }
    val currentOnUnplayable by rememberUpdatedState(onUnplayable)
    Box(
        modifier
            .fillMaxWidth()
            .background(Color.Black)
            .semantics { contentDescription = "動画プレーヤー" },
        contentAlignment = Alignment.Center
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize().alpha(if (isReady) 1f else 0f),
            factory = { context ->
                val main = Handler(Looper.getMainLooper())
                WebView(context).apply {
                    setBackgroundColor(AndroidColor.BLACK)
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    // 押した操作で開くプレーヤーなので、読み込んだらそのまま再生する。
                    settings.mediaPlaybackRequiresUserGesture = false
                    isVerticalScrollBarEnabled = false
                    isHorizontalScrollBarEnabled = false
                    addJavascriptInterface(object {
                        @JavascriptInterface
                        fun post(message: String) {
                            main.post {
                                when (youtubePlayerEvent(message)) {
                                    YouTubePlayerEvent.READY -> isReady = true
                                    YouTubePlayerEvent.UNPLAYABLE -> currentOnUnplayable()
                                    YouTubePlayerEvent.OTHER -> Unit
                                }
                            }
                        }
                    }, player.bridgeName)
                    webViewClient = object : WebViewClient() {
                        // プレーヤーの中のリンク (ロゴ・タイトル・関連動画) は WebView で開かず、
                        // YouTube アプリ / ブラウザに渡す。最初のページ読み込み (base URL) は通す。
                        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                            if (!request.isForMainFrame || !request.hasGesture()) return false
                            runCatching { view.context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(request.url.toString()))) }
                            return true
                        }
                    }
                    loadDataWithBaseURL(player.baseUrl, player.html, "text/html", "utf-8", null)
                }
            },
            // 画面から外れたら音を止めて片付ける (WebView が残っても鳴り続けないように)。
            onRelease = { webView ->
                webView.stopLoading()
                webView.loadUrl("about:blank")
                webView.destroy()
            }
        )
        if (!isReady) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
        }
    }
}

/** 埋め込みを止めている動画の案内 (小窓の中と、一覧の行の下)。押すと YouTube で開く。大きさは置く側が決める。 */
@Composable
fun YouTubeUnplayableNotice(onOpen: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .background(DS.surface2)
            .clickable(onClick = onOpen)
            .padding(DS.sp4),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.sp2)) {
            ImasText("この動画はアプリ内で再生できません", ImasTextRole.META, color = DS.ink2, textAlign = TextAlign.Center)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.sp2)) {
                Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, tint = DS.danger, modifier = Modifier.size(18.dp))
                ImasText("YouTube で開く", ImasTextRole.VALUE, color = DS.danger)
            }
        }
    }
}
