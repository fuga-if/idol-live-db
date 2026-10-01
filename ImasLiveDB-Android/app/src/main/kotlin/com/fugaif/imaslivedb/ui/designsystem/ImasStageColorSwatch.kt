package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.QS
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.imasPress

// =============================================================================
// メンバーカラークイズの色見本 (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStageColorSwatch.swift` の移植。
//
// ImasStageColorSwatch      色そのものを選択肢として見せる (4 択の候補・並べるの色パレット)。
// ImasStageAssignmentTarget 色を割り当てる的 (引いて置く / 押して置くの行き先)。
// ImasStageColorGridIcon    4 色の小さな格子の記号 (ハブの「メンバーカラー合わせ」入口)。
//
// 色はステージ固定の `QS`。選択肢の色は問題のデータ (アイドルの色) をそのまま塗る。
// =============================================================================

/** 色見本の使い方 (iOS `ImasStageColorSwatch.Style`)。 */
enum class ImasStageColorSwatchStyle {
    /** 4 択の候補 (大きめ・押すと確定)。 */
    CHOICE,

    /** 並べるの引き元 (小さめ・使用済みの状態あり)。 */
    PALETTE
}

/**
 * 色そのものを選択肢として見せる (iOS `ImasStageColorSwatch`。メンバーカラークイズ専用)。
 *
 * @param letter 先頭の記号 (A/B/C…)。
 * @param isUsed 既にどこかへ割り当て済み (PALETTE のみ)。
 * @param isEliminated ヒントで消された (CHOICE のみ、押せない)。
 */
@Composable
fun ImasStageColorSwatch(
    hex: String,
    modifier: Modifier = Modifier,
    letter: String? = null,
    style: ImasStageColorSwatchStyle = ImasStageColorSwatchStyle.CHOICE,
    isSelected: Boolean = false,
    isUsed: Boolean = false,
    isEliminated: Boolean = false,
    onClick: (() -> Unit)? = null
) {
    val choice = style == ImasStageColorSwatchStyle.CHOICE
    val swatchHeight = if (choice) 76.dp else 56.dp
    val corner = if (choice) 18.dp else 16.dp
    val color = hexToColor(hex)
    val scale by animateFloatAsState(
        if (isSelected) 1.03f else 1f,
        spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow),
        label = "stageSwatch"
    )
    val spoken = listOfNotNull("色", letter, hex).joinToString(" ")
    Column(
        modifier
            .scale(scale)
            .alpha(if (isEliminated) 0.18f else if (isUsed && !isSelected) 0.45f else 1f)
            .clearAndSetSemantics {
                contentDescription = spoken
                selected = isSelected
                if (onClick != null) {
                    role = Role.Button
                    if (isEliminated) disabled() else onClick { onClick(); true }
                }
            }
            .then(if (onClick != null) Modifier.imasPress(enabled = !isEliminated, onClick = onClick) else Modifier)
            .background(QS.panel, RoundedCornerShape(corner))
            .border(if (isSelected) 2.5.dp else 1.dp, if (isSelected) QS.ink else QS.line, RoundedCornerShape(corner))
            .padding(if (choice) 8.dp else 6.dp),
        verticalArrangement = Arrangement.spacedBy(if (choice) 8.dp else 6.dp)
    ) {
        val inner = RoundedCornerShape(if (choice) 12.dp else 10.dp)
        Box(
            Modifier
                .fillMaxWidth()
                .height(swatchHeight)
                .background(color, inner)
                .then(if (choice) Modifier.border(1.dp, QS.line, inner) else Modifier),
            contentAlignment = Alignment.Center
        ) {
            if (!choice && isUsed) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = ImasTheme.onColor(color), modifier = Modifier.size(18.dp))
            }
        }
        if (letter != null) {
            Row(Modifier.padding(horizontal = if (choice) 4.dp else 2.dp), verticalAlignment = Alignment.CenterVertically) {
                val mono = QS.mono(if (choice) 11 else 10)
                Text(letter, style = mono, color = QS.faint)
                Spacer(Modifier.weight(1f).width(2.dp))
                Text(hex.uppercase(), style = mono, color = QS.ink, maxLines = 1)
            }
        }
    }
}

/**
 * 色を割り当てる的 (iOS `ImasStageAssignmentTarget`)。未割り当ては点線の丸に「?」。
 *
 * @param verdict 判定後の正誤 (null = まだ判定していない)。
 */
@Composable
fun ImasStageAssignmentTarget(
    assignedHex: String?,
    modifier: Modifier = Modifier,
    isTargeted: Boolean = false,
    verdict: Boolean? = null
) {
    val scale by animateFloatAsState(
        if (isTargeted) 1.12f else 1f,
        spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow),
        label = "stageTarget"
    )
    val ring = if (isTargeted) QS.paperInk else QS.paperMuted
    Box(
        modifier
            .size(44.dp)
            .scale(scale)
            .then(
                if (assignedHex != null) {
                    Modifier.background(hexToColor(assignedHex), CircleShape)
                } else {
                    Modifier.drawBehind {
                        val w = 2.dp.toPx()
                        drawCircle(
                            ring,
                            radius = (size.minDimension - w) / 2,
                            style = Stroke(width = w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx())))
                        )
                    }
                }
            ),
        contentAlignment = Alignment.Center
    ) {
        if (assignedHex == null) {
            Text("?", style = QS.num(18), color = QS.paperSub)
        }
        if (verdict != null) {
            Icon(
                if (verdict) Icons.Filled.Check else Icons.Filled.Close,
                contentDescription = if (verdict) "正解" else "不正解",
                tint = assignedHex?.let { ImasTheme.onColor(hexToColor(it)) } ?: QS.paperInk,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

/** 4 色の小さな格子の記号 (iOS `ImasStageColorGridIcon`。ハブの「メンバーカラー合わせ」入口)。 */
@Composable
fun ImasStageColorGridIcon(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(40.dp)
            .background(QS.bg, RoundedCornerShape(10.dp))
            .padding(9.dp)
            .clearAndSetSemantics { }
            .drawBehind {
                val gap = 3.dp.toPx()
                val cell = (size.width - gap) / 2
                val h = 9.dp.toPx()
                val top = (size.height - (h * 2 + gap)) / 2
                listOf(0, 4, 2, 3).forEachIndexed { i, colorIndex ->
                    val x = (i % 2) * (cell + gap)
                    val y = top + (i / 2) * (h + gap)
                    drawRoundRect(
                        QS.penlight(colorIndex),
                        topLeft = Offset(x, y),
                        size = Size(cell, h),
                        cornerRadius = CornerRadius(4.dp.toPx())
                    )
                }
            }
    )
}
