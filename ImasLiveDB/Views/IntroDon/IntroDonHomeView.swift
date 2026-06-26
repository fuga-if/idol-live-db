import SwiftUI
import MusicKit

struct IntroDonHomeView: View {
    @Environment(AppDatabase.self) private var database
    @State private var showSetup = false
    @State private var authStatus: MusicAuthorization.Status = MusicKitService.shared.authorizationStatus

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                Spacer().frame(height: 28)

                VStack(spacing: 12) {
                    IDActionButton(
                        title: "ゲームをはじめる",
                        icon: "play.fill",
                        style: .primary
                    ) {
                        AppAnalytics.tap("intro_don_home.start_game")
                        showSetup = true
                    }
                    .padding(.horizontal, 20)

                    if authStatus != .authorized {
                        authWarningCard
                            .padding(.horizontal, 20)
                    }
                }

                Spacer().frame(height: 28)

                IDSectionLabel(text: "対戦モード")
                    .padding(.horizontal, 20)

                Spacer().frame(height: 12)

                battleModeCard
                    .padding(.horizontal, 20)

                Spacer().frame(height: 32)
            }
        }
        .background(ID.menuBg.ignoresSafeArea())
        .navigationTitle("イントロドン")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showSetup) {
            IntroGameSetupView()
        }
        .task {
            if MusicKitService.shared.authorizationStatus == .notDetermined {
                await MusicKitService.shared.requestAuthorization()
            }
            authStatus = MusicKitService.shared.authorizationStatus
        }
        .trackScreen("intro_don_home")
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    IDCorner(radius: 16)
                        .fill(ID.menuCardDark)
                        .frame(width: 64, height: 64)
                    Image(systemName: "music.note.list")
                        .font(.imasScaled( 28, weight: .semibold))
                        .foregroundColor(ID.menuCardDarkText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("INTRO DON")
                        .font(ID.font(11, weight: .bold))
                        .tracking(2)
                        .foregroundColor(ID.menuTextSecondary)
                    Text("イントロドン")
                        .font(ID.font(28, weight: .black))
                        .tracking(-0.5)
                        .foregroundColor(ID.menuText)
                }
            }

            Text("Apple Music のイントロを聴いて\n曲名をいち早く当てよう")
                .font(.imasScaled( 14))
                .foregroundColor(ID.menuTextSecondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(ID.menuCardSubtle)
        .clipShape(IDCorner())
    }

    private var authWarningCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(ID.accentGold)
                Text("Apple Music が未認証です")
                    .font(ID.font(14, weight: .semibold))
                    .foregroundColor(ID.menuText)
                Spacer()
            }

            IDActionButton(title: "Apple Music を許可する", icon: "music.note", style: .secondary) {
                AppAnalytics.tap("intro_don_home.music_auth")
                Task {
                    await MusicKitService.shared.requestAuthorization()
                    authStatus = MusicKitService.shared.authorizationStatus
                }
            }
        }
        .padding(16)
        .background(ID.accentGold.opacity(0.08))
        .clipShape(IDCorner(radius: 16))
        .overlay(
            IDCorner(radius: 16)
                .stroke(ID.accentGold.opacity(0.25), lineWidth: 1)
        )
    }

    private var battleModeCard: some View {
        let searchUrl = URL(string: "https://apps.apple.com/jp/app/intro-%E3%82%A4%E3%83%B3%E3%83%88%E3%83%AD%E3%82%AF%E3%82%A4%E3%82%BA/id6760829877")!

        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BATTLE MODE")
                        .font(ID.font(11, weight: .bold))
                        .tracking(2)
                        .foregroundColor(ID.menuTextSecondary)
                    Text("友達と対戦したい方へ")
                        .font(ID.font(18, weight: .black))
                        .tracking(-0.3)
                        .foregroundColor(ID.menuText)
                    Text("姉妹アプリ「イントロドン」でローカル\n・オンライン対戦ができます")
                        .font(.imasScaled( 12))
                        .foregroundColor(ID.menuTextSecondary)
                        .lineSpacing(2)
                        .padding(.top, 2)
                }
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.imasScaled( 28))
                    .foregroundColor(ID.menuTextMuted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()
                .background(ID.menuDivider)
                .padding(.horizontal, 16)

            Link(destination: searchUrl) {
                HStack(spacing: 8) {
                    Text("App Store で開く")
                        .font(ID.font(14, weight: .semibold))
                        .foregroundColor(ID.menuTextSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(.imasScaled( 12, weight: .semibold))
                        .foregroundColor(ID.menuTextMuted)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(ID.menuCardSubtle)
        .clipShape(IDCorner())
    }
}
