import os
import SwiftUI

/// Event (イベント) の基本情報を編集 / 新規作成する。ログイン済みユーザーが利用可能。
/// - `.update`: 既存イベントの修正。
/// - `.create`: 新規イベント作成 (recordName はサーバ採番)。
struct EventEditView: View {
    let mode: EditMode<Event>

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var brandId: String
    @State private var kind: EventKind
    /// 語彙に無い種別 (または "other") を持つ既存イベントの元の値。
    /// 利用者が種別を選び直さない限り、この値をそのまま送り返す。
    private let unlistedKindRaw: String?
    @State private var ticketUrl: String
    @State private var jointBrandIds: String
    @State private var allBrands: [Brand] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var requestSent = false
    /// チケット受付の一覧 (既存イベント編集時のみ表示。新規作成は先に本体を保存してから)。
    @State private var ticketSales: [TicketSale] = []
    @State private var eventShows: [Show] = []
    @State private var editTicketSale: TicketSale?
    @State private var showTicketSaleCreate = false

    /// 既存編集用。
    init(event: Event) {
        self.mode = .update(original: event)
        _name = State(initialValue: event.name)
        _brandId = State(initialValue: event.brandId ?? "")
        _kind = State(initialValue: event.eventKind)
        self.unlistedKindRaw = event.eventKind == .other ? event.kind : nil
        _ticketUrl = State(initialValue: event.ticketUrl ?? "")
        _jointBrandIds = State(initialValue: event.jointBrandIds ?? "")
    }

    /// 新規作成用。ブランドの初期選択だけ受け取る (一覧のフィルタ文脈などから)。
    init(newEventBrandId: String? = nil) {
        self.mode = .create
        _name = State(initialValue: "")
        _brandId = State(initialValue: newEventBrandId ?? "")
        _kind = State(initialValue: .live)
        self.unlistedKindRaw = nil
        _ticketUrl = State(initialValue: "")
        _jointBrandIds = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                ImasListSection("基本情報") {
                    if let original = mode.original {
                        ImasValueRow(key: "ID", value: original.id, expandable: true, copyable: false)
                    }
                    ImasTextFieldRow(title: "イベント名", text: $name)
                    ImasMenuRow(title: "ブランド", options: [""] + allBrands.map(\.id), selection: $brandId) { id in
                        id.isEmpty ? "未指定" : (allBrands.first { $0.id == id }?.name ?? id)
                    }
                    ImasMenuRow(title: "種別", options: kindOptions, selection: $kind) { k in
                        k == .other ? "変更しない (\(unlistedKindRaw ?? ""))" : k.displayLabel
                    }
                    ImasTextFieldRow(title: "合同ブランド (カンマ区切り)", text: $jointBrandIds)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                ImasListSection("チケット") {
                    ImasTextFieldRow(title: "案内 URL (イベント全体)", text: $ticketUrl, keyboard: .URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                // 受付の日程・種別・対象公演は ticket_sales 側の個別編集 (TicketSaleEditView) に移った。
                // 新規イベントは先に本体を保存してから (id が要る)、この画面には出さない。
                if let original = mode.original {
                    ImasListSection("チケット受付") {
                        if ticketSales.isEmpty {
                            ImasNote("チケット受付は未登録です")
                        } else {
                            ForEach(ticketSales) { sale in
                                Button {
                                    editTicketSale = sale
                                } label: {
                                    // ImasNavRow は題を 1 行に固定するため使わない。受付名は
                                    // 「岩手公演 公式リセール(9月22日(火)公演)」のように末尾でしか
                                    // 見分けが付かないものがあるので、ここでは行数を広げて全文を出す。
                                    ImasRow(
                                        title: sale.name,
                                        trailing: .custom(AnyView(
                                            HStack(spacing: DS.Space.gap) {
                                                Text(sale.stageLabel).imasText(.value, color: DS.ink2).lineLimit(1)
                                                ImasRowChevron()
                                            }
                                        )),
                                        density: .compact,
                                        titleLineLimit: 3,
                                        titleRole: .rowLabel
                                    ) {
                                        if let period = sale.periodLabel {
                                            Text(period).imasText(.meta)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .buttonStyle(.imasRow)
                            }
                        }
                        ImasActionRow(title: "受付を追加", systemImage: "plus.circle") {
                            showTicketSaleCreate = true
                        }
                    }
                    .task { await loadTicketSales(eventId: original.id) }
                }
            }
            .imasForm()
            .navigationTitle(mode.isCreate ? "イベント追加" : "イベント編集")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(
                canSave: !isSaving && !name.trimmingCharacters(in: .whitespaces).isEmpty,
                onCancel: { dismiss() },
                onSave: { AppAnalytics.tap("event_edit.save"); Task { await save() } }
            ))
            .imasSavingOverlay(isSaving)
            .imasErrorAlert("エラー", message: $errorMessage)
            .editRequestSentAlert(isPresented: $requestSent, onDismiss: { dismiss() })
            .task {
                allBrands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            }
            .sheet(item: $editTicketSale, onDismiss: { Task { if let id = mode.original?.id { await loadTicketSales(eventId: id) } } }) { sale in
                TicketSaleEditView(ticketSale: sale, eventShows: eventShows)
            }
            .sheet(isPresented: $showTicketSaleCreate, onDismiss: { Task { if let id = mode.original?.id { await loadTicketSales(eventId: id) } } }) {
                if let id = mode.original?.id {
                    TicketSaleEditView(newSaleEventId: id, eventShows: eventShows, suggestedSortOrder: ticketSales.count)
                }
            }
            .trackScreen("event_edit")
        }
    }

    /// 「その他」は知らない種別の受け皿なので、書き込む値としては出さない
    /// (元が未知の種別だったときだけ「変更しない」の選択肢として残す)。
    private var kindOptions: [EventKind] {
        EventKind.allCases.filter { $0 != .other } + (unlistedKindRaw != nil ? [.other] : [])
    }

    /// イベント編集画面用のチケット受付一覧 + 対象公演読み込み。
    private func loadTicketSales(eventId: String) async {
        async let sales = AppContainer.shared.eventReading.ticketSales(eventId: eventId)
        async let shows = AppContainer.shared.showReading.shows(eventId: eventId)
        ticketSales = (try? await sales) ?? []
        eventShows = (try? await shows) ?? []
    }

    private var kindToSend: String {
        Self.kindToSend(selected: kind, unlistedRaw: unlistedKindRaw)
    }

    /// 「その他」は知らない種別の受け皿なので、選ばれていれば元の生の値を返す
    /// (黙って "other" に潰すと、新しい種別のイベントを直した人がその種別を消してしまう)。
    nonisolated static func kindToSend(selected: EventKind, unlistedRaw: String?) -> String {
        selected == .other ? (unlistedRaw ?? selected.rawValue) : selected.rawValue
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "イベント名を入力してください"
            return
        }

        // 互換フィールド (isStreaming / isSolo) は既存値を維持。新規は既定値。
        // eventType は催しの性格 (周年 / オケ / 外部イベント …) なので、新規は**未分類**で出す。
        // "live" を既定にすると、発表されたばかりの周年ライブが自社の単発公演として
        // 数えられ、「AS の周年では」の答えが静かに変わる。
        let original = mode.original
        let eventType = original?.eventType ?? ""
        let isStreaming = original?.isStreaming ?? false
        let isSolo = original?.isSolo ?? false

        var fields: [String: AnyEncodable] = [
            "name": AnyEncodable(trimmedName),
            "eventType": AnyEncodable(eventType),
            "isStreaming": AnyEncodable(isStreaming ? 1 : 0),
            "isSolo": AnyEncodable(isSolo ? 1 : 0),
            "kind": AnyEncodable(kindToSend),
        ]
        // update はサーバ側マージ (未送信 = 現状維持)。空にした場合は null 明示送信でクリア。
        let resolvedBrandId = brandId.isEmpty ? nil : brandId
        fields["brandId"] = AnyEncodable.clearable(brandId, original: original?.brandId)
        fields["ticketUrl"] = AnyEncodable.clearable(ticketUrl, original: original?.ticketUrl)
        fields["jointBrandIds"] = AnyEncodable.clearable(jointBrandIds, original: original?.jointBrandIds)

        let op = EditService.EditOperation(
            op: mode.isCreate ? .create : .update,
            recordType: "Event",
            recordName: original?.id,
            fields: fields
        )

        do {
            let outcome = try await EditService.shared.submitMaster(ops: [op], summary: mode.isCreate ? "イベント追加" : "イベント編集")
            guard case .applied(let resp) = outcome else {
                requestSent = true
                return
            }
            // ローカル upsert はサーバ確定 recordName を使う (create はサーバ採番 ID)。
            let resolvedId = resp.primaryRecordName(fallback: original?.id)
            guard let id = resolvedId else {
                errorMessage = "保存に失敗しました (ID 未確定)"
                return
            }
            let saved = Event(
                id: id,
                brandId: resolvedBrandId,
                name: trimmedName,
                eventType: eventType,
                isStreaming: isStreaming,
                isSolo: isSolo,
                kind: kindToSend,
                ticketUrl: ticketUrl.isEmpty ? nil : ticketUrl,
                jointBrandIds: jointBrandIds.isEmpty ? nil : jointBrandIds
            )
            try await AppContainer.shared.eventWriting.upsertEvents([saved])
            Logger.database.notice("event_\(mode.isCreate ? "created" : "edited", privacy: .public) id=\(id, privacy: .public)")
            dismiss()
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
        }
    }
}
