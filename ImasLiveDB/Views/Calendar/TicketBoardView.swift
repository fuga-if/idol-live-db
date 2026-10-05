import SwiftUI

/// チケットの画面 (カレンダーから開く)。
///
/// カレンダーの帯でチケットの受付期間を見せると、同時に受け付けている件数が増えるほど
/// 月セル・週レーンが帯で埋まって見づらくなる (カレンダーは「その日の予定」を見る場所で、
/// 期間の広がりを見る場所ではない)。受付の期間そのものはここに一本化し、
/// カレンダーには期限日 (申込締切・当落発表・アーカイブ終了) だけを単日点で出す。
///
/// 席種だけ違う受付 (SP席/S席、ティーン割 等) は共有コアの `sale_groups` が 1 行にまとめてある
/// (`nameLabel` / `saleIds`)。
struct TicketBoardView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var board: TicketBoard?
    @State private var sheetDestination: DetailDestination?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ImasListSkeleton(rows: 6, thumb: .none)
                        .padding(.horizontal, DS.Space.screen)
                        .padding(.top, DS.Space.gap)
                } else if isEmpty {
                    VStack {
                        ImasEmptyState(
                            systemImage: "ticket",
                            title: "チケットなし",
                            message: "受付中・これから受付・結果待ち・見られるアーカイブのいずれもありません"
                        )
                        Spacer(minLength: 0)
                    }
                } else {
                    List {
                        if let board, !board.open.isEmpty {
                            section(title: "受付中", count: board.open.count) {
                                ForEach(Array(board.open.enumerated()), id: \.element.sale.id) { index, open in
                                    row(
                                        eventId: open.sale.eventId,
                                        title: open.sale.eventName,
                                        subtitle: [open.nameLabel, open.deadlineLabel].compactMap { $0 }.joined(separator: " ・ "),
                                        seed: open.brandColor,
                                        trailing: openTrailing(open),
                                        isFirst: index == 0
                                    )
                                }
                            }
                        }
                        if let board, !board.upcoming.isEmpty {
                            section(title: "これから受付", count: board.upcoming.count) {
                                ForEach(Array(board.upcoming.enumerated()), id: \.element.saleIds) { index, sale in
                                    row(
                                        eventId: sale.sale.eventId,
                                        title: sale.sale.eventName,
                                        subtitle: [sale.nameLabel, sale.dateLabel].joined(separator: " ・ "),
                                        seed: sale.brandColor,
                                        trailing: .badge(ImasBadge(text: sale.remainingLabel, kind: .neutral)),
                                        isFirst: index == 0
                                    )
                                }
                            }
                        }
                        if let board, !board.awaiting.isEmpty {
                            section(title: "結果待ち", count: board.awaiting.count) {
                                ForEach(Array(board.awaiting.enumerated()), id: \.element.saleIds) { index, sale in
                                    row(
                                        eventId: sale.sale.eventId,
                                        title: sale.sale.eventName,
                                        subtitle: [sale.nameLabel, sale.dateLabel].joined(separator: " ・ "),
                                        seed: sale.brandColor,
                                        trailing: awaitingTrailing(sale),
                                        isFirst: index == 0
                                    )
                                }
                            }
                        }
                        if let board, !board.archives.isEmpty {
                            section(title: "見られるアーカイブ", count: board.archives.count) {
                                ForEach(Array(board.archives.enumerated()), id: \.element.showIds) { index, archive in
                                    row(
                                        eventId: archive.eventId,
                                        title: archive.eventName,
                                        subtitle: ([archive.showLabels.joined(separator: "・")] + [archive.endsLabel])
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " ・ "),
                                        seed: archive.brandColor,
                                        trailing: .badge(ImasBadge(text: archive.remainingLabel, kind: .attention)),
                                        isFirst: index == 0
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(DS.bg)
                }
            }
            .background(DS.bg)
            .navigationTitle("チケット")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
            .sheet(item: $sheetDestination) { dest in
                DetailSheetView(destination: dest)
                    .environment(database)
            }
            .task { await load() }
            .trackScreen("ticket_board")
        }
    }

    private var isEmpty: Bool {
        guard let board else { return true }
        return board.open.isEmpty && board.upcoming.isEmpty && board.awaiting.isEmpty && board.archives.isEmpty
    }

    // MARK: - 行の組み立て

    @ViewBuilder
    private func section<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        ImasSection(title, count: "\(count)件", style: .small) {
            ImasCardList {
                content()
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, DS.Space.gap)
        .listRowInsets(EdgeInsets())
        .listRowBackground(DS.bg)
        .listRowSeparator(.hidden)
    }

    private func row(eventId: String, title: String, subtitle: String, seed: String?,
                     trailing: ImasRowTrailing, isFirst: Bool) -> some View {
        Button {
            Task {
                if let event = try? await AppContainer.shared.eventReading.event(id: eventId) {
                    sheetDestination = .event(event)
                }
            }
        } label: {
            ImasRow(
                title: title,
                subtitle: subtitle,
                leading: .bar(seed: seed),
                trailing: trailing,
                density: .compact,
                subtitleLineLimit: 2
            )
        }
        .buttonStyle(.imasRow)
        .environment(\.imasRowPosition, isFirst ? .first : .following)
    }

    /// 受付中の行の末尾。申し込み済みなら締切より記録を見せる (もう急ぐ必要がない)。
    /// 席種だけ違う受付をまとめた行は、その中のどれか 1 つに記録があれば代表させる。
    private func openTrailing(_ open: OpenTicketSale) -> ImasRowTrailing {
        if let application = firstApplication(saleIds: open.saleIds) {
            return .badge(ImasBadge(text: ticketApplicationLabel(kind: open.sale.kind, application: application), kind: .guest))
        }
        return open.remainingLabel.map { .badge(ImasBadge(text: $0, kind: .attention)) } ?? .none
    }

    /// 結果待ちの行の末尾。当落の記録があればそれを、無ければ発表日までの残りを見せる。
    private func awaitingTrailing(_ sale: TicketBoardSale) -> ImasRowTrailing {
        if let application = firstApplication(saleIds: sale.saleIds) {
            return .badge(ImasBadge(text: ticketApplicationLabel(kind: sale.sale.kind, application: application), kind: .guest))
        }
        return .badge(ImasBadge(text: sale.remainingLabel, kind: .attention))
    }

    /// まとめた受付 id 群のうち、最初に見つかった申込記録。
    private func firstApplication(saleIds: [String]) -> TicketApplication? {
        for id in saleIds {
            if let application = UserMarkService.shared.ticketApplication(saleId: id) {
                return application
            }
        }
        return nil
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        board = try? await AppContainer.shared.eventReading.ticketBoard()
    }
}
