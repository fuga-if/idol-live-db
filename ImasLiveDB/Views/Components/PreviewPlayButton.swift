import SwiftUI

/// 30秒プレビュー再生ボタン（アプリ内再生）
struct PreviewPlayButton: View {
    let url: URL
    let title: String

    var body: some View {
        Button {
            MusicKitService.shared.togglePreview(url: url, title: title)
        } label: {
            HStack {
                Label {
                    if isCurrentlyPlaying {
                        Text("再生中…")
                    } else {
                        Text("30秒プレビュー")
                    }
                } icon: {
                    Image(systemName: isCurrentlyPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.imasTitle3)
                        .foregroundStyle(isCurrentlyPlaying ? .red : .accentColor)
                }
                Spacer()
            }
        }
    }

    private var isCurrentlyPlaying: Bool {
        MusicKitService.shared.isPlaying && MusicKitService.shared.nowPlayingTitle == title
    }
}
