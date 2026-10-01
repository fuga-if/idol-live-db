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

    init(tag: CommunityTag, domain: TagDomain = .song) {
        self.tag = tag
        self.domain = domain
        _description = State(initialValue: tag.description ?? "")
        _selectedCategory = State(initialValue: tag.category?.rawValue ?? "")
        _selectedColor = State(initialValue: tag.color?.rawValue ?? "")
    }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                ImasFormCard {
                    ImasFormField(label: "説明文（任意）", imprint: "DESCRIPTION", systemImage: "text.alignleft") {
                        VStack(alignment: .trailing, spacing: DS.Space.gapTight) {
                            TextField("どんな時に使うタグか", text: $description, axis: .vertical)
                                .font(.imasBody)
                                .lineLimit(3...6)
                                .onChange(of: description) { _, new in
                                    let clamped = InputLimits.clamp(.tagDescription, new)
                                    if clamped != new { description = clamped }
                                }
                            Text(InputLimits.counter(.tagDescription, description))
                                .font(.imasCaption.monospacedDigit())
                                .foregroundStyle(DS.ink3)
                        }
                    }
                    ImasFormField(label: "カテゴリ（任意）", imprint: "CATEGORY") {
                        ImasChipFlow {
                            categoryChip(value: "", label: Vocab.table.tagCategoryNoneLabel)
                            ForEach(TagCategoryOptions.options(for: domain), id: \.value) { cat in
                                categoryChip(value: cat.value, label: cat.label)
                            }
                        }
                    }
                    ImasFormField(label: "色（任意）", imprint: "COLOR") {
                        ImasColorPicker(selectedHex: $selectedColor)
                    }
                }

                if let errorMessage {
                    ImasNotice(kind: .error, message: errorMessage)
                }
            }
            .navigationTitle("「\(tag.name)」を編集")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("tag_edit")
            .imasSheetToolbar(.edit(canSave: !isSaving, onCancel: { dismiss() }, onSave: {
                AppAnalytics.tap("tag_edit.save")
                Task { await save() }
            }))
        }
    }

    private func categoryChip(value: String, label: String) -> some View {
        ImasFilterChip(text: label, isSelected: selectedCategory == value) {
            selectedCategory = value
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let desc = description.isEmpty ? nil : description
            let cat = selectedCategory.isEmpty ? nil : selectedCategory
            let color = selectedColor.isEmpty ? nil : selectedColor
            let writing = AppContainer.shared.communityTagWriting
            switch domain {
            case .song:
                _ = try await writing.updateTag(id: tag.id, description: desc, category: cat, color: color)
            case .idol:
                _ = try await writing.updateIdolTag(id: tag.id, description: desc, category: cat, color: color)
            case .unit:
                _ = try await writing.updateUnitTag(id: tag.id, description: desc, category: cat, color: color)
            }
            dismiss()
        } catch let error as CommunityAPIError {
            errorMessage = error.errorDescription ?? "保存に失敗しました"
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}
