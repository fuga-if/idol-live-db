import SwiftUI

/// イベントカード左端のブランドカラーバー
struct BrandColorBar: View {
    @Environment(AppDatabase.self) private var database
    let brandId: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(brandColor)
            .frame(width: 4, height: 40)
    }

    private var brandColor: Color {
        guard let hex = BrandPalette.hex(for: brandId) else { return .gray }
        return Color(hexString: hex)
    }
}

/// ブランド色ドット + 略称 + 件数 のセクション見出し。
/// アイドル一覧/グリッドのブランド区切り見出しを 1 部品に統一。
/// 末尾の開閉シェブロン等は呼び出し側で HStack に並べる (本部品は Spacer まで)。
struct BrandSectionHeader: View {
    let brand: Brand
    let count: Int
    /// 件数の単位 (人/曲 等)。
    var unit: String = "人"

    var body: some View {
        HStack(spacing: DS.sp3) {
            Circle()
                .fill(Color(hexString: brand.color, default: DS.ink3))
                .frame(width: 9, height: 9)
            Text(brand.shortName)
                .font(.imasScaled( 13, weight: .semibold))
                .foregroundStyle(DS.ink2)
            Text("\(count)\(unit)")
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
            Spacer()
        }
    }
}
