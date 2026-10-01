package com.fugaif.imaslivedb.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// =============================================================================
// ゲームの「ステージ」の配色・書体 (docs/DESIGN_SYSTEM.md §12)。iOS `Views/Games/QuizStage.swift` の `QS`。
//
// ゲーム中の画面だけは、アプリ本体の画面ではなくライブ会場の暗いステージにする。ステージ固定の配色なので
// DS のトークン (ライト/ダークで変わる) ではなくこの固定色を使う。ステージの部品 (`ImasStage*`) と
// ゲームの画面 (ui/games・ui/introdon) の両方が引くので、テーマの層に置く (部品が画面の package に頼らないため)。
// =============================================================================

/** ステージ画面の配色・書体。値は iOS の `QS` と同じ。 */
object QS {
    val bg = Color(0xFF15131C)
    val panel = Color(0xFF1F1C28)
    val raised = Color(0xFF24212E)
    val line = Color(0xFF3A3547)
    val rowLine = Color(0xFF2E2A38)
    val missFill = Color(0xFF26232F)

    /** 本文 (生成り)。 */
    val ink = Color(0xFFF6F1E7)
    val dim = Color(0xFFA7A1B5)
    val faint = Color(0xFF8C8699)

    /** チケット (生成りの紙) の上の色。 */
    val paper = ink
    val paperInk = Color(0xFF1B1822)
    val paperTile = Color(0xFFEAE3D6)
    val paperHighlight = Color(0xFFEFE8DB)
    val paperSub = Color(0xFF6B6478)
    val paperMuted = Color(0xFFA49B8C)
    val paperLine = Color(0xFFE4DCCD)
    val paperDash = Color(0xFFC9C0B0)
    val stamp = Color(0xFFB42335)

    /** 答えの色が無いとき (曲など) にペンライトへ回す色。アプリアイコンの帯の色 (合同ライブの虹と同じ)。 */
    val penlights: List<Color> = ImasRainbow

    fun penlight(index: Int): Color = penlights[index.mod(penlights.size)]

    private val noPadding = PlatformTextStyle(includeFontPadding = false)

    /**
     * 大きな数字 (細長い太字・等幅数字)。書体は DS の [ImasType.condensedFamily]
     * (iOS の `.width(.compressed)` に当たる端末の sans-serif-condensed を太さごとに引く)。
     * 以前は Typeface 1 本で包んでいたので、太さの指定が効かずに細い字で出ていた。
     */
    fun num(size: Int, weight: FontWeight = FontWeight.ExtraBold): TextStyle = TextStyle(
        fontFamily = ImasType.condensedFamily, fontSize = size.sp, fontWeight = weight,
        fontFeatureSettings = "tnum", platformStyle = noPadding
    )

    /** 英字ラベル・番号 (等幅)。 */
    fun mono(size: Int, tracking: Float = 0f): TextStyle = TextStyle(
        fontFamily = FontFamily.Monospace, fontSize = size.sp, fontWeight = FontWeight.SemiBold,
        letterSpacing = tracking.sp, platformStyle = noPadding
    )

    fun text(size: Int, weight: FontWeight = FontWeight.Normal): TextStyle =
        TextStyle(fontSize = size.sp, fontWeight = weight, platformStyle = noPadding)
}
