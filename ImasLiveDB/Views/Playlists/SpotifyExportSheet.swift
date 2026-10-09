import SwiftUI

/// 曲の並びを Spotify のプレイリストに書き出すシート (セトリ・自分のプレイリスト)。
///
/// 連携していればすぐ始める。していなければ、連携の画面へ進む入口を出す (戻ってきたら始められる)。
/// 見つからなかった曲は必ず名前で出す (黙って抜けると、欠けたプレイリストのまま気付かない)。
struct SpotifyExportSheet: View {
    struct Entry: Identifiable, Hashable {
        let songId: String
        let title: String
        let position: Int
        var id: Int { position }
    }

    /// Spotify 側のプレイリスト名。
    let name: String
    let entries: [Entry]

    init(name: String, songs: [(songId: String, title: String)]) {
        self.name = name
        entries = songs.enumerated().map { Entry(songId: $1.songId, title: $1.title, position: $0) }
    }

    private enum Phase {
        case idle
        case running(done: Int, total: Int)
        case finished(SpotifyService.ExportResult)
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phase: Phase = .idle
    @State private var task: Task<Void, Never>?
    private var spotify: SpotifyService { .shared }

    var body: some View {
        NavigationStack {
            List { content }
                .listStyle(.insetGrouped)
                .imasForm()
                .navigationTitle("Spotify に書き出す")
                .navigationBarTitleDisplayMode(.inline)
                .imasSheetToolbar(.read(onClose: close))
        }
        .task {
            if spotify.isConnected { start() }
        }
        .sensoryFeedback(.success, trigger: isFinished)
    }

    private var isFinished: Bool {
        if case .finished = phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            if spotify.isConnected {
                ImasListSection(footer: "非公開のプレイリストとして作ります。") {
                    ImasValueRow(key: "プレイリスト名", value: name)
                    ImasValueRow(key: "曲", value: "\(entries.count) 曲", monospaced: true)
                    startButton
                }
            } else {
                ImasListSection(footer: "自分の Spotify アカウントで作った「アプリ」の Client ID を使います。最初の 1 回だけ設定が要ります。") {
                    NavigationLink {
                        SpotifySettingsView()
                    } label: {
                        ImasNavRow(title: "Spotify と連携する", systemImage: "music.note.list", showsChevron: false)
                    }
                }
            }
        case let .running(done, total):
            ImasListSection("Spotify で曲を探しています") {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    ImasProgressBar(fraction: total == 0 ? 0 : Double(done) / Double(total))
                    Text("\(done) / \(total) 曲").font(ImasNumeralSize.small.font).foregroundStyle(DS.ink2)
                }
                .padding(.vertical, DS.Space.gap)
                .accessibilityElement(children: .combine)
            }
        case let .finished(result):
            finishedSections(result)
        case let .failed(message):
            ImasListSection {
                ImasNotice(kind: .error, title: "書き出せませんでした", message: message)
                    .padding(.vertical, DS.Space.gapTight)
                if spotify.isConnected {
                    startButton
                } else {
                    NavigationLink {
                        SpotifySettingsView()
                    } label: {
                        ImasNavRow(title: "Spotify にログインし直す", systemImage: "music.note.list", showsChevron: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func finishedSections(_ result: SpotifyService.ExportResult) -> some View {
        ImasListSection {
            ImasNotice(kind: result.added > 0 ? .success : .warning,
                       message: spotifyExportSummary(added: UInt32(result.added), missing: UInt32(result.missingSongIds.count)))
                .padding(.vertical, DS.Space.gapTight)
            if let url = result.playlistURL {
                ImasButton(title: "Spotify で開く", systemImage: "arrow.up.right.square",
                           role: .primary, size: .large, fillsWidth: true) {
                    openURL(url)
                }
                .padding(.vertical, DS.Space.gapTight)
            }
        }
        let missing = missingEntries(result)
        if !missing.isEmpty {
            ImasListSection("見つからなかった曲", count: "\(missing.count)",
                            footer: "Spotify で配信されていないか、名義が違って見分けられなかった曲です。") {
                ForEach(missing) { entry in
                    Text(entry.title).imasText(.rowLabel)
                }
            }
        }
    }

    private var startButton: some View {
        ImasButton(title: "Spotify に書き出す", systemImage: "square.and.arrow.up",
                   role: .primary, size: .large, fillsWidth: true) { start() }
            .padding(.vertical, DS.Space.gapTight)
    }

    /// 見つからなかった曲を元の順で。同じ曲が 2 回あっても 1 回だけ出す。
    private func missingEntries(_ result: SpotifyService.ExportResult) -> [Entry] {
        let missing = Set(result.missingSongIds)
        var seen = Set<String>()
        return entries.filter { missing.contains($0.songId) && seen.insert($0.songId).inserted }
    }

    private func start() {
        task?.cancel()
        let songIds = entries.map(\.songId)
        phase = .running(done: 0, total: songIds.count)
        task = Task {
            do {
                let result = try await spotify.exportPlaylist(name: name, songIds: songIds) { done, total in
                    phase = .running(done: done, total: total)
                }
                phase = .finished(result)
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func close() {
        task?.cancel()
        dismiss()
    }
}
