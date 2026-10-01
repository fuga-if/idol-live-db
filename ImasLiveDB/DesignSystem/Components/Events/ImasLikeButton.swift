import SwiftUI

// =============================================================================
// Good ボタン (docs/DESIGN_SYSTEM.md §9・§5.6)
//
// セトリの行の「この曲が良かった」トグル。親指のアイコンと、件数があれば下に小さく。
// ON は担当色 (DS.pick)、OFF は薄い墨。行の末尾 (`ImasRowTrailing.custom`) に置く。
// =============================================================================

/// セトリの行の Good トグル。
struct ImasLikeButton: View {
    let isOn: Bool
    /// 現在の票数。0 なら数字を出さない。
    let count: Int
    /// 連打防止 (通信中)。
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            Button(action: action) {
                Image(systemName: isOn ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.imasScaled(18, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? DS.pick : DS.ink3)
                    .frame(minWidth: DS.Size.touch, minHeight: DS.Size.chip)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
            .sensoryFeedback(.impact(weight: .light), trigger: isOn)
            .accessibilityLabel(isOn ? "Good を取り消す" : "この曲が良かった")

            if count > 0 {
                Text("\(count)")
                    .font(.imasDisplay(10))
                    .foregroundStyle(DS.ink3)
            }
        }
    }
}
