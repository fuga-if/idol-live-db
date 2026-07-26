import SwiftUI

/// 楽曲詳細の「披露履歴」タブ。総披露 / 初披露 / 最終披露 と、公演ごとの履歴一覧。
///
/// 親の状態は一切触らない。公演への遷移だけ `navigate` で返す。
struct SongHistoryTab: View {
    let seed: String?
    let vm: DetailSheetViewModel
    let navigate: (DetailDestination) -> Void

    var body: some View {
        VStack(spacing: DS.sp5) {
            if vm.history.isEmpty {
                ImasEmptyState(
                    systemImage: "mic",
                    title: "披露履歴はまだありません",
                    message: "この曲がライブで披露されると、ここに記録されます。",
                    seed: seed
                )
            } else {
                summaryTiles
                VStack(alignment: .leading, spacing: DS.sp3) {
                    ImasSectionHeader(title: "ライブ披露履歴", count: "\(vm.history.count)回", tight: true)
                    ImasListContainer {
                        ForEach(Array(vm.history.enumerated()), id: \.offset) { idx, row in
                            if idx > 0 { ImasRowDivider(inset: DS.sp4) }
                            historyRow(row)
                        }
                    }
                }
            }
        }
        .padding(.top, DS.sp4)
        .padding(.horizontal, DS.sp5)
    }

    /// 履歴は新しい順なので、初披露は末尾・最終披露は先頭。
    @ViewBuilder
    private var summaryTiles: some View {
        if let first = vm.history.last?.date, let last = vm.history.first?.date {
            HStack(spacing: DS.sp3) {
                ImasStatTile(systemImage: "mic.fill", value: "\(vm.history.count)", unit: "回", label: "総披露", seed: seed)
                ImasStatTile(systemImage: "calendar", value: ShortYearMonth.format(first), label: "初披露", seed: seed)
                ImasStatTile(systemImage: "calendar.badge.clock", value: ShortYearMonth.format(last), label: "最終披露", seed: seed)
            }
        }
    }

    private func historyRow(_ row: PerformanceHistoryRow) -> some View {
        Button {
            Task { if let show = await vm.resolveShow(id: row.showId) { navigate(.show(show)) } }
        } label: {
            HStack(spacing: 0) {
                ImasLeadBar(seed: seed)
                    .frame(height: 34)
                    .padding(.trailing, DS.sp4)
                VStack(alignment: .leading, spacing: DS.sp1) {
                    Text(eventDisplayName(row.eventName)).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(1)
                    Text([row.showName, row.date].joined(separator: " ・ "))
                        .font(.imasCaption).foregroundStyle(DS.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                ImasRowChevron()
            }
            .padding(.horizontal, DS.sp4).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
