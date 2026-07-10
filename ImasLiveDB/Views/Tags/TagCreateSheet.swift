import SwiftUI

/// タグの作成先プール。曲タグ (tags) とアイドルタグ (idol_tag_master) は別マスタなので、
/// UI は共通のままこのフラグで作成 API だけ切り替える。
enum TagDomain {
    case song
    case idol
}

struct TagCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    var domain: TagDomain = .song
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
                        // タップ直後に同期的にガードを立てる (SongTagPicker.apply と同じ理由)。
                        guard !isCreating else { return }
                        AppAnalytics.tap("tag_create.submit")
                        isCreating = true
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
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let desc = description.isEmpty ? nil : description
            let cat = selectedCategory.isEmpty ? nil : selectedCategory
            let color = selectedColor.isEmpty ? nil : selectedColor
            let tag: CommunityTag
            switch domain {
            case .song:
                tag = try await CommunityAPI.shared.createTag(name: trimmedName, description: desc, category: cat, color: color)
            case .idol:
                tag = try await CommunityAPI.shared.createIdolTag(name: trimmedName, description: desc, category: cat, color: color)
            }
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
