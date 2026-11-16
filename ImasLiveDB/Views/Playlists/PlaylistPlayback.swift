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

    /// フル尺で鳴らせず飛ばす曲の数 (Apple Music に無い曲と、聴き放題に無い版の曲)。一覧で「n 曲は飛ばします」と出す。
    /// 聴き放題に無い版は `checkStreamable` で調べた分だけ数える。
    /// Spotify で鳴らすときは曲名で探すので、鳴らしてみるまで分からない (0 を返して出さない)。
    static func unplayableCount(_ songs: [Song]) -> Int {
        MusicKitService.shared.fullPlaySkipCount(songs.map(\.appleMusicId))
    }

    /// この曲を飛ばすか (一覧の行を薄くして「聴けない」と出す)。
    static func skips(_ song: Song) -> Bool {
        MusicKitService.shared.fullPlaySkips(song.appleMusicId)
    }

    /// 並べた曲が聴き放題で鳴らせるかを調べる (画面を開いたときに 1 回。結果で `unplayableCount` が変わる)。
    static func checkStreamable(_ songs: [Song]) async {
        await MusicKitService.shared.checkStreamable(songs.map(\.appleMusicId))
    }
}
