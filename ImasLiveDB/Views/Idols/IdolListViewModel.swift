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

    /// ブランド ID → ブランドカラー hex。
    /// 通しリストの行やテーマの下ごしらえは 1 件ずつブランド色を引くので、
    /// `brands.first(where:)` の線形探索を件数ぶん繰り返さないようロード時に辞書へ畳む。
    private(set) var brandColorById: [String: String] = [:]

    /// 読み込んだ元データ (idols/brands) の版。**絞り込みでは動かず、再ロードでのみ増える。**
    /// 全件から作る派生物 (テーマの下ごしらえ等) を作り直すべきかの判定に使う。
    private(set) var dataVersion = 0

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

    func loadData(filter: IdolFilterContext, sortOrder: IdolSortOrder = .official, ascending: Bool? = nil) async {
        defer { isLoading = false }
        do {
            async let b = brandReading.brands()
            async let i = idolReading.idols(brandId: nil)
            async let c = idolReading.idolCastNames()
            (brands, idols, castNames) = try await (b, i, c)
            // 先勝ち。`brands.first(where:)` が返していたのと同じブランドを引くため。
            brandColorById = Dictionary(
                brands.compactMap { brand -> (String, String)? in
                    guard let color = brand.color else { return nil }
                    return (brand.id, color)
                },
                uniquingKeysWith: { first, _ in first })
            dataVersion += 1
            rebuild(filter: filter, sortOrder: sortOrder, ascending: ascending)
        } catch {
            Logger.database.error("load_failed idols: \(error.localizedDescription)")
        }
    }

    /// 通しリスト (ブランド別セクションが無い並び) の行が引くブランド色。
    func brandColor(for idol: Idol) -> String? {
        brandColorById[idol.brandId]
    }

    func refreshPickIds() {
        pickIds = Set(UserMarkService.shared.allMarked(kind: .myPick, entity: .idol))
    }

    /// 絞り込み + 並び替え + ブランド別グループ化を再計算する。
    /// `filter.castNames` は呼び出し側で詰めなくてもよい (ここで VM 保持の値を補完する)。
    ///
    /// 公式順以外を選んだときはブランドの区切りを外し、通しの 1 リストにする
    /// (`visibleBrands` を空にすることで View 側が通し表示に切り替わる)。
    func rebuild(filter: IdolFilterContext, sortOrder: IdolSortOrder = .official, ascending: Bool? = nil) {
        var ctx = filter
        ctx.castNames = castNames

        let result = sortIdols(filterIdols(idols, ctx), by: sortOrder, ascending: ascending)
        filteredIdols = result

        guard sortOrder.keepsBrandGrouping else {
            groupedByBrand = [:]
            visibleBrands = []
            return
        }
        // grouped に載るのは必ず 1 件以上なので、キー有無で表示ブランドを判定できる。
        let grouped = Dictionary(grouping: result, by: \.brandId)
        groupedByBrand = grouped
        visibleBrands = brands.filter { grouped[$0.id] != nil }
    }
}
