import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "community_api")

/// コミュニティ集計 API クライアント。X-Device-Id ヘッダを自動付与する。
actor CommunityAPI {
    static let shared = CommunityAPI()
    private init() {}

    /// キャッシュ済みパレット
    private var cachedPalette: [PenlightPaletteEntry]?

    /// タグ一覧の短期メモリキャッシュ。タグ追加 UI を開き直すたびに /tags を取りに行くと
    /// 体感ロードが長いため、クエリ単位で TTL キャッシュして再オープンを即時化する。
    /// タグ作成/付与で件数が変わるので、その時はキャッシュを無効化する。
    private var tagsCache: [String: (tags: [CommunityTag], at: Date)] = [:]
    private let tagsCacheTTL: TimeInterval = 300

    /// タグ詳細 (タグ絞り込みで叩く /tags/:id) の TTL キャッシュ。tag_id 単位。
    /// 絞り込みでタグを付け外しするたびに毎回ネットワークを叩くのを防ぐ。
    /// タグ所属・票数は変化が緩やかで、自分のタグ付け時は即無効化されるため長めで安全。
    private var tagDetailCache: [String: (detail: TagDetailResponse, at: Date)] = [:]
    private let tagDetailCacheTTL: TimeInterval = 300

    /// タグ類似曲 (/songs/:id/similar) の TTL キャッシュ。song_id 単位。
    /// 曲詳細を開くたびに毎回ネットワークを叩いていた。レスポンスは完全にユーザー非依存
    /// (共有タグ数の集計のみ) で、タグ分布で決まり変化が非常に緩やかなので長めの TTL で安全。
    /// 自分のタグ付け/取消で類似関係が変わりうるので、その曲のエントリは無効化する。
    private var similarSongsCache: [String: (response: SimilarSongsResponse, at: Date)] = [:]
    private let similarSongsCacheTTL: TimeInterval = 600

    /// ペンライト投票集計 (/penlight/votes/:id) の TTL キャッシュ。song_id 単位。
    /// レスポンスに my_vote (自分の投票) が含まれるため **ユーザー固有** であり、
    /// エッジ共有キャッシュには絶対載せられない (端末ごとに my_vote が異なる)。
    /// per-device のメモリキャッシュのみ許可。集計なので変化は中程度、TTL は短め (60s)。
    /// 自分が投票/取消したらその曲を即無効化する (my_vote が古いと UI が誤表示になる)。
    private var penlightVotesCache: [String: (result: PenlightVoteResult, at: Date)] = [:]
    private let penlightVotesCacheTTL: TimeInterval = 60

    /// 曲タグ一覧 (/songs/:id/tags) の TTL キャッシュ。song_id 単位。
    /// レスポンスに my_tag_ids (自分が付けたタグ) が含まれるため **ユーザー固有**。
    /// エッジ共有キャッシュ禁止。per-device メモリキャッシュのみ。曲詳細を開くたびに叩かれる。
    /// 票数集計の変化は緩やかだが、自分のタグ付け/取消で my_tag_ids が変わるので即無効化する。
    private var songTagsCache: [String: (response: SongTagListResponse, at: Date)] = [:]
    private let songTagsCacheTTL: TimeInterval = 120

    /// タグ一覧・タグ詳細の両キャッシュを無効化する (タグ作成/付与/取消で件数・票数が変わるため)。
    /// あわせて、その曲のタグ集計に依存する曲タグ一覧・類似曲キャッシュも song 単位で無効化する。
    private func invalidateTagsCache(songId: String? = nil) {
        tagsCache.removeAll()
        tagDetailCache.removeAll()
        if let songId {
            songTagsCache[songId] = nil
            // 自分のタグ付けは類似関係 (共有タグ) を変えうるので、その曲の類似キャッシュも捨てる。
            similarSongsCache[songId] = nil
        }
    }

    // MARK: - Favorites

    func toggleFavorite(songId: String, value: Bool) async throws {
        struct Body: Encodable { let songId: String; let value: Bool }
        let _: FavoriteToggleResponse = try await APIClient.shared.request(
            "POST", path: "/favorites/toggle",
            body: Body(songId: songId, value: value)
        )
    }

    func favoritesRanking(brandId: String?, limit: Int = 20) async throws -> [FavoriteRankingEntry] {
        // API はコミュニティ集計 (song_id, count) のみ返す。曲メタ・ブランドは local カタログで
        // 解決する (D1 ミラー非依存)。ブランド絞り込み後に top N を切るため、API からは多めに取る。
        let dtos: [FavoriteRankingDTO] = try await APIClient.shared.request("GET", path: "/favorites/ranking")
        let songs = (try? AppDatabase.shared.fetchSongs(ids: dtos.map(\.songId))) ?? []
        let songsById = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        let entries = dtos
            .map { FavoriteRankingEntry(dto: $0, song: songsById[$0.songId]) }
            .filter { brandId == nil || $0.brandId == brandId }
        return Array(entries.prefix(limit))
    }

    // MARK: - Penlight

    func votePenlight(songId: String, colors: [String]) async throws {
        struct Body: Encodable { let songId: String; let colors: [String] }
        try await APIClient.shared.requestVoid(
            "POST", path: "/penlight/vote",
            body: Body(songId: songId, colors: colors)
        )
        // 自分の投票で my_vote と集計が変わるので、その曲の集計キャッシュを無効化。
        penlightVotesCache[songId] = nil
    }

    func clearPenlightVote(songId: String) async throws {
        // クエリは URLQueryItem が自動エンコードするので raw のまま渡す。
        try await APIClient.shared.requestVoid(
            "DELETE", path: "/penlight/vote",
            query: ["song_id": songId]
        )
        // 自分の取消で my_vote と集計が変わるので、その曲の集計キャッシュを無効化。
        penlightVotesCache[songId] = nil
    }

    func penlightVotes(songId: String) async throws -> PenlightVoteResult {
        if let hit = penlightVotesCache[songId], Date().timeIntervalSince(hit.at) < penlightVotesCacheTTL {
            return hit.result
        }
        // path は APIClient の URLComponents が 1 回エンコードする。 ここでの手動 encode は
        // 二重エンコードとなり、 サーバ側の decodeURIComponent 1 回では戻りきらず別キー扱いになる。
        // レスポンスに my_vote (ユーザー固有) を含むため per-device メモリキャッシュのみ。
        let result: PenlightVoteResult = try await APIClient.shared.request("GET", path: "/penlight/votes/\(songId)")
        penlightVotesCache[songId] = (result, Date())
        return result
    }

    func penlightPalette() async throws -> [PenlightPaletteEntry] {
        if let cached = cachedPalette { return cached }
        let result: [PenlightPaletteEntry] = try await APIClient.shared.request("GET", path: "/penlight/palette")
        cachedPalette = result
        return result
    }

    // MARK: - Tags

    func createTag(name: String, description: String? = nil, category: String? = nil, color: String? = nil) async throws -> CommunityTag {
        var body: [String: String] = ["name": name]
        if let description { body["description"] = description }
        if let category { body["category"] = category }
        if let color { body["color"] = color }
        // 同名タグが既存なら 409 で既存タグが返るので、それを採用して冪等にする (名前で一意)。
        let response: TagCreateResponse = try await APIClient.shared.request(
            "POST", path: "/tags", body: body, treatConflictAsSuccess: true
        )
        invalidateTagsCache()
        return response.tag
    }

    func tags(search: String = "", category: String = "", sort: String = "popular", limit: Int = 50, offset: Int = 0) async throws -> [CommunityTag] {
        let cacheKey = "\(sort)|\(limit)|\(offset)|\(category)|\(search)"
        if let hit = tagsCache[cacheKey], Date().timeIntervalSince(hit.at) < tagsCacheTTL {
            return hit.tags
        }
        var query: [String: String] = [
            "sort": sort,
            "limit": "\(limit)",
            "offset": "\(offset)"
        ]
        if !search.isEmpty { query["search"] = search }
        if !category.isEmpty { query["category"] = category }
        let response: TagsListResponse = try await APIClient.shared.request("GET", path: "/tags", query: query)
        tagsCache[cacheKey] = (response.tags, Date())
        return response.tags
    }

    // path に渡す ID 系は全て raw のまま。 APIClient.URLComponents が path セグメントを
    // 自動で 1 回エンコードする。 手動 addingPercentEncoding を被せると二重エンコードになり、
    // サーバ側の decodeURIComponent 1 回では戻りきらず別キー扱いになる致命バグになる。

    func tag(id: String) async throws -> TagDetailResponse {
        if let hit = tagDetailCache[id], Date().timeIntervalSince(hit.at) < tagDetailCacheTTL {
            return hit.detail
        }
        let detail: TagDetailResponse = try await APIClient.shared.request("GET", path: "/tags/\(id)")
        tagDetailCache[id] = (detail, Date())
        return detail
    }

    func updateTag(id: String, description: String? = nil, category: String? = nil, color: String? = nil) async throws -> CommunityTag {
        var body: [String: String] = [:]
        if let description { body["description"] = description }
        if let category { body["category"] = category }
        if let color { body["color"] = color }
        let response: [String: CommunityTag] = try await APIClient.shared.request("PUT", path: "/tags/\(id)", body: body)
        guard let tag = response["tag"] else { throw URLError(.badServerResponse) }
        invalidateTagsCache()
        return tag
    }

    func tagHistory(id: String) async throws -> [TagHistoryEntry] {
        return try await APIClient.shared.request("GET", path: "/tags/\(id)/history")
    }

    func applySongTags(songId: String, tagIds: [String]) async throws {
        struct Body: Encodable { let tagIds: [String] }
        let _: SongTagApplyResponse = try await APIClient.shared.request(
            "POST", path: "/songs/\(songId)/tags",
            body: Body(tagIds: tagIds)
        )
        // 自分のタグ付けで my_tag_ids・票数・類似関係が変わるので該当 song も無効化。
        invalidateTagsCache(songId: songId)
    }

    func removeSongTag(songId: String, tagId: String) async throws {
        try await APIClient.shared.requestVoid(
            "DELETE", path: "/songs/\(songId)/tags/\(tagId)"
        )
        // 自分のタグ取消で my_tag_ids・票数・類似関係が変わるので該当 song も無効化。
        invalidateTagsCache(songId: songId)
    }

    func songTags(songId: String) async throws -> SongTagListResponse {
        if let hit = songTagsCache[songId], Date().timeIntervalSince(hit.at) < songTagsCacheTTL {
            return hit.response
        }
        // レスポンスに my_tag_ids (ユーザー固有) を含むため per-device メモリキャッシュのみ。
        let response: SongTagListResponse = try await APIClient.shared.request("GET", path: "/songs/\(songId)/tags")
        songTagsCache[songId] = (response, Date())
        return response
    }

    /// タグが似ている楽曲 (この曲が好きな人にはこれもおすすめ)。共有タグ数の多い順。
    func similarSongsByTags(songId: String, limit: Int = 10) async throws -> SimilarSongsResponse {
        // limit は呼び出し側で固定 (DetailSheet=既定)。同一 song の再オープンを即時化するため
        // song_id 単位でキャッシュ。完全にユーザー非依存なので長め TTL でよい。
        if let hit = similarSongsCache[songId], Date().timeIntervalSince(hit.at) < similarSongsCacheTTL {
            return hit.response
        }
        let response: SimilarSongsResponse = try await APIClient.shared.request("GET", path: "/songs/\(songId)/similar?limit=\(limit)")
        similarSongsCache[songId] = (response, Date())
        return response
    }

    func reportTag(id: String, reason: String? = nil) async throws {
        var body: [String: String] = [:]
        if let reason { body["reason"] = reason }
        try await APIClient.shared.requestVoid(
            "POST", path: "/tags/\(id)/report",
            body: body
        )
    }

    // MARK: - Polls

    func polls(status: String) async throws -> [Poll] {
        return try await APIClient.shared.request("GET", path: "/polls", query: ["status": status])
    }

    func poll(id: String) async throws -> PollDetail {
        // authorized: true 必須。これが無いとサーバが利用者を識別できず myVoteCount=0 で返り、
        // 投票済みでも「残り3/3」表示 → 投票するとサーバに重複拒否されてエラーになる。
        // 未ログインは匿名で取得 (myVoteCount=0)、期限切れトークンは 401→sliding refresh で自己回復。
        return try await APIClient.shared.request("GET", path: "/polls/\(id)", authorized: true)
    }

    /// 終了お題の優勝者一覧 (殿堂)。
    func pollResults() async throws -> [PollResult] {
        return try await APIClient.shared.request("GET", path: "/polls/results")
    }

    /// 指定エンティティ(曲/アイドル)の終了お題での順位実績 (上位3位)。
    func pollAchievements(entityId: String) async throws -> [PollAchievement] {
        return try await APIClient.shared.request("GET", path: "/polls/achievements/\(entityId)")
    }

    func createPoll(title: String, description: String?, targetType: PollTargetType, days: Int) async throws -> Poll {
        struct Body: Encodable {
            let title: String
            let description: String?
            let targetType: String
            let days: Int
        }
        return try await APIClient.shared.request(
            "POST", path: "/polls",
            body: Body(title: title, description: description, targetType: targetType.rawValue, days: days),
            authorized: true
        )
    }

    func votePoll(pollId: String, entityId: String) async throws -> PollVoteResult {
        struct Body: Encodable { let entityId: String }
        return try await APIClient.shared.request(
            "POST", path: "/polls/\(pollId)/votes",
            body: Body(entityId: entityId),
            authorized: true,
            treatConflictAsSuccess: true
        )
    }

    func unvotePoll(pollId: String, entityId: String) async throws -> PollVoteResult {
        return try await APIClient.shared.request(
            "DELETE", path: "/polls/\(pollId)/votes/\(entityId)",
            authorized: true
        )
    }

    func deletePoll(id: String) async throws {
        try await APIClient.shared.requestVoid(
            "DELETE", path: "/polls/\(id)",
            authorized: true
        )
    }
}

// MARK: - CommunityAPIError (typealiased to APIClientError for compatibility)

typealias CommunityAPIError = APIClientError

// MARK: - Domain 適合 (Data レイヤ)

/// `CommunityVoting` (Domain の口) への適合。既存の poll 系メソッドがそのまま witness になる。
/// Presentation はこの actor 具象ではなく `any CommunityVoting` に依存する。
extension CommunityAPI: CommunityVoting {}
