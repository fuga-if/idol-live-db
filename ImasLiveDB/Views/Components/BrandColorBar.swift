import SwiftUI

/// イベントカード左端のブランドカラーバー。見た目は DS の `ImasLeadBar`
/// (ブランド色が引けないときは `ImasLeadBar` 自身のニュートラル配色に委ねる)。
struct BrandColorBar: View {
    let brandId: String?

    var body: some View {
        ImasLeadBar(brand: brandId)
            .frame(width: DS.Size.leadBar, height: 40)
    }
}

/// ブランド色ドット + 略称 + 件数 のセクション見出し。見た目は DS の `ImasSectionHeader`
/// (先頭のペンライトがブランド色のドット、`count` が件数に当たる)。
/// アイドル一覧/グリッドのブランド区切り見出しを 1 部品に統一。
/// 末尾の開閉シェブロン等は呼び出し側で HStack に並べる (本部品は内部の Spacer まで)。
struct BrandSectionHeader: View {
    let brand: Brand
    let count: Int
    /// 件数の単位 (人/曲 等)。
    var unit: String = "人"

    var body: some View {
        ImasSectionHeader(brand.shortName, count: "\(count)\(unit)", seed: brand.color, style: .small)
    }
}
