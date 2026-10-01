package com.fugaif.imaslivedb.ui.theme

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Density
import androidx.core.view.WindowCompat

// iOS の DS トークンに合わせた固定スキーム。Material You 動的カラーは使わない
// (端末壁紙由来の色が iOS デザインと乖離する原因だった)。クロムは無彩 (primary=ink)、
// 色はブランドアクセントとして各所で別途供給する。
//
// ライト/ダークで違うのはトークンの値だけなので、割り当ては 1 本にして [ImasColors] を差し替える。
// 2 本書き分けると片方だけ直す事故が必ず起きる (実際、ライト側は久しく死んでいた)。
// Material の既定 (紫系のベースライン) が画面に漏れないよう、役割は全部 DS のトークンに割り当てる。
private fun imasColorScheme(c: ImasColors): ColorScheme {
    val base = if (c.dark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = c.ink,
        onPrimary = c.onSys,
        primaryContainer = c.surface2,
        onPrimaryContainer = c.ink,
        inversePrimary = c.onSys,
        secondary = c.ink2,
        onSecondary = c.onSys,
        secondaryContainer = c.surface2,
        onSecondaryContainer = c.ink,
        tertiary = c.ink2,
        onTertiary = c.onSys,
        tertiaryContainer = c.surface2,
        onTertiaryContainer = c.ink,
        background = c.bg,
        onBackground = c.ink,
        surface = c.surface,
        onSurface = c.ink,
        surfaceVariant = c.surface2,
        onSurfaceVariant = c.ink2,
        // `copy` は primary から導かれる既定を引き直さないので明示する (渡さないとベースラインの紫が残る)。
        // 値は primary と同じ ink (追従前の `darkColorScheme(primary = …)` が既定で入れていたもの)。
        surfaceTint = c.ink,
        inverseSurface = c.sys,
        inverseOnSurface = c.onSys,
        error = c.danger,
        onError = c.onSys,
        errorContainer = c.surface2,
        onErrorContainer = c.danger,
        // 輪郭 (入力欄の枠・未選択のスイッチのつまみと縁・枠線のボタン) は、面と溝の上で見分けが付く濃さ
        // (区切り線の sep では 1.1〜1.3:1 しか出ず、未選択のスイッチがほぼ消える)。区切り線は outlineVariant。
        outline = c.ink3,
        outlineVariant = c.sep,
        // ダイアログ/シートの下に敷く幕。ライトでも黒の半透明で正しい (面を暗く沈めるのが目的)。
        scrim = Color(0xCC000000),
        surfaceBright = c.surface,
        surfaceContainer = c.surface,
        surfaceContainerHigh = c.surface2,
        surfaceContainerHighest = c.surface2,
        surfaceContainerLow = c.surface,
        surfaceContainerLowest = c.bg,
        surfaceDim = c.bg
    )
}

private val ImasDarkColorScheme = imasColorScheme(ImasColorsDark)
private val ImasLightColorScheme = imasColorScheme(ImasColorsLight)

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
private fun ColorScheme.withOshiAccent(hex: String, colors: ImasColors): ColorScheme {
    if (hex.isBlank()) return this
    val theme = ImasTheme.derive(hex = hex, dark = colors.dark)
    // 無効な hex はコアがニュートラルグレーへ倒すので、その場合は既定のままにする
    // (設定 ON なのに色が灰色に化ける、を避ける)。
    if (theme.isNeutral) return this
    // primary はボタンの地だけでなく、TextButton・入力欄のラベル・カーソルの「文字の色」として面の上にも載る。
    // アクセントは明度の幅を絞っただけなので、ライトの紙の上では黄色系が読めない (1.1:1 まで落ちる)。
    // いちばんコントラストの取りにくい面 (surface2 = ダイアログの地。ライトでは最も暗く、ダークでは最も明るい)
    // に対して本文と同じ 4.5:1 になるまで明度を寄せる。判断はコアの ensure_contrast (足りていれば元の色のまま)。
    val accent = ImasTheme.ensureContrast(theme.accent, colors.surface2, MIN_TEXT_CONTRAST)
    return copy(primary = accent, onPrimary = ImasTheme.onColor(accent))
}

/** 文字として面に載せる色のコントラスト (WCAG AA の本文。コアの `DEFAULT_MIN_CONTRAST_RATIO` と同じ)。 */
private const val MIN_TEXT_CONTRAST = 4.5

/** その配色の Material スキーム (担当カラーの設定込み)。設定は合成の中で読むので変更に追従する。 */
@Composable
private fun imasMaterialScheme(colors: ImasColors): ColorScheme =
    (if (colors.dark) ImasDarkColorScheme else ImasLightColorScheme)
        .withOshiAccent(AppPreferences.oshiColorHex.takeIf { AppPreferences.useOshiColor }.orEmpty(), colors)

@Composable
fun ImasLiveDBTheme(
    // 端末のライト/ダーク設定に追従する (iOS が `@Environment(\.colorScheme)` を見るのと同じ)。
    // アプリ内に配色の設定項目は持たない。引数を残してあるのはプレビュー/テストが
    // 片方を名指しで出せるようにするためで、アプリ本体は既定のまま呼ぶこと。
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    // 表示設定はここが最初の読み手。Activity 側は `ImasLiveDBTheme { }` と呼ぶだけなので、
    // 読み込みもここで済ませる (合成の外から注入できる引数が無い)。
    val context = LocalContext.current
    remember(context) { AppPreferences.bind(context); Unit }

    val colors = if (darkTheme) ImasColorsDark else ImasColorsLight
    val scheme = imasMaterialScheme(colors)

    // アプリ内の文字サイズ倍率は Density の fontScale に掛ける。Typography だけ拡大すると
    // 直接 sp を指定している画面 (大半) が置いていかれるので、sp → px の変換そのものに効かせる。
    // dp は density 側なのでレイアウト寸法は変わらない。OS のフォントサイズ設定 (元の fontScale) に
    // 乗算するのは iOS が Dynamic Type に乗算するのと同じ扱い。
    val density = LocalDensity.current
    val scaled = remember(density, AppPreferences.textScale) {
        Density(density.density, density.fontScale * AppPreferences.textScale)
    }

    CompositionLocalProvider(LocalDensity provides scaled, LocalImasColors provides colors) {
        MaterialTheme(
            colorScheme = scheme,
            typography = Typography,
            content = content
        )
    }
}

/**
 * 中身だけを端末の設定に関係なくダークの配色で組む (iOS の `.environment(\.colorScheme, .dark)`)。
 *
 * ライト/ダークで反転させない暗い地の上に置く物に使う: ゲームのステージ (`QS.bg`) と
 * 共有画像 (`ShareInk.nearBlack`)。中で `DS.*` / `imasTheme(...)` / Material の部品の既定色を
 * 使っても、ライトモードで暗い地に暗い文字が載ることが無い。
 * 文字サイズの倍率 (Density) は [ImasLiveDBTheme] が掛けたものをそのまま使う (二重に掛けない)。
 */
@Composable
fun ImasAlwaysDark(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalImasColors provides ImasColorsDark) {
        MaterialTheme(colorScheme = imasMaterialScheme(ImasColorsDark), typography = Typography) {
            // Text / Icon の既定色。外側の明るい面が決めた暗い文字色を引き継がないようにする。
            CompositionLocalProvider(LocalContentColor provides ImasColorsDark.ink, content = content)
        }
    }
}

/**
 * この画面が出ている間だけ、ナビゲーションバー (画面下端の操作バー) のアイコンを明るい色にする
 * (iOS の `.toolbarColorScheme(.dark)` のうち下端の分)。
 *
 * ライト/ダークで反転させない暗い地を下端まで敷く所 (ゲームのステージ。タブバーを隠すので地が
 * ナビゲーションバーの裏まで伸びる) で使う。`enableEdgeToEdge()` はアイコンの色を端末のモードから
 * 決めるので、端末がライトだと暗い地に暗いアイコンが載る。画面を離れたら端末のモードの色に戻す。
 * 画面の切り替えの間は前後の画面が両方いることがあるので、最後の 1 つが消えたときだけ戻す。
 *
 * ステータスバーは触らない。上端はアプリの外枠 (AppNavigation の Scaffold) がステータスバーの高さを
 * 空けていて、裏に見えるのは外枠の地 (DS.bg = モードに追従) だから。ここを明るいアイコンにすると、
 * ライトでは生成りの地に白いアイコンが載って時刻も電池も消える。
 * Android 9 以下も触らない。ナビゲーションバーの地は enableEdgeToEdge が敷いた明るい地のままなので、
 * アイコンだけ明るくすると白地に白になる (Android 10 以上はアイコンの色に合わせて端末が地を敷き直す)。
 */
@Composable
fun ImasDarkNavigationBar() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
    val view = LocalView.current
    val systemDark = isSystemInDarkTheme()
    if (view.isInEditMode) return
    DisposableEffect(view, systemDark) {
        val window = view.context.findActivity()?.window ?: return@DisposableEffect onDispose { }
        val controller = WindowCompat.getInsetsController(window, view)
        darkNavigationBarRequests++
        controller.isAppearanceLightNavigationBars = false
        onDispose {
            darkNavigationBarRequests--
            if (darkNavigationBarRequests == 0) controller.isAppearanceLightNavigationBars = !systemDark
        }
    }
}

/** [ImasDarkNavigationBar] を出している画面の数 (合成はメインスレッドだけで走るので同期は要らない)。 */
private var darkNavigationBarRequests = 0

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
