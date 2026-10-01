import CoreText
import SwiftUI
import UIKit

// =============================================================================
// ImasLiveDB — ファウンデーション・トークン  ※ design/tokens.css の移植
// ニュートラル階調 / セマンティック / スペーシング / 角丸 / 影 / タイポ。
// テーマ非依存の「土台色」。エンティティ色は ImasTheme が別途供給する。
// =============================================================================

enum DS {
    // 世界は「会場とチケット」(docs/DESIGN_SYSTEM.md §1)。ライトは開演前のロビー (生成りの地に
    // 墨の文字)、ダークは客席の暗転 (紫がかった闇に生成りの文字)。チケットだけはダークでも紙のまま。

    // MARK: - ニュートラル (ライト/ダーク自動切替)
    /// 画面の地。ロビーの生成り / 客席の闇。
    static let bg        = solid(light: 0xF4F0E8, dark: 0x15131C)
    /// 地の上に置く面 (カード・行のまとまり・シートの欄)。
    static let surface   = solid(light: 0xFFFDF8, dark: 0x1F1C28)
    /// 面の中にもう一段置く面。
    static let surface2  = solid(light: 0xF1EBDF, dark: 0x2A2633)
    static let fill      = rgba(light: (27, 24, 34, 0.06), dark: (246, 241, 231, 0.10))
    static let sep       = solid(light: 0xE4DBCB, dark: 0x2F2A3A)
    static let ink       = solid(light: 0x1B1822, dark: 0xF6F1E7)
    static let ink2      = solid(light: 0x6B6478, dark: 0xA7A1B5)
    static let ink3      = solid(light: 0xA49B8C, dark: 0x7E7890)

    // MARK: - 紙面 (docs/DESIGN_SYSTEM.md §4)
    /// 一覧・詳細・ハブの地。`bg` と同じ (地は 1 種類)。
    static let paper     = bg
    /// 地の上に置く面。`surface` と同じ。
    static let panel     = surface
    /// 線で形を取る部品 (切り替え・札・入口) の輪郭。区切り線 (`sep`) より一段濃い。
    static let line      = solid(light: 0xDCD2C0, dark: 0x3A3547)

    // MARK: - チケットの紙 (ダークでも紙のまま光る)
    /// チケット・半券の紙。ダークでも生成りのまま (暗い客席で手元のチケットだけが白く見える)。
    static let ticket     = solid(light: 0xFFFDF8, dark: 0xF6F1E7)
    /// チケットの上の文字。紙は常に明るいので、ダークでも墨。
    static let ticketInk  = solid(light: 0x1B1822, dark: 0x1B1822)
    static let ticketSub  = solid(light: 0x6B6478, dark: 0x6B6478)
    /// 切り取り線 (点線)。
    static let ticketDash = solid(light: 0xCEC3B0, dark: 0xC9C0B0)
    /// 面の上の切り取り線 (ダークの面は暗いので一段明るく)。
    static let perforation = solid(light: 0xCEC3B0, dark: 0x4A4458)

    // MARK: - 電光掲示板 (記録・出演の数)
    static let board      = solid(light: 0x1F1C28, dark: 0x24212E)
    static let boardInk   = solid(light: 0xF6F1E7, dark: 0xF6F1E7)
    static let boardDim   = solid(light: 0xA7A1B5, dark: 0xA7A1B5)
    static let boardLine  = solid(light: 0x3A3547, dark: 0x3A3547)

    // MARK: - 判子・穴
    /// 判子の朱。回収・参加の印と、取り返しのつかない操作。
    static let stamp      = solid(light: 0xB42335, dark: 0xE0546A)
    /// 掲示板のランプ (暗い板の上の赤)。
    static let lamp       = solid(light: 0xFF4D5E, dark: 0xFF4D5E)
    /// パンチ穴の向こう。ライトは暗い客席、ダークは照明が漏れて明るい。
    static let hole       = solid(light: 0x2A2633, dark: 0xE9E2D3)

    // MARK: - 曜日
    static let saturday   = solid(light: 0x2E6BD8, dark: 0x7EA6FF)
    static let sunday     = solid(light: 0xC8293F, dark: 0xFF6B7D)

    // MARK: - セマンティック
    static let success   = solid(light: 0x2F8F4E, dark: 0x4CC97A)
    /// 薄い塗りの上に載せる緑。`success` は塗りの上だと 11pt の札の文字に足りない
    /// (WCAG AA は 4.5:1)。ダークは `success` のままで足りる。
    static let successInk = solid(light: 0x1F6B39, dark: 0x4CC97A)
    static let warning   = solid(light: 0xC27200, dark: 0xF2A83B)
    /// 取り返しのつかない操作と失敗。判子の朱と同じ。
    static let danger    = stamp
    /// システムクロムは墨 1 色。色は常にエンティティ側から来る → けばけばしさ回避。
    static let sys       = solid(light: 0x1B1822, dark: 0xF6F1E7)
    /// sys を背景にしたときの前景色 (sys の反転)。
    static let onSys     = solid(light: 0xF6F1E7, dark: 0x1B1822)
    static let sys2      = solid(light: 0x6B6478, dark: 0xA7A1B5)
    /// スイッチの ON の地。OS のスイッチのつまみは白なので、ダークでも白に沈まない濃さにする。
    static let switchOn  = solid(light: 0x1B1822, dark: 0x5E5675)

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
    /// アプリ内の文字サイズ倍率 (極小 / 小 / 中 / 大 / 特大)。UserDefaults "text_scale" を読む。
    /// 未設定 (0) は 1.0 = 中。これは OS の Dynamic Type とは独立した「アプリ内追加倍率」で、
    /// Dynamic Type によるスケールに対して乗算で併用される。タイポトークンを `static var`
    /// (毎回評価) にすることで、設定変更・Dynamic Type 変更後に View が再評価されれば反映される。
    static var imasTextScale: CGFloat {
        let v = UserDefaults.standard.double(forKey: "text_scale")
        return v == 0 ? 1.0 : CGFloat(v)
    }

    /// 固定 pt サイズを「OS の Dynamic Type」と「アプリ内倍率 imasTextScale」の両方でスケールさせる中核。
    /// 指定した TextStyle のスケール曲線に沿って追随する。SwiftUI の `.system(size:)` 単体は
    /// Dynamic Type に追随しないため、UIFontMetrics で包んで Dynamic Type 対応にする。
    private static func scaled(
        _ size: CGFloat,
        relativeTo style: UIFont.TextStyle,
        weight: UIFont.Weight,
        design: UIFontDescriptor.SystemDesign = .default,
        proportional: Bool = false
    ) -> Font {
        let pointSize = size * imasTextScale
        let base = UIFont.systemFont(ofSize: pointSize, weight: weight)
        var uiFont: UIFont
        if design == .default {
            uiFont = base
        } else if let descriptor = base.fontDescriptor.withDesign(design) {
            uiFont = UIFont(descriptor: descriptor, size: pointSize)
        } else {
            uiFont = base
        }
        if proportional {
            // かなの詰め (palt)。見出しの「プロデュース」「セトリを予想する」のような
            // かな・カナの続く行が、等幅の全角送りだと間延びして素人っぽく見える。
            // 本文は読みやすさのために等幅のまま (詰めるのは見出しだけ)。
            let descriptor = uiFont.fontDescriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kTextSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kAltProportionalTextSelector,
                ]],
            ])
            uiFont = UIFont(descriptor: descriptor, size: pointSize)
        }
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: uiFont))
    }

    /// かなを詰めた (palt) UIKit の書体。OS の枠 (ナビバーの題) に渡すとき用。
    static func imasProportionalUIFont(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kTextSpacingType,
                UIFontDescriptor.FeatureKey.selector: kAltProportionalTextSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// 見出しの書体。かなを詰めて組む (palt)。題・見出し・カードの題・ヒーローの名前に使う。
    static func imasHeading(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        scaled(size, relativeTo: textStyle(forSize: size), weight: uiWeight(weight), proportional: true)
    }

    /// 数値・順位・日付・英字ラベル用の「ディスプレイ」フォント。等幅数字付き。
    static func imasDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        scaled(size, relativeTo: textStyle(forSize: size), weight: uiWeight(weight)).monospacedDigit()
    }

    /// 英字の印字 (ADMIT ONE・SETLIST・M01・OPEN / START)。チケットの印字のような等幅。
    /// 大文字と字間は `.imasText(.imprint)` が付ける。
    static func imasMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        scaled(size, relativeTo: textStyle(forSize: size), weight: uiWeight(weight), design: .monospaced)
    }
    /// 生の固定サイズ指定を Dynamic Type + アプリ内倍率でスケールするショートカット。
    static func imasScaled(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        scaled(size, relativeTo: textStyle(forSize: size), weight: uiWeight(weight), design: uiDesign(design))
    }
    /// iOS タイポスケール準拠の本文系ショートカット (Dynamic Type + アプリ内倍率でスケール)。
    static var imasLargeTitle: Font { scaled(34, relativeTo: .largeTitle, weight: .bold) }
    static var imasTitle1: Font     { scaled(28, relativeTo: .title1, weight: .bold) }
    static var imasTitle2: Font     { scaled(22, relativeTo: .title2, weight: .bold) }
    static var imasTitle3: Font     { scaled(20, relativeTo: .title3, weight: .semibold) }
    static var imasHeadline: Font   { scaled(17, relativeTo: .headline, weight: .semibold) }
    static var imasBody: Font       { scaled(17, relativeTo: .body, weight: .regular) }
    static var imasCallout: Font    { scaled(16, relativeTo: .callout, weight: .regular) }
    static var imasSubhead: Font    { scaled(15, relativeTo: .subheadline, weight: .regular) }
    static var imasFootnote: Font   { scaled(13, relativeTo: .footnote, weight: .regular) }
    static var imasCaption: Font    { scaled(12, relativeTo: .caption1, weight: .regular) }
    /// 補助ラベル (バッジ内の数字、チップの添え字 等)。 アプリで最も多く使われる小サイズ
    /// なのに名前が無く、 50 箇所以上が `imasScaled(11)` を直接書いていた。
    static var imasCaption2: Font   { scaled(11, relativeTo: .caption2, weight: .regular) }

    // MARK: - UIKit マッピング (SwiftUI → UIKit の橋渡し)

    /// 任意 pt サイズを最も近い TextStyle に割り当て、Dynamic Type の増分カーブを役割相応にする。
    private static func textStyle(forSize size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case 33...:        return .largeTitle
        case 25 ..< 33:    return .title1
        case 21 ..< 25:    return .title2
        case 19 ..< 21:    return .title3
        case 16.5 ..< 19:  return .body
        case 15.5 ..< 16.5: return .callout
        case 14 ..< 15.5:  return .subheadline
        case 12.5 ..< 14:  return .footnote
        case 11.5 ..< 12.5: return .caption1
        default:           return .caption2
        }
    }
    private static func uiWeight(_ w: Font.Weight) -> UIFont.Weight {
        switch w {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
    }
    private static func uiDesign(_ d: Font.Design) -> UIFontDescriptor.SystemDesign {
        switch d {
        case .serif:      return .serif
        case .rounded:    return .rounded
        case .monospaced: return .monospaced
        default:          return .default
        }
    }
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
