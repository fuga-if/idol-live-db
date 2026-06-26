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
    val onSys = Color(0xFF1C1C1E)

    // マイマーク
    val pick = Color(0xFFFF5A8C)
    val favorite = Color(0xFFFFC83E)
}

// Brand color constants
val Brand765AS = Color(0xFFFE0000)
val Brand961 = Color(0xFF520000)
val Brand876 = Color(0xFF6EC6C8)
val BrandCG = Color(0xFF2681C8)
val BrandML = Color(0xFFFFC30B)
val BrandSideM = Color(0xFF0FBE94)
val BrandSC = Color(0xFF6BB6B9)
val BrandGakuen = Color(0xFFFF6699)
val BrandValiv = Color(0xFF7F51DC)

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
fun brandColor(brandId: String?): Color = when (brandId) {
    "765as" -> Brand765AS
    "961" -> Brand961
    "876" -> Brand876
    "cg" -> BrandCG
    "ml" -> BrandML
    "sidem" -> BrandSideM
    "sc" -> BrandSC
    "gakuen" -> BrandGakuen
    "valiv" -> BrandValiv
    else -> Color.Gray
}
