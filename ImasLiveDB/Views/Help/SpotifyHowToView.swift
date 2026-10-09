import SwiftUI

/// Spotify 連携の始め方を、Spotify の開発者サイトの画面を模した図つきで案内する画面。
/// ヘルプ →「Spotify と連携する」と、設定の「Spotify」から開く。
///
/// 手順の題と説明・注意はコア (`spotifySetupGuide`) が持つ (設定の画面と同じ文)。
/// 図の中の英語は Spotify の画面に出る表記そのまま (探すときに同じ字面で見つけられるように)。
struct SpotifyHowToView: View {
    private let guide = spotifySetupGuide(platform: .ios)
    @Environment(\.openURL) private var openURL

    var body: some View {
        ImasPage {
            header
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                ImasCard {
                    ImasStepList(steps: [
                        .init(title: step.title, detail: step.detail) { illustration(index) },
                    ], startIndex: index + 1)
                }
            }
            tips
            NavigationLink {
                SpotifySettingsView()
            } label: {
                Label("Spotify の設定を開く", systemImage: "music.note.list")
            }
            .buttonStyle(.imas(.primary, size: .large, fillsWidth: true))
        }
        .navigationTitle("Spotify と連携する")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("spotify_how_to")
    }

    // MARK: - 頭・注意

    private var header: some View {
        VStack(spacing: DS.Space.gap) {
            ImasIconTile(systemImage: "music.note.list", size: .s56, tone: .solid)
            Text("Spotify と連携する").imasText(.cardTitle)
            Text(guide.lead)
                .imasText(.note)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.gap)
    }

    private var tips: some View {
        ImasCard {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                ForEach(guide.notes, id: \.self) { Label($0, systemImage: "info.circle") }
                ForEach(guide.troubleshooting, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
            }
            .imasText(.note)
        }
    }

    // MARK: - 図

    /// その手順で貼る値を、写せる形で並べる。
    private func copyFields(_ step: SpotifyGuideStep) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            ForEach(step.values, id: \.label) { ImasCopyField(label: $0.label, value: $0.value) }
        }
    }

    @ViewBuilder
    private func illustration(_ index: Int) -> some View {
        switch index {
        case 0:
            ImasMockBrowser(url: "developer.spotify.com/dashboard") {
                Text("Dashboard").imasText(.rowTitle)
                ImasMockButton(title: "Log in", isTarget: true)
            }
            ImasButton(title: "開発者サイトを開く", systemImage: "safari", role: .secondary, size: .small) {
                if let url = URL(string: guide.dashboardUrl) { openURL(url) }
            }
        case 1:
            ImasMockBrowser(url: "developer.spotify.com/dashboard") {
                ImasMockButton(title: "Create app", isTarget: true)
                ImasMockField(label: "App name", value: "アイドルライブDB")
                ImasMockField(label: "App description", value: "アイマスのライブの記録")
            }
        case 2:
            ImasMockBrowser(url: "developer.spotify.com/dashboard/create") {
                ImasMockField(label: "Redirect URIs", value: guide.redirectUri, isTarget: true)
                ImasMockButton(title: "Add", isTarget: true)
            }
            copyFields(guide.steps[2])
        case 3:
            ImasMockBrowser(url: "developer.spotify.com/dashboard/create") {
                Text("Which API/SDKs are you planning to use?").imasText(.meta)
                ImasMockCheck(label: "Web API", isChecked: true)
                ImasMockCheck(label: "Web Playback SDK")
                ImasMockCheck(label: "Android")
                ImasMockCheck(label: "iOS", isChecked: true)
                ForEach(guide.steps[3].values, id: \.label) { ImasMockField(label: $0.label, value: $0.value, isTarget: true) }
                ImasMockButton(title: "Save", isTarget: true)
            }
            copyFields(guide.steps[3])
        default:
            ImasMockBrowser(url: "developer.spotify.com/dashboard/…/settings") {
                Text("Basic Information").imasText(.rowTitle)
                ImasMockField(label: "Client ID", value: "1a2b3c4d5e6f…", isTarget: true)
                ImasMockField(label: "Client secret", value: "View client secret", isUnused: true)
            }
        }
    }
}

#Preview {
    NavigationStack { SpotifyHowToView() }
}
