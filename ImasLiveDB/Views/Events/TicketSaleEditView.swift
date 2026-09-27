import os
import SwiftUI

/// チケット受付 (`TicketSale`) の追加 / 編集 / 削除。ログイン済みユーザーが利用可能。
///
/// 日時の読み方・検査・その文言はすべて共有コア (`normalizeTicketSaleMoment` /
/// `validateTicketSaleDraft` / `ticketSaleIssueMessage`) に任せる。Swift 側では
/// 日付の比較も規則も書かない。段階・並びは表示専用の `TicketSale` (コアの射影) が決め切って
/// 返すので、このフォームは入力の受け皿と検査結果の表示だけを担う。
struct TicketSaleEditView: View {
    private let eventId: String
    /// この受付の対象になりうる公演。`showIds` 検査・対象公演選択に使う。
    private let eventShows: [Show]
    /// 既存編集時の元の受付 (削除ボタン・recordName の元)。新規作成時は nil。
    private let original: TicketSale?

    @Environment(\.dismiss) private var dismiss

    @State private var kind: TicketSaleKind
    @State private var name: String
    @State private var selectedShowIds: Set<String>
    @State private var startsAt: String
    @State private var endsAt: String
    @State private var resultAt: String
    @State private var url: String
    @State private var note: String
    @State private var sourceUrl: String
    @State private var sortOrder: Int

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var requestSent = false
    @State private var showDeleteConfirm = false

    private static let kinds: [TicketSaleKind] = [.lottery, .firstCome, .resale, .sameDay]

    /// 既存編集用。
    init(ticketSale: TicketSale, eventShows: [Show]) {
        self.eventId = ticketSale.eventId
        self.eventShows = eventShows
        self.original = ticketSale
        _kind = State(initialValue: ticketSale.kind)
        _name = State(initialValue: ticketSale.name)
        _selectedShowIds = State(initialValue: Set(ticketSale.showIds))
        _startsAt = State(initialValue: ticketSale.startsAt ?? "")
        _endsAt = State(initialValue: ticketSale.endsAt ?? "")
        _resultAt = State(initialValue: ticketSale.resultAt ?? "")
        _url = State(initialValue: ticketSale.url ?? "")
        _note = State(initialValue: ticketSale.note ?? "")
        _sourceUrl = State(initialValue: ticketSale.sourceUrl)
        _sortOrder = State(initialValue: Int(ticketSale.sortOrder))
    }

    /// 新規作成用。
    init(newSaleEventId: String, eventShows: [Show], suggestedSortOrder: Int = 0) {
        self.eventId = newSaleEventId
        self.eventShows = eventShows
        self.original = nil
        _kind = State(initialValue: .lottery)
        _name = State(initialValue: "")
        _selectedShowIds = State(initialValue: [])
        _startsAt = State(initialValue: "")
        _endsAt = State(initialValue: "")
        _resultAt = State(initialValue: "")
        _url = State(initialValue: "")
        _note = State(initialValue: "")
        _sourceUrl = State(initialValue: "")
        _sortOrder = State(initialValue: suggestedSortOrder)
    }

    private var isCreate: Bool { original == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    if let original {
                        LabeledContent("ID") { Text(original.id).foregroundStyle(DS.ink2) }
                    }
                    TextField("受付名 (例: 最速先行抽選)", text: $name)
                    Picker("種別", selection: $kind) {
                        ForEach(Self.kinds, id: \.self) { k in
                            Text(kindLabel(k)).tag(k)
                        }
                    }
                    Stepper("並び順: \(sortOrder)", value: $sortOrder, in: 0...999)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section {
                    if eventShows.isEmpty {
                        Text("公演が未登録です").foregroundStyle(DS.ink3)
                    } else {
                        ForEach(eventShows) { show in
                            Button {
                                toggle(show.id)
                            } label: {
                                HStack {
                                    Text(show.name.isEmpty ? show.date : "\(show.name) ・ \(show.date)")
                                        .foregroundStyle(DS.ink)
                                    Spacer()
                                    if selectedShowIds.contains(show.id) {
                                        Image(systemName: "checkmark").foregroundStyle(DS.sys)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("対象公演")
                } footer: {
                    Text(selectedShowIds.isEmpty ? "未選択 = 全公演が対象" : "\(selectedShowIds.count) 公演を選択中")
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section {
                    TextField("受付開始", text: $startsAt).autocapitalization(.none).autocorrectionDisabled()
                    TextField("申込締切", text: $endsAt).autocapitalization(.none).autocorrectionDisabled()
                    TextField("当落発表", text: $resultAt).autocapitalization(.none).autocorrectionDisabled()
                } header: {
                    Text("日程")
                } footer: {
                    Text("YYYY-MM-DD、または時刻つき YYYY-MM-DD HH:MM。1 つも入力が無いと保存できません。")
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("リンク・補足") {
                    TextField("申込 URL", text: $url)
                        .keyboardType(.URL).autocapitalization(.none).autocorrectionDisabled()
                    TextField("出典 URL (必須)", text: $sourceUrl)
                        .keyboardType(.URL).autocapitalization(.none).autocorrectionDisabled()
                    TextField("補足", text: $note, axis: .vertical)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                if original != nil {
                    Section {
                        Button("この受付を削除", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .disabled(isSaving)
                    }
                    .listRowBackground(DS.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle(isCreate ? "受付を追加" : "受付を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { AppAnalytics.tap("ticket_sale_edit.save"); Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overlay { if isSaving { savingOverlay } }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
            .alert("この受付を削除しますか?", isPresented: $showDeleteConfirm) {
                Button("削除する", role: .destructive) { Task { await delete() } }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("「\(name)」を削除します。この操作は取り消せません。")
            }
            .editRequestSentAlert(isPresented: $requestSent, onDismiss: { dismiss() })
            .trackScreen("ticket_sale_edit")
        }
    }

    private func kindLabel(_ k: TicketSaleKind) -> String {
        let raw = ticketSaleKindRaw(kind: k)
        return Vocab.ticketSaleKind(raw)?.label ?? raw
    }

    private func toggle(_ showId: String) {
        if selectedShowIds.contains(showId) {
            selectedShowIds.remove(showId)
        } else {
            selectedShowIds.insert(showId)
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("保存中…").padding(DS.sp7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 自由記述の日時を保存用の正規形に直す。空欄は nil (未入力)。
    /// 正規化できない入力はそのまま渡し、検査 (`badMoment`) に判断を委ねる。
    private func normalizedOrNil(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return normalizeTicketSaleMoment(input: trimmed) ?? trimmed
    }

    private func trimmedOrNil(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func draft() -> TicketSaleDraft {
        TicketSaleDraft(
            eventId: eventId,
            showIds: Array(selectedShowIds),
            kind: kind,
            name: name.trimmingCharacters(in: .whitespaces),
            startsAt: normalizedOrNil(startsAt),
            endsAt: normalizedOrNil(endsAt),
            resultAt: normalizedOrNil(resultAt),
            url: trimmedOrNil(url),
            note: trimmedOrNil(note),
            sourceUrl: sourceUrl.trimmingCharacters(in: .whitespaces),
            sortOrder: Int64(sortOrder)
        )
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let d = draft()
        let issues = validateTicketSaleDraft(draft: d, eventShowIds: eventShows.map(\.id))
        if let issue = issues.first {
            errorMessage = ticketSaleIssueMessage(issue: issue)
            return
        }

        let fields: [String: AnyEncodable] = [
            "eventId": AnyEncodable(d.eventId),
            "kind": AnyEncodable(ticketSaleKindRaw(kind: d.kind)),
            "name": AnyEncodable(d.name),
            "showIds": AnyEncodable(d.showIds.joined(separator: ",")),
            "startsAt": d.startsAt.map(AnyEncodable.init) ?? AnyEncodable.null,
            "endsAt": d.endsAt.map(AnyEncodable.init) ?? AnyEncodable.null,
            "resultAt": d.resultAt.map(AnyEncodable.init) ?? AnyEncodable.null,
            "url": d.url.map(AnyEncodable.init) ?? AnyEncodable.null,
            "note": d.note.map(AnyEncodable.init) ?? AnyEncodable.null,
            "sourceUrl": AnyEncodable(d.sourceUrl),
            "sortOrder": AnyEncodable(d.sortOrder),
        ]

        let op = EditService.EditOperation(
            op: isCreate ? .create : .update,
            recordType: "TicketSale",
            recordName: original?.id,
            fields: fields
        )

        do {
            let outcome = try await EditService.shared.submitMaster(
                ops: [op], summary: isCreate ? "チケット受付追加" : "チケット受付編集"
            )
            guard case .applied(let resp) = outcome else {
                requestSent = true
                return
            }
            guard let id = resp.primaryRecordName(fallback: original?.id) else {
                errorMessage = "保存に失敗しました (ID 未確定)"
                return
            }
            let saved = TicketSaleRecord(
                id: id, eventId: d.eventId, showIds: d.showIds.isEmpty ? nil : d.showIds.joined(separator: ","),
                kind: ticketSaleKindRaw(kind: d.kind), name: d.name, startsAt: d.startsAt, endsAt: d.endsAt,
                resultAt: d.resultAt, url: d.url, note: d.note, sourceUrl: d.sourceUrl, sortOrder: d.sortOrder
            )
            try await AppContainer.shared.ticketSaleWriting.upsertTicketSales([saved])
            Logger.database.notice("ticket_sale_\(isCreate ? "created" : "edited", privacy: .public) id=\(id, privacy: .public)")
            dismiss()
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
        }
    }

    private func delete() async {
        guard let original else { return }
        isSaving = true
        defer { isSaving = false }

        let op = EditService.EditOperation(op: .delete, recordType: "TicketSale", recordName: original.id)
        do {
            let outcome = try await EditService.shared.submitMaster(ops: [op], summary: "チケット受付削除")
            guard case .applied = outcome else {
                requestSent = true
                return
            }
            try await AppContainer.shared.ticketSaleWriting.deleteTicketSales(ids: [original.id])
            Logger.database.notice("ticket_sale_deleted id=\(original.id, privacy: .public)")
            dismiss()
        } catch {
            errorMessage = "削除失敗: \(error.localizedDescription)"
        }
    }
}
