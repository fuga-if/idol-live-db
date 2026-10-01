import SwiftUI

struct TagDetailView: View {
    @Environment(AppDatabase.self) private var database
    let tagId: String
    let tagName: String

    @State private var detail: TagDetailResponse?
    @State private var isLoading = true
    @State private var showEditSheet = false
    @State private var showHistoryView = false
    @State private var showReportAlert = false
    @State private var reportSuccessAlert = false
    @State private var alertError: CommunityAPIError?
    @State private var songCache: [String: Song] = [:]
    @State private var nextDestination: DetailDestination?

    var body: some View {
        List {
            if isLoading {
                ImasInlineLoading()
                    .listRowBackground(Color.clear)
            } else if let detail {
                // タグ情報セクション
                Section {
                    ImasTagHeaderCard(
                        name: detail.tag.name,
                        colorHex: detail.tag.color?.rawValue,
                        categoryLabel: detail.tag.category.map { categoryLabel($0.rawValue) },
                        description: detail.tag.description
                    )
                    .listRowInsets(EdgeInsets(top: DS.Space.rowV, leading: DS.Space.screen,
                                              bottom: DS.Space.rowV, trailing: DS.Space.screen))
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                } footer: {
                    HStack {
                        Button("説明を編集") {
                            AppAnalytics.tap("tag_detail.edit")
                            showEditSheet = true
                        }
                        .buttonStyle(.imas(.plain, size: .small))
                        Spacer()
                        Button("編集履歴") {
                            AppAnalytics.tap("tag_detail.history")
                            showHistoryView = true
                        }
                        .buttonStyle(.imas(.plain, size: .small))
                    }
                }

                // 付いた曲セクション
                if !detail.songs.isEmpty {
                    // 「このタグが一番多く付いた曲」ランキング (票数降順)。順位バッジ + 票数。
                    ImasListSection(title: "「\(detail.tag.name)」な曲ランキング（\(detail.songs.count)曲）") {
                        ForEach(Array(detail.songs.enumerated()), id: \.element.id) { idx, entry in
                            songRankRow(entry: entry, rank: idx + 1)
                        }
                    }
                } else {
                    Section {
                        ImasEmptyState(systemImage: "tag", title: "まだこのタグが付いた曲はありません")
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .navigationTitle(tagName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        AppAnalytics.tap("tag_detail.report")
                        showReportAlert = true
                    } label: {
                        Label("不適切なタグを通報", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(DS.ink2)
                }
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: { Task { await loadDetail() } }) {
            if let detail { TagEditSheet(tag: detail.tag) }
        }
        .sheet(isPresented: $showHistoryView) {
            NavigationStack {
                TagHistoryView(tagId: tagId)
            }
        }
        .sheet(item: $nextDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .alert("タグを通報", isPresented: $showReportAlert) {
            Button("通報する", role: .destructive) {
                Task { await reportTag() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("不適切なコンテンツとして通報します")
        }
        .alert("通報しました", isPresented: $reportSuccessAlert) {
            Button("OK") {}
        } message: {
            Text("ご報告ありがとうございます。内容を確認します。")
        }
        .alert("通報エラー", isPresented: Binding(
            get: { alertError != nil },
            set: { if !$0 { alertError = nil } }
        )) {
            Button("OK") { alertError = nil }
        } message: {
            if let err = alertError {
                if case .rateLimited = err {
                    Text("本日通報上限です。明日また試してください。")
                } else {
                    Text(err.errorDescription ?? "エラーが発生しました")
                }
            }
        }
        .task { await loadDetail() }
        .trackScreen("tag_detail")
    }

    private func reportTag() async {
        do {
            try await AppContainer.shared.communityTagWriting.reportTag(id: tagId, reason: nil)
            reportSuccessAlert = true
        } catch let error as CommunityAPIError {
            alertError = error
        } catch {
            alertError = .transport(error)
        }
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await AppContainer.shared.communityTagReading.tag(id: tagId)
        if let songs = detail?.songs {
            // N+1 を避けてIN句で一括取得し、O(1)辞書化。表示順序は ForEach(detail.songs) が維持。
            let missingIds = songs.map(\.songId).filter { songCache[$0] == nil }
            if let fetched = try? await AppContainer.shared.songReading.songs(ids: missingIds) {
                for song in fetched {
                    songCache[song.id] = song
                }
            }
        }
    }

    private func categoryLabel(_ cat: String) -> String {
        TagCategoryOptions.song.first { $0.value == cat }?.label ?? cat
    }

    /// 曲ランキング 1 行。解決済みなら曲の行 (ジャケ+曲名+歌唱者) とタップで詳細へ、
    /// 未解決ならタイトルの代わりに ID を薄字で出す。
    @ViewBuilder
    private func songRankRow(entry: TagSongEntry, rank: Int) -> some View {
        if let song = songCache[entry.songId] {
            Button {
                nextDestination = .song(song)
            } label: {
                HStack(spacing: DS.Space.gapTight) {
                    ImasRankBadge(rank: rank)
                    ImasSongRow(song: song, subtitle: song.singerLabel, trailing: .custom(AnyView(
                        HStack(spacing: DS.Space.gap) {
                            ImasMetric(value: "\(entry.voteCount)", unit: "票", size: .medium)
                            ImasRowChevron()
                        }
                    )))
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: DS.Space.gapTight) {
                ImasRankBadge(rank: rank)
                ImasRow(title: entry.songId, trailing: .metric("\(entry.voteCount)", unit: "票"), emphasis: .dimmed)
            }
        }
    }
}
