import Foundation
import os

/// UnitDetailView のデータ取得担当 (IdolDetailViewModel と同じ役割分担)。
/// ユニットには横断的な「出演履歴」クエリが無いため、保持するのは楽曲・メンバー・ブランドのみ。
@MainActor
@Observable
final class UnitDetailViewModel {
    private(set) var songs: [Song] = []
    private(set) var members: [Idol] = []
    private(set) var brand: Brand?

    private let unitReading: any UnitReading
    private let brandReading: any BrandReading

    nonisolated init(
        unitReading: any UnitReading = AppContainer.shared.unitReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading
    ) {
        self.unitReading = unitReading
        self.brandReading = brandReading
    }

    func loadDetails(unit: Unit) async {
        do {
            async let m = unitReading.unitMembers(unitId: unit.id)
            async let s = unitReading.unitSongs(unitId: unit.id)
            async let b = brandReading.brands()
            let (loadedMembers, loadedSongs, brands) = try await (m, s, b)
            members = loadedMembers
            songs = loadedSongs
            brand = brands.first { $0.id == unit.brandId }
        } catch {
            Logger.database.error("load_failed unit_detail: \(error.localizedDescription)")
        }
    }
}
