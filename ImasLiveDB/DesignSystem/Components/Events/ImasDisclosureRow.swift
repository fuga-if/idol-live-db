import SwiftUI

// =============================================================================
// 開閉トグルの行 (docs/DESIGN_SYSTEM.md)
//
// 行・区画の中身をその場で開閉する (個別衣装・歌唱メンバー予想など)。
// 押すたびに chevron が回転する。
// =============================================================================

/// 開閉トグルの行。題 + 件数 + 開閉の chevron。
struct ImasDisclosureRow: View {
    let title: String
    var count: String? = nil
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.imasStandard) { isExpanded.toggle() }
        } label: {
            HStack(spacing: DS.Space.gap) {
                Text(title).imasText(.rowLabel)
                if let count { Text(count).imasText(.meta) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.imasScaled(12, weight: .semibold))
                    .foregroundStyle(DS.ink3)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, DS.Space.rowH)
            .frame(minHeight: DS.Size.touch, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.imasRow)
        .accessibilityLabel([title, count].compactMap { $0 }.joined(separator: " "))
        .accessibilityHint(isExpanded ? "畳む" : "開く")
    }
}
