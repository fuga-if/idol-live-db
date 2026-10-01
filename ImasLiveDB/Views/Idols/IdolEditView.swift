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
                ImasListSection("名前") {
                    ImasValueRow(key: "ID", value: original.id, expandable: true, copyable: false)
                    ImasTextFieldRow(title: "名前", text: $name)
                    ImasTextFieldRow(title: "カナ", text: $nameKana)
                    ImasTextFieldRow(title: "ローマ字", text: $nameRomaji)
                    ImasTextFieldRow(title: "別名 (カンマ区切り)", text: $aliases)
                }
                ImasListSection("分類") {
                    ImasMenuRow(title: "ブランド", options: allBrands.map(\.id), selection: $brandId) { id in
                        allBrands.first { $0.id == id }?.name ?? id
                    }
                    ImasTextFieldRow(title: "属性 (cute/cool/passion 等)", text: $attribute)
                    ImasStepperRow(title: "並び順", value: $sortOrder, range: 0...9999)
                }
                ImasListSection("プロフィール") {
                    ImasTextFieldRow(title: "カラー (#hex)", text: $color)
                        .autocapitalization(.none).autocorrectionDisabled()
                    ImasTextFieldRow(title: "誕生日 (MM-DD)", text: $birthday)
                    ImasTextFieldRow(title: "血液型", text: $bloodType)
                    ImasTextFieldRow(title: "出身地", text: $birthPlace)
                    ImasTextFieldRow(title: "実装日 (YYYY-MM-DD)", text: $debutDate)
                }
            }
            .imasForm()
            .navigationTitle("アイドル編集")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: !isSaving, onCancel: { dismiss() }, onSave: {
                AppAnalytics.tap("idol_edit.save")
                Task { await save() }
            }))
            .imasSavingOverlay(isSaving, label: "保存中")
            .imasErrorAlert("エラー", message: $errorMessage)
            .editRequestSentAlert(isPresented: $requestSent, onDismiss: { dismiss() })
            .task { allBrands = (try? await AppContainer.shared.brandReading.brands()) ?? [] }
            .trackScreen("idol_edit")
        }
    }

    /// マスタの色は `#RRGGBB` 表記で統一されており、サーバの検証もそれを正とする。
    /// `#` を省いて打っても弾かれないよう、送る前にこちらで補う。
    private var canonicalColor: String {
        guard !color.isEmpty, let hex = ColorMath.normalizedHex(color) else { return color }
        return "#" + hex.uppercased()
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        var updated = original
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.nameKana = nameKana.isEmpty ? nil : nameKana
        updated.nameRomaji = nameRomaji.isEmpty ? nil : nameRomaji
        updated.brandId = brandId
        updated.color = color.isEmpty ? nil : canonicalColor
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
        fields["color"] = AnyEncodable.clearable(canonicalColor, original: original.color)
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
