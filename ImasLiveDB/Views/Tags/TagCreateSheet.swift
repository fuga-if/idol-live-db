import SwiftUI

/// タグの作成先プール。曲タグ (tags) とアイドルタグ (idol_tag_master) は別マスタなので、
/// UI は共通のままこのフラグで作成 API・カテゴリ候補だけ切り替える。
enum TagDomain {
    case song
    case idol
}

/// タグカテゴリの候補。ドメインごとに語彙が異なる (曲=ムード/シーン等、アイドル=性格/魅力等) ので
/// tags/idol_tag_master 分離にあわせてここも分ける。
enum TagCategoryOptions {
    static let song: [(value: String, label: String)] = [
        ("mood", "ムード"), ("scene", "シーン"), ("special", "特別"), ("free", "フリー"),
    ]
    static let idol: [(value: String, label: String)] = [
        ("personality", "性格"), ("charm", "魅力・外見"), ("talent", "特技"), ("free", "フリー"),
    ]

    static func options(for domain: TagDomain) -> [(value: String, label: String)] {
        switch domain {
        case .song: return song
        case .idol: return idol
        }
    }
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

    private var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 1 && trimmed.count <= 30
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp6) {
                    fieldSection(header: "タグ名", counter: "\(name.trimmingCharacters(in: .whitespaces).count) / 30文字", counterIsError: !isNameValid && !name.isEmpty) {
                        TextField("例: エモい", text: $name)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink)
                            .autocorrectionDisabled()
                            .onAppear { if name.isEmpty { name = initialName } }
                            .onChange(of: name) { _, new in
                                if new.count > 30 { name = String(new.prefix(30)) }
                            }
                    }

                    fieldSection(header: "説明文（任意）", counter: nil) {
                        TextField("どんな時に使うタグか（任意）", text: $description, axis: .vertical)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink)
                            .lineLimit(2...5)
                    }

                    VStack(alignment: .leading, spacing: DS.sp3) {
                        ImasSectionHeader(title: "カテゴリ（任意）", tight: true)
                        FlowLayout(spacing: DS.sp2) {
                            categoryChip(value: "", label: "なし")
                            ForEach(TagCategoryOptions.options(for: domain), id: \.value) { cat in
                                categoryChip(value: cat.value, label: cat.label)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.sp3) {
                        ImasSectionHeader(title: "色（任意）", tight: true)
                        ImasListContainer {
                            TagColorPicker(selectedHex: $selectedColor)
                                .padding(.horizontal, DS.sp4)
                                .padding(.vertical, DS.sp3)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.imasFootnote)
                            .foregroundStyle(DS.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp4)
                .padding(.bottom, DS.sp7)
            }
            .background(DS.bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
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

    // MARK: - Pieces

    @ViewBuilder
    private func fieldSection<Content: View>(
        header: String, counter: String?, counterIsError: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: header, tight: true)
            ImasListContainer {
                content()
                    .padding(.horizontal, DS.sp4)
                    .padding(.vertical, DS.sp3)
            }
            if let counter {
                Text(counter)
                    .font(.imasCaption)
                    .foregroundStyle(counterIsError ? DS.danger : DS.ink3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func categoryChip(value: String, label: String) -> some View {
        let on = selectedCategory == value
        return Button { selectedCategory = value } label: {
            Text(label)
                .font(.imasScaled(13.5, weight: .semibold))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .foregroundStyle(on ? Color.white : DS.ink2)
                .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(DS.fill), in: Capsule())
        }
        .buttonStyle(.plain)
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
