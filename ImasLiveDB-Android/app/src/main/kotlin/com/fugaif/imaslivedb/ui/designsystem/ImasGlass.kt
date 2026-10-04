package com.fugaif.imaslivedb.ui.designsystem

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Dp
import com.fugaif.imaslivedb.ui.theme.DS
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource

// =============================================================================
// ガラス (API 31 以降の背景ぼかし、Haze ライブラリ) は**浮いている枠だけ**に使う。
//
// 紙面 (地・一覧・カード・帯) は今までどおり平ら。ぼかした光・光沢を中身に足さない決まり
// (docs/DESIGN_SYSTEM.md・グラデーションと光の禁止) はそのまま。ぼかすのは、中身の上に浮いて
// 中身が透けて見える部品 — 歌詞プレイヤーの操作面・再生中バー — だけ。API 30 以前と、
// 供え ([imasHazeSource]) の無い画面では、今までの平らな面のまま。
// iOS `ImasGlass.swift` (`#available(iOS 26, *)` で `glassEffect` / それ以前は `DS.surface`) と対。
// =============================================================================

/**
 * 今の画面の浮いている枠が後ろの中身をぼかすための器。画面の根が [imasHazeSource] で 1 つ供え、
 * 浮く枠が [imasFloatingChrome] でそこから借りる。1 画面 (1 つの Dialog・1 つのタブの根) に 1 つ。
 */
val LocalImasHaze = staticCompositionLocalOf<HazeState?> { null }

/**
 * 画面の中身 (歌詞のスクロール・ナビゲーションの NavHost など) を [LocalImasHaze] の
 * 供え元として登録する。供え ([LocalImasHaze] を供える [androidx.compose.runtime.CompositionLocalProvider])
 * が無い画面では何もしない。
 */
@Composable
fun Modifier.imasHazeSource(): Modifier {
    val state = LocalImasHaze.current ?: return this
    return hazeSource(state = state)
}

/**
 * 浮いている枠の面 (歌詞プレイヤーの操作面・再生中バーなど)。API 31 以降は [imasHazeSource] で
 * 供えた中身をぼかすガラス、それより前と供えの無い画面では平らな面 (`DS.surface`)。
 *
 * @param cornerRadius 角丸。既定は浮いている枠の既定値 `DS.rXL` (iOS と同じ)。
 */
@Composable
fun Modifier.imasFloatingChrome(cornerRadius: Dp = DS.rXL): Modifier {
    val shape = RoundedCornerShape(cornerRadius)
    val state = LocalImasHaze.current
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && state != null) {
        // 紙の色を濃いめに敷き、後ろは「何かが流れている」程度にだけ透かす (iOS の imasGlassPaperFill と同じ 0.82)。
        // 粒子 (noise) は付けない。
        val style = HazeStyle(
            backgroundColor = DS.surface,
            tint = HazeTint(DS.surface.copy(alpha = 0.82f)),
            blurRadius = 24.dp,
            noiseFactor = 0f,
        )
        clip(shape).hazeEffect(state = state, style = style)
    } else {
        background(DS.surface, shape)
    }
}
