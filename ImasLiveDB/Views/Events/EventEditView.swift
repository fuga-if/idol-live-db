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
    @State private var ticketOpenDate: String
    @State private var ticketDeadline: String
    @State private var ticketLotteryDate: String
    @State private var ticketUrl: String
    @State private var jointBrandIds: String
    @State private var allBrands: [Brand] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// 既存編集用。
    init(event: Event) {
        self.mode = .update(original: event)
        _name = State(initialValue: event.name)
        _brandId = State(initialValue: event.brandId ?? "")
        _kind = State(initialValue: event.eventKind)
        _ticketOpenDate = State(initialValue: event.ticketOpenDate ?? "")
        _ticketDeadline = State(initialValue: event.ticketDeadline ?? "")
        _ticketLotteryDate = State(initialValue: event.ticketLotteryDate ?? "")
        _ticketUrl = State(initialValue: event.ticketUrl ?? "")
        _jointBrandIds = State(initialValue: event.jointBrandIds ?? "")
    }

    /// 新規作成用。ブランドの初期選択だけ受け取る (一覧のフィルタ文脈などから)。
    init(newEventBrandId: String? = nil) {
        self.mode = .create
        _name = State(initialValue: "")
        _brandId = State(initialValue: newEventBrandId ?? "")
        _kind = State(initialValue: .live)
        _ticketOpenDate = State(initialValue: "")
        _ticketDeadline = State(initialValue: "")
        _ticketLotteryDate = State(initialValue: "")
        _ticketUrl = State(initialValue: "")
        _jointBrandIds = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    if let original = mode.original {
                        LabeledContent("ID") { Text(original.id).foregroundStyle(DS.ink2) }
                    }
                    TextField("イベント名", text: $name)
                    Picker("ブランド", selection: $brandId) {
                        Text("未指定").tag("")
                        ForEach(allBrands) { brand in
                            Text(brand.name).tag(brand.id)
                        }
                    }
                    Picker("種別", selection: $kind) {
                        ForEach(EventKind.allCases, id: \.self) {
                            Text($0.displayLabel).tag($0)
                        }
                    }
                    TextField("合同ブランド (カンマ区切り)", text: $jointBrandIds)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
                Section("チケット") {
                    TextField("受付開始 (YYYY-MM-DD)", text: $ticketOpenDate)
                    TextField("先行締切 (YYYY-MM-DD)", text: $ticketDeadline)
                    TextField("当落発表 (YYYY-MM-DD)", text: $ticketLotteryDate)
                    TextField("URL", text: $ticketUrl)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle(mode.isCreate ? "イベント追加" : "イベント編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { AppAnalytics.tap("event_edit.save"); Task { await save() } }
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
            .task {
                allBrands = (try? await AppContainer.shared.brandReading.brands()) ?? []
            }
            .trackScreen("event_edit")
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("保存中…").padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "イベント名を入力してください"
            return
        }

        // 互換フィールド (eventType / isStreaming / isSolo) は既存値を維持。新規は既定値。
        let original = mode.original
        let eventType = original?.eventType ?? "live"
        let isStreaming = original?.isStreaming ?? false
        let isSolo = original?.isSolo ?? false

        var fields: [String: AnyEncodable] = [
            "name": AnyEncodable(trimmedName),
            "eventType": AnyEncodable(eventType),
            "isStreaming": AnyEncodable(isStreaming ? 1 : 0),
            "isSolo": AnyEncodable(isSolo ? 1 : 0),
            "kind": AnyEncodable(kind.rawValue),
        ]
        // update はサーバ側マージ (未送信 = 現状維持)。空にした場合は null 明示送信でクリア。
        let resolvedBrandId = brandId.isEmpty ? nil : brandId
        fields["brandId"] = AnyEncodable.clearable(brandId, original: original?.brandId)
        fields["ticketOpenDate"] = AnyEncodable.clearable(ticketOpenDate, original: original?.ticketOpenDate)
        fields["ticketDeadline"] = AnyEncodable.clearable(ticketDeadline, original: original?.ticketDeadline)
        fields["ticketLotteryDate"] = AnyEncodable.clearable(ticketLotteryDate, original: original?.ticketLotteryDate)
        fields["ticketUrl"] = AnyEncodable.clearable(ticketUrl, original: original?.ticketUrl)
        fields["jointBrandIds"] = AnyEncodable.clearable(jointBrandIds, original: original?.jointBrandIds)

        let op = EditService.EditOperation(
            op: mode.isCreate ? .create : .update,
            recordType: "Event",
            recordName: original?.id,
            fields: fields
        )

        do {
            let resp = try await EditService.shared.submit(ops: [op], summary: mode.isCreate ? "イベント追加" : "イベント編集")
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
                kind: kind.rawValue,
                ticketOpenDate: ticketOpenDate.isEmpty ? nil : ticketOpenDate,
                ticketDeadline: ticketDeadline.isEmpty ? nil : ticketDeadline,
                ticketLotteryDate: ticketLotteryDate.isEmpty ? nil : ticketLotteryDate,
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
