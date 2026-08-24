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
    private(set) var songs: [SongWithArtists] = [] {
        didSet { rebuildSearchIndex() }
    }
    /// `searchText` で絞り込んだ表示用キャッシュ (毎 body 評価で全曲走査しないため)。
    private(set) var displayedSongs: [SongWithArtists] = []
    private(set) var isLoading = false

    /// `songs` と同じ並びの検索用インデックス。スコープごとに 1 本ずつ前処理して持つ。
    ///
    /// 打鍵ごとに `title.lowercased().contains(...)` を全曲ぶん回すと、2,000 曲で
    /// 1 打鍵 1.4ms 掛かっていた (`String` は書記素クラスタ単位で走るため日本語で遅い)。
    /// 読み込み時に小文字化した UTF-8 バイト列を作っておけば、3 スコープぶん数えても
    /// 0.1ms で済む。詳しい実測は `TextSearchIndex` のコメント。
    private var searchIndex: [SongScopeIndex] = []

    /// 1 曲ぶんの、手元で判定できるスコープの索引。
    private struct SongScopeIndex {
        let title: TextSearchIndex
        let performer: TextSearchIndex
        let creator: TextSearchIndex

        func index(for scope: SongSearchMode) -> TextSearchIndex? {
            switch scope {
            case .title:     title
            case .performer: performer
            case .creator:   creator
            case .lyrics:    nil   // サーバ側。手元では判定できない
            }
        }
    }

    private func rebuildSearchIndex() {
        searchIndex = songs.map { item in
            let song = item.song
            return SongScopeIndex(
                title: TextSearchIndex([song.title, song.titleKana]),
                // ユニット名・歌唱者表記・出演アイドル (よみ含む) を横並びに見る。
                // 「ミリオンスターズ」でも「春日未来」でも当たってほしいので、
                // どれか 1 つに寄せられない。
                performer: TextSearchIndex(
                    [song.unitName, song.singerLabel, item.artistNames]
                        + item.performerIdols.flatMap { [$0.name, $0.nameKana] }),
                creator: TextSearchIndex([song.lyricist, song.composer, song.arranger]))
        }
    }

    /// いま効いている絞り込みの中で、**表示中でない**スコープに何件当たるか。
    ///
    /// 結果は 1 スコープぶんに保ったまま「アイドル名でも 8 件ある」と伝えるためのもの。
    /// `songs` は既にブランド絞り込み等を通った後なので、ここの数字はそのまま
    /// 切り替えた後の件数と一致する。歌詞は含まない (D1 を叩かないと分からず、
    /// 数えるだけでクエリを消費する)。
    ///
    /// ⚠️ 計算済みの値を持つこと。View の計算プロパティにすると `body` 評価のたびに
    /// 2,000 曲を走査する (打鍵のたび・シート開閉のたび・行タップのたび)。
    private(set) var otherScopeCounts: [SongSearchMode: Int] = [:]

    // 行アイコン用のマーク集合・回収数 (song_id ベース)。
    private(set) var collectedCounts: [String: Int] = [:]
    /// song_id → 全公演での披露回数。
    ///
    /// 「披露回数順 / 回収率順」で並べている時だけ読む。それ以外の並びでは行に出さないので、
    /// 取っても捨てるだけ (タブを開くたびに setlist_items 全体を数える必要はない)。
    private(set) var performanceCounts: [String: Int] = [:]
    private(set) var favoriteSongIds: Set<String> = []
    private(set) var myPickSongIds: Set<String> = []
    private(set) var notedSongIds: Set<String> = []

    // タグ絞り込みの解決済み集合 (selectedTags から導出)。
    private(set) var tagSongIds: Set<String>?
    private(set) var tagVoteCounts: [String: Int] = [:]
    /// 直近の `resolveTagFilter` がオフライン等で失敗したか。
    /// 失敗時は「タグに合致する曲が0件」と誤読させないよう、絞り込み自体は適用せず本フラグで通知する。
    private(set) var tagFilterError = false

    private var loadTask: Task<Void, Never>?
    private var currentTaskId: UUID = UUID()

    private let songReading: any SongReading
    private var markService: UserMarkService { UserMarkService.shared }

    nonisolated init(songReading: any SongReading = AppContainer.shared.songReading) {
        self.songReading = songReading
    }

    @discardableResult
    func scheduleLoad(_ request: SongListRequest, debounce: Bool) -> Task<Void, Never> {
        loadTask?.cancel()
        let task = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            await load(request)
        }
        loadTask = task
        return task
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

            // アイドルアイコン用の performer idol と、行に出す披露回数は互いに独立なので
            // 並べて投げる。直列に await すると、その順で並べている間だけスケルトンが伸びる。
            // (披露回数は「その順で並んでいる根拠」を出す並びのときだけ数える)
            let songIds = results.map(\.song.id)
            async let performerMapTask = songReading.songPerformerIdolsMap(songIds: songIds)
            async let countsTask = request.sortOrder.showsPerformanceCount
                ? songReading.songPerformanceCounts() : [:]
            let performerMap = (try? await performerMapTask) ?? [:]
            let counts = (try? await countsTask) ?? [:]
            for i in results.indices {
                results[i].performerIdols = performerMap[results[i].song.id] ?? []
            }
            // 世代ガード: await の間により新しい load が始まっていたら、この結果は stale なので捨てる。
            guard currentTaskId == taskId else { return }
            performanceCounts = counts
            songs = results
            applyFilter(searchText: request.searchText, scope: request.searchScope)
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

    /// 歌詞検索の結果 (song_id → 一致箇所)。非 nil の間は手元の索引ではなくこれで絞る。
    ///
    /// ⚠️ View ではなく **VM 側**に持つこと。View だけが持っていた頃は、ブランド絞り込みを
    /// 変えるたびに `load` が `recomputeDisplayed` を呼び直して歌詞の結果を黙って捨て、
    /// 「絞り込み結果がありません」になっていた。歌詞検索を他の条件と合成できることが、
    /// 検索を一覧側に移した理由そのものなので、再ロードを跨いで生き残る場所に置く。
    ///
    /// スニペットまで一緒に持つのは、行に「どこで引っかかったか」を出すため。
    /// id だけを VM、スニペットを View に分けると、二か所を手で同期することになる。
    private(set) var lyricsHits: [String: [LyricsSnippet]]?

    /// 一覧の絞り込みを掛け直す。**絞り込みの入口はここ 1 本**。
    ///
    /// 引数を省ける形にしない (以前 `scope` に既定値があったせいで、渡し忘れた経路が
    /// 黙って曲名で絞り、直後に正しいスコープで数え直す二度手間になっていた)。
    ///
    /// - Parameters:
    ///   - searchText: 手元で当てる語。歌詞モードでは空文字。
    ///   - scope: `searchText` を何に当てるか。
    ///   - lyricsHits: 歌詞検索の結果。`.some` で置き換え、`.none` を渡すと据え置き。
    func applyFilter(searchText: String, scope: SongSearchMode,
                     lyricsHits newHits: [String: [LyricsSnippet]]??  = nil) {
        if let newHits { lyricsHits = newHits }
        if let lyricsHits {
            displayedSongs = songs.filter { lyricsHits[$0.song.id] != nil }
            otherScopeCounts = [:]
            return
        }
        let needle = TextSearchIndex.Needle(searchText)
        // インデックスは `songs` と同じ並び。`didSet` で必ず張り直しているが、
        // 万一ずれても落ちないよう件数を見てから添字を使う。
        guard !needle.isEmpty, searchIndex.count == songs.count else {
            displayedSongs = songs
            otherScopeCounts = [:]
            return
        }
        // 絞り込みと「ほかのスコープの件数」を **1 回の走査**でまとめて出す。
        // 表示中のスコープは数えない (件数は `displayedSongs.count` に出る)。
        var matched: [SongWithArtists] = []
        var counts: [SongSearchMode: Int] = [:]
        for i in songs.indices {
            let entry = searchIndex[i]
            if entry.index(for: scope)?.matches(needle) == true { matched.append(songs[i]) }
            for other in SongSearchMode.localScopes where other != scope {
                if entry.index(for: other)?.matches(needle) == true {
                    counts[other, default: 0] += 1
                }
            }
        }
        displayedSongs = matched
        otherScopeCounts = counts
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
    /// 取得失敗時 (オフライン等) は `tagFilterError` を立てて絞り込みを適用しない
    /// (「タグに合致する曲が0件」と「取得失敗」を区別し、オフライン時に一覧を誤って空にしないため)。
    func resolveTagFilter(_ tags: [CommunityTag]) async {
        guard !tags.isEmpty else {
            tagSongIds = nil
            tagVoteCounts = [:]
            tagFilterError = false
            return
        }
        var intersection: Set<String>?
        var counts: [String: Int] = [:]
        var failed = false
        for tag in tags {
            do {
                let tagSongs = try await CommunityAPI.shared.tag(id: tag.id).songs
                let ids = Set(tagSongs.map(\.songId))
                intersection = intersection.map { $0.intersection(ids) } ?? ids
                if tags.count == 1 {
                    counts = Dictionary(tagSongs.map { ($0.songId, $0.voteCount) }, uniquingKeysWith: { a, _ in a })
                }
            } catch {
                failed = true
            }
        }
        tagFilterError = failed
        guard !failed else {
            // 失敗時は絞り込み状態を変更しない (stale な既存集合を保持し、誤って0件にしない)。
            return
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
    /// `searchText` を何に当てるか。歌詞のときは手元で絞れないので空文字が来る。
    var searchScope: SongSearchMode = .title
}
