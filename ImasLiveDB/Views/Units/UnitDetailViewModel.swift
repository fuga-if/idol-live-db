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
    /// 初回ロード中 (スケルトン表示用)。IdolListViewModel/UnitListViewModel と同じ命名。
    private(set) var isLoading = false
    /// 直近ロードの失敗メッセージ。nil なら未失敗 (成功 or 未ロード)。
    /// songs/members が空でも loadError が nil なら「本当に空」、非 nil なら「失敗」と区別できる。
    private(set) var loadError: String?

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
        isLoading = true
        defer { isLoading = false }
        do {
            async let m = unitReading.unitMembers(unitId: unit.id)
            async let s = unitReading.unitSongs(unitId: unit.id)
            async let b = brandReading.brands()
            let (loadedMembers, loadedSongs, brands) = try await (m, s, b)
            members = loadedMembers
            songs = loadedSongs
            brand = brands.first { $0.id == unit.brandId }
            loadError = nil
        } catch {
            Logger.database.error("load_failed unit_detail: \(error.localizedDescription)")
            loadError = "読み込みに失敗しました。通信状況を確認してもう一度お試しください。"
        }
    }
}
