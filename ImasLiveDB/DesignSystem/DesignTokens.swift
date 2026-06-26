import SwiftUI
import UIKit

// =============================================================================
// ImasLiveDB — ファウンデーション・トークン  ※ design/tokens.css の移植
// ニュートラル階調 / セマンティック / スペーシング / 角丸 / 影 / タイポ。
// テーマ非依存の「土台色」。エンティティ色は ImasTheme が別途供給する。
// =============================================================================

enum DS {
    // MARK: - ニュートラル (ライト/ダーク自動切替)
    static let bg        = solid(light: 0xF2F2F7, dark: 0x000000)
    static let surface   = solid(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surface2  = solid(light: 0xF2F2F7, dark: 0x2C2C2E)
    static let fill      = rgba(light: (118, 118, 128, 0.12), dark: (118, 118, 128, 0.24))
    static let sep       = rgba(light: (60, 60, 67, 0.16), dark: (84, 84, 88, 0.42))
    static let ink       = solid(light: 0x1C1C1E, dark: 0xFFFFFF)
    static let ink2      = rgba(light: (60, 60, 67, 0.62), dark: (235, 235, 245, 0.62))
    static let ink3      = rgba(light: (60, 60, 67, 0.34), dark: (235, 235, 245, 0.32))

    // MARK: - セマンティック
    static let success   = solid(light: 0x2FA84F, dark: 0x34D364)
    static let warning   = solid(light: 0xE08600, dark: 0xFFB23E)
    static let danger    = solid(light: 0xE5342B, dark: 0xFF5247)
    /// システムクロムは「ほぼ無彩」。色は常にエンティティ側から来る → けばけばしさ回避。
    static let sys       = solid(light: 0x1C1C1E, dark: 0xFFFFFF)
    /// sys を背景にしたときの前景色 (sys の反転)。ダークモードの sys は白なので白文字固定は不可。
    static let onSys     = solid(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let sys2      = rgba(light: (60, 60, 67, 0.55), dark: (235, 235, 245, 0.55))

    /// マイマーク固有色 (担当♥ / お気に入り★)
    static let pick      = solid(light: 0xFF2D78, dark: 0xFF5A8C)
    static let favorite  = solid(light: 0xE8A800, dark: 0xFFC83E)

    // MARK: - スペーシング (4pt グリッド)
    static let sp1: CGFloat = 2,  sp2: CGFloat = 4,  sp3: CGFloat = 8,  sp4: CGFloat = 12
    static let sp5: CGFloat = 16, sp6: CGFloat = 20, sp7: CGFloat = 24, sp8: CGFloat = 32, sp9: CGFloat = 44

    // MARK: - 角丸
    static let rXS: CGFloat = 6, rSM: CGFloat = 10, rMD: CGFloat = 14
    static let rLG: CGFloat = 18, rXL: CGFloat = 24, rPill: CGFloat = 999

    // MARK: - エレベーション (影) — フラット基調なので控えめ
    static func elevation1(_ scheme: ColorScheme) -> Color { scheme == .dark ? .black.opacity(0.5) : Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.06) }

    // MARK: - dynamic helpers
    private static func solid(light: Int, dark: Int) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark, 1) : uiColor(light, 1) })
    }
    private static func rgba(light: (Int, Int, Int, Double), dark: (Int, Int, Int, Double)) -> Color {
        Color(UIColor { tc in
            let v = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(v.0) / 255, green: CGFloat(v.1) / 255, blue: CGFloat(v.2) / 255, alpha: CGFloat(v.3))
        })
    }
    private static func uiColor(_ hex: Int, _ a: Double) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(a))
    }
}

// =============================================================================
// タイポグラフィ — 本文 = SF Pro + ヒラギノ (system) / 数値・見出し = テクノ系。
// Chakra Petch は未バンドルのため、現状は system + 等幅数字でスタンドインする。
// バンドルしたら `displayFontName` を差し替えるだけで全体に反映される。
// =============================================================================

extension Font {
    /// ユーザー設定の文字サイズ倍率 (極小 / 小 / 中)。UserDefaults "text_scale" を読む。
    /// 未設定 (0) は 1.0 = 中。タイポトークンを `static var` (毎回評価) にすることで、
    /// 設定変更後に View が再評価されれば新しいサイズが反映される。
    static var imasTextScale: CGFloat {
        let v = UserDefaults.standard.double(forKey: "text_scale")
        return v == 0 ? 1.0 : CGFloat(v)
    }

    /// 数値・順位・日付・英字ラベル用の「ディスプレイ」フォント。等幅数字付き。
    static func imasDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size * imasTextScale, weight: weight, design: .default).monospacedDigit()
    }
    /// 生の固定サイズ指定 (.system(size:)) を文字サイズ設定でスケールするショートカット。
    static func imasScaled(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * imasTextScale, weight: weight, design: design)
    }
    /// iOS タイポスケール準拠の本文系ショートカット (文字サイズ設定でスケール)。
    static var imasLargeTitle: Font { .system(size: 34 * imasTextScale, weight: .bold) }
    static var imasTitle1: Font     { .system(size: 28 * imasTextScale, weight: .bold) }
    static var imasTitle2: Font     { .system(size: 22 * imasTextScale, weight: .bold) }
    static var imasTitle3: Font     { .system(size: 20 * imasTextScale, weight: .semibold) }
    static var imasHeadline: Font   { .system(size: 17 * imasTextScale, weight: .semibold) }
    static var imasBody: Font       { .system(size: 17 * imasTextScale, weight: .regular) }
    static var imasCallout: Font    { .system(size: 16 * imasTextScale, weight: .regular) }
    static var imasSubhead: Font    { .system(size: 15 * imasTextScale, weight: .regular) }
    static var imasFootnote: Font   { .system(size: 13 * imasTextScale, weight: .regular) }
    static var imasCaption: Font    { .system(size: 12 * imasTextScale, weight: .regular) }
}

/// 文字サイズ設定をルートから環境に流す依存源。静的 Font ヘルパーは UserDefaults を
/// 直接読むが、ルートでこの値を読む (環境に注入する) ことで設定変更時にアプリ全体が
/// 再評価され、新しいサイズが反映される。
private struct ImasTextScaleKey: EnvironmentKey { static let defaultValue: Double = 1.0 }
extension EnvironmentValues {
    var imasTextScale: Double {
        get { self[ImasTextScaleKey.self] }
        set { self[ImasTextScaleKey.self] = newValue }
    }
}
