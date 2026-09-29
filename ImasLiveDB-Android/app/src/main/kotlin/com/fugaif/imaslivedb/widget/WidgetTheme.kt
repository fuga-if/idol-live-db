package com.fugaif.imaslivedb.widget

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme

/**
 * ホーム画面ウィジェット (Glance) 側の見た目のトークン。
 *
 * ## なぜ DS をそのまま使えないか
 *
 * Glance は Compose とは別の描画系 (RemoteViews) で、色は [ColorProvider]、文字は
 * Glance 独自の [TextStyle] を要求する。アプリ本体の [DS] / [ImasTheme] を **値の出どころ**
 * として引き、ここで Glance の型に包み直すだけにする。ウィジェット側のコードで 16 進や
 * `Color(0xFF…)` を直書きしないこと (アプリと色がずれる)。
 *
 * ## ブランド色だけは DB 由来
 *
 * ブランドカラーは master DB の `brands.color` (hex) が正。そこから実際に塗る色を
 * 導くのは [ImasTheme] (共有コアの色エンジン) で、アプリ本体と同じ発色になる。
 * ウィジェットは壁紙の上に載って背景が読めないぶんコントラストが効きにくいので、
 * ブランド色は [BrandAccent] の組 (濃い色 + その面) でしか使わない。
 */
object WidgetTheme {

    /** ウィジェットの下地。純黒 (DS.bg) だと壁紙から浮くので、アプリのカード面と同じ surface。 */
    val surface: Color = DS.surface

    val ink: Color = DS.ink
    val ink2: Color = DS.ink2
    val ink3: Color = DS.ink3

    /** チケット締切の強調色 (iOS の .orange に対応する DS トークン)。 */
    val warning: Color = DS.warning

    /** ブランド色が引けないときのアクセント。 */
    val fallbackAccent: Color = DS.pick

    /** ウィジェットの角丸。Android 12 未満では無視される (システム側が角丸を持たないため)。 */
    val corner = 16.dp

    /**
     * ブランドカラー (hex) から、塗り色とその上に載せる文字色の組を作る。
     *
     * 導出は共有コア (imas-core) の色エンジン。ネイティブライブラリを積んでいないビルドでは
     * 例外になるので、その場合は無彩の DS トークンへ落とす (ウィジェットが真っ白/真っ黒に
     * ならないための保険)。
     */
    fun brandAccent(hex: String?): BrandAccent {
        val seed = hex?.takeIf { it.isNotBlank() }
        return runCatching {
            val theme = ImasTheme.derive(seed = seed, brand = null, dark = true)
            BrandAccent(accent = theme.accent, tint = theme.tint)
        }.getOrElse { BrandAccent(accent = fallbackAccent, tint = DS.fill) }
    }

    // MARK: - テキストスタイル (ウィジェットの中で sp を直書きしないための入口)

    /** 見出しラベル (「次のライブ」等)。小さく・強く・アクセント色。 */
    fun caption(color: Color) = TextStyle(
        color = ColorProvider(color),
        fontSize = 10.sp,
        fontWeight = FontWeight.Medium
    )

    /** 主題 (イベント名・曲名)。ウィジェットの主役なので太字。 */
    fun title(color: Color = ink, small: Boolean) = TextStyle(
        color = ColorProvider(color),
        fontSize = if (small) 13.sp else 15.sp,
        fontWeight = FontWeight.Bold
    )

    /** 副題 (歌唱者・日付)。 */
    fun body(color: Color = ink2, bold: Boolean = false) = TextStyle(
        color = ColorProvider(color),
        fontSize = 11.sp,
        fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal
    )
}

/**
 * ブランド色から導いた組。[accent] は文字や細帯に載せる濃い色、[tint] はその色の面
 * (薄い下地)。**この 2 つは組で使うこと** — accent を tint 以外の面に置くと、
 * ブランドによっては読めなくなる (黄色 (ml) を白面に置く、など)。
 */
data class BrandAccent(val accent: Color, val tint: Color)

/**
 * 全ウィジェット共通の外枠。
 *
 * [appWidgetBackground] を付けるのは Android 12 以降でシステムが角丸マスクを当てる対象を
 * 見つけられるようにするため (付けないと角が四角いまま浮く)。
 */
@Composable
fun WidgetSurface(
    padding: Int = 12,
    background: Color = WidgetTheme.surface,
    content: @Composable () -> Unit
) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(background)
            .cornerRadius(WidgetTheme.corner)
            .padding(padding.dp),
        contentAlignment = Alignment.TopStart
    ) { content() }
}

/**
 * データが無いときの共通表示。
 *
 * iOS 版は SF Symbols のアイコンを添えているが、こちらは文字だけにしてある。
 * Glance に絵を出すには drawable リソースか Bitmap が要り、ウィジェット 5 種のために
 * アイコン画像一式を抱えるのは割に合わない (説明文の方が「何をすれば出るか」も伝わる)。
 */
@Composable
fun WidgetPlaceholder(message: String, hint: String? = null) {
    WidgetSurface {
        Column(
            modifier = GlanceModifier.fillMaxSize(),
            verticalAlignment = Alignment.Vertical.CenterVertically,
            horizontalAlignment = Alignment.Horizontal.CenterHorizontally
        ) {
            Text(text = message, style = WidgetTheme.body(WidgetTheme.ink2), maxLines = 2)
            if (hint != null) {
                Text(text = hint, style = WidgetTheme.caption(WidgetTheme.ink3), maxLines = 2)
            }
        }
    }
}
