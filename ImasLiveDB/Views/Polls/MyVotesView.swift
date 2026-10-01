import SwiftUI

/// 自分が投票したお題の履歴。プロデュースタブ「投票」タイル → ここに飛ぶ。
/// ローカル (LocalPollVoteLog) に積んだ pollId/entityId からお題詳細と
/// 投票先 (曲/アイドル) 名を解決して並べる。サーバに my-votes API が無いため
/// クライアント駆動の履歴になっている (再インストールで消えうる)。
struct MyVotesView: View {
    @Environment(AppDatabase.self) private var database

    @State private var entries: [Entry] = []
    @State private var isLoading = true
    @State private var sheetDestination: DetailDestination?

    /// 1お題ぶんの表示行。
    private struct Entry: Identifiable {
        let poll: Poll
        /// 自分が選んだエンティティの表示用 (曲名 or アイドル名 + DetailDestination)。
        let myChoices: [Choice]
        var id: String { poll.id }
    }

    private struct Choice: Identifiable {
        let entityId: String
        let label: String
        let destination: DetailDestination?
        var id: String { entityId }
    }

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ImasLoadingState()
            } else if entries.isEmpty {
                ImasEmptyState(
                    systemImage: "chart.bar.doc.horizontal",
                    title: "まだ投票していません",
                    message: "みんなの投票でお題に投票すると、ここに履歴が残ります"
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        Section {
                            ForEach(entry.myChoices) { choice in
                                Button {
                                    sheetDestination = choice.destination
                                } label: {
                                    ImasRow(
                                        title: choice.label,
                                        leading: .icon("checkmark.circle.fill", tone: .positive),
                                        density: .compact,
                                        titleRole: .rowLabel
                                    )
                                }
                                .buttonStyle(.imasRow)
                                .disabled(choice.destination == nil)
                            }
                        } header: {
                            NavigationLink(value: PollRoute.detail(entry.poll.id)) {
                                // お題の題はユーザーが書く文なので区画見出しの既定 2 行で切らない。
                                ImasSectionHeader(entry.poll.title, count: entry.poll.statusLabel, style: .small,
                                                  titleLineLimit: Int.max)
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle("マイ投票")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest).environment(database)
        }
        .task { await load() }
        .trackScreen("my_votes")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let log = LocalPollVoteLog.shared.votes
        guard !log.isEmpty else { entries = []; return }

        // 必要な曲/アイドル ID を全部一括解決してから組み立てる (お題ごとに個別 API するより速い)。
        var allSongIds: Set<String> = []
        var allIdolIds: Set<String> = []
        var allUnitIds: Set<String> = []

        var pollDetails: [(Poll, Set<String>)] = []
        for (pollId, entityIds) in log {
            guard let detail = try? await AppContainer.shared.communityVoting.poll(id: pollId) else { continue }
            switch detail.poll.targetType {
            case .song:  allSongIds.formUnion(entityIds)
            case .idol:  allIdolIds.formUnion(entityIds)
            case .unit:  allUnitIds.formUnion(entityIds)
            }
            pollDetails.append((detail.poll, entityIds))
        }

        let songs = (try? await AppContainer.shared.songReading.songs(ids: Array(allSongIds))) ?? []
        let idols = (try? await AppContainer.shared.idolReading.idols(ids: Array(allIdolIds))) ?? []
        let allUnitsList = (try? await AppContainer.shared.unitReading.allUnits()) ?? []
        let songById = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        let idolById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0) })
        let unitById = Dictionary(uniqueKeysWithValues: allUnitsList.filter { allUnitIds.contains($0.id) }.map { ($0.id, $0) })

        let resolved: [Entry] = pollDetails.map { (poll, ids) in
            let choices: [Choice] = ids.sorted().map { entityId in
                switch poll.targetType {
                case .song:
                    if let s = songById[entityId] {
                        return Choice(entityId: entityId, label: s.title, destination: .song(s))
                    }
                    return Choice(entityId: entityId, label: "(削除済み)", destination: nil)
                case .idol:
                    if let i = idolById[entityId] {
                        return Choice(entityId: entityId, label: i.name, destination: .idol(i))
                    }
                    return Choice(entityId: entityId, label: "(削除済み)", destination: nil)
                case .unit:
                    if let u = unitById[entityId] {
                        return Choice(entityId: entityId, label: u.displayName, destination: .unit(u))
                    }
                    return Choice(entityId: entityId, label: "(削除済み)", destination: nil)
                }
            }
            return Entry(poll: poll, myChoices: choices)
        }
        // 開催中→終了 の順、内部は終了日新しい順。
        entries = resolved.sorted { a, b in
            if a.poll.isActive != b.poll.isActive { return a.poll.isActive }
            return a.poll.endsAt > b.poll.endsAt
        }
    }
}
