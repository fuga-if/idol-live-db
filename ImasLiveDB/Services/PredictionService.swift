import Foundation

// MARK: - PredictionService

@Observable @MainActor
final class PredictionService {
    static let shared = PredictionService()

    private init() {}

    /// 公演ごとの予想集計 (/shows/:id/predictions) DTO の TTL キャッシュ。show_id 単位。
    /// DTO は has_user_voted (自分の投票か) を含む **ユーザー固有** データなので、
    /// エッジ/CDN 共有キャッシュには絶対載せない (backend も public を付けない)。
    /// per-device メモリキャッシュのみ。曲メタの結合は毎回 local カタログでやり直す
    /// (local が更新されても古い結合が残らない)。投票数は他人の操作でも増減するので TTL は短め (60s)。
    /// 自分の vote/unvote は該当 show のキャッシュを無効化して次回再取得させる。
    private var predictionsCache: [String: (dtos: [PredictionDTO], at: Date)] = [:]
    private let predictionsCacheTTL: TimeInterval = 60

    /// 曲ごとの出演者予想 (/shows/:showId/songs/:songId/performers) DTO の TTL キャッシュ。
    /// キー: "\(showId)/\(songId)"。ユーザー固有データなので per-device メモリキャッシュのみ。
    private var performerCache: [String: (dtos: [PerformerPredictionDTO], at: Date)] = [:]
    private let performerCacheTTL: TimeInterval = 60

    // MARK: - Fetch

    func fetch(showId: String) async throws -> [SetlistPrediction] {
        let dtos = try await fetchDTOs(showId: showId)
        // 曲メタデータは API ではなく iOS local カタログから解決する (D1 ミラー非依存)。
        let songs = (try? AppDatabase.shared.fetchSongs(ids: dtos.map(\.songId))) ?? []
        let songsById = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        return dtos.map { SetlistPrediction(dto: $0, song: songsById[$0.songId]) }
    }

    private func fetchDTOs(showId: String) async throws -> [PredictionDTO] {
        if let hit = predictionsCache[showId], Date().timeIntervalSince(hit.at) < predictionsCacheTTL {
            return hit.dtos
        }
        let dtos: [PredictionDTO] = try await APIClient.shared.request(
            "GET",
            path: "/shows/\(showId)/predictions",
            authorized: true
        )
        predictionsCache[showId] = (dtos, Date())
        return dtos
    }

    /// 自分の vote/unvote 後にその公演のキャッシュを捨て、次回 fetch で has_user_voted を取り直す。
    private func invalidate(showId: String) {
        predictionsCache[showId] = nil
    }

    /// サインアウト/アカウント切替時に呼ぶ。has_user_voted は user 依存なので、
    /// 別ユーザーの投票状態が残らないよう全公演の集計キャッシュを捨てる。
    func clearCache() {
        predictionsCache.removeAll()
        performerCache.removeAll()
    }

    // MARK: - My Predictions

    /// 自分が投票した予想一覧 (新しい順)。曲/公演メタは呼び出し側が local カタログで解決する。
    func myPredictions() async throws -> [MyPredictionDTO] {
        guard AuthService.shared.bearerToken != nil else {
            throw PredictionError.unauthorized
        }
        return try await APIClient.shared.request(
            "GET",
            path: "/me/predictions",
            authorized: true
        )
    }

    // MARK: - Vote

    func vote(showId: String, songId: String) async throws -> PredictionVoteResult {
        // bearerToken の事前チェックはしない。トークンが期限切れ (nil) でも isSignedIn は
        // true のまま残ることがあり、ここで弾くと APIClient の 401 自動リフレッシュ経路に
        // 乗らず「ログイン中なのに投票が無言で全部失敗」になる (14th 予想が保存されなかった
        // 原因)。authorized: true で送れば、未トークン→401→sliding refresh→リトライで自己回復する。
        // path 引数は raw のまま渡す (APIClient 内 URLComponents が 1 回エンコード)。
        // 手動 addingPercentEncoding を被せると二重エンコードでサーバ側 decode と食い違う。
        struct Body: Encodable {
            let songId: String
            enum CodingKeys: String, CodingKey { case songId = "song_id" }
        }
        let result: PredictionVoteResult = try await APIClient.shared.request(
            "POST",
            path: "/shows/\(showId)/predictions",
            body: Body(songId: songId),
            authorized: true
        )
        invalidate(showId: showId)
        return result
    }

    // MARK: - Unvote

    func unvote(showId: String, songId: String) async throws {
        // vote() と同じ理由で事前チェックしない (401 自動リフレッシュに委ねる)。
        try await APIClient.shared.requestVoid(
            "DELETE",
            path: "/shows/\(showId)/predictions/\(songId)",
            authorized: true
        )
        invalidate(showId: showId)
    }

    // MARK: - Performers Fetch

    func fetchPerformers(showId: String, songId: String) async throws -> [PerformerPrediction] {
        let dtos = try await fetchPerformerDTOs(showId: showId, songId: songId)
        // アイドルメタデータは API ではなく iOS local カタログから解決する。
        let idolIds = dtos.map(\.idolId)
        let idols = (try? AppDatabase.shared.fetchIdols(ids: idolIds)) ?? []
        let idolsById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0) })
        return dtos.map { PerformerPrediction(dto: $0, idol: idolsById[$0.idolId]) }
    }

    private func fetchPerformerDTOs(showId: String, songId: String) async throws -> [PerformerPredictionDTO] {
        let cacheKey = "\(showId)/\(songId)"
        if let hit = performerCache[cacheKey], Date().timeIntervalSince(hit.at) < performerCacheTTL {
            return hit.dtos
        }
        let dtos: [PerformerPredictionDTO] = try await APIClient.shared.request(
            "GET",
            path: "/shows/\(showId)/songs/\(songId)/performers",
            authorized: true
        )
        performerCache[cacheKey] = (dtos, Date())
        return dtos
    }

    /// 自分の votePerformer/unvotePerformer 後にその曲のキャッシュを捨て、次回 fetch で取り直す。
    private func invalidatePerformer(showId: String, songId: String) {
        performerCache["\(showId)/\(songId)"] = nil
    }

    // MARK: - Performers Vote

    func votePerformer(showId: String, songId: String, idolId: String) async throws -> PerformerVoteResult {
        // bearerToken の事前チェックはしない。vote() と同じ理由 (401 自動リフレッシュに委ねる)。
        struct Body: Encodable {
            let idolId: String
            enum CodingKeys: String, CodingKey { case idolId = "idol_id" }
        }
        let result: PerformerVoteResult
        do {
            result = try await APIClient.shared.request(
                "POST",
                path: "/shows/\(showId)/songs/\(songId)/performers",
                body: Body(idolId: idolId),
                authorized: true
            )
        } catch let APIClientError.server(status, _) where status == 422 {
            // 8人上限 (サーバ生文字列 "Too many votes: max 8 performers per song") を専用和文に握り替える。
            // 429 (レート上限) に専用和文があるのと同じ流儀。
            throw PredictionError.tooManyPerformers
        }
        invalidatePerformer(showId: showId, songId: songId)
        return result
    }

    // MARK: - Performers Unvote

    func unvotePerformer(showId: String, songId: String, idolId: String) async throws {
        // bearerToken の事前チェックはしない。vote() と同じ理由 (401 自動リフレッシュに委ねる)。
        try await APIClient.shared.requestVoid(
            "DELETE",
            path: "/shows/\(showId)/songs/\(songId)/performers/\(idolId)",
            authorized: true
        )
        invalidatePerformer(showId: showId, songId: songId)
    }
}

// MARK: - Errors

enum PredictionError: LocalizedError {
    case unauthorized
    case rateLimited
    case tooManyPerformers
    case notFound
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "投票にはApple Sign Inが必要です"
        case .rateLimited:
            return "投票の制限に達しました。明日またお試しください"
        case .tooManyPerformers:
            return "1曲につき予想できるのは8人までです"
        case .notFound:
            return "対象が見つかりませんでした"
        case .invalidResponse:
            return "サーバーからの応答が不正です"
        case .serverError(let msg):
            return "サーバーエラー: \(msg)"
        }
    }
}
