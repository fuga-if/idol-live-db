import Foundation
import os
import SwiftUI

// MARK: - Models

/// `POST /edits/:batchId/revert` と `POST /admin/revert-user` の per-batch 結果値。
/// 契約値 (RevertOutcome) に厳密一致させ、iOS の表示マッピングをこれに合わせる。
enum RevertOutcome: String, Decodable, Sendable {
    case reverted
    case alreadyReverted = "already_reverted"
    case skippedConflict = "skipped_conflict"
    case notFound = "not_found"
    case notApplied = "not_applied"
    case forbidden
    case failed

    /// 不明値 (将来のサーバ拡張) は `.failed` 扱いにフォールバックする。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RevertOutcome(rawValue: raw) ?? .failed
    }

    /// 一覧 1 行のラベル。
    var label: String {
        switch self {
        case .reverted: return "巻き戻し済み"
        case .alreadyReverted: return "スキップ (revert 済み)"
        case .skippedConflict: return "スキップ (後続編集あり)"
        case .notFound: return "対象なし"
        case .notApplied: return "未適用"
        case .forbidden: return "権限なし"
        case .failed: return "失敗"
        }
    }

    /// 巻き戻し成功 (アイコン / 色で「成功」表示)。
    var isReverted: Bool { self == .reverted }

    /// 失敗扱い (失敗 / 権限なし)。スキップ系 (competition / 既 revert / 対象なし / 未適用) は
    /// 成功でも失敗でもない中立として扱う。
    var isFailed: Bool {
        switch self {
        case .failed, .forbidden: return true
        default: return false
        }
    }

    /// 行のアクセント色。
    var color: Color {
        if isReverted { return .green }
        if isFailed { return .red }
        return .secondary
    }
}

/// admin がユーザーの編集 batch 一覧を閲覧する 1 行 (`GET /admin/users/:id/edits` の edits[])。
/// 契約 §1: `{ batchId, recordType, recordName, opCount, reverted, revertedAt, createdAt }`。
struct AdminUserEdit: Decodable, Identifiable, Sendable {
    let batchId: Int
    let recordType: String
    let recordName: String
    /// この batch に含まれる op 数 (setlist スナップショット等で複数になりうる)。
    let opCount: Int
    let reverted: Bool
    /// revert 実行時刻 (ミリ秒 epoch)。未 revert なら nil。
    let revertedAt: Int64?
    /// 作成時刻 (ミリ秒 epoch)。
    let createdAt: Int64

    var id: Int { batchId }

    private enum CodingKeys: String, CodingKey {
        case batchId, recordType, recordName, opCount, reverted, revertedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batchId = (try c.decodeIfPresent(Int.self, forKey: .batchId)) ?? 0
        recordType = (try c.decodeIfPresent(String.self, forKey: .recordType)) ?? ""
        recordName = (try c.decodeIfPresent(String.self, forKey: .recordName)) ?? ""
        opCount = (try c.decodeIfPresent(Int.self, forKey: .opCount)) ?? 1
        reverted = (try c.decodeIfPresent(Bool.self, forKey: .reverted)) ?? false
        revertedAt = try c.decodeIfPresent(Int64.self, forKey: .revertedAt)
        createdAt = (try c.decodeIfPresent(Int64.self, forKey: .createdAt)) ?? 0
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000.0)
    }
}

/// 対象ユーザーの要約 (`GET /admin/users/:id/edits` の user)。
struct AdminUserSummary: Decodable, Sendable {
    let displayName: String?
    let isBanned: Bool

    private enum CodingKeys: String, CodingKey {
        case displayName, isBanned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        isBanned = (try c.decodeIfPresent(Bool.self, forKey: .isBanned)) ?? false
    }
}

/// `GET /admin/users/:id/edits` のレスポンス全体。
/// 契約 §1: `{ user:{ displayName, isBanned }, total, edits:[...] }`。
struct AdminUserEditsPage: Decodable, Sendable {
    let user: AdminUserSummary?
    let total: Int
    let edits: [AdminUserEdit]

    private enum CodingKeys: String, CodingKey {
        case user, total, edits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try c.decodeIfPresent(AdminUserSummary.self, forKey: .user)
        edits = (try c.decodeIfPresent([AdminUserEdit].self, forKey: .edits)) ?? []
        total = (try c.decodeIfPresent(Int.self, forKey: .total)) ?? edits.count
    }
}

/// `POST /admin/revert-user` の per-batch 結果 1 行。
/// 契約 §1: `{ batchId, outcome, revertBatchId, reason }`。
struct UserRevertItem: Decodable, Identifiable, Sendable {
    let batchId: Int
    let outcome: RevertOutcome
    /// revert によって生成された打ち消し batch の id (成功時のみ)。
    let revertBatchId: Int?
    let reason: String?

    var id: Int { batchId }

    private enum CodingKeys: String, CodingKey {
        case batchId, outcome, revertBatchId, reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batchId = (try c.decodeIfPresent(Int.self, forKey: .batchId)) ?? 0
        outcome = (try c.decodeIfPresent(RevertOutcome.self, forKey: .outcome)) ?? .failed
        revertBatchId = try c.decodeIfPresent(Int.self, forKey: .revertBatchId)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// `POST /admin/revert-user` のレスポンス全体 (集計 + per-batch 明細)。
/// 契約 §1/§2: `{ userId, banned, reverted, skipped, failed, alreadyReverted, dryRun, items }`。
/// `dryRun=true` のときは CloudKit を一切叩かず予測のみ。`banned` は dryRun では常に false。
struct UserRevertResult: Decodable, Sendable {
    let userId: String?
    let banned: Bool
    let reverted: Int
    let skipped: Int
    let failed: Int
    let alreadyReverted: Int
    let dryRun: Bool
    let items: [UserRevertItem]

    private enum CodingKeys: String, CodingKey {
        case userId, banned, reverted, skipped, failed, alreadyReverted, dryRun, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        banned = (try c.decodeIfPresent(Bool.self, forKey: .banned)) ?? false
        reverted = (try c.decodeIfPresent(Int.self, forKey: .reverted)) ?? 0
        skipped = (try c.decodeIfPresent(Int.self, forKey: .skipped)) ?? 0
        failed = (try c.decodeIfPresent(Int.self, forKey: .failed)) ?? 0
        alreadyReverted = (try c.decodeIfPresent(Int.self, forKey: .alreadyReverted)) ?? 0
        dryRun = (try c.decodeIfPresent(Bool.self, forKey: .dryRun)) ?? false
        items = (try c.decodeIfPresent([UserRevertItem].self, forKey: .items)) ?? []
    }
}

// MARK: - Service

/// admin 専用モデレーション操作 (BAN + ユーザー単位 / batch 単位 revert + 編集履歴閲覧) の薄いラッパ。
///
/// 確定モデル: 即時オープン編集 + 事後モデレーション。荒らしは
///   1. BAN (書き込み遮断) … `POST /admin/ban`
///   2. ユーザーの全編集を一括 revert (データ修復) … `POST /admin/revert-user`
///   3. 個別 batch の revert (本人 or admin) … `POST /edits/:batchId/revert`
/// の 3 軸で対処する (BAN とデータ修復は分離。RedTeam: 2 軸設計)。
///
/// revert は CloudKit ハード削除を伝播しないため、サーバ側で soft delete (deletedAt) /
/// before スナップショットへの forceUpdate として逆適用される (契約 v2 #1)。
/// クライアントは結果集計を受け取り表示するだけ。
///
/// すべて `authorized: true` (Bearer sessionToken)。admin 判定はサーバ側 checkIsAdmin が行い、
/// 非 admin は 403 → `APIClientError.notAuthorized` になる。
actor AdminModerationService {
    static let shared = AdminModerationService()

    /// `/admin/revert-user` の body は確定契約 §2 で **camelCase 直受け**
    /// (`{ userId, since?, alsoBan?, dryRun? }`)。`APIClient` 共通 encoder は
    /// `.convertToSnakeCase` で camelCase キーを潰してしまうため、EditService と同じく
    /// 専用 encoder (変換なし) + 直接 URLSession で送る。
    private let session = URLSession.shared
    private let camelEncoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        self.camelEncoder = enc

        let dec = JSONDecoder()
        // 契約 §1 は素の camelCase 直返し。アンダースコア無しの camelCase キーは
        // convertFromSnakeCase 下でも無変換で突き合うので、共通 decoder と同じ設定にする。
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .secondsSince1970
        self.decoder = dec
    }

    // MARK: - ユーザーの編集履歴 (admin 閲覧)

    /// 指定ユーザーの編集 batch 一覧を新しい順で取得する (`GET /admin/users/:id/edits`)。
    /// バックエンドは `limit` / `offset` ページングを取る (page ではない)。
    func userEdits(userId: String, offset: Int = 0, limit: Int = 50) async throws -> AdminUserEditsPage {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        return try await APIClient.shared.request(
            "GET",
            path: "/admin/users/\(encoded)/edits",
            query: ["offset": "\(offset)", "limit": "\(limit)"],
            authorized: true
        )
    }

    // MARK: - 一括 revert + BAN

    /// 指定ユーザーの未 revert 編集を一括で巻き戻す (`POST /admin/revert-user`)。
    ///
    /// 契約 §2: body は camelCase `{ userId, since?, alsoBan?, dryRun? }`。
    /// `dryRun=true` のときサーバは CloudKit を一切叩かず、対象 batchId と各 batch の
    /// 予測 outcome (競合スキップ判定を含む) だけを返す (banned=false 固定)。
    /// 後続編集の保護 (skip conflict) はサーバ既定で常時 ON (body では送らない)。
    /// - Parameters:
    ///   - alsoBan: 同時に BAN するか。dryRun=true では無視される (副作用ゼロ)。
    ///   - dryRun: true なら CloudKit を叩かず巻き戻し対象のプレビューのみ返す。
    func revertUser(
        userId: String,
        alsoBan: Bool,
        dryRun: Bool
    ) async throws -> UserRevertResult {
        struct Body: Encodable {
            let userId: String
            let alsoBan: Bool
            let dryRun: Bool
        }
        let body = Body(userId: userId, alsoBan: alsoBan, dryRun: dryRun)
        let data = try await postCamelJSON(path: "/admin/revert-user", body: body)
        return try decoder.decode(UserRevertResult.self, from: data)
    }

    // MARK: - BAN 単独

    /// ユーザーを BAN する (`POST /admin/ban`)。書き込み遮断のみ (編集の巻き戻しは revertUser)。
    /// このエンドポイントはサーバが `body.user_id` (snake) を読むため共通 encoder で送る。
    func ban(userId: String) async throws {
        struct Body: Encodable { let user_id: String }
        try await APIClient.shared.requestVoid(
            "POST",
            path: "/admin/ban",
            body: Body(user_id: userId),
            authorized: true
        )
    }

    // MARK: - 個別 batch revert (本人 or admin)

    /// 1 件の編集 batch を巻き戻す (`POST /edits/:batchId/revert`)。
    /// 本人 revert / admin のピンポイント修正の双方で使う (サーバが権限判定)。
    ///
    /// 契約 §1: レスポンスは `{ batchId, outcome, revertBatchId, reason }`。
    /// サーバは outcome を HTTP ステータスに対応付ける (reverted/already_reverted/
    /// skipped_conflict=200, not_found=404, not_applied=409, forbidden=403, failed=502)。
    /// このメソッドは 200 系で outcome を返し、それ以外 (404/409/403/5xx) は throw する。
    @discardableResult
    func revertBatch(batchId: Int) async throws -> RevertOutcome {
        let item: UserRevertItem = try await APIClient.shared.request(
            "POST",
            path: "/edits/\(batchId)/revert",
            authorized: true
        )
        return item.outcome
    }

    // MARK: - camelCase 直送ヘルパ (共通 encoder の snake 変換を避ける)

    /// camelCase body を変換せず POST し、生 Data を返す。認証 / エラー分類は
    /// APIClient と同等に行う (401/403→notAuthorized, 429→rateLimited, その他→server)。
    private func postCamelJSON<B: Encodable>(path: String, body: B) async throws -> Data {
        let url = APIEndpoints.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceIdentity.shared, forHTTPHeaderField: "X-Device-Id")
        if let token = await AuthService.shared.bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try camelEncoder.encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIClientError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.transport(URLError(.badServerResponse))
        }
        if !(200..<300).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8)
            switch http.statusCode {
            case 401, 403:
                await AuthService.shared.invalidateToken()
                throw APIClientError.notAuthorized
            case 404:
                throw APIClientError.notFound
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
                throw APIClientError.rateLimited(retryAfter: retryAfter)
            default:
                throw APIClientError.server(status: http.statusCode, body: bodyString)
            }
        }
        return data
    }
}
