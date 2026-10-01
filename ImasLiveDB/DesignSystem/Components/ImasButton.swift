import SwiftUI

// =============================================================================
// ボタン (docs/DESIGN_SYSTEM.md §9)
//
// 用途      押して何かを起こすもの。画面の主な操作・カードの操作・行の中の小さい操作。
// 使わない  選択の切り替え → ImasFilterChip / 印 (担当・参加) → ImasMarkToggle /
//           別の画面への入口 → ImasNavRow・ImasEntryCard
// 構成      [記号 (任意)] [文言]、形は角丸の四角 (50→12, 40→10, 32→8)。カプセルにしない。
// 種類      役割 primary / secondary / plain / destructive × 大きさ large / medium / small
// 状態      通常 / 押下 (0.97 に縮む) / 無効 (薄く) / 読み込み中 (文言の代わりにくるくる)
//
// 主ボタンは 1 画面に 1 つ。色は墨 (ライトは黒・ダークは白) で、アイドルの画面でも変えない。
// アイドル・ブランドの色はペンライト・帯・選んだ印に出す (塗りのボタンを色で塗らない)。
// =============================================================================

enum ImasButtonRole {
    /// 画面で一番大事な操作。塗り。
    case primary
    /// 主の隣・単独の操作。墨の線。
    case secondary
    /// 補助の操作。地なしの文字だけ。
    case plain
    /// 削除・取り消し。確認とセットで使う。
    case destructive
}

enum ImasButtonSize {
    /// 高さ 50。画面の下に固定する主ボタン、空状態の操作、ゲームの開始。
    case large
    /// 高さ 40。カード・ヒーローの中。
    case medium
    /// 高さ 32。行の中、ログインの誘い。
    case small

    var height: CGFloat {
        switch self {
        case .large: return 50
        case .medium: return 40
        case .small: return 32
        }
    }

    var font: Font {
        switch self {
        case .large: return .imasHeading(16, weight: .bold)
        case .medium: return .imasHeading(15, weight: .bold)
        case .small: return .imasHeading(13, weight: .bold)
        }
    }

    var iconFont: Font {
        switch self {
        case .large: return .imasScaled(16, weight: .bold)
        case .medium: return .imasScaled(14, weight: .bold)
        case .small: return .imasScaled(12, weight: .bold)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .large: return 24
        case .medium: return 16
        case .small: return 12
        }
    }

    var cornerRadius: CGFloat { DS.rControl(height) }
}

/// `.buttonStyle(.imas(...))` で使う見た目。文言と記号は `Label` / `Text` で渡す。
struct ImasButtonStyle: ButtonStyle {
    var role: ImasButtonRole = .primary
    var size: ImasButtonSize = .medium
    /// 横幅いっぱいに広げる。`large` は既定で広げる。
    var fillsWidth: Bool? = nil

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let colors = colors()
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        configuration.label
            .labelStyle(ImasButtonLabelStyle(size: size))
            .font(size.font)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(colors.fg)
            .padding(.horizontal, role == .plain ? 0 : size.horizontalPadding)
            .frame(maxWidth: (fillsWidth ?? (size == .large)) ? .infinity : nil)
            .frame(minHeight: size.height)
            .background(colors.bg, in: shape)
            .overlay { if let stroke = colors.stroke { shape.strokeBorder(stroke, lineWidth: 1.5) } }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.imasStandard, value: configuration.isPressed)
    }

    private func colors() -> (bg: Color, fg: Color, stroke: Color?) {
        switch role {
        case .primary: return (DS.sys, DS.onSys, nil)
        case .secondary: return (.clear, DS.ink, DS.ink)
        case .plain: return (.clear, DS.ink, nil)
        case .destructive: return (.clear, DS.danger, DS.danger.opacity(0.45))
        }
    }
}

/// ボタンの中の記号と文言の間隔を大きさに合わせる。
private struct ImasButtonLabelStyle: LabelStyle {
    let size: ImasButtonSize
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: size == .small ? DS.Space.gapTight : 6) {
            configuration.icon.font(size.iconFont)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == ImasButtonStyle {
    /// デザインシステムのボタン。`Button("保存") { }.buttonStyle(.imas(.primary, size: .large))`
    static func imas(_ role: ImasButtonRole = .primary, size: ImasButtonSize = .medium,
                     fillsWidth: Bool? = nil) -> ImasButtonStyle {
        ImasButtonStyle(role: role, size: size, fillsWidth: fillsWidth)
    }
}

/// 読み込み中を持てるボタン。押してから終わるまで文言をくるくるに替え、幅は変えない。
struct ImasButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ImasButtonRole = .primary
    var size: ImasButtonSize = .medium
    var fillsWidth: Bool? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            // 読み込み中は押せない。指の当たり判定だけでは VoiceOver・スイッチコントロールからの実行が通るので、
            // ここでも止める (共有画像の準備中に押されると、ジャケの無いカードが焼かれる)。
            guard !isLoading else { return }
            action()
        } label: {
            ZStack {
                label.opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().controlSize(.small).tint(role == .primary ? DS.onSys : DS.ink2)
                }
            }
        }
        .buttonStyle(.imas(role, size: size, fillsWidth: fillsWidth))
        // 読み込み中は押せないだけで、無効 (薄い) の見た目にはしない。
        .allowsHitTesting(!isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "処理中" : "")
    }

    @ViewBuilder private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

// MARK: - 記号だけのボタン

/// 記号だけの丸いボタン。月の送り・再生など、文言が無くても分かる操作。
/// 読み上げ用の `label` は必ず渡す。丸は OS のツールバーの記号ボタンと同じ形 (中身のボタンで丸いのはこれだけ)。
struct ImasIconButton: View {
    enum Size {
        /// 32 の丸。行・カードの中。
        case small
        /// 44 の丸。画面の中の独立した操作。
        case regular

        var diameter: CGFloat { self == .small ? 32 : 44 }
        var iconFont: Font { self == .small ? .imasScaled(13, weight: .semibold) : .imasScaled(16, weight: .semibold) }
    }

    enum Style {
        /// 灰の地 (既定)。
        case tinted
        /// 墨の塗り (再生など、その画面の主の操作)。
        case filled
        /// 地なし。
        case plain
    }

    let systemImage: String
    let label: String
    var size: Size = .regular
    var style: Style = .tinted
    /// 押してから終わるまで記号をくるくるに替える (削除中など)。
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            // 読み込み中は VoiceOver・スイッチコントロールからの実行も止める。
            guard !isLoading else { return }
            action()
        } label: {
            ZStack {
                Image(systemName: systemImage).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().controlSize(.small).tint(fg)
                }
            }
            .font(size.iconFont)
            .foregroundStyle(fg)
            .frame(width: size.diameter, height: size.diameter)
            .background(bg, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.imasPress)
        .frame(minWidth: DS.Size.touch, minHeight: DS.Size.touch)
        .allowsHitTesting(!isLoading)
        .accessibilityLabel(label)
        .accessibilityValue(isLoading ? "処理中" : "")
    }

    private var bg: Color {
        switch style {
        case .tinted: return DS.fill
        case .filled: return DS.sys
        case .plain: return .clear
        }
    }

    private var fg: Color {
        switch style {
        case .tinted: return DS.ink
        case .filled: return DS.onSys
        case .plain: return DS.ink2
        }
    }
}
