import SwiftUI
import UIKit

// =============================================================================
// ImasLiveDB — 無限色テーマエンジン (Theme Engine)  ※ design/theme-engine.js の 1:1 移植
// -----------------------------------------------------------------------------
// 入力は「シード色 1 色」だけ。そこから UI に必要なトークン一式を機械的に導出する。
// ロジックは HSL 操作 + WCAG コントラストのみ。SwiftUI でも JS と同じ計算結果になるよう
// 各トークンの導出規則を design/theme-engine.js と完全に揃えている。
//
// 集約 (一覧) では穏やか・フォーカス (詳細/担当ヒーロー) では鮮やか、の原則に従い、
// 色の優先順位は「アイドル色 → 所属ブランド色 → ニュートラル」のフォールバック連鎖。
// =============================================================================

/// シード 1 色から導出されたテーマトークン一式。ライト/ダークで導出規則が変わる。
struct ImasTheme: Equatable {
    var accent: Color
    var onAccent: Color
    var tint: Color
    var tintStrong: Color
    var chipBg: Color
    var chipText: Color
    var ring: Color
    var bar: Color
    var dot: Color
    var gradFrom: Color
    var gradTo: Color
    var separator: Color
    var heroSurface: Color
    /// 低彩度シード (S < 0.10) は「グレー」扱いで発色を抑える。
    var isNeutral: Bool

    // MARK: - 導出エントリポイント

    /// シード hex (アイドル色) → トークン。色が無ければブランド色 → ニュートラルへフォールバック。
    /// - Parameters:
    ///   - seed: アイドル等のイメージカラー hex (`#RRGGBB`)。nil/不正なら次へ。
    ///   - brand: ブランドカラー hex。seed が無いときのフォールバック。
    ///   - scheme: ライト/ダーク。
    static func derive(seed: String?, brand: String? = nil, scheme: ColorScheme) -> ImasTheme {
        let hex = ColorMath.firstValidHex(seed, brand) ?? ColorMath.neutralSeed
        return derive(hex: hex, dark: scheme == .dark)
    }

    /// 導出結果のメモ。(hex|dark) ごとに 1 度だけ計算する。一覧では全行の avatar/chip が
    /// 同じ少数の色を何度も導出するため、HSL 演算 + 十数トークン生成を毎描画で繰り返すと
    /// スクロール/タブ切替のフレーム落ちになる。distinct な色数は高々アイドル数×2 で有界。
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: ImasTheme] = [:]

    /// 単一の有効な hex からトークンを導出する低レベル API (メモ化付き)。
    static func derive(hex: String, dark: Bool) -> ImasTheme {
        let key = "\(hex)|\(dark)"
        if let cached = cacheLock.withLock({ cache[key] }) { return cached }

        let theme = compute(hex: hex, dark: dark)
        cacheLock.withLock { cache[key] = theme }
        return theme
    }

    /// 実際の導出計算 (純粋関数)。derive(hex:dark:) からのみ呼ぶ。
    private static func compute(hex: String, dark: Bool) -> ImasTheme {
        let (h, s, l) = ColorMath.rgbToHsl(ColorMath.hexToRgb(hex))
        let neutral = s < 0.10
        func col(_ hh: Double, _ ss: Double, _ ll: Double) -> Color { ColorMath.color(h: hh, s: ss, l: ll) }
        let clamp = ColorMath.clamp

        if !dark {
            let aS = neutral ? clamp(s, 0, 0.10) : clamp(s, 0.42, 0.92)
            let aL = clamp(l, 0.30, 0.54)
            let accentRGB = ColorMath.hslToRgb(h, clamp(aS, 0, 1), clamp(aL, 0, 1))
            return ImasTheme(
                accent: ColorMath.color(accentRGB),
                onAccent: ColorMath.onColor(accentRGB),
                tint: col(h, neutral ? 0.04 : clamp(s * 0.5, 0.08, 0.34), 0.965),
                tintStrong: col(h, neutral ? 0.05 : clamp(s * 0.55, 0.10, 0.42), 0.910),
                chipBg: col(h, neutral ? 0.05 : clamp(s * 0.5, 0.10, 0.34), 0.935),
                chipText: col(h, neutral ? clamp(s, 0, 0.12) : clamp(s, 0.50, 0.95), clamp(l, 0.24, 0.40)),
                ring: col(h, aS, clamp(aL + 0.06, 0, 0.62)),
                bar: ColorMath.color(accentRGB),
                dot: ColorMath.color(accentRGB),
                gradFrom: col(h, aS, clamp(aL + 0.05, 0, 0.60)),
                gradTo: col(h, clamp(aS + 0.05, 0, 1), clamp(aL - 0.10, 0.16, 1)),
                separator: col(h, neutral ? 0.04 : clamp(s * 0.4, 0.06, 0.24), 0.86),
                heroSurface: col(h, neutral ? 0.05 : clamp(s * 0.5, 0.10, 0.40), 0.955),
                isNeutral: neutral
            )
        } else {
            let aS = neutral ? clamp(s, 0, 0.14) : clamp(s, 0.45, 0.88)
            let aL = clamp(l, 0.56, 0.74)
            let accentRGB = ColorMath.hslToRgb(h, clamp(aS, 0, 1), clamp(aL, 0, 1))
            return ImasTheme(
                accent: ColorMath.color(accentRGB),
                onAccent: ColorMath.onColor(accentRGB),
                tint: col(h, neutral ? 0.06 : clamp(s * 0.5, 0.10, 0.42), 0.175),
                tintStrong: col(h, neutral ? 0.07 : clamp(s * 0.55, 0.12, 0.48), 0.235),
                chipBg: col(h, neutral ? 0.07 : clamp(s * 0.5, 0.12, 0.42), 0.225),
                chipText: col(h, aS, clamp(aL + 0.06, 0, 0.84)),
                ring: col(h, aS, clamp(aL, 0, 0.70)),
                bar: ColorMath.color(accentRGB),
                dot: ColorMath.color(accentRGB),
                gradFrom: col(h, aS, clamp(aL, 0, 0.66)),
                gradTo: col(h, clamp(aS + 0.04, 0, 1), clamp(aL - 0.14, 0.30, 1)),
                separator: col(h, neutral ? 0.05 : clamp(s * 0.4, 0.08, 0.30), 0.30),
                heroSurface: col(h, neutral ? 0.06 : clamp(s * 0.5, 0.10, 0.45), 0.20),
                isNeutral: neutral
            )
        }
    }
}

// MARK: - 色変換 / WCAG コントラスト (theme-engine.js と同じ式)

enum ColorMath {
    /// 色が無いときに使う低彩度グレーのシード (ニュートラル経路に落ちる)。
    static let neutralSeed = "#8E8E93"

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    /// 最初に見つかった有効な hex を返す。
    static func firstValidHex(_ candidates: String?...) -> String? {
        for c in candidates {
            if let c, normalizedHex(c) != nil { return c }
        }
        return nil
    }

    /// `#RGB` / `#RRGGBB` を 6 桁小文字 hex に正規化。無効なら nil。
    static func normalizedHex(_ hex: String) -> String? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return s.lowercased()
    }

    struct RGB { var r: Double; var g: Double; var b: Double } // 0–255

    static func hexToRgb(_ hex: String) -> RGB {
        let s = normalizedHex(hex) ?? "8e8e93"
        let n = UInt32(s, radix: 16) ?? 0
        return RGB(r: Double((n >> 16) & 255), g: Double((n >> 8) & 255), b: Double(n & 255))
    }

    static func rgbToHsl(_ rgb: RGB) -> (h: Double, s: Double, l: Double) {
        let r = rgb.r / 255, g = rgb.g / 255, b = rgb.b / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        var h = 0.0, s = 0.0
        let l = (mx + mn) / 2
        if mx != mn {
            let d = mx - mn
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            switch mx {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h /= 6
        }
        return (h * 360, s, l)
    }

    static func hslToRgb(_ hDeg: Double, _ s: Double, _ l: Double) -> RGB {
        let h = (hDeg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        if s == 0 { return RGB(r: l * 255, g: l * 255, b: l * 255) }
        func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return RGB(r: hue2rgb(p, q, h + 1.0 / 3) * 255,
                   g: hue2rgb(p, q, h) * 255,
                   b: hue2rgb(p, q, h - 1.0 / 3) * 255)
    }

    static func color(_ rgb: RGB) -> Color {
        Color(.sRGB, red: clamp(rgb.r, 0, 255) / 255, green: clamp(rgb.g, 0, 255) / 255, blue: clamp(rgb.b, 0, 255) / 255)
    }

    static func color(h: Double, s: Double, l: Double) -> Color {
        color(hslToRgb(h, clamp(s, 0, 1), clamp(l, 0, 1)))
    }

    // WCAG 相対輝度
    static func relLum(_ rgb: RGB) -> Double {
        func f(_ x: Double) -> Double {
            let c = x / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(rgb.r) + 0.7152 * f(rgb.g) + 0.0722 * f(rgb.b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let l1 = relLum(a), l2 = relLum(b)
        let hi = max(l1, l2), lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// accent 面の上に乗せる前景色。コントラスト比 4.5:1 以上の黒/白を自動選択。
    static func onColor(_ bg: RGB) -> Color {
        onColor(over: [bg])
    }

    /// 複数の背景 (グラデーション停止色など) すべての上で読める黒/白を選ぶ。
    /// 全停止色との最小コントラストで判定し、4.5:1 を満たす方を優先する。
    static func onColor(over backgrounds: [RGB]) -> Color {
        let ink = RGB(r: 0x15, g: 0x16, b: 0x1A), paper = RGB(r: 255, g: 255, b: 255)
        let cInk = backgrounds.map { contrast($0, ink) }.min() ?? 0
        let cWhite = backgrounds.map { contrast($0, paper) }.min() ?? 0
        if cWhite >= 4.5 { return color(paper) }
        if cInk >= 4.5 { return color(ink) }
        return cWhite > cInk ? color(paper) : color(ink)
    }

    /// 任意の背景 Color (メンバーカラー/ブランドカラーの帯・チップ等) の上に乗せる
    /// 前景色を WCAG コントラストで黒/白から自動選択する。
    /// 黄色 (#F5C900 系)・白系・水色系など明るい背景での白文字固定の破綻を防ぐ共通入口。
    static func onColor(_ bg: Color) -> Color {
        onColor(rgb(of: bg))
    }

    /// SwiftUI Color → sRGB 8bit RGB (UIColor ブリッジ)。動的色は現在のトレイトで解決。
    static func rgb(of color: Color) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGB(r: Double(r) * 255, g: Double(g) * 255, b: Double(b) * 255)
    }

    /// fg の色相・彩度は保ったまま、bg から離れる方向へ明度を調整して
    /// minRatio 以上のコントラストを確保した RGB を返す。
    /// chipText のような「着色インク」を白面に乗せる時、明るいシード
    /// (黄色等) でも読めるようにするための補正。
    static func ensureContrast(fg: RGB, on bg: RGB, minRatio: Double = 4.5) -> RGB {
        let (h, s, startL) = rgbToHsl(fg)
        var l = startL
        let step = relLum(bg) >= relLum(fg) ? -0.02 : 0.02
        var current = fg
        while contrast(current, bg) < minRatio {
            l += step
            guard (0.0...1.0).contains(l) else { break }
            current = hslToRgb(h, s, l)
        }
        return current
    }
}

// MARK: - SwiftUI 連携

private struct ImasThemeKey: EnvironmentKey {
    static let defaultValue = ImasTheme.derive(hex: ColorMath.neutralSeed, dark: false)
}

extension EnvironmentValues {
    /// 祖先が `.imasTheme(seed:)` を与えた場合に読めるテーマ。
    var imasTheme: ImasTheme {
        get { self[ImasThemeKey.self] }
        set { self[ImasThemeKey.self] = newValue }
    }
}

extension View {
    /// このサブツリーに seed 由来のテーマを供給する。配下は `@Environment(\.imasTheme)` で参照。
    func imasTheme(seed: String?, brand: String? = nil) -> some View {
        modifier(ImasThemeModifier(seed: seed, brand: brand))
    }
}

private struct ImasThemeModifier: ViewModifier {
    let seed: String?
    let brand: String?
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.environment(\.imasTheme, ImasTheme.derive(seed: seed, brand: brand, scheme: scheme))
    }
}
