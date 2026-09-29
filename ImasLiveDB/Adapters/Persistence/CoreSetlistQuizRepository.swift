import Foundation

/// `SetlistQuizReading` のコア実装。出題はスナップショットからコアが一括で作る。
struct CoreSetlistQuizRepository: SetlistQuizReading {
    let snapshot: CoreSnapshotManager

    func poolEstimate(brandIds: [String]) async throws -> SetlistQuizPoolEstimate {
        try await snapshot.withStore { store in
            try store.setlistQuizPoolEstimate(brandIds: brandIds)
        }
    }

    func session(brandIds: [String], seed: UInt64) async throws -> [SetlistQuizQuestion] {
        try await snapshot.withStore { store in
            try store.setlistQuizSession(brandIds: brandIds, seed: seed)
        }
    }
}
