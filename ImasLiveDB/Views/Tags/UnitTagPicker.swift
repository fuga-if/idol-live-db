import SwiftUI

/// ユニットにタグを付ける picker。IdolTagPicker と同じ見た目・操作感だが、タグは曲/アイドルとは
/// 別プール (unit_tag_master) から検索・作成する。付与したらそのまま閉じる。
struct UnitTagPicker: View {
    @Environment(\.dismiss) private var dismiss
    /// タグ色なしチップの背景 .accentColor (= 推しカラー tint) を実色解決するために保持。
    let unit: Unit
    var onApplied: (() -> Void)?

    @State private var vm: UnitTagPickerViewModel
    @State private var searchText = ""
    @State private var selectedTagIds: Set<String> = []
    /// 選択された CommunityTag の実体辞書。検索で tags が差し替わっても選択済みを保持する。
    @State private var selectedTagsById: [String: CommunityTag] = [:]
    @State private var showCreateSheet = false

    init(unit: Unit, onApplied: (() -> Void)? = nil) {
        self.unit = unit
        self.onApplied = onApplied
        _vm = State(initialValue: UnitTagPickerViewModel(unitId: unit.id))
    }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var exactMatchExists: Bool { vm.tags.contains { $0.name == trimmedSearch } }

    var body: some View {
        NavigationStack {
            ImasFormPage {
                // 対象ユニットを明示する見出し行。
                ImasCardList {
                    ImasRow(
                        title: unit.displayName,
                        leading: .custom(AnyView(UnitAvatarView(unit: unit, size: 40)), width: 40),
                        density: .compact
                    )
                }

                // 検索語をそのまま新規タグ名にできる導線。
                if !trimmedSearch.isEmpty && !exactMatchExists {
                    ImasCardList {
                        ImasActionRow(title: "「\(trimmedSearch)」を作成", systemImage: "plus.circle.fill") {
                            AppAnalytics.tap("unit_tag_picker.create_from_search")
                            showCreateSheet = true
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DS.Space.header) {
                    ImasSectionHeader(trimmedSearch.isEmpty ? "よく使われるタグ" : "候補", style: .small)
                    if vm.isLoading {
                        ImasInlineLoading()
                    } else if vm.tags.isEmpty {
                        ImasNote("タグが見つかりません")
                    } else {
                        ImasChipFlow {
                            ForEach(vm.tags) { tag in tagChip(tag) }
                        }
                    }
                }

                ImasActionRow(title: "色やカテゴリを付けて新規作成", systemImage: "plus") {
                    AppAnalytics.tap("unit_tag_picker.create_full")
                    showCreateSheet = true
                }
            }
            .navigationTitle("タグを追加")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("unit_tag_picker")
            .searchable(text: $searchText, prompt: "タグを検索 / 新規作成")
            .imasSheetToolbar(.submit(canSubmit: !selectedTagIds.isEmpty && !vm.isApplying, onCancel: { dismiss() }, onSubmit: {
                guard !vm.isApplying else { return }
                AppAnalytics.tap("unit_tag_picker.apply")
                Task {
                    if await vm.applyTags(selectedTagIds) {
                        onApplied?()
                        dismiss()
                    }
                }
            }))
            .sheet(isPresented: $showCreateSheet) {
                TagCreateSheet(domain: .unit, onCreated: { newTag in
                    vm.insertCreated(newTag)
                    selectedTagIds.insert(newTag.id)
                    selectedTagsById[newTag.id] = newTag
                }, initialName: trimmedSearch)
            }
            .alert("タグの追加に失敗しました", isPresented: Binding(get: { vm.applyError != nil }, set: { if !$0 { vm.applyError = nil } })) {
                Button("OK") { vm.applyError = nil }
            } message: {
                Text(vm.applyError ?? "")
            }
            .task { await vm.loadData() }
            .onChange(of: searchText) { _, new in vm.scheduleSearch(new) }
        }
    }

    @ViewBuilder
    private func tagChip(_ tag: CommunityTag) -> some View {
        TagSelectChip(
            tag: tag,
            isApplied: vm.myTagIds.contains(tag.id),
            isSelected: selectedTagIds.contains(tag.id)
        ) {
            if selectedTagIds.contains(tag.id) {
                selectedTagIds.remove(tag.id)
                selectedTagsById.removeValue(forKey: tag.id)
            } else {
                selectedTagIds.insert(tag.id)
                selectedTagsById[tag.id] = tag
            }
        }
    }

}
