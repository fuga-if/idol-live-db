import SwiftUI

/// プロフィール帳の載せるものを選ぶ。上に出来上がりの見本 (その場で変わる)、下に選ぶものだけ。
///
/// 自分で書く欄は無い。様式と大きさ、担当ブランドの丸 (押すたびに 丸 → 二重丸 (メイン) → 丸なし)、
/// 載せる記録の付け外しだけ。記録の無い欄・その様式で使わない欄は並べない。
/// 欄の一覧と見本の値・丸の回し方はコア (`profileAutoFieldRows` / `profileToggleField` /
/// `profileBrandMarks` / `profileToggleBrand`)。項目の多い設定寄りのシートなので Form の型で組む。
struct ProfileSheetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let card: MyProducerCard
    let materials: ProfileSheetMaterials
    let onSave: (ProfileSheet) async throws -> Void

    @State private var sheet: ProfileSheet
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmDiscard = false

    private let styles = profileSheetStyles()
    private let sizes = profileSheetSizes()

    init(card: MyProducerCard, materials: ProfileSheetMaterials,
         onSave: @escaping (ProfileSheet) async throws -> Void) {
        self.card = card
        self.materials = materials
        self.onSave = onSave
        _sheet = State(initialValue: card.profile)
    }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            List {
                Section { preview }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ImasListSection("様式") {
                    ImasSegmented(options: styles.map(\.style), selection: $sheet.style) { style in
                        styles.first { $0.style == style }?.label ?? ""
                    }
                    ImasSegmented(options: sizes.map(\.size), selection: $sheet.size) { size in
                        sizes.first { $0.size == size }.map { "\($0.label) \($0.caption)" } ?? ""
                    }
                }
                brandsSection.id("brands")
                fieldsSection.id("fields")
                if let error {
                    Section { Text(error).imasText(.note, color: DS.danger) }
                        .listRowBackground(Color.clear)
                }
            }
            .imasForm()
            #if DEBUG
            .onAppear {
                // シミュレータでの見た目確認 (PROFILE_SCROLL=brands|fields)。
                if let target = ProcessInfo.processInfo.environment["PROFILE_SCROLL"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { proxy.scrollTo(target, anchor: .top) }
                }
            }
            #endif
            .navigationTitle("載せる記録を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .imasSheetToolbar(.edit(canSave: !isSaving, onCancel: cancel, onSave: { Task { await save() } }))
            .imasSavingOverlay(isSaving, label: "保存中")
            .imasDiscardConfirmation(isPresented: $confirmDiscard) { dismiss() }
            .interactiveDismissDisabled(isDirty)
          }
        }
    }

    // MARK: - 見本

    private var preview: some View {
        let layout = profileSheetLayout(sheet: sheet, record: materials.record)
        return ShareCardPreview(size: ProfileSheetInk.size(sheet.size)) {
            ProfileSheetCard(layout: layout, materials: materials)
        }
        .accessibilityLabel("\(layout.title)の見本")
    }

    // MARK: - 担当ブランド

    private var brandsSection: some View {
        let marks = profileBrandMarks(sheet: sheet, record: materials.record)
        return ImasListSection("担当ブランド",
                               footer: "担当と参加した公演のブランドに丸が付いています。押すたびに 丸 → 二重丸 (メイン) → 丸なし と変わります。メインは 1 つです。") {
            ImasChipFlow {
                ForEach(marks, id: \.id) { mark in
                    ImasFilterChip(text: mark.label, systemImage: mark.main ? "circle.circle" : nil,
                                   isSelected: mark.checked, brand: mark.color) {
                        sheet = profileToggleBrand(sheet: sheet, record: materials.record, brandId: mark.id)
                    }
                    .accessibilityValue(mark.main ? "メイン" : mark.checked ? "丸あり" : "丸なし")
                    .accessibilityHint(mark.fromRecord ? "記録から丸が付くブランド" : "")
                }
            }
            .listRowBackground(DS.surface)
        }
    }

    // MARK: - 載せる記録

    private var fieldsSection: some View {
        let rows = profileAutoFieldRows(sheet: sheet, record: materials.record)
        return ImasListSection("載せる記録", footer: "記録の無いものは並びません。外したものは画像に載りません。") {
            ForEach(rows, id: \.key) { row in
                ImasToggleRow(title: row.label, subtitle: row.value.isEmpty ? nil : row.value,
                              isOn: Binding(get: { row.shown },
                                            set: { _ in sheet = profileToggleField(sheet: sheet, field: row.field) }))
            }
        }
    }

    // MARK: - 保存

    private var isDirty: Bool { sheet != card.profile }

    private func cancel() {
        if isDirty { confirmDiscard = true } else { dismiss() }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(sheet)
            AppAnalytics.tap("profile_sheet.save")
            dismiss()
        } catch {
            self.error = "保存できませんでした。\(error.localizedDescription)"
        }
    }
}
