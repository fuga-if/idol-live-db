import SwiftUI

/// 歌詞プレイヤーの「次に流れる曲」。積んだ曲の残りを並べ、∞ で「次はこれ」(終わったら似た曲を
/// 足して流し続ける) を入れ切りする (Apple Music の自動再生と同じ置き場所)。既定は切。
struct PlayQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [String: Song] = [:]

    private var player: MusicKitService { MusicKitService.shared }

    /// いまの曲より後ろに積んである曲。
    private var upcoming: [String] {
        guard let index = player.queueIndex, index + 1 < player.queueSongIds.count else { return [] }
        return Array(player.queueSongIds[(index + 1)...])
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ImasRow(title: "自動再生",
                            subtitle: player.autoplayNext ? "終わったら似た曲を続けて流します" : "積んだ曲で終わります",
                            leading: .icon("infinity", tone: .neutral),
                            trailing: .custom(AnyView(autoplayToggle)), density: .compact)
                }
                if !upcoming.isEmpty {
                    ImasListSection("次に流れる曲") {
                        ForEach(Array(upcoming.enumerated()), id: \.offset) { offset, id in
                            let song = songs[id]
                            let row = ImasRow(title: song?.title ?? "次の曲", subtitle: player.recommendedLabels[id],
                                              leading: .artwork(title: song?.title ?? "", seed: BrandColors.hex(for: song?.brandId),
                                                                imageURL: song?.artworkUrl.flatMap(URL.init(string:))),
                                              density: .compact)
                            if offset == 0 {
                                Button {
                                    AppAnalytics.tap("lyrics_player.up_next")
                                    player.skipToNext()
                                } label: { row }
                                .buttonStyle(.imasRow)
                                .accessibilityHint("この曲へ送る")
                            } else {
                                row
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .imasForm()
            .navigationTitle("次に流れる曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ImasIconButton(systemImage: "xmark", label: "閉じる", size: .small, style: .plain) { dismiss() }
                }
            }
        }
        .task(id: upcoming) {
            for id in upcoming where songs[id] == nil {
                songs[id] = try? await AppContainer.shared.songReading.song(id: id)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var autoplayToggle: some View {
        ImasIconButton(systemImage: "infinity",
                       label: player.autoplayNext ? "自動再生: オン" : "自動再生: オフ",
                       size: .small, style: player.autoplayNext ? .filled : .plain) {
            AppAnalytics.tap("lyrics_player.toggle_autoplay")
            player.autoplayNext.toggle()
        }
    }
}
