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
            // 名前と別名の両方を綴りに入れる (「Cleasky」でも「クレスカイ」でも当たる)。
            catalog = TextSearchCatalog(fieldsPerItem: loadedUnits.map { [$0.name, $0.nameAlt] })
            rebuild(searchText: searchText)
        } catch {
            Logger.database.error("load_failed units: \(error.localizedDescription)")
        }
    }

    /// 絞り込み用の索引。`units` を読んだ時に 1 回だけ組む。
    ///
    /// 1 打鍵 = `matchingIndices` 1 呼び出し (項目ごとに FFI を跨がない)。
    /// 曲一覧・アイドル一覧と同じ作りで、照合規則もコア
    /// (`domain/text_search_index.rs`) の同じ関数を通る。
    private var catalog: TextSearchCatalog?

    /// 検索語で絞り込み + ブランド別グループ化を再計算する。
    func rebuild(searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // 照合はコア (`domain/text_search_index.rs`) に一任する。
        // ここで `localizedCaseInsensitiveContains` を書いていたせいで、曲・アイドル・
        // ライブは「あるすとろめりあ」で当たるのにユニットだけ当たらなかった
        // (かなを畳んでいなかった)。同じ検索欄に打つ人からは説明の付かない差になる。
        // 索引が無い (読み込み前) なら素通し。黙って 0 件にする方が悪い。
        let result = trimmed.isEmpty ? units : (catalog?.filter(units, needle: trimmed) ?? units)
        filteredUnits = result

        let grouped = Dictionary(grouping: result, by: \.brandId)
        groupedByBrand = grouped
        visibleBrands = brands.filter { grouped[$0.id] != nil }
    }
}
