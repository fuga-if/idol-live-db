import Foundation
import os

/// SongListView のデータ取得・絞り込みオーケストレーション担当。
///
/// 役割分担:
/// - **VM (ここ)**: ポート越しの曲取得 (`songReading`)、純粋 UseCase (`applySongMarkFilters`) による
///   絞り込み/ランキング、行アイコン用のマーク集合・回収数の bulk 取得、検索語クライアント絞り込みの
///   結果保持。タグ絞り込みの song_id 集合解決 (`CommunityAPI`) も持つ。
/// - **View 側**: フィルタ条件・ソート・表示モード・選択タグ等の UI 状態を保持し、
///   `SongListRequest` にまとめて VM へ渡す。
///
/// マーク集合の解決は `UserMarkService.shared` を直接読む (メソッド呼び出しは観測を張らないので
/// VM 文脈で問題ない。`@Observable` 観測が要るトグル UI は View 側のまま)。
@MainActor
@Observable
final class SongListViewModel {
    private(set) var songs: [SongWithArtists] = []
    /// `searchText` で絞り込んだ表示用キャッシュ (毎 body 評価で全曲走査しないため)。
    private(set) var displayedSongs: [SongWithArtists] = []
    private(set) var isLoading = false

    // 行アイコン用のマーク集合・回収数 (song_id ベース)。
    private(set) var collectedCounts: [String: Int] = [:]
    private(set) var favoriteSongIds: Set<String> = []
    private(set) var myPickSongIds: Set<String> = []
    private(set) var notedSongIds: Set<String> = []

    // タグ絞り込みの解決済み集合 (selectedTags から導出)。
    private(set) var tagSongIds: Set<String>?
    private(set) var tagVoteCounts: [String: Int] = [:]

    private var loadTask: Task<Void, Never>?
    private var currentTaskId: UUID = UUID()

    private let songReading: any SongReading
    private var markService: UserMarkService { UserMarkService.shared }

    nonisolated init(songReading: any SongReading = AppContainer.shared.songReading) {
        self.songReading = songReading
    }

    func scheduleLoad(_ request: SongListRequest, debounce: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            await load(request)
        }
    }

    func load(_ request: SongListRequest) async {
        let taskId = UUID()
        currentTaskId = taskId
        isLoading = true
        defer {
            if currentTaskId == taskId { isLoading = false }
        }
        do {
            try Task.checkCancellation()
            // 「その他」表示トグルを反映 (ブランド未選択時のみ効く)。
            var queryFilter = request.filter
            queryFilter.includeOtherBrand = request.showOtherBrand
            queryFilter.excludeLiveOnly = request.excludeLiveOnly
            var results = try await songReading.songs(
                filter: queryFilter, sortOrder: request.sortOrder, ascending: request.sortAscending)
            try Task.checkCancellation()
            // マーク集合を解決し、絞り込み+ランキングは純粋ロジックに委ねる。
            let ctx = try await markFilterContext(request)
            results = applySongMarkFilters(results, ctx)

            // アイドルアイコン用に performer idol を一括取得して merge
            let performerMap = (try? await songReading.songPerformerIdolsMap(songIds: results.map(\.song.id))) ?? [:]
            for i in results.indices {
                results[i].performerIdols = performerMap[results[i].song.id] ?? []
            }
            songs = results
            recomputeDisplayed(searchText: request.searchText)
            await refreshMarkDisplays()
        } catch is CancellationError {
            // キャンセル済み
        } catch {
            Logger.database.error("load_failed songs: \(error.localizedDescription)")
        }
    }

    private func markFilterContext(_ request: SongListRequest) async throws -> SongMarkFilterContext {
        var ctx = SongMarkFilterContext(collectFilter: request.collectFilter)
        if request.collectFilter != .all {
            ctx.collectedIds = markService.autoCollectedSongIds()
        }
        if request.myMarkFilter.requireFavorite {
            ctx.requireFavorite = true
            ctx.favoriteIds = Set(markService.allMarked(kind: .favorite, entity: .song))
        }
        if request.myMarkFilter.requireNote {
            ctx.requireNote = true
            ctx.noteIds = Set(markService.allMarked(kind: .note, entity: .song))
        }
        if request.myMarkFilter.requireMyPick {
            ctx.requireMyPick = true
            ctx.myPickSongIds = await myPickSongIdSet()
        }
        if let tagSongIds {
            ctx.tagSongIds = tagSongIds
            ctx.rankByTagVotes = request.selectedTagCount == 1
                && request.sortOrder == .titleKana && request.sortAscending == nil
            ctx.tagVoteCounts = tagVoteCounts
        }
        return ctx
    }

    /// `searchText` で songs をクライアント側フィルタし `displayedSongs` を更新する。
    /// songs 読み込み完了時と searchText 変化時にのみ呼ぶ。
    func recomputeDisplayed(searchText: String) {
        guard !searchText.isEmpty else {
            displayedSongs = songs
            return
        }
        let lower = searchText.lowercased()
        displayedSongs = songs.filter { sa in
            sa.song.title.lowercased().contains(lower) ||
            sa.song.titleKana?.lowercased().contains(lower) == true
        }
    }

    /// 一覧行アイコン用のマイマーク集合・回収数を bulk 取得する。
    /// 曲データ本体の再取得を伴わないので、タブ再表示時の軽量リフレッシュにも使う。
    func refreshMarkDisplays() async {
        favoriteSongIds = Set(markService.allMarked(kind: .favorite, entity: .song))
        notedSongIds = Set(markService.allMarked(kind: .note, entity: .song))
        myPickSongIds = await myPickSongIdSet()
        collectedCounts = (try? await songReading.songCollectedCounts()) ?? [:]
    }

    /// 担当アイドルが原唱に絡む曲の song_id 集合。担当未設定なら空集合。
    private func myPickSongIdSet() async -> Set<String> {
        let pickIdols = Set(markService.allMarked(kind: .myPick, entity: .idol))
        guard !pickIdols.isEmpty else { return [] }
        return (try? await songReading.songIdsWithAnyArtist(idolIds: pickIdols)) ?? []
    }

    /// タグ絞り込みの song_id 集合を解決する。複数選択時は各タグの song_id 集合の **積集合** (AND)。
    /// 空なら絞り込み解除。単一タグ時のみ票数バッジ用に voteCount を保持する。
    func resolveTagFilter(_ tags: [CommunityTag]) async {
        guard !tags.isEmpty else {
            tagSongIds = nil
            tagVoteCounts = [:]
            return
        }
        var intersection: Set<String>?
        var counts: [String: Int] = [:]
        for tag in tags {
            let tagSongs = (try? await CommunityAPI.shared.tag(id: tag.id))?.songs ?? []
            let ids = Set(tagSongs.map(\.songId))
            intersection = intersection.map { $0.intersection(ids) } ?? ids
            if tags.count == 1 {
                counts = Dictionary(tagSongs.map { ($0.songId, $0.voteCount) }, uniquingKeysWith: { a, _ in a })
            }
        }
        tagSongIds = intersection ?? []
        tagVoteCounts = counts
    }
}

/// SongListView の現在の UI 状態を、データ取得に必要な純粋値へまとめたリクエスト。
struct SongListRequest {
    var filter: SongSearchFilter
    var sortOrder: SongSortOrder
    var sortAscending: Bool?
    var showOtherBrand: Bool
    /// ライブ履歴のみのファントム曲を除外するか (曲一覧ブラウズ用)。
    var excludeLiveOnly: Bool
    var collectFilter: SongCollectFilter
    var myMarkFilter: SongMyMarkFilter
    var selectedTagCount: Int
    var searchText: String
}
