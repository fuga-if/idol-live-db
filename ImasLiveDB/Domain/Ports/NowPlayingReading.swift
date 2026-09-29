import Foundation

/// 再生中バーの読み取りポート (driven port)。
///
/// 「バーに何を出すか」はコア (`imas-core` の `now_playing`) の判断なので、
/// ここは `song_id` と再生状態を渡して 1 枚受け取るだけの口。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol NowPlayingReading: Sendable {
    /// 鳴っている曲のバー 1 枚。鳴らす曲を知らない / スナップショット未ロードなら nil。
    func bar(songId: String, kind: NowPlayingKind, isPlaying: Bool) async -> NowPlayingBar?
}
