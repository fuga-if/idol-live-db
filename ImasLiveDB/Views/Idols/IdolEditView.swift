import os
import SwiftUI

/// Idol 編集 (主に名前・読み・誕生日・色・属性)。ログイン済みユーザーが利用可能。
/// 軽微な誤字修正用途を主目的とする。 詳細プロフィール (BWH 等) は別途。
/// アイドルの新規作成はスコープ外 (admin 限定 / サーバ側 NO_CREATE_TYPES) のため update のみ。
struct IdolEditView: View {
    let original: Idol

    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var nameKana: String
    @State private var nameRomaji: String
    @State private var brandId: String
    @State private var color: String
    @State private var birthday: String
    @State private var bloodType: String
    @State private var birthPlace: String
    @State private var attribute: String
    @State private var aliases: String
    @State private var debutDate: String
    @State private var sortOrder: Int
    @State private var allBrands: [Brand] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var requestSent = false

    init(idol: Idol) {
        self.original = idol
        _name = State(initialValue: idol.name)
        _nameKana = State(initialValue: idol.nameKana ?? "")
        _nameRomaji = State(initialValue: idol.nameRomaji ?? "")
        _brandId = State(initialValue: idol.brandId)
        _color = State(initialValue: idol.color ?? "")
        _birthday = State(initialValue: idol.birthday ?? "")
        _bloodType = State(initialValue: idol.bloodType ?? "")
        _birthPlace = State(initialValue: idol.birthPlace ?? "")
        _attribute = State(initialValue: idol.attribute ?? "")
        _aliases = State(initialValue: idol.aliases ?? "")
        _debutDate = State(initialValue: idol.debutDate ?? "")
        _sortOrder = State(initialValue: idol.sortOrder)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    LabeledContent("ID") { Text(original.id).foregroundStyle(DS.ink2) }
                    TextField("名前", text: $name)
                    TextField("カナ", text: $nameKana)
                    TextField("ローマ字", text: $nameRomaji)
                    TextField("別名 (カンマ区切り)", text: $aliases)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
                Section("分類") {
                    Picker("ブランド", selection: $brandId) {
                        ForEach(allBrands) { Text($0.name).tag($0.id) }
                    }
                    TextField("属性 (cute/cool/passion 等)", text: $attribute)
                    Stepper("並び順: \(sortOrder)", value: $sortOrder, in: 0...9999)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
                Section("プロフィール") {
                    TextField("カラー (#hex)", text: $color)
                        .autocapitalization(.none).autocorrectionDisabled()
                    TextField("誕生日 (MM-DD)", text: $birthday)
                    TextField("血液型", text: $bloodType)
                    TextField("出身地", text: $birthPlace)
                    TextField("実装日 (YYYY-MM-DD)", text: $debutDate)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("アイドル編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { AppAnalytics.tap("idol_edit.save"); Task { await save() } }.disabled(isSaving)
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
            .task { allBrands = (try? await AppContainer.shared.brandReading.brands()) ?? [] }
            .trackScreen("idol_edit")
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

        var updated = original
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.nameKana = nameKana.isEmpty ? nil : nameKana
        updated.nameRomaji = nameRomaji.isEmpty ? nil : nameRomaji
        updated.brandId = brandId
        updated.color = color.isEmpty ? nil : color
        updated.birthday = birthday.isEmpty ? nil : birthday
        updated.bloodType = bloodType.isEmpty ? nil : bloodType
        updated.birthPlace = birthPlace.isEmpty ? nil : birthPlace
        updated.attribute = attribute.isEmpty ? nil : attribute
        updated.aliases = aliases.isEmpty ? nil : aliases
        updated.debutDate = debutDate.isEmpty ? nil : debutDate
        updated.sortOrder = sortOrder

        var fields: [String: AnyEncodable] = [
            "name": AnyEncodable(updated.name),
            "brandId": AnyEncodable(updated.brandId),
            "sortOrder": AnyEncodable(updated.sortOrder),
        ]
        // update はサーバ側マージ (未送信 = 現状維持)。空にした場合は null 明示送信でクリア。
        fields["nameKana"] = AnyEncodable.clearable(nameKana, original: original.nameKana)
        fields["nameRomaji"] = AnyEncodable.clearable(nameRomaji, original: original.nameRomaji)
        fields["color"] = AnyEncodable.clearable(color, original: original.color)
        fields["birthday"] = AnyEncodable.clearable(birthday, original: original.birthday)
        fields["bloodType"] = AnyEncodable.clearable(bloodType, original: original.bloodType)
        fields["birthPlace"] = AnyEncodable.clearable(birthPlace, original: original.birthPlace)
        fields["attribute"] = AnyEncodable.clearable(attribute, original: original.attribute)
        fields["aliases"] = AnyEncodable.clearable(aliases, original: original.aliases)
        fields["debutDate"] = AnyEncodable.clearable(debutDate, original: original.debutDate)

        let op = EditService.EditOperation(
            op: .update,
            recordType: "Idol",
            recordName: updated.id,
            fields: fields
        )

        do {
            let outcome = try await EditService.shared.submitMaster(ops: [op], summary: "アイドル編集")
            switch outcome {
            case .applied(let resp):
                var saved = updated
                saved.id = resp.primaryRecordName(fallback: updated.id) ?? updated.id
                try await AppContainer.shared.idolWriting.upsertIdols([saved])
                Logger.database.notice("idol_edit_saved id=\(saved.id, privacy: .public)")
                dismiss()
            case .requested:
                requestSent = true
            }
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
        }
    }
}
