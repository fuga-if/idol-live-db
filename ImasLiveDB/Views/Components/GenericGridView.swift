import SwiftUI

// MARK: - Protocol

protocol GridCardItem: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String? { get }
    var artworkUrl: String? { get }
    var placeholderSystemImage: String { get }
}

// MARK: - GenericGridView

/// アルバム・シリーズなど「ジャケ + 題」の格子一覧。見た目は `ImasArtworkCell` (DS §6.6)。
struct GenericGridView<Item: GridCardItem>: View {
    let items: [Item]
    let isLoading: Bool
    let emptyTitle: String
    let emptySystemImage: String
    let onSelect: (Item) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: DS.Space.screen)]

    init(
        items: [Item],
        isLoading: Bool = false,
        emptyTitle: String = "アイテムが見つかりません",
        emptySystemImage: String = "square.grid.2x2",
        onSelect: @escaping (Item) -> Void
    ) {
        self.items = items
        self.isLoading = isLoading
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ImasInlineLoading()
            } else if items.isEmpty {
                ImasEmptyState(systemImage: emptySystemImage, title: emptyTitle)
                    .padding(.top, DS.Space.section * 2)
            } else {
                LazyVGrid(columns: columns, spacing: DS.Space.screen) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            ImasArtworkCell(title: item.title, subtitle: item.subtitle,
                                            imageURL: item.artworkUrl.flatMap(URL.init))
                        }
                        .buttonStyle(.imasPress)
                    }
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, DS.Space.screen)
                .padding(.bottom, DS.Space.section)
            }
        }
        .clipped()
    }
}
