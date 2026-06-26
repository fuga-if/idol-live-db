import MusicKit
import SwiftUI

struct FullPlayButton: View {
    let songInfo: MusicKitSongInfo
    let title: String

    @State private var isRequesting = false

    var body: some View {
        Button {
            Task { await start() }
        } label: {
            HStack {
                Label {
                    Text(labelText)
                } icon: {
                    Image(systemName: iconName)
                        .font(.imasTitle3)
                        .foregroundStyle(iconColor)
                }
                Spacer()
                if isRequesting {
                    ProgressView()
                }
            }
        }
        .disabled(isRequesting)
    }

    private var isPlayingFull: Bool {
        let svc = MusicKitService.shared
        return svc.isPlaying && svc.isFullPlayback && svc.nowPlayingTitle == title
    }

    private var labelText: String {
        if isPlayingFull { return "フル再生中…停止" }
        if MusicKitService.shared.hasAppleMusicSubscription { return "Apple Musicでフル再生" }
        return "Apple Musicでフル再生 (要許可)"
    }

    private var iconName: String {
        isPlayingFull ? "stop.circle.fill" : "play.circle.fill"
    }

    private var iconColor: Color {
        isPlayingFull ? .red : .pink
    }

    private func start() async {
        if isPlayingFull {
            MusicKitService.shared.stop()
            return
        }
        isRequesting = true
        defer { isRequesting = false }

        if !MusicKitService.shared.hasAppleMusicSubscription {
            await MusicKitService.shared.requestAuthorization()
            guard MusicKitService.shared.hasAppleMusicSubscription else { return }
        }
        await MusicKitService.shared.playFull(songInfo: songInfo, title: title)
    }
}
