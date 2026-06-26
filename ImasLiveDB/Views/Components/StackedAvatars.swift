import SwiftUI

/// アイドルアイコンをオーバーラップして横並びに表示するスタック。
/// Slack / FaceTime の参加者ピル風の見た目。
struct StackedAvatars: View {
    let idols: [Idol]
    var maxVisible: Int = 5
    var size: CGFloat = 24
    var onTap: (() -> Void)? = nil

    var body: some View {
        stack
            .accessibilityElement(children: .combine)
            .accessibilityLabel("出演者 \(idols.count)名")
    }

    /// onTap が指定されている時だけタップを受ける。nil の場合は親 View の
    /// gesture (onTapGesture / Button) にイベントを通すため tap modifier を付けない。
    @ViewBuilder
    private var stack: some View {
        if let onTap {
            stackBody
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
        } else {
            stackBody
        }
    }

    private var stackBody: some View {
        HStack(spacing: -(size * 0.4)) {
            ForEach(Array(idols.prefix(maxVisible).enumerated()), id: \.offset) { idx, idol in
                IdolAvatarView(idol: idol, size: size)
                    .overlay(
                        Circle().strokeBorder(Color(.systemBackground), lineWidth: 2)
                    )
                    .zIndex(Double(maxVisible - idx))
            }
            if idols.count > maxVisible {
                Text("+\(idols.count - maxVisible)")
                    .font(.imasScaled(11).bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .zIndex(0)
            }
        }
    }
}
