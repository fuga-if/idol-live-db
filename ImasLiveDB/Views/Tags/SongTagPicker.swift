import SwiftUI

struct SongTagPicker: View {
    @Environment(\.dismiss) private var dismiss
    /// タグ色なしチップの背景 .accentColor (= 推しカラー tint) を実色解決するために保持。
    @Environment(\.self) private var environment
    let songId: String
    /// 対象曲（どの曲にタグを付けているか明示する見出し用）。汎用の SongRowView で表示する。
    var song: SongWithArtists? = nil
    var onApplied: (() -> Void)?

    @State private var searchText = ""
    @State private var tags: [CommunityTag] = []
    @State private var myTagIds: Set<String> = []
    @State private var selectedTagIds: Set<String> = []
    /// 選択された CommunityTag の実体辞書。検索で tags が差し替わっても選択済みを保持する。
    @State private var selectedTagsById: [String: CommunityTag] = [:]
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var showCreateSheet = false
    /// 適用完了後のシェア導線。非 nil で完了 + シェア画面に切り替わる。
    @State private var appliedShare: TagShareContext?
    @State private var applyError: String?

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var exactMatchExists: Bool { tags.contains { $0.name == trimmedSearch } }

    var body: some View {
        NavigationStack {
            if let share = appliedShare {
                TagShareCompletionView(context: share, onClose: { dismiss() })
                    .navigationTitle("タグを追加")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") { dismiss() }
                        }
                    }
            } else {
                pickerContent
            }
        }
    }

    private var pickerContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp6) {
                    // 対象曲を汎用の曲行コンポーネントで表示 (どの曲に付けているか明示)。
                    if let song {
                        ImasListContainer {
                            SongRowView(item: song)
                        }
                    }

                    // 検索語をそのまま新規タグ名にできる導線 (デザインの「このタグを作成」)。
                    if !trimmedSearch.isEmpty && !exactMatchExists {
                        Button {
                            AppAnalytics.tap("song_tag_picker.create_from_search")
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
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, DS.sp5)
                        } else if tags.isEmpty {
                            Text("タグが見つかりません").font(.imasFootnote).foregroundStyle(DS.ink3)
                        } else {
                            FlowLayout(spacing: DS.sp2) {
                                ForEach(tags) { tag in tagChip(tag) }
                            }
                        }
                    }

                    // 作成だけしたい場合のフォールバック (色やカテゴリも付けたいとき)。
                    Button {
                        AppAnalytics.tap("song_tag_picker.create_full")
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
            .trackScreen("song_tag_picker")
            .searchable(text: $searchText, prompt: "タグを検索 / 新規作成")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("追加") {
                        AppAnalytics.tap("song_tag_picker.apply")
                        Task { await applyTags() }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedTagIds.isEmpty || isApplying)
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                TagCreateSheet(onCreated: { newTag in
                    tags.insert(newTag, at: 0)
                    selectedTagIds.insert(newTag.id)
                    selectedTagsById[newTag.id] = newTag
                }, initialName: trimmedSearch)
            }
            .alert("タグの追加に失敗しました", isPresented: Binding(get: { applyError != nil }, set: { if !$0 { applyError = nil } })) {
                Button("OK") { applyError = nil }
            } message: {
                Text(applyError ?? "")
            }
            .task { await loadData() }
            .onChange(of: searchText) { _, _ in Task { await loadTags() } }
    }

    /// タグ chip。未適用=ニュートラル / 選択中=タグ色 / 適用済=タグ色+チェック(無効)。
    @ViewBuilder
    private func tagChip(_ tag: CommunityTag) -> some View {
        let applied = myTagIds.contains(tag.id)
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

    /// タグ色の上に乗せる前景色を WCAG コントラストで黒/白から選ぶ。
    /// タグ色なし時の背景 .accentColor は推しカラー (黄色・白系もあり得る) なので、
    /// 白文字固定にせず Environment で実色解決してから判定する。
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

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        async let tagResult = CommunityAPI.shared.tags(sort: "popular")
        async let songTagResult = CommunityAPI.shared.songTags(songId: songId)
        tags = (try? await tagResult) ?? []
        if let result = try? await songTagResult {
            myTagIds = Set(result.myTagIds)
        }
    }

    private func loadTags() async {
        tags = (try? await CommunityAPI.shared.tags(search: searchText, sort: "popular")) ?? []
    }

    private func applyTags() async {
        guard !selectedTagIds.isEmpty else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            try await CommunityAPI.shared.applySongTags(songId: songId, tagIds: Array(selectedTagIds))
            onApplied?()
            // 即 dismiss せず、完了 + シェア導線に切り替える (閉じるのはユーザー操作)。
            let appliedTags = selectedTagIds.compactMap { selectedTagsById[$0] }
            appliedShare = await makeShareContext(applied: appliedTags)
        } catch {
            applyError = (error as? APIClientError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 付与完了シェアの内容を組み立てる。seed は曲のブランドカラー → 先頭タグ色。
    /// 曲・ブランドの引き当ては SongReading / BrandReading ポート経由 (AppDatabase 直叩きを排除)。
    private func makeShareContext(applied: [CommunityTag]) async -> TagShareContext {
        let resolvedSong: Song?
        if let loaded = song?.song {
            resolvedSong = loaded
        } else {
            resolvedSong = try? await AppContainer.shared.songReading.song(id: songId)
        }
        var brandColor: String?
        if let bid = resolvedSong?.brandId {
            brandColor = (try? await AppContainer.shared.brandReading.brands())?.first { $0.id == bid }?.color
        }
        return TagShareContext(
            songTitle: resolvedSong?.title ?? "この曲",
            artistNames: song?.artistNames ?? resolvedSong?.singerLabel,
            tags: applied,
            seed: ColorMath.firstValidHex(brandColor, applied.first?.color?.rawValue),
            artworkUrl: resolvedSong?.artworkUrl
        )
    }
}
