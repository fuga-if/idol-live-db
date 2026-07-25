import SwiftUI

struct SongTagPicker: View {
    @Environment(\.dismiss) private var dismiss
    /// タグ色なしチップの背景 .accentColor (= 推しカラー tint) を実色解決するために保持。
    let songId: String
    /// 対象曲（どの曲にタグを付けているか明示する見出し用）。汎用の SongRowView で表示する。
    var song: SongWithArtists?
    var onApplied: (() -> Void)?

    @State private var vm: SongTagPickerViewModel
    @State private var searchText = ""
    @State private var selectedTagIds: Set<String> = []
    /// 選択された CommunityTag の実体辞書。検索で tags が差し替わっても選択済みを保持する。
    @State private var selectedTagsById: [String: CommunityTag] = [:]
    @State private var showCreateSheet = false
    /// 適用完了後のシェア導線。非 nil で完了 + シェア画面に切り替わる。
    @State private var appliedShare: TagShareContext?

    init(songId: String, song: SongWithArtists? = nil, onApplied: (() -> Void)? = nil) {
        self.songId = songId
        self.song = song
        self.onApplied = onApplied
        _vm = State(initialValue: SongTagPickerViewModel(songId: songId))
    }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var exactMatchExists: Bool { vm.tags.contains { $0.name == trimmedSearch } }

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
                            .foregroundStyle(DS.sys)
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
                        // タップ直後に同期的にガードを立てる。Task 起動〜isApplying=true までの
                        // 間隙での連打による二重送信を防ぐ (サーバは冪等だが UI 上のフラッシュ防止)。
                        guard !vm.isApplying else { return }
                        AppAnalytics.tap("song_tag_picker.apply")
                        Task {
                            if let share = await vm.applyTags(selectedTagIds, selectedTagsById: selectedTagsById, song: song) {
                                onApplied?()
                                // 即 dismiss せず、完了 + シェア導線に切り替える (閉じるのはユーザー操作)。
                                appliedShare = share
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedTagIds.isEmpty || vm.isApplying)
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                TagCreateSheet(onCreated: { newTag in
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
