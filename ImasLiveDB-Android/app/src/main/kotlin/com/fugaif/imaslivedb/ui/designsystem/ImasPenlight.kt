package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.lyrics.LyricPartCast
import com.fugaif.imaslivedb.data.lyrics.LyricPenlight
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.QS
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.imasStripesVertical
import uniffi.imas_core.PenlightColorKind
import uniffi.imas_core.lyricPenlightColorName
import uniffi.imas_core.lyricPenlightFallbackText

// =============================================================================
// ペンライトの指示 (ペンラ芸) の見た目。iOS DesignSystem/Components/ImasPenlight.swift と 1:1。
//
// 光らせない。棒は角のある平らな色の面で、光・ぼかし・グラデーションは使わない
// (担当色のような「人によって違う色」は縞)。白が地に溶けないよう細い墨の縁を必ず引く。
// =============================================================================

/** 棒の塗り。 */
sealed interface ImasPenlightFill {
    data class Solid(val color: Color) : ImasPenlightFill
    /** 各自の担当色 (人によって違う) を縞で。 */
    data class Stripes(val colors: List<Color>) : ImasPenlightFill
    /** 色の指示なし (メモだけ)。縁だけ描く。 */
    data object None : ImasPenlightFill
}

/** ペンライトの指示を描くための引き方 (iOS `PenlightLook`)。色の書き方はコア、アイドルの色と名前は原唱者から。 */
class PenlightLook(val penlight: LyricPenlight, private val cast: LyricPartCast) {
    private val parsed = penlight.parsedColor

    val fill: ImasPenlightFill
        get() {
            val p = parsed ?: return ImasPenlightFill.None
            return when (p.kind) {
                PenlightColorKind.OSHI -> ImasPenlightFill.Stripes(QS.penlights)
                PenlightColorKind.IDOL -> p.idolId?.let { cast.colors(listOf(it)).firstOrNull() }
                    ?.let { ImasPenlightFill.Solid(hexToColor(it)) } ?: ImasPenlightFill.None
                PenlightColorKind.FIXED -> ImasPenlightFill.Solid(rgbColor(p.rgb ?: 0u))
            }
        }

    val colorName: String?
        get() {
            val given = if (parsed?.kind == PenlightColorKind.IDOL) {
                parsed.idolId?.let { cast.names(listOf(it)).firstOrNull() }?.let { "${it}の色" }
            } else null
            return lyricPenlightColorName(penlight.color, given)
        }

    /** 読み上げる文 (「ペンライト: 青・左右に振る」)。 */
    val description: String
        get() = lyricPenlightFallbackText(penlight.color, colorName, penlight.note)

    companion object {
        fun rgbColor(rgb: UInt): Color = Color(0xFF000000.toInt() or (rgb.toInt() and 0xFFFFFF))
    }
}

/** ペンライトの棒 1 本。 */
@Composable
fun ImasPenlightStick(fill: ImasPenlightFill, height: Dp = 16.dp, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(1.5.dp)
    val base = modifier.size(width = maxOf(5.dp, height * 0.34f), height = height)
    val filled = when (fill) {
        is ImasPenlightFill.Solid -> base.clip(shape).background(fill.color)
        is ImasPenlightFill.Stripes -> base.clip(shape).drawBehind { drawRect(imasStripesVertical(fill.colors, size.height)) }
        ImasPenlightFill.None -> base
    }
    Box(filled.border(1.dp, DS.ink.copy(alpha = if (fill == ImasPenlightFill.None) 0.45f else 0.3f), shape))
}

/** 歌詞の行の下に並ぶペンライトの指示 1 つ: 棒 + メモ (iOS `ImasPenlightCueLabel`)。 */
@Composable
fun ImasPenlightCueLabel(look: PenlightLook, modifier: Modifier = Modifier, player: Boolean = false, isActive: Boolean = true) {
    val stick by animateFloatAsState(if (!player) 16f else if (isActive) 30f else 20f, label = "imasPenlightStick")
    val textSize = if (!player) 13f else if (isActive) 18f else 14f
    Row(
        modifier
            .alpha(if (player && !isActive) 0.55f else 1f)
            .clearAndSetSemantics { contentDescription = look.description },
        horizontalArrangement = Arrangement.spacedBy(if (player) DS.sp2 else 5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasPenlightStick(look.fill, height = stick.dp)
        look.penlight.note?.let {
            Text(it, style = if (player) ImasType.heading(textSize.sp, FontWeight.Bold) else ImasType.text(textSize.sp, FontWeight.SemiBold),
                color = DS.ink2)
        }
    }
}

/** 歌詞プレイヤーで行の直下に流すペンライトの指示 (iOS `ImasPlayerPenlightLine`)。 */
@Composable
fun ImasPlayerPenlightLine(marker: String, look: PenlightLook, isActive: Boolean, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .padding(start = DS.sp3)
            .clearAndSetSemantics {
                contentDescription = look.description
                selected = isActive
            },
        horizontalArrangement = Arrangement.spacedBy(DS.sp2),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(marker, style = ImasType.text(12.sp), color = DS.ink3, textAlign = TextAlign.End, modifier = Modifier.width(16.dp))
        ImasPenlightCueLabel(look, player = true, isActive = isActive)
    }
}
