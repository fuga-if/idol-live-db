import Foundation

/// プレイリスト (曲の並び) を Apple Music で順に鳴らす。曲詳細の「再生」と同じく、
/// 契約が無ければ認可を尋ねてから。フル再生できなければ鳴らさない (試聴は 30 秒で曲送りにならない)。
@MainActor
enum PlaylistPlayback {
    /// - Returns: 鳴らし始められたか。false は未契約か、Apple Music にある曲が 1 つも無い。
    @discardableResult
    static func play(_ songs: [Song], startAt index: Int = 0) async -> Bool {
        let player = MusicKitService.shared
        if !player.hasAppleMusicSubscription {
            await player.requestAuthorization()
            guard player.hasAppleMusicSubscription else { return false }
        }
        let entries = songs.compactMap { song in
            song.appleMusicId.flatMap { $0.isEmpty ? nil : (songId: song.id, appleMusicId: $0) }
        }
        // 押した曲が Apple Music に無ければ、その後ろで最初に鳴らせる曲から。
        let start = songs[index...].lazy.compactMap { s in entries.firstIndex { $0.songId == s.id } }.first ?? 0
        await player.playQueue(entries, startAt: start)
        return player.isFullPlayback
    }

    /// Apple Music で鳴らせない曲 (配信なし) の数。一覧で「n 曲は飛ばします」と出す。
    static func unplayableCount(_ songs: [Song]) -> Int {
        songs.filter { ($0.appleMusicId ?? "").isEmpty }.count
    }
}
