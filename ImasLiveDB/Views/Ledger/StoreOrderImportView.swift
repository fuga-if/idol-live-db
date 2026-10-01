import SwiftUI

/// 通販の購入明細 (アソビストアの「購入完了のご連絡」メール) を貼り付けて、
/// グッズ代・チケット代をまとめて帳簿に入れるシート。
///
/// 明細の読み方・費目の推し方・送料や値引きの寄せ方・記録済みの判定・紐づけ先の推し方は
/// **共有コア** (`domain/store_order.rs`) 一本。ここは貼り付けを受けて、
/// 返ってきた注文を見せて、選んだ分を書くだけ。
struct StoreOrderImportView: View {
    @Environment(\.dismiss) private var dismiss

    /// 帳簿にある支出のメモ (同じ注文を 2 度入れないための判定に渡す)。
    let existingNotes: [String]
    /// 書く。
    let onSave: ([Expense]) async -> Void

    @State private var text = ""
    @State private var drafts: [DraftOrder] = []
    @State private var showOptions: [LedgerShowOption] = []
    @State private var picking: DraftOrder.ID?
    @State private var saving = false

    private var categories: [ExpenseCategoryInfo] { expenseCategories() }

    /// 記録する支出 (含める注文 × 費目ごと)。
    private var planned: [StoreExpenseDraft] {
        drafts.filter(\.include).flatMap { draft in
            storeOrderExpenses(order: draft.order, showId: draft.showId, eventId: draft.eventId)
        }
    }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                if drafts.isEmpty {
                    guideCard
                    pasteCard
                } else {
                    ForEach($drafts) { $draft in
                        orderCard($draft)
                    }
                    Button("別の明細を貼り直す") { reset() }
                        .buttonStyle(.imas(.plain, size: .medium))
                }
            }
            .navigationTitle("アソビストアの明細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 件数を文言に出す (「記録」だけの DS 既定より、今いくつ記録されるかが分かる方が要る)。
                    Button(planned.isEmpty ? "記録" : "\(planned.count)件を記録") {
                        Task { await save() }
                    }
                    .disabled(planned.isEmpty || saving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !planned.isEmpty { totalBar }
            }
            .sheet(item: Binding(
                get: { picking.map(PickingTarget.init) },
                set: { picking = $0?.id }
            )) { target in
                LedgerShowPicker(options: showOptions) { option in
                    if let index = drafts.firstIndex(where: { $0.id == target.id }) {
                        drafts[index].showId = option?.id
                        drafts[index].eventId = option?.eventId
                    }
                    picking = nil
                }
            }
            .task { await loadOptions() }
            .onChange(of: text) { parse() }
        }
    }

    // MARK: - 案内

    /// 手順の案内。購入履歴一覧の表をコピーするのが一番手早い (1 画面で全注文が出る)。
    private var guideCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.header) {
            ImasFormCard {
                VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
                    Text("取り込み方").imasText(.sectionLabel)
                    ImasStepList(steps: [
                        .init(title: "アソビストアの購入履歴を開く") {
                            if let url = URL(string: asobiOrderHistoryUrl()) {
                                Link(destination: url) {
                                    Label("購入履歴を開く", systemImage: "arrow.up.right.square")
                                        .font(.imasFootnote.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                        },
                        .init(title: "「購入履歴一覧」の表を、見出しから最後の行まで選んでコピーする"),
                        .init(title: "下の「ペースト」を押す"),
                    ])
                }
            }
            ImasNote("「購入完了のご連絡」メールの本文を貼っても読めます。メールなら品名まで入ります。")
        }
    }

    // MARK: - 貼り付け

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.header) {
            ImasFormCard {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    PasteButton(payloadType: String.self) { strings in
                        let pasted = strings.joined(separator: "\n")
                        Task { @MainActor in text = pasted }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)

                    ImasFormTextArea(label: "貼り付け", imprint: "PASTE", text: $text, prompt: "または、ここに直接貼り付け")
                }
            }
            if !text.isEmpty {
                Text("注文を読み取れませんでした。購入履歴は表の見出しの行から、メールは「【注文番号】」から「【お買上金額】」までが入るように貼ってください。")
                    .imasText(.note, color: DS.danger)
            } else {
                ImasNote("送料やポイントの値引きも含めて、実際に払った額で記録します。チケット代は公演の参加から記録するので、チケットは最初から外してあります。")
            }
        }
    }

    // MARK: - 注文

    private func orderCard(_ draft: Binding<DraftOrder>) -> some View {
        let order = draft.wrappedValue.order
        return VStack(alignment: .leading, spacing: DS.Space.header) {
            Text("\(longDate(order.date))　\(order.store)").imasText(.sectionLabel)
            ImasFormCard {
                VStack(alignment: .leading, spacing: DS.Space.rowGap) {
                    Toggle(isOn: draft.include) {
                        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                            Text(formatYen(amount: order.paidTotal))
                                .font(.imasBody.weight(.bold)).foregroundStyle(DS.ink).monospacedDigit()
                            if order.alreadyRecorded {
                                Text("この注文は記録済みです").imasText(.note, color: DS.danger)
                            }
                            if order.hasUnreadItems {
                                Text("読み取れなかった品目があります。額は合計に含めています").imasText(.note, color: DS.danger)
                            }
                        }
                    }

                    if draft.wrappedValue.include {
                        ForEach(draft.order.items.indices, id: \.self) { index in
                            itemRow(draft.order.items[index])
                        }
                        if order.adjustment != 0 {
                            adjustmentRow(order)
                        }
                        showRow(draft.wrappedValue)
                    }
                }
            }
            if !order.orderNumber.isEmpty {
                ImasNote("注文番号 \(order.orderNumber)")
            }
        }
    }

    private func itemRow(_ item: Binding<StoreOrderItem>) -> some View {
        let value = item.wrappedValue
        return HStack(alignment: .top, spacing: DS.Space.gap) {
            Button {
                item.included.wrappedValue.toggle()
            } label: {
                ImasSelectionMark(isSelected: value.included)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(value.included ? "記録から外す" : "記録に含める")

            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text(value.name)
                    .font(.imasFootnote)
                    .foregroundStyle(value.included ? DS.ink : DS.ink3)
                    .lineLimit(3)
                HStack(spacing: DS.Space.gap) {
                    Menu {
                        ForEach(categories, id: \.key) { info in
                            Button(info.label) { item.category.wrappedValue = info.category }
                        }
                    } label: {
                        HStack(spacing: DS.Space.gapTight) {
                            Text(expenseCategoryLabel(category: value.category)).imasText(.value, color: DS.ink2)
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                                .foregroundStyle(DS.ink3)
                        }
                    }
                    .disabled(!value.included)
                    .accessibilityLabel("費目: \(expenseCategoryLabel(category: value.category))")
                    Spacer(minLength: DS.Space.gapTight)
                    Text(value.quantity > 1
                         ? "\(value.quantity)点 \(formatYen(amount: value.subtotal))"
                         : formatYen(amount: value.subtotal))
                        .font(.imasFootnote.weight(.semibold))
                        .foregroundStyle(value.included ? DS.ink : DS.ink3)
                        .monospacedDigit()
                        .strikethrough(!value.included)
                }
            }
        }
    }

    private func adjustmentRow(_ order: StoreOrder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                Text(order.hasUnreadItems ? "その他の品目・送料など"
                     : order.adjustment > 0 ? "送料・手数料" : "ポイント・値引き")
                    .font(.imasFootnote).foregroundStyle(DS.ink)
                Text("一番多い費目に含めて記録します")
                    .font(.imasCaption).foregroundStyle(DS.ink3)
            }
            Spacer()
            Text((order.adjustment > 0 ? "+" : "") + formatYen(amount: order.adjustment))
                .font(.imasFootnote.weight(.semibold)).foregroundStyle(DS.ink2).monospacedDigit()
        }
    }

    private func showRow(_ draft: DraftOrder) -> some View {
        Button {
            picking = draft.id
        } label: {
            HStack {
                Image(systemName: "music.mic").foregroundStyle(DS.ink3)
                Text(draft.showId.flatMap { id in showOptions.first { $0.id == id }?.label } ?? "公演に紐づけない")
                    .font(.imasFootnote)
                    .foregroundStyle(draft.showId == nil ? DS.ink2 : DS.ink)
                    .lineLimit(2)
                Spacer()
                ImasRowChevron()
            }
        }
    }

    private var totalBar: some View {
        HStack {
            Text("記録する額").font(.imasFootnote).foregroundStyle(DS.ink2)
            Spacer()
            Text(formatYen(amount: planned.reduce(0) { $0 + $1.amount }))
                .font(.imasBody.weight(.bold)).foregroundStyle(DS.ink).monospacedDigit()
        }
        .padding(.horizontal, DS.Space.screen).padding(.vertical, DS.Space.gap)
        .background(.bar)
    }

    // MARK: - 読み書き

    private func loadOptions() async {
        showOptions = (try? await AppContainer.shared.ledgerReading.attendedShowOptions()) ?? []
        // 読み込みより先に貼って直し始めていたら作り直さない (直した費目や除外が消える)。
        if drafts.isEmpty { parse() }
    }

    private func parse() {
        let candidates = showOptions.map {
            StoreShowCandidate(showId: $0.id, eventId: $0.eventId, eventName: $0.eventName, date: $0.date)
        }
        let orders = parseStoreOrders(text: text, today: Expense.today,
                                      candidates: candidates, existingNotes: existingNotes)
        drafts = orders.enumerated().map { index, order in
            DraftOrder(id: index, order: order,
                       // 記録済みの注文・チケットだけの注文は最初から外しておく (判断はコア)。
                       include: order.includeByDefault,
                       showId: order.suggestedShowId, eventId: order.suggestedEventId)
        }
    }

    private func reset() {
        text = ""
        drafts = []
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        let expenses = planned.map { draft in
            Expense.make(date: draft.date, category: draft.category, amount: draft.amount,
                         showId: draft.showId, eventId: draft.eventId, note: draft.note)
        }
        await onSave(expenses)
        saving = false
        dismiss()
    }

    private func longDate(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return date }
        return "\(parts[0])年\(parts[1])月\(parts[2])日"
    }
}

/// 画面で直せる注文 1 件 (含めるか・紐づけ先・品目ごとの費目と含めるか)。
private struct DraftOrder: Identifiable {
    let id: Int
    var order: StoreOrder
    var include: Bool
    var showId: String?
    var eventId: String?
}

private struct PickingTarget: Identifiable {
    let id: Int
}
