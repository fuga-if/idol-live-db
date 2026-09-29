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
    private var brandColor: String? { idol.brandId }

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
                    VStack(spacing: DS.sp3) {
                        ImasSectionHeader(title: "披露履歴", count: "\(history.count)", tight: true)
                        ImasListContainer {
                            ForEach(Array(history.enumerated()), id: \.offset) { idx, row in
                                if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                                historyRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, DS.sp5)
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

    private func historyRow(_ row: CastShowRow) -> some View {
        Button {
            Task {
                if let show = try? await AppContainer.shared.showReading.show(id: row.showId) {
                    navigate(.show(show))
                }
            }
        } label: {
            HStack(spacing: DS.sp3) {
                ImasLeadBar(seed: seed, brand: brandColor)
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text(row.eventName)
                        .font(.imasBody.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    Text([row.date, row.venue, row.showName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ・ "))
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ImasRowChevron()
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
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
