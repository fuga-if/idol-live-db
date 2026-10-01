package com.fugaif.imaslivedb.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.DeviceFontFamilyName
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

// iOS の imas タイポスケール (DesignTokens.swift) に合わせた値。
// 本文系は letterSpacing 0、見出しは bold/semibold。system フォント (Android=Roboto)。
val Typography = Typography(
    displayLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 34.sp, lineHeight = 41.sp),
    displayMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 28.sp, lineHeight = 34.sp),
    displaySmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 24.sp, lineHeight = 30.sp),
    // 見出し: largeTitle / title1 / title2
    headlineLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 34.sp, lineHeight = 41.sp),
    headlineMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 28.sp, lineHeight = 34.sp),
    headlineSmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 22.sp, lineHeight = 28.sp),
    // タイトル: title2 / headline / subhead-semibold
    titleLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Bold, fontSize = 22.sp, lineHeight = 28.sp),
    titleMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp),
    titleSmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, lineHeight = 20.sp),
    // 本文: body / subhead / footnote
    bodyLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 17.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 15.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 18.sp),
    // ラベル: callout / footnote / caption
    labelLarge = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 21.sp),
    labelMedium = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 18.sp),
    labelSmall = TextStyle(fontFamily = FontFamily.Default, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp)
)

// =============================================================================
// 書体の段 (iOS `DesignTokens.swift` の `Font.imas*`)。
//
// 本文 = system (Roboto + Noto Sans CJK)、数字 = 細長い太字、英字の印字 = 等幅。
// 文字の役割 ([ImasTextRole]) と数字の大きさ ([ImasNumeralSize]) はここの関数で組む。
//
// 大きさは sp のまま渡す。iOS は Dynamic Type とアプリ内の文字サイズ倍率を `UIFontMetrics` で
// 掛けているが、Android は [ImasLiveDBTheme] が Density の fontScale に両方を掛けているので、
// sp で書けば同じように拡大される (ここで倍率を掛け直すと二重になる)。
// =============================================================================

object ImasType {
    private val condensedName = DeviceFontFamilyName("sans-serif-condensed")

    /**
     * 細長い太字 (iOS の `.width(.compressed)` / `.width(.condensed)`)。
     *
     * Android に SF Pro の Compressed / Condensed は無いので、両方とも端末の `sans-serif-condensed`
     * (Roboto Condensed) の太字にする。太さごとに並べてあるのは、太さを可変で持つ端末で
     * その太さを引けるようにするため (1 本だけだと全部同じ太さに丸まる)。
     * 端末に無ければ通常のサンセリフの同じ太さに落ちる。
     */
    val condensedFamily: FontFamily = FontFamily(
        Font(condensedName, FontWeight.SemiBold),
        Font(condensedName, FontWeight.Bold),
        Font(condensedName, FontWeight.ExtraBold),
        Font(condensedName, FontWeight.Black)
    )

    /** 英字の印字 (ADMIT ONE・SETLIST・M01・OPEN / START)。iOS の SF Mono に当たる端末の等幅。 */
    val monoFamily: FontFamily = FontFamily.Monospace

    /** 本文の書体 (iOS `Font.imasScaled` / `imasBody` などの段)。 */
    fun text(size: TextUnit, weight: FontWeight = FontWeight.Normal): TextStyle =
        TextStyle(fontSize = size, fontWeight = weight)

    /**
     * 見出しの書体 (iOS `Font.imasHeading`)。かなを詰めて組む (palt)。
     * 「プロデュース」「セトリを予想する」のような かな・カナの続く行が、全角送りだと間延びして見えるため。
     * 本文は読みやすさのために詰めない。
     */
    fun heading(size: TextUnit, weight: FontWeight = FontWeight.Bold): TextStyle =
        TextStyle(fontSize = size, fontWeight = weight, fontFeatureSettings = "palt")

    /** 英字の印字の書体 (iOS `Font.imasMono`)。字間は [ImasTextRole.IMPRINT] が付ける (大文字にはしない。決まった英字は大文字で書く)。 */
    fun mono(size: TextUnit, weight: FontWeight = FontWeight.Medium): TextStyle =
        TextStyle(fontFamily = monoFamily, fontSize = size, fontWeight = weight)

    /**
     * 数字の書体 (iOS `.imasScaled(size, weight).width(.compressed).monospacedDigit()`)。
     * 細長い太字の等幅数字 (tnum)。桁が変わっても横幅が揺れない。
     */
    fun numeral(size: TextUnit, weight: FontWeight): TextStyle =
        TextStyle(fontFamily = condensedFamily, fontSize = size, fontWeight = weight, fontFeatureSettings = "tnum")
}
