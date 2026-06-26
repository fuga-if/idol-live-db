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
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let detail {
                // タグ情報セクション
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            if let hexColor = detail.tag.color {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hexColor: hexColor))
                                    .frame(width: 16, height: 16)
                                    .accessibilityLabel("タグカラー: \(hexColor.rawValue)")
                            }
                            Text(detail.tag.name)
                                .font(.imasTitle2.bold())
                            Spacer()
                            if let cat = detail.tag.category {
                                Text(categoryLabel(cat.rawValue))
                                    .font(.imasCaption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(categoryColor(cat.rawValue).opacity(0.2))
                                    .foregroundStyle(categoryColor(cat.rawValue))
                                    .clipShape(Capsule())
                                    .accessibilityLabel("カテゴリ: \(categoryLabel(cat.rawValue))")
                            }
                        }
                        if let desc = detail.tag.description, !desc.isEmpty {
                            Text(desc)
                                .font(.imasBody)
                                .foregroundStyle(DS.ink)
                        } else {
                            Text("説明なし")
                                .font(.imasBody)
                                .foregroundStyle(DS.ink3)
                                .italic()
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                } footer: {
                    HStack {
                        Button("説明を編集") {
                            AppAnalytics.tap("tag_detail.edit")
                            showEditSheet = true
                        }
                            .font(.imasCaption)
                        Spacer()
                        Button("編集履歴") {
                            AppAnalytics.tap("tag_detail.history")
                            showHistoryView = true
                        }
                            .font(.imasCaption)
                    }
                }

                // 付いた曲セクション
                if !detail.songs.isEmpty {
                    // 「このタグが一番多く付いた曲」ランキング (票数降順)。順位バッジ + 票数。
                    Section("「\(detail.tag.name)」な曲ランキング（\(detail.songs.count)曲）") {
                        ForEach(Array(detail.songs.enumerated()), id: \.element.id) { idx, entry in
                            if let song = songCache[entry.songId] {
                                Button { nextDestination = .song(song) } label: {
                                    HStack(spacing: DS.sp2) {
                                        TagRankBadge(rank: idx + 1)
                                        SongTitleRow(song: song, subtitle: song.singerLabel, showsChevron: false)
                                        Text("\(entry.voteCount)票")
                                            .font(.imasCaption.monospacedDigit())
                                            .foregroundStyle(DS.ink2)
                                        Image(systemName: "chevron.right")
                                            .font(.imasCaption)
                                            .foregroundStyle(DS.ink3)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack(spacing: DS.sp2) {
                                    TagRankBadge(rank: idx + 1)
                                    Text(entry.songId)
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                    Spacer()
                                    Text("\(entry.voteCount)票")
                                        .font(.imasCaption)
                                        .foregroundStyle(DS.ink2)
                                }
                            }
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                    }
                } else {
                    Section {
                        Text("まだこのタグが付いた曲はありません")
                            .foregroundStyle(DS.ink2)
                            .font(.imasCaption)
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
            try await CommunityAPI.shared.reportTag(id: tagId)
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
        detail = try? await CommunityAPI.shared.tag(id: tagId)
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
        switch cat {
        case "mood": return "ムード"
        case "scene": return "シーン"
        case "special": return "特別"
        case "free": return "フリー"
        default: return cat
        }
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "mood": return .purple
        case "scene": return .blue
        case "special": return .orange
        case "free": return .green
        default: return .secondary
        }
    }
}
