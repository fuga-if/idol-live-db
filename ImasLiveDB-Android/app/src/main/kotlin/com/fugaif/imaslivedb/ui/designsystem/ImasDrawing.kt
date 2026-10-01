package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.addOutline
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// =============================================================================
// 部品の中だけで使う描き方の道具 (iOS では SwiftUI が持っている物の代わり)。
//
// - 柔らかい影 (`.shadow(color:radius:y:)`)。Compose の elevation の影は光源つきの濃い影で、
//   iOS の「紙が少し浮く」薄い影にならないので、塗りに影の層を付けて描く。
// - 点線 (`StrokeStyle(dash:)`)。
// - 入りきらないときだけ縮む文字 (`.minimumScaleFactor`)。
// - 左右へはみ出させる (`.padding(.horizontal, -x)`)。
//
// 画面からは使わない (部品が使う)。
// =============================================================================

/**
 * 形 [shape] を [fill] で塗り、その下に柔らかい影を落とす (iOS `.shadow(color:radius:y:)`)。
 *
 * 影は塗りに付けた影の層 (`setShadowLayer`) で描く。塗りが透明だと影も出ないので、
 * 上に描く面と同じ色を [fill] に渡す (面はそのまま上に重なる)。
 * Android 9 未満のハードウェア描画は図形の影の層を描かないので、そこでは影が付かない (塗りだけ)。
 *
 * @param blur ぼかしの半径。0 は影の層を外す扱いになるので、くっきりした影は [offsetY] だけずらした塗りで描く。
 */
internal fun Modifier.imasSoftShadow(
    shape: Shape,
    fill: Color,
    color: Color,
    blur: Dp,
    offsetY: Dp = 0.dp
): Modifier = drawWithCache {
    val path = androidx.compose.ui.graphics.Path().apply {
        addOutline(shape.createOutline(size, layoutDirection, this@drawWithCache))
    }
    val dy = offsetY.toPx()
    val blurPx = blur.toPx()
    val paint = Paint().apply {
        this.color = fill
        if (blurPx > 0f) asFrameworkPaint().setShadowLayer(blurPx, 0f, dy, color.toArgb())
    }
    val hardShadow = if (blurPx > 0f) null else Paint().apply { this.color = color }
    onDrawBehind {
        drawIntoCanvas { canvas ->
            if (hardShadow != null) {
                translate(top = dy) { canvas.drawPath(path, hardShadow) }
            }
            canvas.drawPath(path, paint)
        }
    }
}

/** 点線を 1 本引く (切り取り線)。点と間は線の太さの 3 倍 (iOS `ImasPerforation` と同じ)。 */
internal fun DrawScope.drawImasDash(start: Offset, end: Offset, color: Color, width: Float) {
    drawLine(
        color = color,
        start = start,
        end = end,
        strokeWidth = width,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf(width * 3f, width * 3f))
    )
}

/**
 * 左右へ [horizontal] だけはみ出させる (iOS の負の余白 `.padding(.horizontal, -x)`)。
 * 紙面にそのまま並べる一覧 (`ImasCardList(PLAIN)`) で、行を画面の端から端まで届かせる。
 */
internal fun Modifier.imasBleed(horizontal: Dp): Modifier = layout { measurable, constraints ->
    val bleed = horizontal.roundToPx()
    val wide = if (constraints.hasBoundedWidth) {
        constraints.copy(
            minWidth = constraints.minWidth + bleed * 2,
            maxWidth = constraints.maxWidth + bleed * 2
        )
    } else constraints
    val placeable = measurable.measure(wide)
    val width = (placeable.width - bleed * 2).coerceIn(constraints.minWidth, constraints.maxWidth)
    layout(width, placeable.height) { placeable.place(-bleed, 0) }
}

/**
 * 入りきらないときだけ文字を縮める (iOS の `.minimumScaleFactor`)。
 * Compose 1.7 には文字の自動縮小が無いので、はみ出したら 1 割ずつ縮めて測り直す。
 * 測り終わるまでは描かない (縮む途中のちらつきを見せない)。ゲームの `QSFitText` と同じ作り。
 */
@Composable
internal fun ImasFitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    maxLines: Int = 1,
    minScale: Float = 0.6f,
    textAlign: TextAlign? = null,
    textDecoration: TextDecoration? = null
) {
    var scale by remember(text, style) { mutableFloatStateOf(1f) }
    var ready by remember(text, style) { mutableStateOf(false) }
    // 置き場所の幅が変わったら (回転・分割画面) 測り直す。
    var measuredFor by remember(text, style) { mutableIntStateOf(-1) }
    Text(
        text = text,
        style = style.copy(fontSize = style.fontSize * scale),
        color = color,
        maxLines = maxLines,
        softWrap = maxLines > 1,
        overflow = if (ready) TextOverflow.Ellipsis else TextOverflow.Clip,
        textAlign = textAlign,
        textDecoration = textDecoration,
        modifier = modifier.drawWithContent { if (ready) drawContent() },
        onTextLayout = { r ->
            val width = r.layoutInput.constraints.maxWidth
            if (ready && measuredFor != width) {
                measuredFor = width
                scale = 1f
                ready = false
                return@Text
            }
            measuredFor = width
            if (!ready) {
                if (r.hasVisualOverflow && scale > minScale) {
                    scale = maxOf(minScale, scale * 0.9f)
                } else {
                    ready = true
                }
            }
        }
    )
}
