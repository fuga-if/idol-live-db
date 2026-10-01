import SwiftUI

struct IdolGridView: View {
    let idols: [Idol]
    let brands: [Brand]
    /// 担当アイドル ID。アバターの二重輪 (isPick) 表示に使う。
    var pickIds: Set<String> = []
    /// idol id → セルに併記する指標 (公式順以外。`brands` は空で渡して通しグリッドにする)。
    var metricLabels: [String: String] = [:]
    /// 通し表示時の見出し (「年齢順 / 342人」等)。
    var flatHeader: String? = nil
    let onSelect: (Idol) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// 1 行あたりの列数。コンパクト幅 (iPhone) は 4、レギュラー幅 (iPad) は 6。
    /// フルネーム表示のため列数を抑え気味にしている。
    private var columnCount: Int { sizeClass == .regular ? 6 : 4 }

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
                                .imasText(.sectionLabel)
                                .padding(.horizontal, DS.sp5)
                        }
                        ImasIdolGrid(columns: columnCount) {
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

                        ImasIdolGrid(columns: columnCount) {
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

    // MARK: - Idol Cell (名札。写真があれば写真、無ければ判子)

    private func cell(_ idol: Idol, brand: Brand?) -> some View {
        // metric: 何順に並んでいるかセルから読めるようにする (公式順/五十音順では nil)。
        ImasIdolCell(idol: idol, isPick: pickIds.contains(idol.id), metric: metricLabels[idol.id])
            .contentShape(Rectangle())
            .onTapGesture { onSelect(idol) }
    }
}
