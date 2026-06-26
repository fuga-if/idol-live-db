import SwiftUI

/// セクションヘッダー部分でのみ開閉操作を行う折りたたみセクション。
/// `List` 標準のヘッダー pinning により、開いた状態で下にスクロールしても
/// ヘッダー（= 閉じるボタン）が画面上部に追従する。
struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    @State private var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        count: Int,
        defaultExpanded: Bool? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        let expanded = defaultExpanded ?? (count <= 3)
        self._isExpanded = State(initialValue: expanded)
        self.content = content
    }

    var body: some View {
        Section {
            if isExpanded {
                content()
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.imasSubhead.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    Text("\(count)件")
                        .font(.imasCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.imasCaption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }
}
