import NukeUI
import SwiftUI

// MARK: - Protocol

protocol GridCardItem: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String? { get }
    var artworkUrl: String? { get }
    var placeholderSystemImage: String { get }
}

// MARK: - GenericGridView

struct GenericGridView<Item: GridCardItem>: View {
    let items: [Item]
    let isLoading: Bool
    let emptyTitle: String
    let emptySystemImage: String
    let onSelect: (Item) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]

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
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            GridCardView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .clipped()
    }
}

// MARK: - GridCardView

struct GridCardView<Item: GridCardItem>: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artworkSection
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            Text(item.title)
                .font(.imasHeadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.imasCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var artworkSection: some View {
        if let url = item.artworkUrl.flatMap(URL.init) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray4), Color(.systemGray5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: item.placeholderSystemImage)
                    .font(.imasScaled( 28))
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.imasScaled(11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }
        }
    }
}
