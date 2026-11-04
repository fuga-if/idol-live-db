import SwiftUI

// =============================================================================
// ペンライトの指示 (ペンラ芸) の見た目
//
// 光らせない。棒は角のある平らな色の面で、光・ぼかし・グラデーションは使わない
// (グラデーション禁止の規則。担当色のような「人によって違う色」は縞で表す)。
// 白い色が地に溶けないよう、棒には細い墨の縁を必ず引く。
// =============================================================================

/// ペンライトの棒 1 本。
struct ImasPenlightStick: View {
    enum Fill: Hashable {
        /// アイドルの色 (マスタの HEX)。読めなければ縁だけ。
        case hex(String)
        /// 決まった色 (`0xRRGGBB`)。
        case rgb(UInt32)
        /// 各自の担当色 (人によって違う) を縞で。
        case oshi
        /// 色の指示なし (メモだけ)。縁だけ描く。
        case none
    }

    let fill: Fill
    var height: CGFloat = 16

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 1.5, style: .continuous) }

    var body: some View {
        ZStack {
            switch fill {
            case .hex(let hex): shape.fill(Color(hexString: hex, default: .clear))
            case .rgb(let rgb): shape.fill(Self.color(rgb: rgb))
            case .oshi: shape.fill(ImasStripes.vertical(QS.penlights))
            case .none: Color.clear
            }
            shape.strokeBorder(DS.ink.opacity(fill == .none ? 0.45 : 0.3), lineWidth: 1)
        }
        .frame(width: max(5, height * 0.34), height: height)
        .accessibilityHidden(true)
    }

    private static func color(rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255)
    }
}

/// ペンライトの色を選ぶ札 1 枚 (棒 + 名前)。選んでいる札は墨の枠で囲む。
struct ImasPenlightSwatch: View {
    let fill: ImasPenlightStick.Fill
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.rControl(DS.Size.chip), style: .continuous)
        Button(action: action) {
            VStack(spacing: DS.sp1) {
                ImasPenlightStick(fill: fill, height: 28)
                Text(name)
                    .font(.imasCaption2)
                    .foregroundStyle(isSelected ? DS.ink : DS.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(shape)
            .overlay(shape.strokeBorder(isSelected ? DS.ink : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 歌詞の行の下に並ぶペンライトの指示 1 つ: 棒 + メモ。
struct ImasPenlightCueLabel: View {
    let fill: ImasPenlightStick.Fill
    let note: String?
    /// 歌詞プレイヤーで大きく出すとき。
    var size: Size = .compact
    var isActive: Bool = true

    enum Size { case compact, player }

    var body: some View {
        HStack(alignment: .center, spacing: size == .player ? DS.sp2 : 5) {
            ImasPenlightStick(fill: fill, height: stickHeight)
            if let note, !note.isEmpty {
                Text(note)
                    .font(size == .player ? .imasHeading(isActive ? 18 : 14, weight: .bold) : .imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .opacity(size == .player && !isActive ? 0.55 : 1)
    }

    private var stickHeight: CGFloat {
        switch size {
        case .compact: return 16
        case .player: return isActive ? 30 : 20
        }
    }
}

/// 歌詞プレイヤーで行の直下に流すペンライトの指示 (`ImasPlayerCallLine` の隣り)。
/// いま出す指示だけ大きく、ほかは小さく薄く。
struct ImasPlayerPenlightLine: View {
    let marker: String
    let fill: ImasPenlightStick.Fill
    let note: String?
    /// 読み上げる文 (「ペンライト: 青・サビ頭で一斉に」)。
    let description: String
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DS.sp2) {
            Text(marker)
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
                .frame(width: 16, alignment: .trailing)
            ImasPenlightCueLabel(fill: fill, note: note, size: .player, isActive: isActive)
            Spacer(minLength: 0)
        }
        .padding(.leading, DS.sp3)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
