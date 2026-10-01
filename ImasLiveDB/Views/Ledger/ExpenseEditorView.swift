import SwiftUI

/// 支出 1 件の入力。追加も編集も同じ画面。
///
/// 入力の検査 (日付の形・金額の範囲) は**共有コア** (`validateExpense`) 一本。
/// ここは弾かれた理由を日本語に直して出すだけで、条件を Swift に書かない。
struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// nil なら新規作成。
    let expense: Expense?
    /// 保存する。書けたら true。書けなかったときは画面を閉じない (入力を捨てない)。
    let onSave: (Expense) async -> Bool

    @State private var date = Date()
    @State private var category: ExpenseCategory = .ticket
    @State private var amount: Int?
    @State private var note = ""
    @State private var showId: String?
    @State private var eventId: String?
    @State private var showOptions: [LedgerShowOption] = []
    @State private var showPicker = false
    @State private var isSaving = false

    private var categories: [ExpenseCategoryInfo] { expenseCategories() }
    private var dateText: String { Self.dateFormatter.string(from: date) }
    private var validation: ExpenseInputError? { validateExpense(date: dateText, amount: Int64(amount ?? 0)) }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    ImasFormAmount(label: "金額", imprint: "AMOUNT", systemImage: "yensign.circle", amount: $amount)
                }
                if let error = validation, amount != nil || error == .badDate {
                    Text(message(for: error)).imasText(.note, color: DS.danger)
                }

                ImasFormCard {
                    ImasFormField(label: "費目", imprint: "CATEGORY") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.gap), count: 3),
                                  spacing: DS.Space.gap) {
                            // 並びはコアが決める。画面ごとに並べ替えない。
                            ForEach(categories, id: \.key) { info in
                                ImasFilterChip(text: info.label, isSelected: info.category == category) {
                                    category = info.category
                                }
                            }
                        }
                    }
                }

                ImasFormCard {
                    ImasFormField(label: "日付", imprint: "DATE") {
                        DatePicker("日付", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                }

                ImasFormCard {
                    ImasFormField(label: "公演", imprint: "SHOW") {
                        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                            Button {
                                showPicker = true
                            } label: {
                                HStack {
                                    Text(linkedLabel).imasText(.value, color: showId == nil ? DS.ink2 : DS.ink)
                                    Spacer()
                                    ImasRowChevron()
                                }
                            }
                            if showId != nil {
                                Button {
                                    showId = nil
                                    eventId = nil
                                } label: {
                                    Text("公演との紐づけを外す").imasText(.note, color: DS.danger)
                                }
                            }
                        }
                    }
                }
                ImasNote("紐づけると「この遠征でいくら使ったか」が出ます。課金やグッズの通販は紐づけなくて構いません。")

                ImasFormCard {
                    ImasFormTextArea(label: "メモ", imprint: "NOTE", text: $note, prompt: "任意")
                }
            }
            .navigationTitle(expense == nil ? "支出を足す" : "支出を直す")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(
                canSave: validation == nil && !isSaving,
                onCancel: { dismiss() },
                onSave: { Task { await save() } }
            ))
            .sheet(isPresented: $showPicker) {
                LedgerShowPicker(options: showOptions) { option in
                    showId = option?.id
                    eventId = option?.eventId
                    // 日付を入れ直していなければ公演の日に合わせる (遠征費は当日が大半)。
                    if let option, expense == nil, amount == nil,
                       let parsed = Self.dateFormatter.date(from: option.date) {
                        date = parsed
                    }
                    showPicker = false
                }
            }
            .task { await loadOptions() }
        }
        .onAppear(perform: fill)
    }

    private var linkedLabel: String {
        guard let showId else { return "公演に紐づけない" }
        return showOptions.first { $0.id == showId }?.label ?? "紐づけた公演"
    }

    private func message(for error: ExpenseInputError) -> String {
        switch error {
        case .badDate: return "日付を選んでください"
        case .notPositive: return "金額を入れてください"
        case .tooLarge: return "桁が多すぎます (1 億円未満)"
        }
    }

    private func fill() {
        guard let expense else { return }
        if let parsed = Self.dateFormatter.date(from: expense.date) { date = parsed }
        category = expense.categoryValue
        amount = Int(expense.amount)
        note = expense.note ?? ""
        showId = expense.showId
        eventId = expense.eventId
    }

    private func loadOptions() async {
        showOptions = (try? await AppContainer.shared.ledgerReading.attendedShowOptions()) ?? []
    }

    private func save() async {
        guard validation == nil, !isSaving else { return }
        var saved = expense ?? Expense.make(
            date: dateText, category: category, amount: Int64(amount ?? 0),
            showId: showId, eventId: eventId, note: note
        )
        saved.date = dateText
        saved.category = expenseCategoryKey(category: category)
        saved.amount = Int64(amount ?? 0)
        saved.showId = showId
        saved.eventId = eventId
        saved.note = note.isEmpty ? nil : note
        isSaving = true
        let succeeded = await onSave(saved)
        isSaving = false
        if succeeded { dismiss() }
    }
}

/// 紐づける公演を選ぶ。参加を付けた公演だけが並ぶ。
struct LedgerShowPicker: View {
    @Environment(\.dismiss) private var dismiss
    let options: [LedgerShowOption]
    let onPick: (LedgerShowOption?) -> Void

    @State private var query = ""

    private var shown: [LedgerShowOption] {
        guard !query.isEmpty else { return options }
        // 照合の規則はコア一本 (画面で contains を書かない)。
        return options.filter { textSearchMatchRange(haystack: $0.label, needle: query) != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                ImasListSection {
                    ImasActionRow(title: "公演に紐づけない", systemImage: "xmark.circle") { onPick(nil) }
                    if options.isEmpty {
                        ImasEmptyState(
                            systemImage: "music.mic",
                            title: "参加した公演がありません",
                            message: "ライブに「参加」を付けると、ここに並びます。"
                        )
                    }
                    ForEach(shown) { option in
                        Button {
                            onPick(option)
                        } label: {
                            ImasRow(title: option.label, subtitle: option.date, titleRole: .rowLabel)
                        }
                        .buttonStyle(.imasRow)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .imasForm()
            .searchable(text: $query, prompt: "公演を探す")
            .navigationTitle("公演を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.read(onClose: { dismiss() }))
        }
    }
}
