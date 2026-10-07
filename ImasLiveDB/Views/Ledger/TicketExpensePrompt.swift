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
/// 出すのは「その形態の券種がマスタにあり、まだその公演のその形態のチケット代を
/// 記録していない」ときだけ (現地のチケット代があっても、足した配信のぶんは聞く)。券が 1 種なら金額そのまま、複数なら選ばせる。
struct TicketExpensePromptModifier: ViewModifier {
    let ledgerReading: any LedgerReading
    let ledgerWriting: any LedgerWriting
    let showReading: any ShowReading

    /// いま出している確認。
    @State private var request: TicketExpensePromptRequest?
    /// 出番待ちの確認。**2days をまとめて付けると通知が続けて届く**ので、
    /// 1 つの枠に入れると後の公演で前の公演が上書きされ、片方しか聞けない。
    @State private var pending: [TicketExpensePromptRequest] = []

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .attendanceMarked)) { note in
                guard let showId = note.userInfo?[AttendanceMarkedKey.showId] as? String,
                      let raw = note.userInfo?[AttendanceMarkedKey.type] as? String,
                      let type = AttendanceType(rawValue: raw) else { return }
                // 載っているのはいま付けた 1 つの形態 (現地に配信を足したなら配信)。
                Task { await prepare(showId: showId, type: type) }
            }
            .sheet(item: $request, onDismiss: presentNext) { request in
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
            existingExpenses: existing.map(\.recorded)) else { return }

        let options = (try? await ledgerReading.attendedShowOptions()) ?? []
        let option = options.first { $0.id == showId }
        enqueue(TicketExpensePromptRequest(
            showId: showId,
            showLabel: option?.label ?? "この公演",
            eventId: option?.eventId,
            date: option?.date ?? "",
            kind: prompt.kind,
            tickets: prompt.tickets
        ))
    }

    /// 空いていればすぐ出し、出していれば待ち行列に積む。同じ公演の同じ形態は 1 度だけ聞く
    /// (付け外しを繰り返したときに同じ確認を重ねない)。待ちは公演日順に並べる
    /// (通知ごとの読み込みは並行に走るので、届いた順は日付順とは限らない)。
    private func enqueue(_ next: TicketExpensePromptRequest) {
        guard request?.id != next.id,
              !pending.contains(where: { $0.id == next.id }) else { return }
        guard request != nil else {
            request = next
            return
        }
        pending.append(next)
        pending.sort { ($0.date, $0.showId) < ($1.date, $1.showId) }
    }

    /// 閉じ終わってから次を出す (閉じている途中に差し替えると出ないことがある)。
    private func presentNext() {
        guard !pending.isEmpty else { return }
        request = pending.removeFirst()
    }

    private func save(request: TicketExpensePromptRequest, ticket: ShowTicket, amount: Int64) async {
        let note = ticketExpenseNote(ticket: ticket)
        let expense = Expense.make(
            date: request.date.isEmpty ? Expense.today : request.date,
            category: .ticket,
            amount: amount,
            showId: request.showId,
            eventId: request.eventId,
            note: note,
            ticketKind: request.kind
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
    @State private var amount: Int?

    private var ticket: ShowTicket? { selected ?? request.tickets.first }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    Text(request.showLabel).imasText(.sectionTitle)
                    Text("\(ticketKindLabel(kind: request.kind))で参加").imasText(.note)
                }

                ImasFormCard {
                    ForEach(request.tickets, id: \.id) { candidate in
                        ImasSelectableRow(
                            title: candidate.name,
                            subtitle: candidate.isEstimate ? "推定" : nil,
                            trailing: .custom(AnyView(
                                Text(formatYen(amount: candidate.price))
                                    .imasText(.value, color: DS.ink2)
                                    .monospacedDigit()
                            )),
                            isSelected: candidate.id == ticket?.id,
                            isSingle: true
                        ) {
                            selected = candidate
                            amount = Int(candidate.price)
                        }
                    }
                }

                ImasFormCard {
                    ImasFormAmount(label: "記録する金額", imprint: "AMOUNT", systemImage: "yensign.circle", amount: $amount)
                }
                ImasNote("手数料や先行の差額を含めたいときは、ここで直してください。")
            }
            .navigationTitle("チケット代を記録")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.prompt(
                canRecord: (amount ?? 0) > 0,
                onLater: { dismiss() },
                onRecord: {
                    if let ticket { onSave(ticket, Int64(amount ?? 0)) }
                    dismiss()
                }
            ))
            .onAppear {
                if amount == nil, let first = request.tickets.first {
                    // 候補が 1 つなら決め打ちでよい。複数あるときも先頭 (公式の表記順)
                    // を初期値にして、選び直せるようにする。
                    selected = request.tickets.count == 1 ? first : nil
                    amount = Int(first.price)
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
    var id: String { "\(showId)|\(ticketKindRaw(kind: kind))" }
}
