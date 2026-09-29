import SwiftUI

/// 文字列候補から 1 つ選ぶ汎用ピッカー (シリーズ / CDシリーズ / ライブ名 共通)。
///
/// フィルタシート内から **push** して使う。以前はシートの中からさらにシートを開いており、
/// フィルタ 1 枚のために最大 2 枚のモーダルが重なっていた。選択したら自動で 1 つ戻る。
struct ListPickerView: View {
    let title: String
    let items: [String]
    @Binding var selected: String?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    /// 絞り込み用の索引。`items` は開いている間変わらないので 1 回だけ組む。
    /// 照合規則はコア (`domain/text_search_index.rs`) に一任し、シリーズ名を
    /// かなで打っても当たるようにする (曲一覧と同じ規則)。
    @State private var catalog: TextSearchCatalog?

    private var filteredItems: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        // 索引が無い間は絞り込まない (黙って 0 件にする方が悪い)。
        guard let catalog else { return items }
        return catalog.filter(items, needle: trimmed)
    }

    var body: some View {
        List {
            // 「選択なし」= 絞り込み解除
            row(label: "選択なし", value: nil, muted: true)

            if filteredItems.isEmpty {
                ImasEmptyState(
                    systemImage: "magnifyingglass",
                    title: "見つかりません",
                    message: "「\(searchText)」に一致する項目がありません"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredItems, id: \.self) { item in
                    row(label: item, value: item, muted: false)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .searchable(text: $searchText, prompt: "\(title)を検索")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { catalog = TextSearchCatalog(fieldsPerItem: items.map { [$0] }) }
    }

    private func row(label: String, value: String?, muted: Bool) -> some View {
        Button {
            selected = value
            dismiss()
        } label: {
            HStack(spacing: DS.sp3) {
                Text(label)
                    .font(.imasSubhead)
                    .foregroundStyle(muted ? DS.ink2 : DS.ink)
                    .lineLimit(2)
                Spacer(minLength: DS.sp3)
                if selected == value {
                    Image(systemName: "checkmark")
                        .font(.imasScaled(14, weight: .semibold))
                        .foregroundStyle(DS.sys)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(DS.surface)
        .listRowSeparatorTint(DS.sep)
        .accessibilityAddTraits(selected == value ? .isSelected : [])
    }
}
