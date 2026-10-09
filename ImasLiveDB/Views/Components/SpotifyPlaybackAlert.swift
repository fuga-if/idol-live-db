import SwiftUI

extension View {
    /// Spotify で鳴らせなかったときの案内 (`MusicKitService.spotifyFailure`)。
    ///
    /// アラートはいま前に出ている画面にしか出ないので、曲を鳴らせる画面の根 (タブ・詳細シート・歌詞プレイヤー) に付ける。
    /// 鳴らす先が無いときは Spotify アプリを開く口を添える (開けば鳴らす先として見えるようになる)。
    func spotifyPlaybackAlert() -> some View { modifier(SpotifyPlaybackAlert()) }
}

private struct SpotifyPlaybackAlert: ViewModifier {
    @Environment(\.openURL) private var openURL
    private var player: MusicKitService { .shared }

    func body(content: Content) -> some View {
        content.alert(
            "Spotify で鳴らせませんでした",
            isPresented: Binding(get: { player.spotifyFailure != nil }, set: { if !$0 { player.clearSpotifyFailure() } }),
            presenting: player.spotifyFailure
        ) { failure in
            if failure == .noDevice {
                Button("Spotify を開く") {
                    // アプリが無ければ Web の Spotify へ。
                    openURL(URL(string: "spotify:")!) { opened in
                        if !opened, let web = URL(string: "https://open.spotify.com") { openURL(web) }
                    }
                }
            }
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(spotifyFailureMessage(failure: failure))
        }
    }
}
