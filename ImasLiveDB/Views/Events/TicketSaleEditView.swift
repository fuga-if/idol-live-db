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
                ImasListSection("基本情報") {
                    if let original {
                        ImasValueRow(key: "ID", value: original.id)
                    }
                    ImasTextFieldRow(title: "受付名 (例: 最速先行抽選)", text: $name)
                    ImasMenuRow(title: "種別", options: Self.kinds, selection: $kind, label: kindLabel)
                    ImasStepperRow(title: "並び順", value: $sortOrder, range: 0...999)
                }

                ImasListSection(
                    "対象公演",
                    footer: selectedShowIds.isEmpty ? "未選択 = 全公演が対象" : "\(selectedShowIds.count) 公演を選択中"
                ) {
                    if eventShows.isEmpty {
                        ImasNote("公演が未登録です")
                    } else {
                        ForEach(eventShows) { show in
                            ImasSelectableRow(
                                title: show.name.isEmpty ? show.date : "\(show.name) ・ \(show.date)",
                                isSelected: selectedShowIds.contains(show.id)
                            ) {
                                toggle(show.id)
                            }
                        }
                    }
                }

                ImasListSection("日程", footer: "YYYY-MM-DD、または時刻つき YYYY-MM-DD HH:MM。1 つも入力が無いと保存できません。") {
                    ImasTextFieldRow(title: "受付開始", text: $startsAt)
                        .autocapitalization(.none).autocorrectionDisabled()
                    ImasTextFieldRow(title: "申込締切", text: $endsAt)
                        .autocapitalization(.none).autocorrectionDisabled()
                    ImasTextFieldRow(title: "当落発表", text: $resultAt)
                        .autocapitalization(.none).autocorrectionDisabled()
                }

                ImasListSection("リンク・補足") {
                    ImasTextFieldRow(title: "申込 URL", text: $url, keyboard: .URL)
                        .autocapitalization(.none).autocorrectionDisabled()
                    ImasTextFieldRow(title: "出典 URL (必須)", text: $sourceUrl, keyboard: .URL)
                        .autocapitalization(.none).autocorrectionDisabled()
                    ImasTextAreaRow(text: $note, prompt: "補足")
                }

                if original != nil {
                    ImasListSection {
                        ImasActionRow(title: "この受付を削除", kind: .destructive) {
                            showDeleteConfirm = true
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .imasForm()
            .navigationTitle(isCreate ? "受付を追加" : "受付を編集")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(
                canSave: !isSaving && !name.trimmingCharacters(in: .whitespaces).isEmpty,
                onCancel: { dismiss() },
                onSave: { AppAnalytics.tap("ticket_sale_edit.save"); Task { await save() } }
            ))
            .imasSavingOverlay(isSaving)
            .imasErrorAlert(message: $errorMessage)
            .imasConfirmDestructive(
                "この受付を削除しますか?", isPresented: $showDeleteConfirm, actionTitle: "削除する",
                message: "「\(name)」を削除します。この操作は取り消せません。"
            ) {
                Task { await delete() }
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

    /// 選択済み公演 id を、集合の反復順ではなく公演の並び順 (`eventShows` の順) で並べる。
    /// 集合のまま送ると保存のたびに `show_ids` の並びが変わり、無駄な差分通知や表示順の
    /// 揺れ (L6) を起こす。
    private var orderedSelectedShowIds: [String] {
        eventShows.map(\.id).filter { selectedShowIds.contains($0) }
    }

    private func draft() -> TicketSaleDraft {
        TicketSaleDraft(
            eventId: eventId,
            showIds: orderedSelectedShowIds,
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
