import Foundation
import os

// MARK: - Models

/// 「最近の編集」フィード 1 行 (= edit_batch 1 件)。
///
/// サーバ `GET /edits` / `GET /me/edits` のレスポンス items に対応。確定契約 §1 で
/// **全レスポンスは素の camelCase 直返し**に統一された (snake_case 廃止)。
/// item 形:
/// `{ batchId, editorDisplayName, isOwnEdit, op, source, recordType, recordName,
///    summary, goodCount, hasUserGood, reverted, createdAt }`
///
/// 編集者匿名性のため `editorId` は生で返さない。自分判定はサーバが算出した
/// `isOwnEdit` (Bool) を権威として用いる (クライアントで userId 照合しない)。
/// `id` は `batchId` から decode する。
/// `createdAt` は ミリ秒 epoch の整数 (edit_batch.created_at と同単位) なので、
/// 秒変換ストラテジに任せず Int64 で受けて `createdDate` で Date 化する。
struct EditFeedEntry: Decodable, Identifiable, Sendable {
    let id: Int
    let editorDisplayName: String?
    /// サーバ算出の本人判定 (編集者匿名性のため editorId は返らない)。Good ボタンの
    /// 自己賞賛防止 / 「あなたの編集」ラベルの根拠。
    let isOwnEdit: Bool
    /// 'create' | 'update' | 'delete' | 'revert' | 'snapshot' | 'replace'
    let op: String
    /// CloudKit recordType ('Event'|'Show'|'Song'|'Idol'|'SetlistItem'|'ShowSetlist'|...)
    let recordType: String
    let recordName: String
    let summary: String?
    /// ミリ秒 epoch。
    let createdAt: Int64
    let goodCount: Int
    let hasUserGood: Bool
    /// この batch が既に revert 済みか (二重 revert / revert ボタン無効化に使う)。
    let reverted: Bool
    /// batch の出所 ('app'|'revert'|'admin'|'seed')。'revert' の batch 自体は再 revert させない。
    let source: String?

    /// 契約 §1: 素の camelCase キーを直接 decode する。CodingKey は camelCase のまま
    /// (`.convertFromSnakeCase` 下でもアンダースコアの無い camelCase キーは無変換で
    /// 突き合うため、共通 decoder を変更せずに契約に一致する)。
    /// reverted / source は一部レスポンスで欠けても落ちないよう optional で補完する。
    private enum CodingKeys: String, CodingKey {
        case batchId
        case editorDisplayName
        case isOwnEdit
        case op
        case recordType
        case recordName
        case summary
        case createdAt
        case goodCount
        case hasUserGood
        case reverted
        case source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .batchId)
        editorDisplayName = try c.decodeIfPresent(String.self, forKey: .editorDisplayName)
        isOwnEdit = (try c.decodeIfPresent(Bool.self, forKey: .isOwnEdit)) ?? false
        op = try c.decode(String.self, forKey: .op)
        recordType = (try c.decodeIfPresent(String.self, forKey: .recordType)) ?? ""
        recordName = (try c.decodeIfPresent(String.self, forKey: .recordName)) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        goodCount = (try c.decodeIfPresent(Int.self, forKey: .goodCount)) ?? 0
        hasUserGood = (try c.decodeIfPresent(Bool.self, forKey: .hasUserGood)) ?? false
        reverted = (try c.decodeIfPresent(Bool.self, forKey: .reverted)) ?? false
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }

    /// 投稿者表示名。privaterelay 系 / メール形式は「名無しのプロデューサー」へマスク
    /// (SubmissionService.authorDisplayName と同等のクライアント側マスク)。
    var editorDisplayLabel: String {
        guard let name = editorDisplayName, !name.isEmpty else { return "名無しのプロデューサー" }
        if name.contains("@") { return "名無しのプロデューサー" }
        return name
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000.0)
    }

    /// 本人 / admin が revert 可能か。既に revert 済み、もしくは revert 操作自体の batch は不可。
    var isRevertable: Bool {
        !reverted && source != "revert"
    }
}

struct EditFeedPage: Decodable, Sendable {
    let items: [EditFeedEntry]
    let total: Int
    let page: Int
    let limit: Int
}

/// Good トグルのレスポンス (`POST` / `DELETE /edits/:batchId/good`)。
/// 契約 §1: `{ batchId, goodCount, gooded }`。
struct GoodResult: Decodable, Sendable {
    let batchId: Int
    let goodCount: Int
    let gooded: Bool
}

/// あるマスタレコードの編集履歴 1 行 (`GET /master/:recordType/:recordName/history` の history[])。
///
/// サーバ (edits.ts handleGetRecordHistory) は `changed_fields` (変更されたフィールド名) と
/// フル diff (`before` / `after`) を併せて返す。一覧では `changedFields` を主表示にし、
/// before/after は必要時の詳細展開に使う。`op='snapshot'` は ShowSetlist の show 単位
/// スナップショット (before/after = { items, performers } 丸ごと) なので changed_fields は空。
struct RecordHistoryEntry: Decodable, Identifiable, Sendable {
    let id: Int
    let batchId: Int
    /// 'create'|'update'|'delete'|'snapshot'
    let op: String
    let changedFields: [String]
    let before: [String: JSONValue]?
    let after: [String: JSONValue]?
    let editorName: String?
    let source: String?
    /// CloudKit custom `modifiedAt` (ミリ秒 epoch)。差分同期の基準値。欠落時は 0。
    let modifiedAt: Int64
    /// ミリ秒 epoch。
    let createdAt: Int64
    let reverted: Bool

    /// 契約 §1: `{ id, batchId, op, changedFields, before, after, editorName, source,
    /// modifiedAt, createdAt, reverted }` を素の camelCase で decode する。
    private enum CodingKeys: String, CodingKey {
        case id, batchId, op, changedFields, before, after, editorName, source, modifiedAt, createdAt, reverted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        batchId = (try c.decodeIfPresent(Int.self, forKey: .batchId)) ?? 0
        op = try c.decode(String.self, forKey: .op)
        changedFields = (try c.decodeIfPresent([String].self, forKey: .changedFields)) ?? []
        before = try c.decodeIfPresent([String: JSONValue].self, forKey: .before)
        after = try c.decodeIfPresent([String: JSONValue].self, forKey: .after)
        editorName = try c.decodeIfPresent(String.self, forKey: .editorName)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        modifiedAt = (try c.decodeIfPresent(Int64.self, forKey: .modifiedAt)) ?? 0
        createdAt = (try c.decodeIfPresent(Int64.self, forKey: .createdAt)) ?? 0
        reverted = (try c.decodeIfPresent(Bool.self, forKey: .reverted)) ?? false
    }

    /// 投稿者表示名。メール形式 / 空は「名無しのプロデューサー」へマスク。
    var editorDisplayLabel: String {
        guard let name = editorName, !name.isEmpty else { return "名無しのプロデューサー" }
        if name.contains("@") { return "名無しのプロデューサー" }
        return name
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000.0)
    }
}

private struct RecordHistoryResponse: Decodable, Sendable {
    let history: [RecordHistoryEntry]
}

/// edit_history の before/after に入る任意 JSON 値 (CK フィールド値) を緩く受けるための型。
/// 文字列 / 数値 / 真偽 / null / 配列 / オブジェクトを表示用に保持する。
enum JSONValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    /// 履歴 diff の 1 セル向けの簡潔な人間可読表現。
    var displayString: String {
        switch self {
        case .string(let s): return s.isEmpty ? "(空)" : s
        case .number(let n):
            // 整数なら小数点を出さない (例: 158.0 → "158")。
            if n.rounded() == n, abs(n) < 1e15 { return String(Int64(n)) }
            return String(n)
        case .bool(let b): return b ? "あり" : "なし"
        case .null: return "(なし)"
        case .array(let a): return "\(a.count) 件"
        case .object: return "{…}"
        }
    }
}

/// 貢献ランキング 1 行 (`GET /leaderboard`)。
///
/// 貢献度は 2 指標を「個別集計」する (合成しない。確定契約 §3):
///   - `editCount`     = 編集 batch 件数 (source='app' かつ cloudkit_ok=1。tier の主指標)
///   - `goodsReceived` = 自分の編集が受けた Good 累計
///
/// 契約 §1: サーバは素の camelCase (`editCount` / `goodsReceived`) を直返しする。
/// 旧名 `contribution_count` / `total_approved` は廃止されたため、`editCount` を
/// 別フィールドとして直接 decode する (旧 `contributionCount` 別名マップは撤去)。
/// `tier` はサーバ側 calcTier の文字列。
struct LeaderboardEntry: Decodable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarUrl: String?
    /// 編集件数 (= サーバ `editCount`)。tier 判定の主指標。欠落時は 0。
    let editCount: Int
    /// 受け取った Good 累計 (= サーバ `goodsReceived`)。欠落時は 0。
    let goodsReceived: Int
    let tier: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case avatarUrl
        case editCount
        case goodsReceived
        case tier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        editCount = (try c.decodeIfPresent(Int.self, forKey: .editCount)) ?? 0
        goodsReceived = (try c.decodeIfPresent(Int.self, forKey: .goodsReceived)) ?? 0
        tier = try c.decodeIfPresent(String.self, forKey: .tier)
    }
}

// MARK: - Service

/// オープン編集フィード (`GET /edits`) と Good トグルの薄いラッパ。
///
/// 設計 (vote-to-good): 承認投票 (OK/NG) を撤去し、編集への「いいね」= Good に一本化する。
/// Good は感謝 / 人気指標で、承認とは切り離されている (反映は即時オープン編集側で完了済み)。
///
/// `APIClient.request` を利用し、decoder は `.convertFromSnakeCase`。
/// 自身の編集 (`mine: true` / `GET /me/edits`) も同じ EditFeedPage で返る。
actor EditFeedService {
    static let shared = EditFeedService()
    private init() {}

    // MARK: - Feed

    /// 最近の編集フィード。`mine: true` は自分の編集のみ (本人 revert / MyPage 用)。
    func fetchEdits(
        page: Int = 1,
        limit: Int = 20,
        recordType: String? = nil,
        brandId: String? = nil,
        mine: Bool = false
    ) async throws -> EditFeedPage {
        // mine は専用エンドポイント /me/edits (要認証)。それ以外は公開フィード /edits。
        let path = mine ? "/me/edits" : "/edits"
        var query: [String: String] = [
            "page": "\(page)",
            "limit": "\(limit)",
        ]
        if let recordType, !recordType.isEmpty { query["record_type"] = recordType }
        if let brandId, !brandId.isEmpty { query["brand_id"] = brandId }
        return try await APIClient.shared.request(
            "GET", path: path,
            query: query,
            authorized: true // 任意認証だが、has_user_good 付与のため常にトークンを乗せる
        )
    }

    // MARK: - Good toggle

    func good(batchId: Int) async throws -> GoodResult {
        try await APIClient.shared.request(
            "POST", path: "/edits/\(batchId)/good",
            authorized: true
        )
    }

    func ungood(batchId: Int) async throws -> GoodResult {
        try await APIClient.shared.request(
            "DELETE", path: "/edits/\(batchId)/good",
            authorized: true
        )
    }

    // MARK: - Leaderboard (Good ランキング)

    func fetchLeaderboard() async throws -> [LeaderboardEntry] {
        try await APIClient.shared.request("GET", path: "/leaderboard")
    }

    // MARK: - Record history (任意レコードの編集履歴)

    /// あるマスタレコード (recordType / recordName) の編集履歴を新しい順で取得する
    /// (`GET /master/:recordType/:recordName/history`)。各 DetailView の「編集履歴」から開く。
    func recordHistory(
        recordType: String,
        recordName: String,
        limit: Int = 30
    ) async throws -> [RecordHistoryEntry] {
        let type = recordType.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? recordType
        let name = recordName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? recordName
        let resp: RecordHistoryResponse = try await APIClient.shared.request(
            "GET",
            path: "/master/\(type)/\(name)/history",
            query: ["limit": "\(limit)"],
            // 認証不要 (公開履歴) だが、可用時はトークンを乗せる (将来の本人判定余地)。
            authorized: true
        )
        return resp.history
    }

    // 個別 batch の revert は `AdminModerationService.revertBatch` に集約 (本人 / admin 共通)。
    // 契約 §1 のレスポンス `{ batchId, outcome, revertBatchId, reason }` を outcome で返す。
}
