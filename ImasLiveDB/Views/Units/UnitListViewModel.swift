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

    // UnitListContent の UI 状態。IdolListView の「ユニット」タブ切替で UnitListContent
    // (View インスタンス) 自体が破棄・再生成されても失われないよう、ここ (hoist された
    // ViewModel) に持たせる。Android 版 UnitListViewModel の uiState と同じ設計。
    var searchText: String = ""
    var isSearching: Bool = false
    var collapsedBrands: Set<String> = []
    var sheetUnit: Unit?

    private let unitReading: any UnitReading
    private let brandReading: any BrandReading

    nonisolated init(
        unitReading: any UnitReading = AppContainer.shared.unitReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading
    ) {
        self.unitReading = unitReading
        self.brandReading = brandReading
    }

    /// タブ切替のたびに View が再生成されて `.task` が再実行されても、初回ロード済みなら
    /// 再フェッチしない (状態は vm 側にあるので再ロードの必要が無い)。
    func loadData() async {
        guard units.isEmpty else { return }
        defer { isLoading = false }
        do {
            async let b = brandReading.brands()
            async let u = unitReading.unitsWithSongs()
            let (loadedBrands, loadedUnits) = try await (b, u)
            brands = loadedBrands
            units = loadedUnits
            rebuild(searchText: searchText)
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
