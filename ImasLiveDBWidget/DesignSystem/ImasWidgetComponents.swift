import SwiftUI
import UIKit

// =============================================================================
// ウィジェット拡張専用の小さな部品一式 (docs/DESIGN_SYSTEM.md の考え方をウィジェットに適用)
//
// ウィジェット拡張 (ImasLiveDBWidget) はサイズの都合でアプリ本体の DesignSystem を
// link していない (project.yml の sources 参照)。そのためここに最小限の部品を持つ。
// 色は DesignSystem/DesignTokens.swift の `DS.*` と同じ値を複製する (値を変えたら両方直す)。
//
// 見た目の方針は本体と同じ「会場とチケット」: 地は紙 (`ImasWidgetColor.paper`)、文字は墨、
// アイドル・ブランドの色は差し色 1 点だけに使う (全面のグラデーションは使わない)。
//
// ImasWidgetColor        DS.* と同じ値のライト/ダーク色 + hex 文字列からの差し色。
// ImasWidgetSpace        役割で引く余白 (DS.Space の小さな部分集合)。
// ImasWidgetTextRole     文字の役割 (題・補足)。太さ・色を役割で決め、大きさだけ呼び出し側が渡す。
// ImasWidgetScaffold      紙の余白と全面への引き伸ばし。左端に差し色の帯を 1 本だけ足せる。
// ImasWidgetEyebrow       記号 + 文言の目印 (「次のライブ」「今日の1曲」)。差し色の点を 1 つ添えられる。
// ImasWidgetMetric        強調する数字 (「あと37日」「今日!」)。細長い太字の等幅。
// ImasWidgetRow           日付 + 本文 + 任意の種別の 3 要素行 (チケット締切)。
// ImasWidgetArtwork       曲のジャケ。実画像が無ければ紙の面 + 音符 (色では飾らない)。
// ImasWidgetPlaceholder   情報なし・未設定の状態 (細い記号 1 つ + 文言)。
// =============================================================================

/// 役割で引く余白 (`DS.Space` の名前と値をそのまま小さく複製する)。
enum ImasWidgetSpace {
    static let gapTight: CGFloat = 4
    static let gap: CGFloat = 8
    /// ジャケと文字列の間 (今日の1曲)。
    static let gapLoose: CGFloat = 10
}

/// ウィジェットの文字の役割。部品はこの名前で太さ・色を引く (画面に生の `.font(.system(` を書かせない)。
/// 大きさは呼び出し側がウィジェットごとに決める (次のライブ・今日の1曲・small/medium で寸法が違うため)。
enum ImasWidgetTextRole {
    /// 題 (イベント名・曲名)。
    case title(size: CGFloat)
    /// 補足 (日付・アーティスト名)。
    case meta(size: CGFloat)

    var font: Font {
        switch self {
        case .title(let size): return .system(size: size, weight: .bold)
        case .meta(let size): return .system(size: size)
        }
    }
    var color: Color {
        switch self {
        case .title: return ImasWidgetColor.ink
        case .meta: return ImasWidgetColor.ink2
        }
    }
}

extension Text {
    /// ウィジェットの文字の役割を当てる (書体 + 色)。
    func imasWidgetText(_ role: ImasWidgetTextRole) -> some View {
        font(role.font).foregroundStyle(role.color)
    }
}

enum ImasWidgetColor {
    // 値は DesignSystem/DesignTokens.swift の DS.* と同じ。
    static let paper   = dynamic(light: 0xF4F0E8, dark: 0x15131C)   // DS.bg
    static let surface = dynamic(light: 0xFFFDF8, dark: 0x1F1C28)   // DS.surface
    static let ink     = dynamic(light: 0x1B1822, dark: 0xF6F1E7)   // DS.ink
    static let ink2    = dynamic(light: 0x6B6478, dark: 0xA7A1B5)   // DS.ink2
    static let ink3    = dynamic(light: 0xA49B8C, dark: 0x7E7890)   // DS.ink3
    static let warning = dynamic(light: 0xC27200, dark: 0xF2A83B)   // DS.warning
    static let fill    = rgba(light: (27, 24, 34, 0.06), dark: (246, 241, 231, 0.10)) // DS.fill
    /// アイドル・ブランドの色が無いときの差し色 (墨)。
    static let neutral = ink

    /// hex 文字列 → 差し色。失敗したら中立色 (墨)。
    static func accent(_ hex: String?) -> Color {
        guard let hex, hex.count >= 6 else { return neutral }
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let v = UInt64(raw.prefix(6), radix: 16) else { return neutral }
        return Color(
            red: Double((v >> 16) & 0xff) / 255,
            green: Double((v >> 8) & 0xff) / 255,
            blue: Double(v & 0xff) / 255
        )
    }

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    private static func rgba(light: (Int, Int, Int, Double), dark: (Int, Int, Int, Double)) -> Color {
        Color(UIColor { tc in
            let v = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(v.0) / 255, green: CGFloat(v.1) / 255, blue: CGFloat(v.2) / 255, alpha: CGFloat(v.3))
        })
    }
    private static func ui(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// ウィジェットの中身の土台。紙の余白 + 全面への引き伸ばし。
/// `accent` を渡すと左端に細い帯を 1 本だけ足す (色は差し色 1 点だけ、という原則をウィジェットでも守る)。
struct ImasWidgetScaffold<Content: View>: View {
    var alignment: Alignment = .topLeading
    var accent: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            if let accent {
                Rectangle().fill(accent).frame(width: 3)
            }
            content
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
    }
}

/// 記号 + 文言の目印 (「次のライブ」「今日の1曲」「チケット締切」)。
/// `accent` を渡すと先頭に差し色の点を 1 つ添える (ペンライト相当)。
struct ImasWidgetEyebrow: View {
    let systemImage: String
    let text: String
    var accent: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let accent {
                Circle().fill(accent).frame(width: 6, height: 6)
            }
            Label {
                Text(text)
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.titleAndIcon)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(ImasWidgetColor.ink2)
    }
}

/// 強調する数字 (「あと37日」「今日!」)。会場の掲示板・チケットと同じ、細長い太字の等幅。
struct ImasWidgetMetric: View {
    let text: String
    var size: CGFloat = 15

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black).width(.compressed))
            .monospacedDigit()
            .foregroundStyle(ImasWidgetColor.ink)
    }
}

/// 日付 + 本文 + 任意の種別の 3 要素行 (チケット締切など)。
struct ImasWidgetRow: View {
    let date: String
    let title: String
    var tag: String? = nil
    /// 日付を目立たせる (締切が近い・当落発表前など)。
    var isEmphasized: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(date)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isEmphasized ? ImasWidgetColor.warning : ImasWidgetColor.ink2)
                .frame(minWidth: 32, alignment: .leading)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(ImasWidgetColor.ink)
                .lineLimit(1)
            if let tag {
                Text(tag)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ImasWidgetColor.ink3)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// 曲のジャケ。実画像があれば表示、無ければ紙の面 + 音符 (DS の `ImasArtwork` のウィジェット版。
/// 色の面に音符を置くと「作った絵」に見えるため、色では飾らない)。
struct ImasWidgetArtwork: View {
    let image: UIImage?
    var size: CGFloat = 50

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    ImasWidgetColor.fill
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(ImasWidgetColor.ink3)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: min(10, max(3, size * 0.08)), style: .continuous))
    }
}

/// 情報なし・未設定の状態。細い記号 1 つ + 文言 (DS の `ImasEmptyState` のウィジェット版)。
/// 文字サイズに追従する OS の文字の段 (`.title2`/`.caption2`) を使う
/// (上限は呼び出し側の `.dynamicTypeSize(...xxxLarge)` が決める)。
struct ImasWidgetPlaceholder: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(text)
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(ImasWidgetColor.ink3)
    }
}
