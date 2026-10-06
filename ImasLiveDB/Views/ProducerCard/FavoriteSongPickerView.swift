import SwiftUI

/// お気に入りの曲から、載せる曲を選ぶ画面 (push で開く)。プロフィール帳の好きな曲に使い、
/// P名刺の編集からも同じ部品で開けるように、保存先は呼び出し側に任せる (`onChange` に曲 id の並びを渡す)。
///
/// 上は載せる曲 (選んだ順。引いて並べ替え、左に引くと外す)、下はお気に入りの曲すべて (付けた新しい順。
/// 押すと載せる / 外す)。お気に入りは何百曲にもなるので曲名で絞る (照合はコアの `TextSearchCatalog`)。
/// 上限・まだ選んでいないときの既定・お気に入りから外れた曲を抜くのはコア (`favoriteSongPicks`)。
struct FavoriteSongPickerView: View {
    /// 今の選択 (nil はまだ選んでいない)。
    let chosen: [String]?
    /// 選び直したとき (曲 id、載せる順)。
    let onChange: ([String]) -> Void

    @State private var current: [String]?
    @State private var favorites: [FavoriteSong] = []
    @State private var catalog: TextSearchCatalog?
    @State private var query = ""
    @State private var loaded = false

    init(chosen: [String]?, onChange: @escaping ([String]) -> Void) {
        self.chosen = chosen
        self.onChange = onChange
        _current = State(initialValue: chosen)
    }

    private var inputs: [ProfileSongInput] { favorites.map(\.input) }

    var body: some View {
        Group {
            if !loaded {
                ImasLoadingState()
            } else if favorites.isEmpty {
                ImasPage {
                    ImasCard {
                        ImasEmptyState(
                            systemImage: "heart",
                            title: "お気に入りの曲がありません",
                            message: "曲の一覧や詳細でお気に入りに付けた曲から選べます。"
                        )
                    }
                }
            } else {
                list(favoriteSongPicks(chosen: current, favorites: inputs))
            }
        }
        .navigationTitle("載せる曲")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            await load()
        }
        .trackScreen("favorite_song_picker")
    }

    private func list(_ picks: FavoriteSongPicks) -> some View {
        let byId = Dictionary(favorites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let picked = picks.picked.compactMap { byId[$0.id] }
        let pickedIds = Set(picked.map(\.id))
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let candidates = trimmed.isEmpty ? favorites : (catalog?.filter(favorites, needle: trimmed) ?? favorites)
        return List {
            if trimmed.isEmpty {
                ImasListSection("載せる曲", count: "\(picked.count) / \(picks.max)",
                                footer: picks.chosenByHand
                                    ? "載せる順に並びます。引いて並べ替え、左に引くと外します。"
                                    : "まだ選んでいないので、お気に入りに付けた新しい順に載せています。選び直すとその順になります。") {
                    if picked.isEmpty {
                        Text("下のお気に入りの曲から選んでください。")
                            .imasText(.note)
                    }
                    ForEach(picked) { fav in
                        ImasSongRow(song: fav.song, playsPreview: false, density: .compact)
                            .imasSwipe(trailing: [ImasSwipeAction(.delete, title: "外す") { toggle(fav.id) }])
                    }
                    .onMove { from, to in
                        var ids = picked.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        set(favoriteSongNormalize(ids: ids, favorites: inputs))
                    }
                }
            }
            ImasListSection("お気に入りの曲", count: "\(candidates.count)曲",
                            footer: picks.full ? "載せられるのは \(picks.max) 曲までです。足すときは先にどれかを外してください。" : nil) {
                ForEach(candidates) { fav in
                    let isPicked = pickedIds.contains(fav.id)
                    let locked = picks.full && !isPicked
                    // 行は Button で包まない (包むと行の余白の指定が List に届かず、上の区画の行とずれる)。
                    ImasSongRow(song: fav.song, playsPreview: false,
                                trailing: .custom(AnyView(ImasSelectionMark(isSelected: isPicked))),
                                density: .compact)
                        .contentShape(Rectangle())
                        .onTapGesture { if !locked { toggle(fav.id) } }
                        .opacity(locked ? 0.45 : 1)
                        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .imasForm()
        .searchable(text: $query, prompt: "曲名で検索")
    }

    private func toggle(_ id: String) {
        AppAnalytics.tap("favorite_song_picker.toggle")
        set(favoriteSongToggle(chosen: current, favorites: inputs, songId: id))
    }

    private func set(_ ids: [String]) {
        guard ids != current else { return }
        current = ids
        onChange(ids)
    }

    private func load() async {
        let loadedFavorites = await FavoriteSongSource.load()
        // 並びはコア (付けた新しい順)。索引はこの並びで 1 回だけ組む。
        let order = favoriteSongPicks(chosen: nil, favorites: loadedFavorites.map(\.input)).favorites.map(\.id)
        let byId = Dictionary(loadedFavorites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        favorites = order.compactMap { byId[$0] }
        catalog = TextSearchCatalog(fieldsPerItem: favorites.map { [$0.song.title, $0.song.titleKana] })
        loaded = true
    }
}
