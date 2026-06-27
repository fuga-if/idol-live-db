import SwiftUI

struct IdolGridView: View {
    let idols: [Idol]
    let brands: [Brand]
    /// 担当アイドル ID。アバターの二重輪 (isPick) 表示に使う。
    var pickIds: Set<String> = []
    let onSelect: (Idol) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// 1 行あたりの列数。コンパクト幅 (iPhone) は 4、レギュラー幅 (iPad) は 6。
    /// フルネーム表示のため列数を抑え気味にしている。
    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 6 : 4
        return Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: count)
    }

    private var groupedIdols: [(brand: Brand, idols: [Idol])] {
        var byBrand: [String: [Idol]] = [:]
        for idol in idols {
            byBrand[idol.brandId, default: []].append(idol)
        }
        return brands.compactMap { brand in
            guard let group = byBrand[brand.id], !group.isEmpty else { return nil }
            return (brand, group)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.sp6) {
                ForEach(groupedIdols, id: \.brand.id) { group in
                    VStack(alignment: .leading, spacing: DS.sp4) {
                        header(group.brand, count: group.idols.count)
                            .padding(.horizontal, DS.sp5)

                        LazyVGrid(columns: columns, spacing: DS.sp5) {
                            ForEach(group.idols) { idol in
                                cell(idol, brand: group.brand)
                            }
                        }
                        .padding(.horizontal, DS.sp4)
                    }
                }
            }
            .padding(.top, DS.sp4)
            .padding(.bottom, DS.sp7)
        }
        .background(DS.bg)
    }

    // MARK: - Brand Header (ブランド色ドット + 名前 + 人数)

    private func header(_ brand: Brand, count: Int) -> some View {
        BrandSectionHeader(brand: brand, count: count)
    }

    // MARK: - Idol Cell (IdolAvatarView 主役・ブランド色をまとう)

    private func cell(_ idol: Idol, brand: Brand) -> some View {
        // 担当/お気に入りバッジは「アバター」の右上に重ねる。セル幅基準 (ZStack topTrailing
        // + offset) だと中央のアバターから離れてセル右端に浮くため、overlay でアバター基準にする。
        VStack(spacing: DS.sp2) {
            IdolAvatarView(idol: idol, size: 60, isPick: pickIds.contains(idol.id))
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: -4) {
                        MyPickToggleButton(id: idol.id, size: 14)
                        FavoriteToggleButton(entity: .idol, id: idol.id, size: 14)
                    }
                    .offset(x: 10, y: -6)
                }
            Text(idol.name)
                .font(.imasCaption)
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(idol) }
    }
}
