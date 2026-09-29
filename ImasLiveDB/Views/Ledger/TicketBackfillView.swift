import SwiftUI

/// 取り込み候補の公演 1 つ (コアの候補 + 画面に出す公演名と日付)。
struct TicketBackfillRow: Identifiable {
    let item: TicketBackfillItem
    let option: LedgerShowOption
    var id: String { item.showId }
}

/// 過去の参加からチケット代を取り込む候補を集める。
///
/// 参加を付けた直後の確認 (`TicketExpensePrompt`) は、確認が入る前に付けた参加を
/// 拾わない。それを後からまとめて入れるための入口。候補にするかはコア
/// (`ticketExpenseBackfill`) で、直後の確認と同じ規則。
@MainActor
enum TicketBackfill {
    static func candidates(container: AppContainer = .shared) async throws -> [TicketBackfillRow] {
        let options = try await container.ledgerReading.attendedShowOptions()
        // 記録済みかは全件を 1 回読んで公演ごとに束ねる (公演ごとに引くと参加数ぶん往復する)。
        let recorded = Dictionary(grouping: try await container.ledgerReading.expenses(),
                                  by: { $0.showId ?? "" })
        var inputs: [TicketBackfillInput] = []
        for option in options {
            guard let type = UserMarkService.shared.attendance(entity: .show, id: option.id) else { continue }
            let tickets = (try? await container.showReading.tickets(showId: option.id)) ?? []
            if tickets.isEmpty { continue }
            inputs.append(TicketBackfillInput(
                showId: option.id,
                attendanceType: type.rawValue,
                tickets: tickets,
                existingExpenseCategories: (recorded[option.id] ?? []).map(\.category)
            ))
        }
        let byId = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
        return ticketExpenseBackfill(inputs: inputs).compactMap { item in
            byId[item.showId].map { TicketBackfillRow(item: item, option: $0) }
        }
    }

    /// 選んだ券を支出にする。日付は公演の日 (分からなければ今日)。
    static func expense(for row: TicketBackfillRow, ticket: ShowTicket) -> Expense {
        Expense.make(
            date: row.option.date.isEmpty ? Expense.today : row.option.date,
            category: .ticket,
            amount: ticket.price,
            showId: row.item.showId,
            eventId: row.option.eventId,
            note: ticketExpenseNote(ticket: ticket)
        )
    }
}

/// 過去の参加からチケット代をまとめて取り込むシート。
///
/// **券種が 1 つの公演だけ最初から選んでおく**。S席と立見のように複数あるときは
/// 選ばれるまで記録しない (先頭を黙って入れると差額が帳簿に乗る)。
struct TicketBackfillView: View {
    @Environment(\.dismiss) private var dismiss

    let rows: [TicketBackfillRow]
    /// 選んだ分を書く。
    let onSave: ([Expense]) async -> Void

    /// 公演 id → 選んだ券。無い公演は記録しない。
    @State private var selection: [String: ShowTicket] = [:]
    @State private var saving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                } footer: {
                    Text("券種が複数ある公演は、選んだものだけ記録します。金額はあとから明細で直せます。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("チケット代を取り込む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("\(selection.count)件を記録") {
                        saving = true
                        let expenses = rows.compactMap { row in
                            selection[row.id].map { TicketBackfill.expense(for: row, ticket: $0) }
                        }
                        Task {
                            await onSave(expenses)
                            dismiss()
                        }
                    }
                    .disabled(selection.isEmpty || saving)
                }
            }
            .onAppear {
                if selection.isEmpty {
                    for row in rows {
                        if let ticket = row.item.preselected { selection[row.id] = ticket }
                    }
                }
            }
        }
    }

    private func rowView(_ row: TicketBackfillRow) -> some View {
        let chosen = selection[row.id]
        return HStack(spacing: DS.sp4) {
            Button {
                if chosen != nil {
                    selection[row.id] = nil
                } else if let only = row.item.preselected {
                    selection[row.id] = only
                }
            } label: {
                Image(systemName: chosen != nil ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen != nil ? DS.ink : DS.ink3)
            }
            .buttonStyle(.plain)
            // 券種が複数あって未選択のときは、丸を押しても選べない (下のメニューで選ぶ)。
            .disabled(chosen == nil && row.item.preselected == nil)
            .accessibilityLabel(chosen != nil ? "記録しない" : "記録する")

            VStack(alignment: .leading, spacing: 2) {
                Text(row.option.label)
                    .font(.imasFootnote.weight(.semibold)).foregroundStyle(DS.ink).lineLimit(2)
                Text("\(row.option.date)・\(ticketKindLabel(kind: row.item.kind))")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }
            Spacer(minLength: 8)
            if row.item.tickets.count > 1 {
                Menu {
                    ForEach(row.item.tickets, id: \.id) { ticket in
                        Button("\(ticket.name)  \(formatYen(amount: ticket.price))") {
                            selection[row.id] = ticket
                        }
                    }
                    if chosen != nil {
                        Button("記録しない", role: .destructive) { selection[row.id] = nil }
                    }
                } label: {
                    Text(chosen.map(label) ?? "券種を選ぶ")
                        .font(.imasCaption.weight(.semibold))
                        .foregroundStyle(chosen != nil ? DS.ink : DS.ink2)
                        .multilineTextAlignment(.trailing)
                }
            } else if let ticket = row.item.tickets.first {
                Text(label(ticket))
                    .font(.imasCaption.weight(.semibold))
                    .foregroundStyle(chosen != nil ? DS.ink : DS.ink3)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, DS.sp2)
    }

    private func label(_ ticket: ShowTicket) -> String {
        "\(ticketExpenseNote(ticket: ticket))\n\(formatYen(amount: ticket.price))"
    }
}
