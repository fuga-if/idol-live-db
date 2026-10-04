import Foundation

/// `NextSongRecommending` の共有コア (スナップショット) アダプタ。FFI は 2 回 (選ぶ・曲を引く)。
struct CoreNextSongRepository: NextSongRecommending {
    let snapshot: CoreSnapshotManager

    func nextSongs(after songId: String, exclude: [String], limit: Int) async throws -> [NextSongCandidate] {
        try await snapshot.withStore { store in
            let picks = try store.nextSongRecommendations(songId: songId, exclude: exclude, limit: UInt32(max(0, limit)))
            guard !picks.isEmpty else { return [] }
            let songs = Dictionary(
                try store.songRecordsByIds(songIds: picks.map(\.songId)).map { ($0.id, CoreSongRepository.song(from: $0)) },
                uniquingKeysWith: { first, _ in first }
            )
            return picks.compactMap { pick in songs[pick.songId].map { NextSongCandidate(song: $0, label: pick.label) } }
        }
    }
}
