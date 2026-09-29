import Foundation

/// `NowPlayingReading` のコア実装。
///
/// 他の `Core*Repository` と同じく、スナップショットがまだならロードを待ってから答える。
/// ロードに失敗したときはバーを出さない (バーは出なくても困らない表示なので、失敗を伝えない)。
struct CoreNowPlayingRepository: NowPlayingReading {
    let snapshot: CoreSnapshotManager

    func bar(songId: String, kind: NowPlayingKind, isPlaying: Bool) async -> NowPlayingBar? {
        try? await snapshot.withStore { store in
            try store.nowPlayingBar(songId: songId, kind: kind, isPlaying: isPlaying)
        }
    }
}
