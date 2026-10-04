import SwiftUI

/// 歌詞プレイヤーの下に出す「次は」の 1 行。押すとその曲へ送る。
/// 右端の記号で「次はこれ」(終わったら似た曲を足して流し続ける) を入れ切りする。
struct UpNextRow: View {
    private var player: MusicKitService { MusicKitService.shared }
    @State private var song: Song?

    var body: some View {
        let next = player.upNext
        Group {
            if let next {
                Button {
                    AppAnalytics.tap("lyrics_player.up_next")
                    player.skipToNext()
                } label: {
                    ImasRow(title: song?.title ?? "次の曲", subtitle: subtitle(next.label),
                            leading: .artwork(title: song?.title ?? "", seed: BrandColors.hex(for: song?.brandId),
                                              imageURL: song?.artworkUrl.flatMap(URL.init(string:))),
                            trailing: .custom(AnyView(autoplayToggle)), density: .compact)
                }
                .buttonStyle(.imasRow)
                .accessibilityHint("この曲へ送る")
            } else if player.isFullPlayback {
                ImasRow(title: player.autoplayNext ? "次の曲を探しています" : "この曲で終わります",
                        subtitle: player.autoplayNext ? nil : "右の記号で、似た曲を続けて流せます",
                        leading: .icon("text.line.last.and.arrowtriangle.forward", tone: .neutral),
                        trailing: .custom(AnyView(autoplayToggle)), density: .compact)
            }
        }
        .task(id: next?.songId) {
            song = nil
            guard let id = next?.songId else { return }
            song = try? await AppContainer.shared.songReading.song(id: id)
        }
    }

    private func subtitle(_ label: String?) -> String {
        ["次は", label].compactMap { $0 }.joined(separator: " · ")
    }

    private var autoplayToggle: some View {
        ImasIconButton(systemImage: "infinity",
                       label: player.autoplayNext ? "次はこれ: オン" : "次はこれ: オフ",
                       size: .small, style: player.autoplayNext ? .filled : .plain) {
            AppAnalytics.tap("lyrics_player.toggle_autoplay")
            player.autoplayNext.toggle()
        }
    }
}
