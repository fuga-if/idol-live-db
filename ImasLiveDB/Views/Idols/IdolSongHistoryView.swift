import os
import SwiftUI

struct IdolSongHistoryView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    let idol: Idol
    let song: Song
    let navigate: (DetailDestination) -> Void

    @State private var history: [CastShowRow] = []
    @State private var isLoading = true

    private var seed: String? { idol.color }
    private var brandColor: String? { BrandColors.hex(for: idol.brandId) }

    /// 披露履歴を年ごとの塊に (新しい年が先)。見出しと並びはコアの `group_indices_by_year_desc`
    /// (ライブ一覧 `FilteredShowsView` と同じ規則)。
    private var yearGroups: [(year: String, rows: [CastShowRow])] {
        groupIndicesByYearDesc(dates: history.map(\.date)).map { group in
            (year: group.label, rows: group.indices.map { history[Int($0)] })
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.sp6) {
                if isLoading {
                    ImasInlineLoading()
                } else if history.isEmpty {
                    ImasEmptyState(
                        systemImage: "music.microphone",
                        title: "披露履歴がありません",
                        message: "\(idol.name) による「\(song.title)」の披露記録はありません",
                        seed: seed,
                        brand: brandColor
                    )
                    .padding(.top, DS.sp6)
                } else {
                    VStack(alignment: .leading, spacing: DS.sp3) {
                        ImasSectionHeader(title: "披露履歴", count: "\(history.count)", tight: true)
                            .padding(.horizontal, DS.sp5)
                        ForEach(yearGroups, id: \.year) { group in
                            ImasDateHeader(big: group.year, imprint: "\(group.rows.count) 件")
                                .padding(.horizontal, DS.sp5)
                            VStack(spacing: DS.Space.gap) {
                                ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                                    historyRow(row)
                                }
                            }
                            .padding(.horizontal, DS.sp5)
                        }
                    }
                }
            }
            .padding(.top, DS.sp4)
            .padding(.bottom, DS.sp7)
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle("\(idol.name) × \(song.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHistory() }
        .trackScreen("idol_song_history")
    }

    /// 半券の行。日付は左の半券、右にライブ名・会場・公演名。
    private func historyRow(_ row: CastShowRow) -> some View {
        Button {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: row.showId) {
                    navigate(.show(show))
                }
            }
        } label: {
            ImasStubRow(
                date: ImasStubDate(row.date),
                title: row.eventName,
                subtitle: [row.venue, row.showName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                seed: seed,
                brand: brandColor,
                spokenDate: spokenDate(date: row.date)
            )
        }
        .buttonStyle(.plain)
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            history = try await AppContainer.shared.idolReading.idolSongHistory(idolId: idol.id, songId: song.id)
        } catch {
            Logger.database.error("load_failed idol_song_history: \(error.localizedDescription)")
            history = []
        }
    }
}
