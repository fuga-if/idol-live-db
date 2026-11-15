import os
import SwiftUI

/// シートに渡す検索文 (`.sheet(item:)` 用)。
struct NaturalSearchQuery: Identifiable {
    let id = UUID()
    let text: String
}

/// 文で探す。利用者の ChatGPT プランでモデルに DB を引かせ、当たったものをいつもの行で出す。
///
/// 文章の答えは出さない (会話にしない)。出すのはコアが「DB に実在する」と確かめた id の
/// 曲・アイドル・ライブだけで、行を押せばいつもの詳細へ進む。
struct NaturalSearchSheet: View {
    let initialQuery: String

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var phase: Phase = .idle
    @State private var path: [DetailDestination] = []
    @State private var runTask: Task<Void, Never>?
    @State private var playFailed = false

    private var session: ChatGPTPlanSession { .shared }

    private enum Phase {
        case idle
        case running(label: String)
        case done(Results)
        case failed(String)
    }

    /// 実体化まで済んだ結果。並びはコアが返した id の順。
    private struct Results {
        var interpretation: String
        var songs: [Song] = []
        var idols: [Idol] = []
        var events: [EventWithDate] = []
        var unreadable = false

        var isEmpty: Bool { songs.isEmpty && idols.isEmpty && events.isEmpty }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ImasPage {
                ImasSearchField(prompt: "文で探す", text: $text, onSubmit: run)
                content
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("文で探す")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .navigationDestination(for: DetailDestination.self) { dest in
                DetailContentView(destination: dest) { path.append($0) }
            }
        }
        .onAppear {
            guard text.isEmpty else { return }
            text = initialQuery
            if session.canUsePlan, naturalSearchAccepts(query: initialQuery) { run() }
        }
        .onDisappear { runTask?.cancel() }
        .trackScreen("natural_search")
    }

    // MARK: - 中身

    @ViewBuilder
    private var content: some View {
        if !session.canUsePlan {
            ImasEmptyState(
                systemImage: "text.magnifyingglass",
                title: "ChatGPT とつなぐと使えます",
                message: "マイページの「ChatGPT とつなぐ」から、ChatGPT Plus / Pro のアカウントでログインしてください"
            )
        } else {
            switch phase {
            case .idle:
                examples
            case .running(let label):
                VStack(spacing: DS.Space.gap) {
                    ImasInlineLoading(tint: DS.sys)
                    Text(label).imasText(.note)
                    ImasButton(title: "やめる", systemImage: "xmark", role: .secondary, size: .small) { cancel() }
                }
                .frame(maxWidth: .infinity)
            case .done(let results):
                resultSections(results)
            case .failed(let message):
                ImasEmptyState(.failed, title: "探せませんでした", message: message,
                               actionTitle: "もう一度", action: run)
            }
        }
    }

    private var examples: some View {
        ImasSection("たとえば", style: .small) {
            ImasCardList(naturalSearchExamples(), id: \.self) { example in
                Button {
                    AppAnalytics.tap("natural_search.example")
                    text = example
                    run()
                } label: {
                    ImasNavRow(title: example, systemImage: "text.magnifyingglass", iconTone: .neutral)
                }
                .buttonStyle(.imasRow)
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ results: Results) -> some View {
        if !results.interpretation.isEmpty {
            ImasNote(results.interpretation, systemImage: "text.magnifyingglass")
        }
        if results.isEmpty {
            ImasEmptyState(
                .noResults,
                title: results.unreadable ? "うまく探せませんでした" : "見つかりませんでした",
                message: "言い方を変えるか、文を短くして試してください"
            )
        }
        if !results.songs.isEmpty {
            // 当たった曲はそのまま続けて流せる (並びはコアが返した順)。
            ImasSection("曲", count: "\(results.songs.count)曲",
                        actionTitle: "続けて流す", actionSystemImage: "play.fill",
                        onAction: { playAll(results.songs) }) {
                if playFailed {
                    ImasNote("続けて流すには Apple Music の契約か Spotify の連携が要ります。", systemImage: "music.note")
                }
                ImasCardList(results.songs, id: \.id) { song in
                    Button { path.append(.song(song)) } label: {
                        ImasSongRow(song: song, trailing: .chevron)
                    }
                    .buttonStyle(.imasRow)
                }
            }
        }
        if !results.idols.isEmpty {
            ImasSection("アイドル", count: "\(results.idols.count)人") {
                ImasCardList(results.idols, id: \.id) { idol in
                    Button { path.append(.idol(idol)) } label: {
                        ImasIdolRow(idol: idol, brand: BrandColors.hex(for: idol.brandId), trailing: .chevron)
                    }
                    .buttonStyle(.imasRow)
                }
            }
        }
        if !results.events.isEmpty {
            ImasSection("ライブ", count: "\(results.events.count)件") {
                ImasCardList(results.events, id: \.id) { item in
                    Button { path.append(.event(item.event)) } label: {
                        ImasEventRow(event: item.event, date: item.firstDate, subtitle: item.dateRange,
                                     showsChevron: true)
                    }
                    .buttonStyle(.imasRow)
                }
            }
        }
    }

    // MARK: - 処理

    private func run() {
        let query = text
        guard session.canUsePlan, naturalSearchAccepts(query: query) else { return }
        runTask?.cancel()
        AppAnalytics.tap("natural_search.run")
        phase = .running(label: "探しています…")
        runTask = Task {
            do {
                let answer = try await NaturalSearchRunner.run(query: query) { label in
                    phase = .running(label: label)
                }
                let results = try await materialize(answer)
                if Task.isCancelled { return }
                phase = .done(results)
            } catch is CancellationError {
                // やめた・打ち直した。表示は呼んだ側が切り替えている。
            } catch {
                if Task.isCancelled { return }
                Logger.database.error("natural_search_failed: \(error.localizedDescription)")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func playAll(_ songs: [Song]) {
        AppAnalytics.tap("natural_search.play_all")
        Task { playFailed = !(await PlaylistPlayback.play(songs)) }
    }

    private func cancel() {
        runTask?.cancel()
        runTask = nil
        phase = .idle
    }

    /// id 列を行に出す実体にする。並びは id 列のまま。
    private func materialize(_ answer: NaturalSearchAnswer) async throws -> Results {
        let container = AppContainer.shared
        async let songs = container.songReading.songs(ids: answer.songIds)
        async let idols = container.idolReading.idols(ids: answer.idolIds)
        async let events = container.eventReading.eventsByIds(answer.eventIds)
        return Results(
            interpretation: answer.interpretation,
            songs: Self.ordered(try await songs, by: answer.songIds),
            idols: Self.ordered(try await idols, by: answer.idolIds),
            events: Self.ordered(try await events, by: answer.eventIds),
            unreadable: answer.unreadable
        )
    }

    /// 読み取りの口が返した並びに依らず、id 列の順に並べる。
    private static func ordered<T: Identifiable>(_ items: [T], by ids: [String]) -> [T] where T.ID == String {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }
}
