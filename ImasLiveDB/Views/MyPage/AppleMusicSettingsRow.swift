import MusicKit
import SwiftUI
import UIKit

/// 設定の「Apple Music」。フル尺で鳴らせるか (許可・契約) と、許可の入口。
///
/// 曲の行の再生ボタンは、鳴らせなければ試聴へ落とす (`MusicKitService.toggleSong`)。許可を断ったまま
/// だと気付く場所が無かったので、ここで状態を出す。Android は同じ欄でサインインする (`AppleMusicSettingsRow.kt`)。
struct AppleMusicSettingsRow: View {
    @State private var status = MusicAuthorization.currentStatus
    @Environment(\.openURL) private var openURL
    private var player: MusicKitService { MusicKitService.shared }

    var body: some View {
        Group {
            switch status {
            case .authorized:
                ImasNavRow(title: player.hasAppleMusicSubscription ? "フル尺で鳴らせます" : "Apple Music の契約がありません",
                           subtitle: player.hasAppleMusicSubscription
                               ? "曲を鳴らすと歌詞を追いかけられます"
                               : "契約するまで、曲は試聴 (30 秒) で鳴ります",
                           systemImage: "music.note", showsChevron: false)
            case .notDetermined:
                Button {
                    Task {
                        await player.requestAuthorization()
                        status = MusicAuthorization.currentStatus
                    }
                } label: {
                    ImasNavRow(title: "Apple Music へのアクセスを許可", subtitle: "許可するまで、曲は試聴 (30 秒) で鳴ります",
                               systemImage: "music.note")
                }
                .buttonStyle(.imasRow)
            default:
                // 断った・制限されている: アプリからはもう聞けないので、設定アプリの許可を開く。
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    ImasNavRow(title: "設定アプリで Apple Music を許可", subtitle: "許可するまで、曲は試聴 (30 秒) で鳴ります",
                               systemImage: "music.note")
                }
                .buttonStyle(.imasRow)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status = MusicAuthorization.currentStatus
        }
    }
}
