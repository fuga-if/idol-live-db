import Foundation

/// 再生との連動。プレイヤーとスクロールは親 (`SongSheetContent`) が持つ。
///
/// 追従・記録はフル再生 (Apple Music) だけ。30 秒試聴は曲のどこを切り出したか
/// 分からないので、行の時刻と突き合わせられない。
struct LyricsPlayback {
    /// この曲がフル尺で読み込まれているか (一時停止中も含む)。
    var isFullLoaded = false
    /// この曲がフル尺で鳴っているか。
    var isPlaying = false
    /// 今の再生位置 (ms)。フル再生でなければ nil。周期で読む。
    var positionMs: () -> Int? = { nil }
    /// 記録のためにこの曲のフル再生を始める。始められなければ false (未契約など)。
    var startFull: () async -> Bool = { false }
    /// 曲の長さ (ms)。フル再生していなければ nil。
    var durationMs: () -> Int? = { nil }
    /// 再生位置を動かす。
    var seek: (Int) -> Void = { _ in }
    /// その位置から鳴らす。フル再生していなければ始めてから動かす (シークバーのタップ)。
    var playFrom: (Int) async -> Void = { _ in }
    /// 再生 / 一時停止を切り替える。
    var togglePlay: () -> Void = {}
    /// その行を画面の中ほどへ寄せる。
    var scrollTo: (String) -> Void = { _ in }
    /// 曲を順に積んで鳴らしているか (プレイリスト)。曲送りのボタンを出す。
    var hasQueue = false
    var canSkipNext = false
    var skipNext: () -> Void = {}
    /// 前の曲へ (少し進んでいれば今の曲の頭へ)。
    var skipPrevious: () -> Void = {}
}

extension LyricsPlayback {
    /// Apple Music (`MusicKitService`) で鳴らす繋ぎ。歌詞タブと再生中バーで同じものを使う。
    ///
    /// - Parameter startFull: この曲のフル再生を始める。始められなければ false。
    @MainActor
    static func appleMusic(songId: String,
                           startFull: @escaping () async -> Bool,
                           scrollTo: @escaping (String) -> Void = { _ in }) -> LyricsPlayback {
        let player = MusicKitService.shared
        return LyricsPlayback(
            isFullLoaded: player.isFullPlayback && player.nowPlayingSongId == songId,
            isPlaying: player.isPlayingFull(songId: songId),
            positionMs: { player.nowPlayingSongId == songId ? player.fullPlaybackPositionMs : nil },
            startFull: startFull,
            durationMs: { player.nowPlayingSongId == songId ? player.fullPlaybackDurationMs : nil },
            seek: { player.seekFull(toMs: $0) },
            playFrom: { ms in
                let loaded = player.isFullPlayback && player.nowPlayingSongId == songId
                if !loaded {
                    guard await startFull() else { return }
                } else if !player.isPlaying {
                    player.resume()
                }
                player.seekFull(toMs: ms)
            },
            togglePlay: {
                if player.isPlaying { player.pause() } else { player.resume() }
            },
            scrollTo: scrollTo,
            hasQueue: player.hasQueue && player.nowPlayingSongId == songId,
            canSkipNext: player.canSkipToNext,
            skipNext: { player.skipToNext() },
            skipPrevious: { player.skipToPrevious() }
        )
    }
}

/// 歌詞行の「ここ好き」の付け外し。歌詞タブと歌詞プレイヤーで同じ動きにするための 1 か所。
///
/// 自分の印は端末に行 ID だけ残し (本文は残さない)、ログインしていればみんなの人数にも足す。
/// 送れなくても自分の印は残す。
@MainActor
enum LyricLikeAction {
    /// - Returns: 付け外し後のその行の人数 (送れたときだけ)。端末への書き込みに失敗したら nil。
    static func toggle(songId: String, lineId: String) async -> Int? {
        AppAnalytics.tap("lyric_like.toggle")
        let marks = UserMarkService.shared
        do {
            try marks.toggleLyricLike(songId: songId, lineId: lineId)
        } catch {
            LocalWriteFailure.report(error, action: "ここ好きの記録")
            return nil
        }
        guard AuthService.shared.isSignedIn else { return nil }
        let liked = marks.lyricLikes(songId: songId).contains(lineId)
        return try? await AppContainer.shared.callGuideWriting
            .setLyricLike(songId: songId, lineId: lineId, liked: liked)
    }
}
