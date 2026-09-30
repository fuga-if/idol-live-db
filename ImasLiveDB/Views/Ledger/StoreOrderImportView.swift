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
    @State private var promptCopied = false
    /// 指示文を貼ってもらう AI を開いたとき、その名前。
    @State private var pasteHint: String?
    @Environment(\.openURL) private var openURL

    private var categories: [ExpenseCategoryInfo] { expenseCategories() }

    /// 記録する支出 (含める注文 × 費目ごと)。
    private var planned: [StoreExpenseDraft] {
        drafts.filter(\.include).flatMap { draft in
            storeOrderExpenses(order: draft.order, showId: draft.showId, eventId: draft.eventId)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if drafts.isEmpty {
                    aiSection
                    pasteSection
                } else {
                    ForEach($drafts) { $draft in
                        orderSection($draft)
                    }
                    Section {
                        Button("別の明細を貼り直す") { reset() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("明細の取り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
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

    // MARK: - AI にまとめてもらう

    /// 指示文を入れて AI を開く。メール・マイページのスクリーンショットなど形の揃わない材料は
    /// 利用者の AI に読ませ、アプリは決まった形の結果だけを読む (指示文と形はコアが持つ)。
    private var aiSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.sp4) {
                Text("メールやマイページのスクリーンショットから、AI に明細をまとめてもらえます。開いたら送信して、返ってきた結果をコピーして下に貼ってください。")
                    .font(.imasFootnote).foregroundStyle(DS.ink2)
                // 狭い画面では 3 つ並ばないので縦に落とす。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.sp3) { aiLinkButtons }
                    VStack(alignment: .leading, spacing: DS.sp2) { aiLinkButtons }
                }
                if let pasteHint {
                    Text("指示文をコピーしました。\(pasteHint)の入力欄に貼り付けて送信してください。")
                        .font(.imasCaption).foregroundStyle(DS.ink2)
                }
                Button {
                    UIPasteboard.general.string = storeOrderAiPrompt()
                    promptCopied = true
                } label: {
                    Label(promptCopied ? "指示文をコピーしました" : "ほかの AI 用に指示文をコピー",
                          systemImage: promptCopied ? "checkmark" : "doc.on.doc")
                }
                .font(.imasFootnote)
                // 行に複数のボタンがあるので、行全体のタップにしない。
                .buttonStyle(.borderless)
            }
            .padding(.vertical, DS.sp2)
        } header: {
            Text("AI にまとめてもらう")
        }
    }

    @ViewBuilder
    private var aiLinkButtons: some View {
        ForEach(storeOrderAiLinks(), id: \.label) { link in
            if let url = URL(string: link.url) {
                Button {
                    // 指示文を URL で渡せない AI には、先にクリップボードへ入れておく。
                    if link.needsPaste {
                        UIPasteboard.general.string = storeOrderAiPrompt()
                        pasteHint = link.label
                    }
                    openURL(url)
                } label: {
                    // 折り返すと ViewThatFits が縦に落とさないので 1 行に固定する。
                    Text(link.label)
                        .font(.imasFootnote.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityLabel("\(link.label)で開く")
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    // MARK: - 貼り付け

    private var pasteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.sp4) {
                Text("AI の結果、アソビストアのマイページの「購入履歴一覧」の表、または「購入完了のご連絡」メールの本文を貼り付けてください。")
                    .font(.imasFootnote).foregroundStyle(DS.ink2)
                PasteButton(payloadType: String.self) { strings in
                    let pasted = strings.joined(separator: "\n")
                    Task { @MainActor in text = pasted }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
            }
            .padding(.vertical, DS.sp2)

            TextEditor(text: $text)
                .font(.imasFootnote)
                .frame(minHeight: 160)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("または、ここに直接貼り付け")
                            .font(.imasFootnote).foregroundStyle(DS.ink3)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("貼り付け")
        } footer: {
            if !text.isEmpty {
                Text("注文を読み取れませんでした。AI の結果はコードブロックの中身ごと、メールは「【注文番号】」から「【お買上金額】」までが入るように貼ってください。")
                    .foregroundStyle(DS.danger)
            } else {
                Text("何通ぶんでも続けて貼れます。送料やポイントの値引きも含めて、実際に払った額で記録します。")
            }
        }
    }

    // MARK: - 注文

    private func orderSection(_ draft: Binding<DraftOrder>) -> some View {
        let order = draft.wrappedValue.order
        return Section {
            Toggle(isOn: draft.include) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatYen(amount: order.paidTotal))
                        .font(.imasBody.weight(.bold)).foregroundStyle(DS.ink).monospacedDigit()
                    if order.alreadyRecorded {
                        Text("この注文は記録済みです")
                            .font(.imasCaption).foregroundStyle(DS.danger)
                    }
                    if order.hasUnreadItems {
                        Text("読み取れなかった品目があります。額は合計に含めています")
                            .font(.imasCaption).foregroundStyle(DS.danger)
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
        } header: {
            Text("\(longDate(order.date))　\(order.store)")
        } footer: {
            if !order.orderNumber.isEmpty {
                Text("注文番号 \(order.orderNumber)")
            }
        }
    }

    private func itemRow(_ item: Binding<StoreOrderItem>) -> some View {
        let value = item.wrappedValue
        return HStack(alignment: .top, spacing: DS.sp3) {
            Button {
                item.included.wrappedValue.toggle()
            } label: {
                Image(systemName: value.included ? "checkmark.circle.fill" : "circle")
                    .font(.imasBody)
                    .foregroundStyle(value.included ? DS.ink : DS.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(value.included ? "記録から外す" : "記録に含める")

            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(value.name)
                    .font(.imasFootnote)
                    .foregroundStyle(value.included ? DS.ink : DS.ink3)
                    .lineLimit(3)
                HStack(spacing: DS.sp2) {
                    Menu {
                        ForEach(categories, id: \.key) { info in
                            Button(info.label) { item.category.wrappedValue = info.category }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(expenseCategoryLabel(category: value.category))
                            Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                        }
                        .font(.imasCaption.weight(.bold))
                        .padding(.horizontal, DS.sp3).padding(.vertical, 2)
                        .background(DS.fill, in: Capsule())
                        .foregroundStyle(DS.ink2)
                    }
                    .disabled(!value.included)
                    .accessibilityLabel("費目: \(expenseCategoryLabel(category: value.category))")
                    Spacer(minLength: 4)
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
        .padding(.vertical, DS.sp1)
    }

    private func adjustmentRow(_ order: StoreOrder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.horizontal, DS.sp5).padding(.vertical, DS.sp4)
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
                       // 記録済みの注文は最初から外しておく (2 度貼っても二重にならない)。
                       include: !order.alreadyRecorded,
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

