import Foundation
import os

/// UnitListView のオーケストレーション担当 (IdolListViewModel と同じ役割分担)。
/// 表示対象は「曲ありユニットのみ」(`UnitIndex.unitsWithSongs`) に絞る。
@MainActor
@Observable
final class UnitListViewModel {
    private(set) var units: [Unit] = []
    private(set) var brands: [Brand] = []
    /// 初回ロード中 (スケルトン表示用)。初回完了で false。
    private(set) var isLoading = true

    // フィルタ済み派生結果
    private(set) var filteredUnits: [Unit] = []
    private(set) var groupedByBrand: [String: [Unit]] = [:]
    private(set) var visibleBrands: [Brand] = []

    private let unitReading: any UnitReading
    private let brandReading: any BrandReading

    nonisolated init(
        unitReading: any UnitReading = AppContainer.shared.unitReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading
    ) {
        self.unitReading = unitReading
        self.brandReading = brandReading
    }

    func loadData() async {
        defer { isLoading = false }
        do {
            async let b = brandReading.brands()
            async let u = unitReading.unitsWithSongs()
            let (loadedBrands, loadedUnits) = try await (b, u)
            brands = loadedBrands
            units = loadedUnits
            rebuild(searchText: "")
        } catch {
            Logger.database.error("load_failed units: \(error.localizedDescription)")
        }
    }

    /// 検索語で絞り込み + ブランド別グループ化を再計算する。
    func rebuild(searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = trimmed.isEmpty
            ? units
            : units.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
        filteredUnits = result

        let grouped = Dictionary(grouping: result, by: \.brandId)
        groupedByBrand = grouped
        visibleBrands = brands.filter { grouped[$0.id] != nil }
    }
}
