package com.fugaif.imaslivedb.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * iOS の DesignTokens (DS) を移植したファウンデーション・トークン。
 * 「システムクロムはほぼ無彩、色は常にブランド/エンティティから供給」という方針。
 * 既定のダーク値を持つ (アプリはダーク基調)。
 */
object DS {
    // ニュートラル (ダーク)
    val bg = Color(0xFF000000)
    val surface = Color(0xFF1C1C1E)
    val surface2 = Color(0xFF2C2C2E)
    val fill = Color(0x3D767680)       // rgba(118,118,128,0.24)
    val sep = Color(0x6B545458)        // rgba(84,84,88,0.42)
    val ink = Color(0xFFFFFFFF)
    val ink2 = Color(0x9EEBEBF5)       // rgba(235,235,245,0.62)
    val ink3 = Color(0x52EBEBF5)       // rgba(235,235,245,0.32)

    // セマンティック
    val success = Color(0xFF34D364)
    val warning = Color(0xFFFFB23E)
    val danger = Color(0xFFFF5247)
    /** システムクロムは「ほぼ無彩」。色は常にエンティティ側から来る → けばけばしさ回避 (iOS DS.sys 相当)。 */
    val sys = ink
    val onSys = Color(0xFF1C1C1E)

    // マイマーク
    val pick = Color(0xFFFF5A8C)
    val favorite = Color(0xFFFFC83E)
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
    BrandPalette.hex(brandId)?.let(::hexToColor) ?: Color.Gray
