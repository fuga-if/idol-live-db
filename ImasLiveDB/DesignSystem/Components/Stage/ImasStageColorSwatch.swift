import SwiftUI

// =============================================================================
// メンバーカラークイズの色見本 (docs/DESIGN_SYSTEM.md §12)
//
// ImasStageColorSwatch     色そのものを選択肢として見せる (4択の候補・並べるの色パレット)。
// ImasStageAssignmentTarget 色を割り当てる的 (ドラッグ&ドロップ / タップの行き先)。
// ImasStageColorGridIcon    4 色のミニ格子アイコン (ハブの「メンバーカラー合わせ」入口)。
// =============================================================================

/// 色そのものを選択肢として見せる (メンバーカラークイズ専用)。
struct ImasStageColorSwatch: View {
    enum Style {
        /// 4 択の候補 (大きめ・押すと確定)。
        case choice
        /// 並べるのドラッグ元 (小さめ・使用済み状態あり)。
        case palette
    }

    let hex: String
    /// 先頭の記号 (A/B/C…)。
    var letter: String? = nil
    var style: Style = .choice
    var isSelected: Bool = false
    /// 既にどこかへ割り当て済み (palette のみ)。
    var isUsed: Bool = false
    /// ヒントで消された (choice のみ、押せない)。
    var isEliminated: Bool = false
    var action: (() -> Void)? = nil

    private var swatchSize: CGFloat { style == .choice ? 76 : 56 }
    private var cornerRadius: CGFloat { style == .choice ? 18 : 16 }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.imasPress)
                    .disabled(isEliminated)
            } else {
                content
            }
        }
        .opacity(isEliminated ? 0.18 : (isUsed && !isSelected ? 0.45 : 1))
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }

    private var content: some View {
        VStack(spacing: style == .choice ? 8 : 6) {
            swatch
            if let letter {
                HStack {
                    Text(letter).foregroundStyle(QS.faint)
                    Spacer(minLength: 2)
                    Text(hex.uppercased())
                }
                .font(style == .choice ? QS.mono(11) : QS.mono(10))
                .foregroundStyle(QS.ink)
                .padding(.horizontal, style == .choice ? 4 : 2)
            }
        }
        .padding(style == .choice ? 8 : 6)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? QS.ink : QS.line, lineWidth: isSelected ? 2.5 : 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["色", letter, hex].compactMap { $0 }.joined(separator: " "))
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: style == .choice ? 12 : 10, style: .continuous)
            .fill(Color(hexString: hex))
            .frame(height: swatchSize)
            .overlay {
                if style == .choice {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(QS.line, lineWidth: 1)
                } else if isUsed {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ColorMath.onColor(Color(hexString: hex)))
                }
            }
    }
}

/// 色を割り当てる的 (ドラッグ&ドロップ / タップの行き先)。未割り当ては点線の丸に「?」。
struct ImasStageAssignmentTarget: View {
    let assignedHex: String?
    var isTargeted: Bool = false
    /// 判定後の正誤 (nil = まだ判定していない)。
    var verdict: Bool? = nil

    var body: some View {
        ZStack {
            if let assignedHex {
                Circle().fill(Color(hexString: assignedHex))
            } else {
                Circle().strokeBorder(isTargeted ? QS.paperInk : QS.paperMuted,
                                      style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                Text("?").font(QS.num(18)).foregroundStyle(QS.paperSub)
            }
            if let verdict {
                Image(systemName: verdict ? "checkmark" : "xmark")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(assignedHex.map { ColorMath.onColor(Color(hexString: $0)) } ?? QS.paperInk)
            }
        }
        .frame(width: 44, height: 44)
        .scaleEffect(isTargeted ? 1.12 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)
    }
}

/// 4 色のミニ格子アイコン (ハブの「メンバーカラー合わせ」入口)。
struct ImasStageColorGridIcon: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)], spacing: 3) {
            ForEach([0, 4, 2, 3], id: \.self) { i in
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(QS.penlight(i)).frame(height: 9)
            }
        }
        .padding(9)
        .frame(width: 40, height: 40)
        .background(QS.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
