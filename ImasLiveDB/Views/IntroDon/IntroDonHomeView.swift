import SwiftUI
import MusicKit

struct IntroDonHomeView: View {
    @State private var showSetup = false
    @State private var authStatus: MusicAuthorization.Status = MusicKitService.shared.authorizationStatus
    @Environment(\.openURL) private var openURL

    private let battleModeURL = URL(string: "https://apps.apple.com/jp/app/intro-%E3%82%A4%E3%83%B3%E3%83%88%E3%83%AD%E3%82%AF%E3%82%A4%E3%82%BA/id6760829877")!

    var body: some View {
        ImasPage {
            ImasMasthead("INTRO DON")
            ImasSetupHeader(systemImage: "music.note.list", title: "イントロドン",
                            message: "Apple Music のイントロを聴いて曲名をいち早く当てよう")
            ImasButton(title: "ゲームをはじめる", systemImage: "play.fill", role: .primary, size: .large) {
                AppAnalytics.tap("intro_don_home.start_game")
                showSetup = true
            }
            if authStatus != .authorized {
                ImasNotice(kind: .warning, message: "Apple Music が未認証です",
                           actionTitle: "Apple Music を許可する", actionSystemImage: "music.note") {
                    AppAnalytics.tap("intro_don_home.music_auth")
                    Task {
                        await MusicKitService.shared.requestAuthorization(includingMediaLibrary: true)
                        authStatus = MusicKitService.shared.authorizationStatus
                    }
                }
            }
            ImasSectionHeader(title: "対戦モード", tight: true)
            battleModeCard
        }
        .navigationTitle("イントロドン")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showSetup) {
            IntroGameSetupView()
        }
        .task {
            if MusicKitService.shared.authorizationStatus == .notDetermined {
                await MusicKitService.shared.requestAuthorization(includingMediaLibrary: true)
            }
            authStatus = MusicKitService.shared.authorizationStatus
        }
        .trackScreen("intro_don_home")
    }

    private var battleModeCard: some View {
        ImasFeatureCard(
            eyebrow: "BATTLE MODE",
            eyebrowPenlight: false,
            title: "友達と対戦したい方へ",
            subtitle: "姉妹アプリ「イントロドン」でローカル・オンライン対戦ができます",
            secondary: .init(title: "App Store で開く", systemImage: "arrow.up.right") {
                openURL(battleModeURL)
            }
        ) {
            Image(systemName: "person.2.fill")
                .font(.imasScaled(28))
                .foregroundStyle(DS.ink3)
        }
    }
}
