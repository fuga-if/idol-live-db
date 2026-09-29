package com.fugaif.imaslivedb.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density

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

/**
 * 担当 (推し) カラーをスキーマのアクセントに差し込む。
 *
 * Material3 で「アプリ全体のアクセント」に当たるのは `primary` なので、そこだけ差し替える
 * (ボタン・スイッチ・進捗・TextButton の文字色などが一斉に担当色になる)。前景色は
 * 白固定にせず色エンジンが WCAG で選んだ `onAccent` を使う — 担当色には黄色や淡色も
 * 普通に存在し、白文字固定だと読めなくなるため。
 *
 * surface / ink 系は触らない。クロムは無彩のまま (DS の方針) で、色はアクセントからだけ差す。
 */
private fun ColorScheme.withOshiAccent(hex: String, dark: Boolean): ColorScheme {
    if (hex.isBlank()) return this
    val theme = ImasTheme.derive(hex = hex, dark = dark)
    // 無効な hex はコアがニュートラルグレーへ倒すので、その場合は既定のままにする
    // (設定 ON なのに色が灰色に化ける、を避ける)。
    if (theme.isNeutral) return this
    return copy(primary = theme.accent, onPrimary = theme.onAccent)
}

@Composable
fun ImasLiveDBTheme(
    darkTheme: Boolean = true,
    content: @Composable () -> Unit
) {
    // 表示設定はここが最初の読み手。Activity 側は `ImasLiveDBTheme { }` と呼ぶだけなので、
    // 読み込みもここで済ませる (合成の外から注入できる引数が無い)。
    val context = LocalContext.current
    remember(context) { AppPreferences.bind(context); Unit }

    val scheme = (if (darkTheme) ImasDarkColorScheme else ImasLightColorScheme)
        .withOshiAccent(AppPreferences.oshiColorHex.takeIf { AppPreferences.useOshiColor }.orEmpty(), darkTheme)

    // アプリ内の文字サイズ倍率は Density の fontScale に掛ける。Typography だけ拡大すると
    // 直接 sp を指定している画面 (大半) が置いていかれるので、sp → px の変換そのものに効かせる。
    // dp は density 側なのでレイアウト寸法は変わらない。OS のフォントサイズ設定 (元の fontScale) に
    // 乗算するのは iOS が Dynamic Type に乗算するのと同じ扱い。
    val density = LocalDensity.current
    val scaled = remember(density, AppPreferences.textScale) {
        Density(density.density, density.fontScale * AppPreferences.textScale)
    }

    CompositionLocalProvider(LocalDensity provides scaled) {
        MaterialTheme(
            colorScheme = scheme,
            typography = Typography,
            content = content
        )
    }
}
