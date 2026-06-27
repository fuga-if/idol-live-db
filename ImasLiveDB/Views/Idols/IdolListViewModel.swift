import Foundation
import os

/// IdolListView のオーケストレーション担当。
///
/// 役割分担:
/// - **VM (ここ)**: ポート越しのデータ取得 (`idolReading`/`brandReading`) と、
///   純粋 UseCase (`filterIdols`) を使った絞り込み・ブランド別グループ化の結果保持。
/// - **View 側**: `@AppStorage` の設定値・選択状態 (ブランド/属性/検索語/必須マーク) を保持し、
///   フィルタ条件として VM のメソッドへ渡す。
///
/// マーク集合の解決 (`UserMarkService`) は `@Observable` 観測を壊さないため View 文脈で行い、
/// 解決済み ID 集合を引数で受け取る。
@MainActor
@Observable
final class IdolListViewModel {
    private(set) var idols: [Idol] = []
    private(set) var brands: [Brand] = []
    private(set) var castNames: [String: String] = [:]
    /// 初回ロード中 (スケルトン表示用)。初回完了で false。
    private(set) var isLoading = true

    // フィルタ済み派生結果
    private(set) var filteredIdols: [Idol] = []
    private(set) var groupedByBrand: [String: [Idol]] = [:]
    private(set) var visibleBrands: [Brand] = []

    // 担当アイドル ID キャッシュ (isPick 判定・twoline 二重輪)
    private(set) var pickIds: Set<String> = []

    private let idolReading: any IdolReading
    private let brandReading: any BrandReading

    nonisolated init(
        idolReading: any IdolReading = AppContainer.shared.idolReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading
    ) {
        self.idolReading = idolReading
        self.brandReading = brandReading
    }

    func loadData(filter: IdolFilterContext) async {
        defer { isLoading = false }
        do {
            async let b = brandReading.brands()
            async let i = idolReading.idols(brandId: nil)
            async let c = idolReading.idolCastNames()
            (brands, idols, castNames) = try await (b, i, c)
            rebuild(filter: filter)
        } catch {
            Logger.database.error("load_failed idols: \(error.localizedDescription)")
        }
    }

    func refreshPickIds() {
        pickIds = Set(UserMarkService.shared.allMarked(kind: .myPick, entity: .idol))
    }

    /// 絞り込み + ブランド別グループ化を再計算する。
    /// `filter.castNames` は呼び出し側で詰めなくてもよい (ここで VM 保持の値を補完する)。
    func rebuild(filter: IdolFilterContext) {
        var ctx = filter
        ctx.castNames = castNames

        let result = filterIdols(idols, ctx)
        filteredIdols = result

        // grouped に載るのは必ず 1 件以上なので、キー有無で表示ブランドを判定できる。
        let grouped = Dictionary(grouping: result, by: \.brandId)
        groupedByBrand = grouped
        visibleBrands = brands.filter { grouped[$0.id] != nil }
    }
}
