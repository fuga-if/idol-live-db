import SwiftUI

/// いま鳴っている曲に付いていく歌詞プレイヤー (再生中バー・プレイリストから開く)。
///
/// 曲送りで曲が替わると、`LyricsSession` が預かり直した歌詞に差し替える。
/// 歌詞が無い曲 (取れなかった曲) では、曲名と曲送りだけを出す。
struct NowPlayingLyricsPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var likeCounts: [String: Int] = [:]
    /// タイミング編集は曲の詳細の歌詞タブから (記録の画面はそちらが持つ)。
    let onEditTimings: (Song) -> Void

    private var player: MusicKitService { MusicKitService.shared }

    var body: some View {
        if let entry = LyricsSession.shared.entry(forSongId: player.nowPlayingSongId) {
            LyricsPlayerView(song: entry.song, seed: entry.seed, artistLine: entry.artistLine,
                             artworkURL: entry.artworkURL, lyrics: entry.lyrics,
                             playback: .appleMusic(songId: entry.song.id, startFull: {
                                 // もう読み込まれている。止まっていれば鳴らし直すだけ。
                                 MusicKitService.shared.resume()
                                 return MusicKitService.shared.nowPlayingSongId == entry.song.id
                             }),
                             likeCounts: $likeCounts,
                             onEditTimings: { onEditTimings(entry.song) },
                             cast: entry.cast)
                .id(entry.song.id)
        } else {
            noLyrics
        }
    }

    /// 歌詞の無い曲・読み込み中。曲送りだけはできるようにする。
    private var noLyrics: some View {
        VStack(spacing: DS.sp5) {
            HStack {
                Spacer()
                ImasIconButton(systemImage: "chevron.down", label: "閉じる", size: .small) { dismiss() }
            }
            Spacer()
            ImasEmptyState(systemImage: "text.quote", title: "この曲の歌詞はまだありません")
            Spacer()
            HStack(spacing: DS.sp8) {
                ImasIconButton(systemImage: "backward.fill", label: "前の曲", style: .plain) {
                    player.skipToPrevious()
                }
                ImasIconButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                               label: player.isPlaying ? "一時停止" : "再生", style: .filled) {
                    if player.isPlaying { player.pause() } else { player.resume() }
                }
                ImasIconButton(systemImage: "forward.fill", label: "次の曲", style: .plain) {
                    player.skipToNext()
                }
                .disabled(!player.canSkipToNext)
            }
            UpNextRow()
        }
        .padding(DS.sp5)
        .background(DS.bg)
    }
}
