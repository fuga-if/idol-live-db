import SwiftUI

/// 曲一覧をコミュニティタグで絞り込むためのタグ**複数選択**シート。
/// 「完了」で onDone(選択タグ配列) を呼ぶ。複数選択時は AND (全タグを含む曲) で絞る想定。
struct TagFilterPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onDone: ([CommunityTag]) -> Void

    @State private var tags: [CommunityTag] = []
    /// 選択中タグ。検索で一覧から消えても保持するため id ではなくオブジェクトで持つ。
    @State private var selected: [CommunityTag]
    @State private var query = ""
    @State private var isLoading = true

    init(initialSelection: [CommunityTag], onDone: @escaping ([CommunityTag]) -> Void) {
        self.onDone = onDone
        _selected = State(initialValue: initialSelection)
    }

    private func isSelected(_ tag: CommunityTag) -> Bool {
        selected.contains { $0.id == tag.id }
    }
    private func toggle(_ tag: CommunityTag) {
        if let idx = selected.firstIndex(where: { $0.id == tag.id }) {
            selected.remove(at: idx)
        } else {
            selected.append(tag)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selected.isEmpty {
                    Section {
                        Text(selected.map(\.name).joined(separator: " ＋ "))
                            .font(.imasCaption)
                            .foregroundStyle(DS.ink2)
                    } header: {
                        Text("選択中 (\(selected.count)) — すべてを含む曲に絞り込み")
                    }
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
                Section {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                    } else if tags.isEmpty {
                        Text("タグがありません").foregroundStyle(DS.ink2)
                            .listRowBackground(DS.surface)
                    } else {
                        ForEach(Array(tags.enumerated()), id: \.element.id) { idx, tag in
                            Button {
                                AppAnalytics.tap("tag_filter.toggle_tag")
                                toggle(tag)
                            } label: {
                                HStack(spacing: 8) {
                                    // 検索していない時は人気順そのものなので順位バッジを出す。
                                    if query.isEmpty {
                                        TagRankBadge(rank: idx + 1)
                                    }
                                    if let color = tag.color {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(hexColor: color))
                                            .frame(width: 14, height: 14)
                                    }
                                    Text(tag.name).foregroundStyle(DS.ink)
                                    Spacer()
                                    if let uses = tag.totalUses, uses > 0 {
                                        Text("\(uses)曲").font(.imasCaption).foregroundStyle(DS.ink2)
                                    }
                                    if isSelected(tag) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .listRowBackground(DS.surface)
                            .listRowSeparatorTint(DS.sep)
                        }
                    }
                } header: {
                    Text(query.isEmpty ? "人気タグランキング" : "検索結果")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .searchable(text: $query, prompt: "タグ名で検索")
            .navigationTitle("タグで絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        AppAnalytics.tap("tag_filter.done")
                        onDone(selected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task(id: query) { await load() }
            .trackScreen("tag_filter")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        tags = (try? await CommunityAPI.shared.tags(search: query, sort: "popular", limit: 100)) ?? []
    }
}
