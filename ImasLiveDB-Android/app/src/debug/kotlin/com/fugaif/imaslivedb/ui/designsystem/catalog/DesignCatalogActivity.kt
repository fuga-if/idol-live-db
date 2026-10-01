package com.fugaif.imaslivedb.ui.designsystem.catalog

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.fugaif.imaslivedb.ui.theme.ImasLiveDBTheme

/**
 * 部品カタログの入口 (デバッグビルドだけ。src/debug の AndroidManifest で宣言する)。
 *
 * 開き方 (adb):
 * ```
 * adb shell am start -n site.fugaapp.imaslivedb/com.fugaif.imaslivedb.ui.designsystem.catalog.DesignCatalogActivity \
 *     --es page venue --es theme dark
 * ```
 * - `page`: ページの id (iOS の `DesignCatalogPage` の rawValue と同じ。venue・venueRows・application・buttons・
 *   chips・rows・rows2・sections・heroSong・heroIdol・heroIdolColor・hub・hubColor・feedback・setlist・list・
 *   form・setup、Android だけの extras・stage)。無ければ目次。
 * - `theme`: light / dark。無ければ端末の設定。画面の上の帯でも切り替えられる。
 * - `scroll`: center / bottom。見本を撮るとき、ページの途中・下を出す (iOS の `DS_SCROLL`)。
 */
class DesignCatalogActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val initialPage = intent.getStringExtra("page")?.let(DesignCatalogPage::fromId)
        val requestedTheme = intent.getStringExtra("theme")
        val scroll = intent.getStringExtra("scroll")
        setContent {
            val system = isSystemInDarkTheme()
            var dark by rememberSaveable {
                mutableStateOf(
                    when (requestedTheme) {
                        "dark" -> true
                        "light" -> false
                        else -> system
                    }
                )
            }
            // ステータスバー・ナビゲーションバーの記号の色も、見ている配色に合わせる。
            LaunchedEffect(dark) {
                val style = if (dark) {
                    SystemBarStyle.dark(Color.TRANSPARENT)
                } else {
                    SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                }
                enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
            }
            ImasLiveDBTheme(darkTheme = dark) {
                DesignCatalogScreen(
                    initialPage = initialPage,
                    scrollAnchor = scroll,
                    dark = dark,
                    onToggleTheme = { dark = !dark },
                    onFinish = ::finish
                )
            }
        }
    }
}
