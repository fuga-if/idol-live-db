import Foundation
import Observation
import os

/// セトリ予想の画面の「機械予測」の節。
///
/// 点数・順位・理由の札・公演の印は、すべてコア (`setlistForecast`) の答えをそのまま出す。
/// ここが持つのは、読み込みの状態と、みんなの予想に入っている曲を隠すことと、
/// 「予想に入れる」(= 既存の投票) の呼び出しだけ。
@MainActor
@Observable
final class SetlistForecastViewModel {
    /// 節に出す曲数。
    static let displayLimit = 20
    /// コアに頼む曲数。みんなの予想に入っている曲を隠しても 20 曲残るよう、多めに引く。
    /// (予想は 1 人 3 票なので、票の入った曲がこれを超えて上位を占めることはまず無い)
    static let fetchLimit = 60

    enum Phase {
        case loading
        case loaded(SetlistForecastRecord)
        /// 予測の対象でない公演か、読み込みに失敗した。節ごと出さない。
        case unavailable
    }

    let showId: String
    private(set) var phase: Phase = .loading
    /// このセッションで「予想に入れる」が成功した曲。みんなの予想の読み直しを待たずに隠す。
    private(set) var promotedSongIds: Set<String> = []
    /// 投票を送っている最中の曲 (連打の防止)。
    private(set) var promotingSongId: String?

    private let reading: any SetlistForecastReading
    private let voting: any SetlistPredictionVoting

    nonisolated init(
        showId: String,
        reading: any SetlistForecastReading = AppContainer.shared.setlistForecastReading,
        voting: any SetlistPredictionVoting = AppContainer.shared.setlistPredictionVoting
    ) {
        self.showId = showId
        self.reading = reading
        self.voting = voting
    }

    func load() async {
        do {
            let record = try await reading.setlistForecast(showId: showId, limit: Self.fetchLimit)
            phase = record.map(Phase.loaded) ?? .unavailable
        } catch {
            Logger.community.error("setlist_forecast_failed show=\(self.showId, privacy: .public): \(error.localizedDescription)")
            phase = .unavailable
        }
    }

    /// 出す曲。みんなの予想 (票のある曲) と、ここで予想に入れた曲は除く。順位はコアのまま。
    func visibleSongs(predictedSongIds: Set<String>) -> [ForecastSongRecord] {
        guard case .loaded(let record) = phase else { return [] }
        return Array(record.songs.lazy
            .filter { !predictedSongIds.contains($0.songId) && !self.promotedSongIds.contains($0.songId) }
            .prefix(Self.displayLimit))
    }

    /// 出演者未発表の印が立っていれば、その注記 (コアの label)。
    var castUnannouncedNote: String? {
        guard case .loaded(let record) = phase else { return nil }
        return record.flags.first { $0.flag == .castUnannounced }?.label
    }

    /// 「予想に入れる」。既存の投票をそのまま呼ぶ。失敗はそのまま投げる (表示は画面の既存の経路)。
    func promote(songId: String) async throws {
        guard promotingSongId == nil else { return }
        promotingSongId = songId
        defer { promotingSongId = nil }
        _ = try await voting.vote(showId: showId, songId: songId)
        promotedSongIds.insert(songId)
    }
}
