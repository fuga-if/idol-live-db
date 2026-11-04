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
        /// 決まった色・アイドルの色。
        case color(Color)
        /// 各自の担当色 (人によって違う) を縞で。
        case stripes([Color])
        /// 色の指示なし (振り方だけ)。縁だけ描く。
        case none
    }

    let fill: Fill
    /// 消灯 (縁だけの点線)。
    var isOff: Bool = false
    var height: CGFloat = 16

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 1.5, style: .continuous) }

    var body: some View {
        ZStack {
            if !isOff {
                switch fill {
                case .color(let color): shape.fill(color)
                case .stripes(let colors): shape.fill(ImasStripes.vertical(colors))
                case .none: Color.clear
                }
            }
            if isOff {
                shape.strokeBorder(DS.ink3, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                shape.strokeBorder(DS.ink.opacity(fill == .none ? 0.45 : 0.3), lineWidth: 1)
            }
        }
        .frame(width: max(5, height * 0.34), height: height)
        .accessibilityHidden(true)
    }
}

/// 歌詞の行の下に並ぶペンライトの指示 1 つ: 棒 + 動きの記号 + メモ。
struct ImasPenlightCueLabel: View {
    let fill: ImasPenlightStick.Fill
    let moveSymbol: String?
    let isOff: Bool
    let note: String?
    /// 歌詞プレイヤーで大きく出すとき。
    var size: Size = .compact
    var isActive: Bool = true

    enum Size { case compact, player }

    var body: some View {
        HStack(alignment: .center, spacing: size == .player ? DS.sp2 : 5) {
            ImasPenlightStick(fill: fill, isOff: isOff, height: stickHeight)
            if let moveSymbol {
                Image(systemName: moveSymbol)
                    .font(size == .player ? .imasHeading(isActive ? 20 : 14, weight: .bold) : .imasFootnote.weight(.semibold))
                    .foregroundStyle(DS.ink)
            }
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
    let moveSymbol: String?
    let isOff: Bool
    let note: String?
    /// 読み上げる文 (「ペンライト: 青・左右に振る」)。
    let description: String
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DS.sp2) {
            Text(marker)
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
                .frame(width: 16, alignment: .trailing)
            ImasPenlightCueLabel(fill: fill, moveSymbol: moveSymbol, isOff: isOff, note: note,
                                 size: .player, isActive: isActive)
            Spacer(minLength: 0)
        }
        .padding(.leading, DS.sp3)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
