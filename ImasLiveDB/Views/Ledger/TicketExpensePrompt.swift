import os
import SwiftUI

/// 参加が付いたことを知らせる通知。
///
/// 参加登録の入口は複数ある (行のスワイプ / 公演の参加シート / セトリ画面) ので、
/// **付いたことだけを 1 本の通知に集めて**、出すかどうかは受け手 (アプリのルート) が決める。
/// 入口ごとにダイアログを書くと、出し分けの規則がすぐ二重になる。
///
/// 通知にしたのは、`@Observable` のシングルトンを `.task(id:)` の鍵にすると
/// 詳細画面での変更でルートの body が評価されず、シートが出ないことがあったため
/// (既存の `.openSettings` と同じ作法に寄せた)。
extension Notification.Name {
    static let attendanceMarked = Notification.Name("ImasAttendanceMarked")
}

/// 通知に載せる情報のキー。
enum AttendanceMarkedKey {
    static let showId = "showId"
    static let type = "type"
}

/// 参加を付けた直後の確認シート。**必ず確認してから**帳簿に書く
/// (勝手に金額が増えると、自分で付けた覚えのない行が帳簿に混ざる)。
///
/// 出すのは「その形態の券種がマスタにあり、まだその公演のチケット代を
/// 記録していない」ときだけ。券が 1 種なら金額そのまま、複数なら選ばせる。
struct TicketExpensePromptModifier: ViewModifier {
    let ledgerReading: any LedgerReading
    let ledgerWriting: any LedgerWriting
    let showReading: any ShowReading

    @State private var request: TicketExpensePromptRequest?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .attendanceMarked)) { note in
                guard let showId = note.userInfo?[AttendanceMarkedKey.showId] as? String,
                      let raw = note.userInfo?[AttendanceMarkedKey.type] as? String,
                      let type = AttendanceType(rawValue: raw) else { return }
                Task { await prepare(showId: showId, type: type) }
            }
            .sheet(item: $request) { request in
                TicketExpenseSheet(request: request) { ticket, amount in
                    Task { await save(request: request, ticket: ticket, amount: amount) }
                }
            }
    }

    /// 出す条件を調べる。**出さない理由が 1 つでもあれば黙って終わる**
    /// (参加を付けただけなのに毎回シートが出ると、付ける作業が止まる)。
    /// 聞くか・どの券を並べるかはコア (`ticket_expense_prompt`)。
    private func prepare(showId: String, type: AttendanceType) async {
        let tickets = (try? await showReading.tickets(showId: showId)) ?? []
        // 記録済みかを読めなかったときは聞かない (付けてあるか分からないまま聞くと二重計上になりうる)。
        let existing: [Expense]
        do {
            existing = try await ledgerReading.expenses(showId: showId)
        } catch {
            Logger.database.error("ticket_prompt_read_failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let prompt = ticketExpensePrompt(
            showTickets: tickets, attendanceType: type.rawValue,
            existingExpenseCategories: existing.map(\.category)) else { return }

        let options = (try? await ledgerReading.attendedShowOptions()) ?? []
        let option = options.first { $0.id == showId }
        request = TicketExpensePromptRequest(
            showId: showId,
            showLabel: option?.label ?? "この公演",
            eventId: option?.eventId,
            date: option?.date ?? "",
            kind: prompt.kind,
            tickets: prompt.tickets
        )
    }

    private func save(request: TicketExpensePromptRequest, ticket: ShowTicket, amount: Int64) async {
        let note = ticketExpenseNote(ticket: ticket)
        let expense = Expense.make(
            date: request.date.isEmpty ? Expense.today : request.date,
            category: .ticket,
            amount: amount,
            showId: request.showId,
            eventId: request.eventId,
            note: note
        )
        do {
            try await ledgerWriting.save(expense)
        } catch {
            LocalWriteFailure.report(error, action: "チケット代の記録")
        }
    }
}

extension View {
    /// アプリのどこで参加を付けても、確認シートがここから出る。
    func ticketExpensePrompt(container: AppContainer = .shared) -> some View {
        modifier(TicketExpensePromptModifier(
            ledgerReading: container.ledgerReading,
            ledgerWriting: container.ledgerWriting,
            showReading: container.showReading))
    }
}

/// 確認シートの中身。金額はその場で直せる (手数料や先行の差額を含めたい人がいる)。
private struct TicketExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: TicketExpensePromptRequest
    let onSave: (ShowTicket, Int64) -> Void

    @State private var selected: ShowTicket?
    @State private var amountText = ""

    private var ticket: ShowTicket? { selected ?? request.tickets.first }
    private var amount: Int64 { Int64(amountText.filter(\.isNumber)) ?? 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(request.showLabel)
                        .font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                    Text("\(ticketKindLabel(kind: request.kind))で参加")
                        .font(.imasCaption).foregroundStyle(DS.ink2)
                }

                Section("券種") {
                    ForEach(request.tickets, id: \.id) { candidate in
                        Button {
                            selected = candidate
                            amountText = String(candidate.price)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name).foregroundStyle(DS.ink)
                                    if candidate.isEstimate {
                                        Text("推定").font(.imasCaption).foregroundStyle(DS.ink3)
                                    }
                                }
                                Spacer()
                                Text(formatYen(amount: candidate.price))
                                    .foregroundStyle(DS.ink2).monospacedDigit()
                                if candidate.id == ticket?.id {
                                    Image(systemName: "checkmark").foregroundStyle(DS.ink2)
                                }
                            }
                            // 行全体を的にする。文字の上しか押せないと、選んだつもりで
                            // 初期値のまま記録される (実機で踏んだ)。
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    HStack {
                        Text("¥").foregroundStyle(DS.ink2)
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .monospacedDigit()
                    }
                } header: {
                    Text("記録する金額")
                } footer: {
                    Text("手数料や先行の差額を含めたいときは、ここで直してください。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("チケット代を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("あとで") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("記録する") {
                        if let ticket { onSave(ticket, amount) }
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
            .onAppear {
                if amountText.isEmpty, let first = request.tickets.first {
                    // 候補が 1 つなら決め打ちでよい。複数あるときも先頭 (公式の表記順)
                    // を初期値にして、選び直せるようにする。
                    selected = request.tickets.count == 1 ? first : nil
                    amountText = String(first.price)
                }
            }
        }
    }
}

/// シートに渡す内容 (modifier の private 型をそのまま使えないので別に持つ)。
struct TicketExpensePromptRequest: Identifiable {
    let showId: String
    let showLabel: String
    let eventId: String?
    let date: String
    let kind: TicketKind
    let tickets: [ShowTicket]
    var id: String { showId }
}
