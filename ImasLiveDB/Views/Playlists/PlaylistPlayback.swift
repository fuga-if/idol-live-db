import Foundation

/// プレイリスト (曲の並び) をフル尺で順に鳴らす (Apple Music か Spotify かは `MusicKitService` が選ぶ)。
/// フル再生できなければ鳴らさない (試聴は 30 秒で曲送りにならない)。
@MainActor
enum PlaylistPlayback {
    /// - Returns: 鳴らし始められたか。false は鳴らせるサービスが無いか、鳴らせる曲が 1 つも無い。
    @discardableResult
    static func play(_ songs: [Song], startAt index: Int = 0) async -> Bool {
        await MusicKitService.shared.playFullSongs(songs.map { (songId: $0.id, appleMusicId: $0.appleMusicId) },
                                                   startAt: index)
    }

    /// Apple Music で鳴らせない曲 (配信なし) の数。一覧で「n 曲は飛ばします」と出す。
    /// Spotify で鳴らすときは曲名で探すので、鳴らしてみるまで分からない (0 を返して出さない)。
    static func unplayableCount(_ songs: [Song]) -> Int {
        guard MusicKitService.shared.fullPlaybackService != .spotify else { return 0 }
        return songs.filter { ($0.appleMusicId ?? "").isEmpty }.count
    }
}
