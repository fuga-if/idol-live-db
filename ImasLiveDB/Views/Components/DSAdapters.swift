import SwiftUI

// =============================================================================
// アプリのモデルから DesignSystem の部品へ写す口。
//
// DesignSystem はアプリのサービス (CustomImageService など) を知らない。画像の在り処や
// 色の引き方のようなアプリ側の事情はここで 1 回だけ解決し、画面は部品にモデルを渡すだけにする。
// =============================================================================

// MARK: - ブランド

extension ImasBrandPicker.Option {
    /// ブランドから。読み込んだロゴがあればロゴ、無ければペンライト。
    @MainActor init(brand: Brand) {
        self.init(id: brand.id, label: brand.shortName, color: brand.color,
                  logoURL: CustomImageService.shared.brandImageURL(for: brand.id))
    }
}

extension ImasBrandPicker {
    /// ブランドの並びから組む。
    @MainActor init(brands: [Brand], selection: Binding<Set<String>>, includesAll: Bool = true,
                    allowsMultiple: Bool = true) {
        self.init(options: brands.map { ImasBrandPicker.Option(brand: $0) }, selection: selection,
                  includesAll: includesAll, allowsMultiple: allowsMultiple)
    }
}

// MARK: - アイドル

extension ImasIdolCell {
    /// アイドルから。写真を設定した子は写真、担当は帯と枠が点く。
    @MainActor init(idol: Idol, isPick: Bool, isSelected: Bool? = nil) {
        self.init(name: idol.name, kana: idol.nameKana, seed: idol.color,
                  brand: BrandColors.hex(for: idol.brandId),
                  imageURL: CustomImageService.shared.imageURL(for: idol.id),
                  isPick: isPick, isSelected: isSelected)
    }
}
