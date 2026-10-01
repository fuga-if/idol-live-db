package com.fugaif.imaslivedb.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

// =============================================================================
// iOS の DesignTokens (DS) を移植したファウンデーション・トークン一式。
// 「システムクロムはほぼ無彩、色は常にブランド/エンティティから供給」という方針。
//
// ライト/ダークの 2 組を値として持ち、どちらを使うかは [LocalImasColors] が決める。
// iOS 側は `UIColor { $0.userInterfaceStyle }` の動的色 1 個で同じことをしているが、
// Compose の `Color` は解決済みの値でしかないので、「現在のトレイト」に当たる物を
// CompositionLocal として持ち回す。
// =============================================================================

/** DS の色トークン 1 組 (ライトかダークのどちらか)。名前は iOS の `DS.*` と同じ。 */
@Immutable
data class ImasColors(
    /** この組がダーク側か。テーマ由来の色 ([ImasTheme]) の導出規則もこれで切り替わる。 */
    val dark: Boolean,
    val bg: Color,
    val surface: Color,
    val surface2: Color,
    val fill: Color,
    val sep: Color,
    val ink: Color,
    val ink2: Color,
    val ink3: Color,
    val success: Color,
    val warning: Color,
    val danger: Color,
    /** システムクロムは「ほぼ無彩」。色は常にエンティティ側から来る → けばけばしさ回避。 */
    val sys: Color,
    /** sys を背景にしたときの前景色 (sys の反転)。sys はモードで白/黒が入れ替わるので固定不可。 */
    val onSys: Color,
    /** マイマーク固有色 (担当♥) */
    val pick: Color,
    /** マイマーク固有色 (お気に入り★) */
    val favorite: Color
)

/** ダーク側のトークン。値は iOS `DesignTokens.swift` の dark 列と 1:1。 */
val ImasColorsDark = ImasColors(
    dark = true,
    bg = Color(0xFF000000),
    surface = Color(0xFF1C1C1E),
    surface2 = Color(0xFF2C2C2E),
    fill = Color(0x3D767680),       // rgba(118,118,128,0.24)
    sep = Color(0x6B545458),        // rgba(84,84,88,0.42)
    ink = Color(0xFFFFFFFF),
    ink2 = Color(0x9EEBEBF5),       // rgba(235,235,245,0.62)
    ink3 = Color(0x52EBEBF5),       // rgba(235,235,245,0.32)
    success = Color(0xFF34D364),
    warning = Color(0xFFFFB23E),
    danger = Color(0xFFFF5247),
    sys = Color(0xFFFFFFFF),
    onSys = Color(0xFF1C1C1E),
    pick = Color(0xFFFF5A8C),
    favorite = Color(0xFFFFC83E)
)

/** ライト側のトークン。値は iOS `DesignTokens.swift` の light 列と 1:1。 */
val ImasColorsLight = ImasColors(
    dark = false,
    bg = Color(0xFFF2F2F7),
    surface = Color(0xFFFFFFFF),
    surface2 = Color(0xFFF2F2F7),
    fill = Color(0x1F767680),       // rgba(118,118,128,0.12)
    sep = Color(0x293C3C43),        // rgba(60,60,67,0.16)
    ink = Color(0xFF1C1C1E),
    ink2 = Color(0x9E3C3C43),       // rgba(60,60,67,0.62)
    ink3 = Color(0x573C3C43),       // rgba(60,60,67,0.34)
    success = Color(0xFF2FA84F),
    warning = Color(0xFFE08600),
    danger = Color(0xFFE5342B),
    sys = Color(0xFF1C1C1E),
    onSys = Color(0xFFFFFFFF),
    pick = Color(0xFFFF2D78),
    favorite = Color(0xFFE8A800)
)

/**
 * 現在の配色。[ImasLiveDBTheme] が端末のライト/ダーク設定から供給する。
 *
 * `static` なのは、この値が変わったとき (= モード切替) は画面全体を描き直すのが正しいから。
 * 通常の CompositionLocal だと読み手だけを賢く無効化しようとするが、色は全域で読まれるので
 * その追跡コストが毎回の再コンポーズに乗るだけで得が無い。
 *
 * 既定をダークにしてあるのは、[ImasLiveDBTheme] の外 (Glance ウィジェット、プレビュー) から
 * 引かれても破綻しないようにするため。アプリ本体は必ずテーマの内側で読む。
 */
val LocalImasColors = staticCompositionLocalOf { ImasColorsDark }

/**
 * トークンの読み出し口。`DS.ink` と書けば現在のモードの ink が返る。
 *
 * プロパティが `@Composable` なのは、iOS の DS が動的 `UIColor` であるのと同じ理由 —
 * 「今どちらのモードか」を知っているのは呼ばれた場所であって、定義した場所ではない。
 * 合成の外 (Glance、DrawScope、非 Composable なヘルパ) から要る場合は、合成の中で
 * `LocalImasColors.current` を値にして渡すか、[ImasColorsDark] / [ImasColorsLight] を名指しで使うこと。
 */
object DS {
    // ニュートラル
    val bg: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.bg
    val surface: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.surface
    val surface2: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.surface2
    val fill: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.fill
    val sep: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.sep
    val ink: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ink
    val ink2: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ink2
    val ink3: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.ink3

    // セマンティック
    val success: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.success
    val warning: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.warning
    val danger: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.danger
    val sys: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.sys
    val onSys: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.onSys

    // マイマーク
    val pick: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.pick
    val favorite: Color @Composable @ReadOnlyComposable get() = LocalImasColors.current.favorite
}

/**
 * Convert a hex color string (with or without leading #) to a Compose Color.
 * Returns Color.Gray on parse failure.
 */
fun hexToColor(hex: String): Color {
    val cleaned = hex.trimStart('#')
    return try {
        val value = cleaned.toLong(16)
        when (cleaned.length) {
            6 -> Color(0xFF000000 or value)
            8 -> Color(value)
            else -> Color.Gray
        }
    } catch (e: NumberFormatException) {
        Color.Gray
    }
}

/** Return the brand color for a given brandId string, or Gray if unknown. */
fun brandColor(brandId: String?): Color =
    BrandColors.hex(brandId)?.let(::hexToColor) ?: Color.Gray
