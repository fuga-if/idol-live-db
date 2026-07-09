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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                    HStack(spacing: DS.sp2) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(DS.success)
                                        Text(choice.label)
                                            .font(.imasSubhead.weight(.semibold))
                                            .foregroundStyle(DS.ink)
                                            .lineLimit(2)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                .disabled(choice.destination == nil)
                            }
                        } header: {
                            NavigationLink(value: PollRoute.detail(entry.poll.id)) {
                                HStack {
                                    Text(entry.poll.title).textCase(nil)
                                        .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                                    Spacer()
                                    Text(entry.poll.statusLabel).font(.imasCaption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
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

        var pollDetails: [(Poll, Set<String>)] = []
        for (pollId, entityIds) in log {
            guard let detail = try? await AppContainer.shared.communityVoting.poll(id: pollId) else { continue }
            switch detail.poll.targetType {
            case .song:  allSongIds.formUnion(entityIds)
            case .idol:  allIdolIds.formUnion(entityIds)
            }
            pollDetails.append((detail.poll, entityIds))
        }

        let songs = (try? await AppContainer.shared.songReading.songs(ids: Array(allSongIds))) ?? []
        let idols = (try? await AppContainer.shared.idolReading.idols(ids: Array(allIdolIds))) ?? []
        let songById = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        let idolById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0) })

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
