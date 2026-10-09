import SwiftUI
import UIKit

/// 設定の「Spotify」の行。状態を出して、案内の画面へ進む。
struct SpotifySettingsRow: View {
    private var spotify: SpotifyService { .shared }

    var body: some View {
        NavigationLink {
            SpotifySettingsView()
        } label: {
            ImasNavRow(
                title: spotify.isConnected ? (spotify.accountName ?? "Spotify") : "Spotify と連携",
                subtitle: spotify.isConnected
                    ? "Spotify でフル尺で鳴らし、書き出せます"
                    : "自分の Spotify アプリの Client ID で使います",
                systemImage: "music.note.list",
                value: spotify.isConnected ? "連携中" : nil,
                showsChevron: false
            )
        }
    }
}

/// Spotify 連携の案内と状態。手順・貼る値・注意の文言はコア (`spotifySetupGuide`) が持つ。
///
/// 連携していなければ、上から順にやれば終わるように「アプリを作る手順 → Client ID → ログイン」と並べる。
/// 手順の中で要る操作 (開発者サイトを開く・Redirect URI を写す) はその手順の真下に置く。
struct SpotifySettingsView: View {
    private var spotify: SpotifyService { .shared }
    private let guide = spotifySetupGuide(platform: .ios)

    @Environment(\.openURL) private var openURL
    @State private var clientIdInput = SpotifyService.shared.clientId ?? ""
    @State private var errorMessage: String?
    @State private var confirmSignOut = false

    private var check: SpotifyClientIdCheck { spotifyCheckClientId(input: clientIdInput) }

    var body: some View {
        List {
            if spotify.isConnected {
                connectedSections
            } else {
                setupSections
            }
        }
        .listStyle(.insetGrouped)
        .imasForm()
        .navigationTitle("Spotify")
        .navigationBarTitleDisplayMode(.inline)
        .imasErrorAlert("Spotify にログインできませんでした", message: $errorMessage)
        .task { await MusicKitService.shared.checkSubscriptionIfAuthorized() }
    }

    // MARK: - 連携中

    @ViewBuilder
    private var connectedSections: some View {
        ImasListSection("Spotify") {
            ImasRow(
                title: spotify.accountName ?? "Spotify アカウント",
                subtitle: "連携中",
                leading: .icon("checkmark.seal.fill", tone: .solid),
                titleRole: .rowLabel
            )
            if let clientId = spotify.clientId {
                ImasValueRow(key: "Client ID", value: Self.masked(clientId), monospaced: true)
            }
        }
        playbackSection
        ImasListSection("できること") {
            ImasPointList(points: [
                .init("music.note.list", "セトリの右上の音符から、公演のセトリを Spotify のプレイリストにできます。"),
                .init("text.badge.plus", "自分のプレイリストを Spotify に書き出せます。"),
                .init("play.fill", "曲を Spotify でフル尺で鳴らし、歌詞を追いかけられます (Spotify Premium が要ります)。"),
                .init("arrow.up.right.square", "曲の画面の「…」から、その曲を Spotify で開けます。"),
            ])
            .padding(.vertical, DS.Space.gapTight)
        }
        ImasListSection(footer: "Spotify 側の許可も外すときは、Spotify のアカウント設定の「アプリ」から外します。") {
            ImasActionRow(title: "連携を解除", systemImage: "rectangle.portrait.and.arrow.right", kind: .destructive) {
                confirmSignOut = true
            }
        }
        .confirmationDialog("Spotify との連携を解除しますか？", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("解除する", role: .destructive) { spotify.signOut() }
            Button("Client ID も消して解除する", role: .destructive) {
                spotify.forgetClientId()
                clientIdInput = ""
            }
            Button("やめる", role: .cancel) {}
        }
    }

    /// フル尺をどちらで鳴らすか。鳴らす許可の無いログイン (プレイリストだけの頃) なら、ログインし直しを促す。
    @ViewBuilder
    private var playbackSection: some View {
        if spotify.canControlPlayback {
            ImasListSection("フル再生", footer: "Spotify で鳴らすときは、音は Spotify アプリから出ます。鳴らす前に一度 Spotify アプリを開いておいてください。") {
                ImasMenuRow(title: "フル尺で鳴らす", systemImage: "play.fill",
                            options: fullPlaybackOptions().map(\.service),
                            selection: fullPlaybackSelection) { service in
                    fullPlaybackOptions().first { $0.service == service }?.label ?? ""
                }
            }
        } else {
            ImasListSection("フル再生") {
                ImasNotice(kind: .info, title: "Spotify で鳴らすには、もう一度ログインが要ります",
                           message: "曲を鳴らす許可を足すためです。Client ID はそのまま使います。")
                    .padding(.vertical, DS.Space.gapTight)
                if let clientId = spotify.clientId {
                    ImasActionRow(title: "もう一度ログイン", systemImage: "person.crop.circle.badge.checkmark",
                                  isLoading: spotify.isSigningIn) {
                        Task {
                            do { try await spotify.signIn(clientId: clientId) } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }

    private var fullPlaybackSelection: Binding<FullPlaybackService> {
        Binding(
            get: { MusicKitService.shared.fullPlaybackService ?? spotify.fullPlaybackPreference ?? .spotify },
            set: { spotify.fullPlaybackPreference = $0 }
        )
    }

    // MARK: - 連携の手順

    @ViewBuilder
    private var setupSections: some View {
        ImasListSection {
            Text(guide.lead)
                .imasText(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, DS.Space.gapTight)
        }
        ImasListSection("Spotify のアプリを作る") {
            ImasStepList(steps: steps)
                .padding(.vertical, DS.Space.gap)
            NavigationLink {
                SpotifyHowToView()
            } label: {
                ImasNavRow(title: "図つきの手順を見る", subtitle: "Spotify の画面のどこを押すかを絵で案内します",
                           systemImage: "photo.on.rectangle", showsChevron: false)
            }
        }
        ImasListSection("Client ID", footer: guide.notes.joined(separator: "\n")) {
            ImasTextFieldRow(title: "Client ID", text: $clientIdInput, prompt: "32 文字の英数字", error: check.problem)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            ImasButton(title: "Spotify にログイン", systemImage: "person.crop.circle.badge.checkmark",
                       role: .primary, size: .large, fillsWidth: true, isLoading: spotify.isSigningIn) {
                signIn()
            }
            .disabled(check.normalized == nil)
            .padding(.vertical, DS.Space.gapTight)
        }
        ImasListSection("うまくいかないとき") {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                ForEach(guide.troubleshooting, id: \.self) { ImasNote($0) }
            }
            .padding(.vertical, DS.Space.gapTight)
        }
    }

    private var steps: [ImasStepList.Step] {
        guide.steps.enumerated().map { index, step in
            if index == 0 {
                return .init(title: step.title, detail: step.detail) {
                    ImasButton(title: "開発者サイトを開く", systemImage: "safari", role: .secondary, size: .small) {
                        if let url = URL(string: guide.dashboardUrl) { openURL(url) }
                    }
                }
            }
            guard !step.values.isEmpty else { return .init(title: step.title, detail: step.detail) }
            return .init(title: step.title, detail: step.detail) {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    ForEach(step.values, id: \.label) { ImasCopyField(label: $0.label, value: $0.value) }
                }
            }
        }
    }

    private func signIn() {
        guard let clientId = check.normalized else { return }
        Task {
            do {
                try await spotify.signIn(clientId: clientId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 長い値は頭と尾だけ見せる (どのアプリの ID かが分かれば足りる)。
    private static func masked(_ id: String) -> String {
        guard id.count > 8 else { return id }
        return "\(id.prefix(4))…\(id.suffix(4))"
    }
}
