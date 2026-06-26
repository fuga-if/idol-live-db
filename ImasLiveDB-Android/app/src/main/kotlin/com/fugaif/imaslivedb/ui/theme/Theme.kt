package com.fugaif.imaslivedb.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// iOS の DS トークンに合わせた固定ダークスキーム。Material You 動的カラーは使わない
// (端末壁紙由来の色が iOS デザインと乖離する原因だった)。クロムは無彩 (primary=白系)、
// 色はブランドアクセントとして各所で別途供給する。
private val ImasDarkColorScheme = darkColorScheme(
    primary = DS.ink,
    onPrimary = DS.onSys,
    primaryContainer = DS.surface2,
    onPrimaryContainer = DS.ink,
    secondary = DS.ink2,
    onSecondary = DS.onSys,
    secondaryContainer = DS.surface2,
    onSecondaryContainer = DS.ink,
    tertiary = DS.ink2,
    onTertiary = DS.onSys,
    background = DS.bg,
    onBackground = DS.ink,
    surface = DS.surface,
    onSurface = DS.ink,
    surfaceVariant = DS.surface2,
    onSurfaceVariant = DS.ink2,
    surfaceContainer = DS.surface,
    surfaceContainerHigh = DS.surface2,
    surfaceContainerHighest = DS.surface2,
    surfaceContainerLow = DS.surface,
    surfaceContainerLowest = DS.bg,
    outline = DS.sep,
    outlineVariant = DS.fill,
    error = DS.danger,
    onError = DS.onSys,
    scrim = Color(0xCC000000)
)

private val ImasLightColorScheme = lightColorScheme(
    primary = Color(0xFF1C1C1E),
    onPrimary = Color.White,
    background = Color(0xFFF2F2F7),
    onBackground = Color(0xFF1C1C1E),
    surface = Color.White,
    onSurface = Color(0xFF1C1C1E),
    surfaceVariant = Color(0xFFF2F2F7),
    onSurfaceVariant = Color(0x9E3C3C43),
    outline = Color(0x293C3C43),
    error = Color(0xFFE5342B),
    onError = Color.White
)

@Composable
fun ImasLiveDBTheme(
    darkTheme: Boolean = true,
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) ImasDarkColorScheme else ImasLightColorScheme,
        typography = Typography,
        content = content
    )
}
