import Foundation
import os

/// IdolDetailView のデータ取得担当。
///
/// 役割分担:
/// - **VM (ここ)**: ポート越しの原曲/歌唱曲/所属ユニット/ブランド/出演履歴取得 (`idolReading`/
///   `brandReading`/`unitReading`) と、ユニットの「曲あり/曲なし」分割結果を保持。
/// - **View 側**: 画像サービス・マークサービスの `@Observable` 観測、セグメント・シート等の UI 状態。
@MainActor
@Observable
final class IdolDetailViewModel {
    private(set) var castShows: [CastShowRow] = []
    private(set) var originalSongSections: [IdolSongSection] = []
    private(set) var performedSongs: [IdolPerformedSong] = []
    private(set) var units: [Unit] = []
    /// 所属ユニットを「曲あり / 曲なし」で分割 (ユニット数が多く煩雑になるため)。
    private(set) var unitsWithSongs: [Unit] = []
    private(set) var unitsWithoutSongs: [Unit] = []
    private(set) var brand: Brand?

    private let idolReading: any IdolReading
    private let brandReading: any BrandReading
    private let unitReading: any UnitReading

    /// 楽曲タブの小タブで初めに選ぶ節 (曲がある最初の枠の見出し)。節が 0 件なら nil。
    /// 節の並び (ソロ→ユニット→全体曲→カバー→その他、0 件は含まない) はコアが決める。
    var initialSongSectionHeading: String? { originalSongSections.first?.heading }

    nonisolated init(
        idolReading: any IdolReading = AppContainer.shared.idolReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading,
        unitReading: any UnitReading = AppContainer.shared.unitReading
    ) {
        self.idolReading = idolReading
        self.brandReading = brandReading
        self.unitReading = unitReading
    }

    func loadDetails(idol: Idol) async {
        do {
            async let o = idolReading.idolOriginalSongSections(idolId: idol.id)
            async let p = idolReading.idolPerformedSongs(idolId: idol.id)
            async let u = idolReading.idolUnits(idolId: idol.id)
            async let b = brandReading.brands()
            async let s = idolReading.idolShows(idolId: idol.id)
            let (loadedOriginal, loadedPerformed, loadedUnits, brands, shows) =
                try await (o, p, u, b, s)
            originalSongSections = loadedOriginal
            performedSongs = loadedPerformed
            units = loadedUnits
            // 曲あり / 曲なし に分割 (順序は元の name 順を維持)。
            let withSongs = (try? await unitReading.unitIdsWithSongs(unitIds: loadedUnits.map(\.id))) ?? []
            unitsWithSongs = loadedUnits.filter { withSongs.contains($0.id) }
            unitsWithoutSongs = loadedUnits.filter { !withSongs.contains($0.id) }
            brand = brands.first { $0.id == idol.brandId }
            castShows = shows
        } catch {
            Logger.database.error("load_failed idol_detail: \(error.localizedDescription)")
        }
    }
}
