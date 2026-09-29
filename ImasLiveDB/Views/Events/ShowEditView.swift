import os
import SwiftUI

/// Show (公演) の基本情報を編集 / 新規作成する。ログイン済みユーザーが利用可能。
/// - `.update`: 既存公演の修正。
/// - `.create`: 新規公演作成。eventId は必須 (必ず既存 Event の詳細画面から作る)。
/// - 保存 → サーバ /edits 経由で CloudKit forceUpdate + ローカル shows テーブル upsert
struct ShowEditView: View {
    let mode: EditMode<Show>
    /// 新規作成時に必須となる親イベント ID。既存編集時は original.eventId を使う。
    private let eventId: String

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var date: String
    @State private var venue: String
    @State private var venueCity: String
    @State private var startTime: String
    @State private var sortOrder: Int
    @State private var performerType: String
    @State private var venueMode: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var requestSent = false

    /// 既存編集用。
    init(show: Show) {
        self.mode = .update(original: show)
        self.eventId = show.eventId
        _name = State(initialValue: show.name)
        _date = State(initialValue: show.date)
        _venue = State(initialValue: show.venue ?? "")
        _venueCity = State(initialValue: show.venueCity ?? "")
        _startTime = State(initialValue: show.startTime ?? "")
        _sortOrder = State(initialValue: show.sortOrder)
        _performerType = State(initialValue: show.performerType ?? "")
        _venueMode = State(initialValue: show.venueMode ?? "")
    }

    /// 新規作成用。親イベントと、既存公演数に応じた sortOrder 初期値を受け取る。
    init(newShowEventId: String, suggestedSortOrder: Int = 0) {
        self.mode = .create
        self.eventId = newShowEventId
        _name = State(initialValue: "")
        _date = State(initialValue: "")
        _venue = State(initialValue: "")
        _venueCity = State(initialValue: "")
        _startTime = State(initialValue: "")
        _sortOrder = State(initialValue: suggestedSortOrder)
        _performerType = State(initialValue: "")
        _venueMode = State(initialValue: "")
    }

    /// screening = MV 上映会など、誰も歌わない公演 (披露回数に数えない)。
    private let performerTypes = ["", "character", "cast", "mixed", "screening"]
    /// 会場の形態の選択肢 (保存値と文言は imas-core)。
    private let venueModes = venueModeOptions()

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    if let original = mode.original {
                        LabeledContent("ID") { Text(original.id).foregroundStyle(DS.ink2) }
                    }
                    TextField("公演名", text: $name)
                    TextField("日付 (YYYY-MM-DD)", text: $date)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("会場", text: $venue)
                    TextField("会場所在地", text: $venueCity)
                    TextField("開演時刻 (HH:mm)", text: $startTime)
                    Stepper("並び順: \(sortOrder)", value: $sortOrder, in: 0...999)
                    Picker("出演形態", selection: $performerType) {
                        ForEach(performerTypes, id: \.self) {
                            Text($0.isEmpty ? "未指定" : $0).tag($0)
                        }
                    }
                    Picker("会場の形態", selection: $venueMode) {
                        ForEach(venueModes, id: \.raw) { option in
                            Text(option.label).tag(option.raw)
                        }
                    }
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle(mode.isCreate ? "公演追加" : "公演編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { AppAnalytics.tap("show_edit.save"); Task { await save() } }
                        .disabled(isSaving || !canSave)
                }
            }
            .overlay { if isSaving { savingOverlay } }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
            .editRequestSentAlert(isPresented: $requestSent, onDismiss: { dismiss() })
            .trackScreen("show_edit")
        }
    }

    /// 公演名・日付が揃って初めて保存可能 (新規/編集とも必須)。
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !date.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView("保存中…").padding(DS.sp7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDate = date.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedDate.isEmpty else {
            errorMessage = "公演名と日付は必須です"
            return
        }
        // 日付フォーマットの軽い前段チェック (サーバ側でも検証されるが UX のため)。
        guard isValidDate(trimmedDate) else {
            errorMessage = "日付は YYYY-MM-DD 形式で入力してください"
            return
        }

        var fields: [String: AnyEncodable] = [
            "eventId": AnyEncodable(eventId),
            "name": AnyEncodable(trimmedName),
            "date": AnyEncodable(trimmedDate),
            "sortOrder": AnyEncodable(sortOrder),
        ]
        // update はサーバ側マージ (未送信 = 現状維持)。空にした場合は null 明示送信でクリア。
        let original = mode.original
        fields["venue"] = AnyEncodable.clearable(venue, original: original?.venue)
        fields["venueCity"] = AnyEncodable.clearable(venueCity, original: original?.venueCity)
        fields["startTime"] = AnyEncodable.clearable(startTime, original: original?.startTime)
        fields["performerType"] = AnyEncodable.clearable(performerType, original: original?.performerType)
        fields["venueMode"] = AnyEncodable.clearable(venueMode, original: original?.venueMode)

        let op = EditService.EditOperation(
            op: mode.isCreate ? .create : .update,
            recordType: "Show",
            recordName: mode.original?.id,
            fields: fields
        )

        do {
            let outcome = try await EditService.shared.submitMaster(ops: [op], summary: mode.isCreate ? "公演追加" : "公演編集")
            guard case .applied(let resp) = outcome else {
                requestSent = true
                return
            }
            // ローカル upsert はサーバ確定 recordName を使う (create はサーバ採番 ID)。
            let resolvedId = resp.primaryRecordName(fallback: mode.original?.id)
            guard let id = resolvedId else {
                errorMessage = "保存に失敗しました (ID 未確定)"
                return
            }
            // venueId / hall / streamPlatform はフォームに無い列。元の行から引き継がないと
            // upsert (行ごと置き換え) で消え、会場の同一性 (venue_id) まで失われる (Android と同じ)。
            var saved = mode.original ?? Show(
                id: id, eventId: eventId, name: "", date: "",
                venue: nil, venueCity: nil, startTime: nil, sortOrder: 0, performerType: nil
            )
            saved.id = id
            saved.eventId = eventId
            saved.name = trimmedName
            saved.date = trimmedDate
            saved.venue = venue.isEmpty ? nil : venue
            saved.venueCity = venueCity.isEmpty ? nil : venueCity
            saved.startTime = startTime.isEmpty ? nil : startTime
            saved.sortOrder = sortOrder
            saved.performerType = performerType.isEmpty ? nil : performerType
            saved.venueMode = venueMode.isEmpty ? nil : venueMode
            try await AppContainer.shared.showWriting.upsertShows([saved])
            Logger.database.notice("show_\(mode.isCreate ? "created" : "edited", privacy: .public) id=\(id, privacy: .public)")
            dismiss()
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
        }
    }

    /// YYYY-MM-DD の最小限の妥当性チェック。
    private func isValidDate(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, Int(parts[0]) != nil,
              let m = Int(parts[1]), (1...12).contains(m),
              let d = Int(parts[2]), (1...31).contains(d) else {
            return false
        }
        return true
    }
}
