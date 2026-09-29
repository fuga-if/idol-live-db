import SwiftUI

/// タグの作成先プール。曲タグ (tags)・アイドルタグ (idol_tag_master)・ユニットタグ
/// (unit_tag_master) は別マスタなので、UI は共通のままこのフラグで作成 API・カテゴリ候補だけ切り替える。
enum TagDomain {
    case song
    case idol
    case unit
}

/// タグカテゴリの候補。ドメインごとに語彙が異なる (曲=ムード/シーン等、アイドル=性格/魅力等) ので
/// tags/idol_tag_master/unit_tag_master 分離にあわせてここも分ける。
/// 語と並びはコアの vocabulary。
enum TagCategoryOptions {
    static let song = pairs(Vocab.table.songTagCategories)
    static let idol = pairs(Vocab.table.idolTagCategories)
    static let unit = pairs(Vocab.table.unitTagCategories)

    private static func pairs(_ terms: [VocabularyTerm]) -> [(value: String, label: String)] {
        terms.map { ($0.value, $0.label) }
    }

    static func options(for domain: TagDomain) -> [(value: String, label: String)] {
        switch domain {
        case .song: return song
        case .idol: return idol
        case .unit: return unit
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

    private var isNameValid: Bool { InputLimits.isAcceptable(.tagName, name) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp6) {
                    fieldSection(header: "タグ名", counter: InputLimits.counter(.tagName, name), counterIsError: !isNameValid && !name.isEmpty) {
                        TextField("例: エモい", text: $name)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink)
                            .autocorrectionDisabled()
                            .onAppear { if name.isEmpty { name = initialName } }
                            .onChange(of: name) { _, new in
                                let clamped = InputLimits.clamp(.tagName, new)
                                if clamped != new { name = clamped }
                            }
                    }

                    fieldSection(header: "説明文（任意）", counter: InputLimits.counter(.tagDescription, description), counterIsError: false) {
                        TextField("どんな時に使うタグか（任意）", text: $description, axis: .vertical)
                            .font(.imasSubhead)
                            .foregroundStyle(DS.ink)
                            .lineLimit(2...5)
                            .onChange(of: description) { _, new in
                                let clamped = InputLimits.clamp(.tagDescription, new)
                                if clamped != new { description = clamped }
                            }
                    }

                    VStack(alignment: .leading, spacing: DS.sp3) {
                        ImasSectionHeader(title: "カテゴリ（任意）", tight: true)
                        FlowLayout(spacing: DS.sp2) {
                            categoryChip(value: "", label: Vocab.table.tagCategoryNoneLabel)
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
        ImasFilterChip(text: label, isSelected: selectedCategory == value) {
            selectedCategory = value
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
            let writing = AppContainer.shared.communityTagWriting
            switch domain {
            case .song:
                tag = try await writing.createTag(name: trimmedName, description: desc, category: cat, color: color)
            case .idol:
                tag = try await writing.createIdolTag(name: trimmedName, description: desc, category: cat, color: color)
            case .unit:
                tag = try await writing.createUnitTag(name: trimmedName, description: desc, category: cat, color: color)
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
