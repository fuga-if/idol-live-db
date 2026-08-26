import SwiftUI

struct IdolGridView: View {
    let idols: [Idol]
    let brands: [Brand]
    /// 担当アイドル ID。アバターの二重輪 (isPick) 表示に使う。
    var pickIds: Set<String> = []
    /// 並び順。公式順以外は `brands` を空で渡して通しグリッドにし、セルに指標を併記する。
    var sortOrder: IdolSortOrder = .official
    /// 通し表示時の見出し (「年齢順 / 342人」等)。
    var flatHeader: String? = nil
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
                // 公式順以外はブランドの区切りを外した通しグリッド
                // (身長順・年齢順はブランドを跨いで初めて意味を持つ指標のため)。
                if brands.isEmpty {
                    VStack(alignment: .leading, spacing: DS.sp4) {
                        if let flatHeader {
                            Text(flatHeader)
                                .font(.imasScaled(13, weight: .semibold))
                                .foregroundStyle(DS.ink2)
                                .padding(.horizontal, DS.sp5)
                        }
                        LazyVGrid(columns: columns, spacing: DS.sp5) {
                            ForEach(idols) { idol in
                                cell(idol, brand: nil)
                            }
                        }
                        .padding(.horizontal, DS.sp4)
                    }
                }
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
        // セルのアバターが引くテーマの温め (`imasThemePrewarm`) はここでは行わない。
        // 受け取る `idols` は絞り込み済みなので、ここで温めると打鍵のたびに母集団が変わり、
        // 温め済みを数え直すだけになる。所有者 (IdolListView) が全件ぶんを 1 回で温めており、
        // ここに並ぶのは常にその部分集合。
        .background(DS.bg)
    }

    // MARK: - Brand Header (ブランド色ドット + 名前 + 人数)

    private func header(_ brand: Brand, count: Int) -> some View {
        BrandSectionHeader(brand: brand, count: count)
    }

    // MARK: - Idol Cell (IdolAvatarView 主役・ブランド色をまとう)

    private func cell(_ idol: Idol, brand: Brand?) -> some View {
        VStack(spacing: DS.sp2) {
            IdolAvatarView(idol: idol, size: 60, isPick: pickIds.contains(idol.id))
            Text(idol.name)
                .font(.imasCaption)
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // 何順に並んでいるかセルから読めるようにする。
            if let metric = sortOrder.metricLabel(for: idol) {
                Text(metric)
                    .font(.imasDisplay(11, weight: .semibold))
                    .foregroundStyle(DS.ink3)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(idol) }
    }
}
