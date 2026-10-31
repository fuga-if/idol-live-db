import SwiftUI

/// 刷る色の選択肢を横に並べる (P名刺の編集の「刷る色」)。担当の色は判子 (`ImasAvatar`)、墨は墨の丸に字。
/// 選んだものだけ墨の輪で囲み、下に名前を添える。横に引いて送る。
struct ImasInkSwatches: View {
    struct Item: Identifiable {
        let id: String
        /// 下に添える名前 (担当の名前・「墨」)。
        let name: String
        /// 判子の略称 (担当の色)。nil は墨。
        var stamp: String? = nil
        var seed: String? = nil
        var brand: String? = nil
        let isSelected: Bool
        /// 読み上げ (「星井美希の色」)。
        let accessibilityLabel: String
    }

    let items: [Item]
    let onSelect: (Item) -> Void

    private static let side: CGFloat = 34

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.gapLoose) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.imasStandard) { onSelect(item) }
                    } label: {
                        VStack(spacing: DS.Space.gapTight) {
                            swatch(item)
                                .padding(3)
                                .overlay(Circle().strokeBorder(item.isSelected ? DS.ink : .clear, lineWidth: 2))
                            Text(item.name)
                                .imasText(.note, color: item.isSelected ? DS.ink : DS.ink2)
                                .lineLimit(1)
                                .frame(maxWidth: 64)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.accessibilityLabel)
                    .accessibilityAddTraits(item.isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .sensoryFeedback(.selection, trigger: items.firstIndex { $0.isSelected })
    }

    @ViewBuilder
    private func swatch(_ item: Item) -> some View {
        if let stamp = item.stamp {
            ImasAvatar(label: stamp, seed: item.seed, brand: item.brand, size: Self.side, reservesPickRing: false)
        } else {
            Circle().fill(DS.ink)
                .overlay(Text(item.name).imasText(.rowLabel, color: DS.bg))
                .frame(width: Self.side, height: Self.side)
        }
    }
}
