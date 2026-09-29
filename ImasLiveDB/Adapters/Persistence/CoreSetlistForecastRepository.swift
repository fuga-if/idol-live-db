import Foundation

/// `SetlistForecastReading` のコア実装。
///
/// `withStore` の本体は nonisolated な async の文脈で走るので、呼び出し側が
/// main actor でもコアの計算はメインスレッドに乗らない。
struct CoreSetlistForecastRepository: SetlistForecastReading {
    let snapshot: CoreSnapshotManager

    func setlistForecast(showId: String, limit: Int) async throws -> SetlistForecastRecord? {
        try await snapshot.withStore { store in
            try store.setlistForecast(showId: showId, limit: UInt32(clamping: max(0, limit)))
        }
    }
}
