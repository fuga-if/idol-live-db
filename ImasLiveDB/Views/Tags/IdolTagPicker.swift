import SwiftUI

/// アイドルにタグを付ける picker。SongTagPicker と同じ見た目・操作感だが、タグは曲とは
/// 別プール (idol_tag_master) から検索・作成する。曲版にある付与完了シェア導線は無く、
/// 付与したらそのまま閉じる。
struct IdolTagPicker: View {
    @Environment(\.dismiss) private var dismiss
    /// タグ色なしチップの背景 .accentColor (= 推しカラー tint) を実色解決するために保持。
    @Environment(\.self) private var environment
    let idol: Idol
    var onApplied: (() -> Void)?

    @State private var vm: IdolTagPickerViewModel
    @State private var searchText = ""
    @State private var selectedTagIds: Set<String> = []
    /// 選択された CommunityTag の実体辞書。検索で tags が差し替わっても選択済みを保持する。
    @State private var selectedTagsById: [String: CommunityTag] = [:]
    @State private var showCreateSheet = false

    init(idol: Idol, onApplied: (() -> Void)? = nil) {
        self.idol = idol
        self.onApplied = onApplied
        _vm = State(initialValue: IdolTagPickerViewModel(idolId: idol.id))
    }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var exactMatchExists: Bool { vm.tags.contains { $0.name == trimmedSearch } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp6) {
                    // 対象アイドルを明示する見出し行。
                    ImasListContainer {
                        HStack(spacing: DS.sp3) {
                            IdolAvatarView(idol: idol, size: 40)
                            Text(idol.name).font(.imasSubhead.weight(.semibold)).foregroundStyle(DS.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, DS.sp4).padding(.vertical, 10)
                    }

                    // 検索語をそのまま新規タグ名にできる導線。
                    if !trimmedSearch.isEmpty && !exactMatchExists {
                        Button {
                            AppAnalytics.tap("idol_tag_picker.create_from_search")
                            showCreateSheet = true
                        } label: {
                            HStack(spacing: DS.sp2) {
                                Image(systemName: "plus.circle.fill").font(.imasScaled( 18, weight: .semibold))
                                Text("「\(trimmedSearch)」を作成").font(.imasSubhead.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, DS.sp4).padding(.vertical, 13)
                            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: DS.sp3) {
                        Text(trimmedSearch.isEmpty ? "よく使われるタグ" : "候補")
                            .font(.imasFootnote.weight(.semibold))
                            .foregroundStyle(DS.ink3)
                        if vm.isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, DS.sp5)
                        } else if vm.tags.isEmpty {
                            Text("タグが見つかりません").font(.imasFootnote).foregroundStyle(DS.ink3)
                        } else {
                            FlowLayout(spacing: DS.sp2) {
                                ForEach(vm.tags) { tag in tagChip(tag) }
                            }
                        }
                    }

                    Button {
                        AppAnalytics.tap("idol_tag_picker.create_full")
                        showCreateSheet = true
                    } label: {
                        HStack(spacing: DS.sp2) {
                            Image(systemName: "plus").font(.imasScaled( 14, weight: .semibold))
                            Text("色やカテゴリを付けて新規作成").font(.imasFootnote.weight(.semibold))
                        }
                        .foregroundStyle(DS.ink2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(DS.sp5)
            }
            .background(DS.bg)
            .navigationTitle("タグを追加")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("idol_tag_picker")
            .searchable(text: $searchText, prompt: "タグを検索 / 新規作成")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("追加") {
                        guard !vm.isApplying else { return }
                        AppAnalytics.tap("idol_tag_picker.apply")
                        Task {
                            if await vm.applyTags(selectedTagIds) {
                                onApplied?()
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedTagIds.isEmpty || vm.isApplying)
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                TagCreateSheet(domain: .idol, onCreated: { newTag in
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

    /// タグ chip。未適用=ニュートラル / 選択中=タグ色 / 適用済=タグ色+チェック(無効)。
    @ViewBuilder
    private func tagChip(_ tag: CommunityTag) -> some View {
        let applied = vm.myTagIds.contains(tag.id)
        let selected = selectedTagIds.contains(tag.id)
        let on = applied || selected
        let tagColor = tag.color.map { Color(hexColor: $0) } ?? .accentColor
        Button {
            if applied { return }
            if selected {
                selectedTagIds.remove(tag.id)
                selectedTagsById.removeValue(forKey: tag.id)
            } else {
                selectedTagIds.insert(tag.id)
                selectedTagsById[tag.id] = tag
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: applied ? "checkmark" : (selected ? "checkmark.circle.fill" : "plus"))
                    .font(.imasScaled( 12, weight: .bold))
                Text(tag.name).font(.imasScaled( 13.5, weight: .semibold))
                if let uses = tag.totalUses, uses > 0 {
                    Text("\(uses)").font(.imasDisplay(11, weight: .semibold)).opacity(0.7)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .foregroundStyle(on ? onColor(tag.color, chipBackground: tagColor) : DS.ink2)
            .background(on ? AnyShapeStyle(tagColor) : AnyShapeStyle(DS.fill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(applied)
        .opacity(applied ? 0.7 : 1)
    }

    /// タグ色の上に乗せる前景色を WCAG コントラストで黒/白から選ぶ (SongTagPicker と同ロジック)。
    private func onColor(_ hex: HexColor?, chipBackground: Color) -> Color {
        if let raw = hex?.rawValue, ColorMath.normalizedHex(raw) != nil {
            return ColorMath.onColor(ColorMath.hexToRgb(raw))
        }
        let resolved = chipBackground.resolve(in: environment)
        return ColorMath.onColor(ColorMath.RGB(
            r: ColorMath.clamp(Double(resolved.red), 0, 1) * 255,
            g: ColorMath.clamp(Double(resolved.green), 0, 1) * 255,
            b: ColorMath.clamp(Double(resolved.blue), 0, 1) * 255
        ))
    }

}
