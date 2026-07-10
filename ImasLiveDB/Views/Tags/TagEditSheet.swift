import SwiftUI

struct TagEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tag: CommunityTag
    var domain: TagDomain = .song

    @State private var description: String
    @State private var selectedCategory: String
    @State private var selectedColor: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let categories = [("", "なし"), ("mood", "ムード"), ("scene", "シーン"), ("special", "特別"), ("free", "フリー")]

    init(tag: CommunityTag, domain: TagDomain = .song) {
        self.tag = tag
        self.domain = domain
        _description = State(initialValue: tag.description ?? "")
        _selectedCategory = State(initialValue: tag.category?.rawValue ?? "")
        _selectedColor = State(initialValue: tag.color?.rawValue ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("説明文") {
                    TextEditor(text: $description)
                        .scrollContentBackground(.hidden)
                        .background(DS.surface)
                        .frame(minHeight: 140)
                        .font(.imasBody)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("カテゴリ") {
                    Picker("カテゴリ", selection: $selectedCategory) {
                        ForEach(categories, id: \.0) { cat in
                            Text(cat.1).tag(cat.0)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("色") {
                    TagColorPicker(selectedHex: $selectedColor)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(DS.danger)
                            .font(.imasCaption)
                    }
                    .listRowBackground(DS.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("タグを編集")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("tag_edit")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        AppAnalytics.tap("tag_edit.save")
                        Task { await save() }
                    }
                    .disabled(isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let desc = description.isEmpty ? nil : description
            let cat = selectedCategory.isEmpty ? nil : selectedCategory
            let color = selectedColor.isEmpty ? nil : selectedColor
            switch domain {
            case .song:
                _ = try await CommunityAPI.shared.updateTag(id: tag.id, description: desc, category: cat, color: color)
            case .idol:
                _ = try await CommunityAPI.shared.updateIdolTag(id: tag.id, description: desc, category: cat, color: color)
            }
            dismiss()
        } catch let error as CommunityAPIError {
            errorMessage = error.errorDescription ?? "保存に失敗しました"
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
