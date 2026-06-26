package com.fugaif.imaslivedb.ui.theme

import androidx.compose.ui.graphics.Color
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

// =============================================================================
// ImasLiveDB — 無限色テーマエンジン (iOS DesignSystem/ImasTheme.swift の 1:1 移植)
// 入力は「シード色1色」だけ。そこから HSL 操作 + WCAG コントラストで UI トークン一式を導出。
// iOS / design/theme-engine.js と同じ計算結果になるよう導出規則を完全に揃える。
// =============================================================================

/** シード1色から導出されたテーマトークン一式。ライト/ダークで導出規則が変わる。 */
data class ImasTheme(
    val accent: Color,
    val onAccent: Color,
    val tint: Color,
    val tintStrong: Color,
    val chipBg: Color,
    val chipText: Color,
    val ring: Color,
    val bar: Color,
    val dot: Color,
    val gradFrom: Color,
    val gradTo: Color,
    val separator: Color,
    val heroSurface: Color,
    /** 低彩度シード (S < 0.10) は「グレー」扱いで発色を抑える。 */
    val isNeutral: Boolean
) {
    companion object {
        private val cache = HashMap<String, ImasTheme>()

        /** シード hex (アイドル色) → トークン。無ければブランド色 → ニュートラルへフォールバック。 */
        fun derive(seed: String?, brand: String? = null, dark: Boolean = true): ImasTheme {
            val hex = ColorMath.firstValidHex(seed, brand) ?: ColorMath.NEUTRAL_SEED
            return derive(hex, dark)
        }

        /** 単一の有効な hex からトークンを導出 (メモ化付き)。 */
        @Synchronized
        fun derive(hex: String, dark: Boolean): ImasTheme {
            val key = "$hex|$dark"
            cache[key]?.let { return it }
            val theme = compute(hex, dark)
            cache[key] = theme
            return theme
        }

        private fun compute(hex: String, dark: Boolean): ImasTheme {
            val (h, s, l) = ColorMath.rgbToHsl(ColorMath.hexToRgb(hex))
            val neutral = s < 0.10
            val clamp = ColorMath::clamp
            fun col(hh: Double, ss: Double, ll: Double): Color = ColorMath.color(hh, ss, ll)

            return if (!dark) {
                val aS = if (neutral) clamp(s, 0.0, 0.10) else clamp(s, 0.42, 0.92)
                val aL = clamp(l, 0.30, 0.54)
                val accentRGB = ColorMath.hslToRgb(h, clamp(aS, 0.0, 1.0), clamp(aL, 0.0, 1.0))
                ImasTheme(
                    accent = ColorMath.color(accentRGB),
                    onAccent = ColorMath.onColor(accentRGB),
                    tint = col(h, if (neutral) 0.04 else clamp(s * 0.5, 0.08, 0.34), 0.965),
                    tintStrong = col(h, if (neutral) 0.05 else clamp(s * 0.55, 0.10, 0.42), 0.910),
                    chipBg = col(h, if (neutral) 0.05 else clamp(s * 0.5, 0.10, 0.34), 0.935),
                    chipText = col(h, if (neutral) clamp(s, 0.0, 0.12) else clamp(s, 0.50, 0.95), clamp(l, 0.24, 0.40)),
                    ring = col(h, aS, clamp(aL + 0.06, 0.0, 0.62)),
                    bar = ColorMath.color(accentRGB),
                    dot = ColorMath.color(accentRGB),
                    gradFrom = col(h, aS, clamp(aL + 0.05, 0.0, 0.60)),
                    gradTo = col(h, clamp(aS + 0.05, 0.0, 1.0), clamp(aL - 0.10, 0.16, 1.0)),
                    separator = col(h, if (neutral) 0.04 else clamp(s * 0.4, 0.06, 0.24), 0.86),
                    heroSurface = col(h, if (neutral) 0.05 else clamp(s * 0.5, 0.10, 0.40), 0.955),
                    isNeutral = neutral
                )
            } else {
                val aS = if (neutral) clamp(s, 0.0, 0.14) else clamp(s, 0.45, 0.88)
                val aL = clamp(l, 0.56, 0.74)
                val accentRGB = ColorMath.hslToRgb(h, clamp(aS, 0.0, 1.0), clamp(aL, 0.0, 1.0))
                ImasTheme(
                    accent = ColorMath.color(accentRGB),
                    onAccent = ColorMath.onColor(accentRGB),
                    tint = col(h, if (neutral) 0.06 else clamp(s * 0.5, 0.10, 0.42), 0.175),
                    tintStrong = col(h, if (neutral) 0.07 else clamp(s * 0.55, 0.12, 0.48), 0.235),
                    chipBg = col(h, if (neutral) 0.07 else clamp(s * 0.5, 0.12, 0.42), 0.225),
                    chipText = col(h, aS, clamp(aL + 0.06, 0.0, 0.84)),
                    ring = col(h, aS, clamp(aL, 0.0, 0.70)),
                    bar = ColorMath.color(accentRGB),
                    dot = ColorMath.color(accentRGB),
                    gradFrom = col(h, aS, clamp(aL, 0.0, 0.66)),
                    gradTo = col(h, clamp(aS + 0.04, 0.0, 1.0), clamp(aL - 0.14, 0.30, 1.0)),
                    separator = col(h, if (neutral) 0.05 else clamp(s * 0.4, 0.08, 0.30), 0.30),
                    heroSurface = col(h, if (neutral) 0.06 else clamp(s * 0.5, 0.10, 0.45), 0.20),
                    isNeutral = neutral
                )
            }
        }
    }
}

/** 色変換 / WCAG コントラスト (iOS ColorMath / theme-engine.js と同じ式)。 */
object ColorMath {
    const val NEUTRAL_SEED = "#8E8E93"

    fun clamp(v: Double, lo: Double, hi: Double): Double = min(hi, max(lo, v))

    fun firstValidHex(vararg candidates: String?): String? =
        candidates.firstOrNull { it != null && normalizedHex(it) != null }

    fun normalizedHex(hex: String): String? {
        var s = hex.trim()
        if (s.startsWith("#")) s = s.substring(1)
        if (s.length == 3) s = s.map { "$it$it" }.joinToString("")
        if (s.length != 6 || !s.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return null
        return s.lowercase()
    }

    data class Rgb(val r: Double, val g: Double, val b: Double) // 0–255

    fun hexToRgb(hex: String): Rgb {
        val s = normalizedHex(hex) ?: "8e8e93"
        val n = s.toLong(16)
        return Rgb(((n shr 16) and 255).toDouble(), ((n shr 8) and 255).toDouble(), (n and 255).toDouble())
    }

    fun rgbToHsl(rgb: Rgb): Triple<Double, Double, Double> {
        val r = rgb.r / 255; val g = rgb.g / 255; val b = rgb.b / 255
        val mx = max(r, max(g, b)); val mn = min(r, min(g, b))
        var h = 0.0; var s = 0.0
        val l = (mx + mn) / 2
        if (mx != mn) {
            val d = mx - mn
            s = if (l > 0.5) d / (2 - mx - mn) else d / (mx + mn)
            h = when (mx) {
                r -> (g - b) / d + (if (g < b) 6 else 0)
                g -> (b - r) / d + 2
                else -> (r - g) / d + 4
            }
            h /= 6
        }
        return Triple(h * 360, s, l)
    }

    fun hslToRgb(hDeg: Double, s: Double, l: Double): Rgb {
        val h = ((hDeg % 360 + 360) % 360) / 360
        if (s == 0.0) return Rgb(l * 255, l * 255, l * 255)
        fun hue2rgb(p: Double, q: Double, tIn: Double): Double {
            var t = tIn
            if (t < 0) t += 1
            if (t > 1) t -= 1
            if (t < 1.0 / 6) return p + (q - p) * 6 * t
            if (t < 1.0 / 2) return q
            if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6
            return p
        }
        val q = if (l < 0.5) l * (1 + s) else l + s - l * s
        val p = 2 * l - q
        return Rgb(hue2rgb(p, q, h + 1.0 / 3) * 255, hue2rgb(p, q, h) * 255, hue2rgb(p, q, h - 1.0 / 3) * 255)
    }

    fun color(rgb: Rgb): Color =
        Color(clamp(rgb.r, 0.0, 255.0).toFloat() / 255f, clamp(rgb.g, 0.0, 255.0).toFloat() / 255f, clamp(rgb.b, 0.0, 255.0).toFloat() / 255f)

    fun color(h: Double, s: Double, l: Double): Color =
        color(hslToRgb(h, clamp(s, 0.0, 1.0), clamp(l, 0.0, 1.0)))

    private fun relLum(rgb: Rgb): Double {
        fun f(x: Double): Double { val c = x / 255; return if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4) }
        return 0.2126 * f(rgb.r) + 0.7152 * f(rgb.g) + 0.0722 * f(rgb.b)
    }

    private fun contrast(a: Rgb, b: Rgb): Double {
        val l1 = relLum(a); val l2 = relLum(b)
        val hi = max(l1, l2); val lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    /** accent 面の上に乗せる前景色 (黒/白を WCAG 4.5:1 で自動選択)。 */
    fun onColor(bg: Rgb): Color {
        val ink = Rgb(0x15.toDouble(), 0x16.toDouble(), 0x1A.toDouble())
        val paper = Rgb(255.0, 255.0, 255.0)
        val cInk = contrast(bg, ink)
        val cWhite = contrast(bg, paper)
        if (cWhite >= 4.5) return color(paper)
        if (cInk >= 4.5) return color(ink)
        return if (cWhite > cInk) color(paper) else color(ink)
    }

    /** 任意の背景 Color の上に乗せる前景色を WCAG で黒/白から選ぶ。 */
    fun onColor(bg: Color): Color =
        onColor(Rgb(bg.red.toDouble() * 255, bg.green.toDouble() * 255, bg.blue.toDouble() * 255))
}
