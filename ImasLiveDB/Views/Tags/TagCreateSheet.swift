import SwiftUI

struct TagCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCreated: ((CommunityTag) -> Void)?
    /// 呼び出し側で入力済みのタグ名を引き継ぐ (タグ追加シートの検索語など)。
    var initialName: String = ""

    @State private var name = ""
    @State private var description = ""
    @State private var selectedCategory = ""
    @State private var selectedColor = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdTag: CommunityTag?

    private let categories = [("", "なし"), ("mood", "ムード"), ("scene", "シーン"), ("special", "特別"), ("free", "フリー")]

    private var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 1 && trimmed.count <= 30
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タグ名（1〜30文字）", text: $name)
                        .autocorrectionDisabled()
                        .onAppear { if name.isEmpty { name = initialName } }
                } header: {
                    Text("タグ名")
                } footer: {
                    Text("\(name.trimmingCharacters(in: .whitespaces).count) / 30文字")
                        .foregroundStyle(isNameValid ? DS.ink2 : DS.danger)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("説明文（任意）") {
                    TextEditor(text: $description)
                        .scrollContentBackground(.hidden)
                        .background(DS.surface)
                        .frame(minHeight: 100)
                        .font(.imasBody)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("カテゴリ（任意）") {
                    Picker("カテゴリ", selection: $selectedCategory) {
                        ForEach(categories, id: \.0) { cat in
                            Text(cat.1).tag(cat.0)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(DS.surface)
                .listRowSeparatorTint(DS.sep)

                Section("色（任意）") {
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
            .navigationTitle("新規タグ作成")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("tag_create")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("作成") {
                        AppAnalytics.tap("tag_create.submit")
                        Task { await create() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isNameValid || isCreating)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        do {
            let tag = try await CommunityAPI.shared.createTag(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.isEmpty ? nil : description,
                category: selectedCategory.isEmpty ? nil : selectedCategory,
                color: selectedColor.isEmpty ? nil : selectedColor
            )
            onCreated?(tag)
            dismiss()
        } catch let error as CommunityAPIError {
            if case .rateLimited = error {
                errorMessage = "1日10件まで作成できます。明日試してください"
            } else {
                errorMessage = error.errorDescription ?? "作成に失敗しました"
            }
        } catch {
            errorMessage = "作成に失敗しました: \(error.localizedDescription)"
        }
    }
}
