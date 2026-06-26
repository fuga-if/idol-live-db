import Foundation

// MARK: - Favorite Ranking

/// お気に入りランキング API が返す「コミュニティ集計」のみ。
///
/// 曲名・ブランド・ジャケ写は **API からは取得しない**。それらの正は CloudKit / iOS local
/// カタログであり、D1 に曲ミラーを持たせると新曲追加のたびにズレて「ランキングから脱落」する
/// バグになるため、iOS local から解決する (予想機能と同方針)。
///
/// APIClient の decoder は `convertFromSnakeCase` を有効にしているため、CodingKeys は書かず
/// property 名 (camelCase) そのままに任せる (snake_case 手書きは keyNotFound になる)。
struct FavoriteRankingDTO: Decodable {
    let songId: String
    let count: Int
}

/// 画面表示用のランキング行。API のコミュニティ集計 (`FavoriteRankingDTO`) に
/// iOS local カタログの曲メタデータを結合して組み立てる。
struct FavoriteRankingEntry: Identifiable {
    var id: String { songId }
    let songId: String
    let count: Int
    let title: String
    let brandId: String?
    let artworkUrl: String?

    /// local に曲が無い場合でも songId を題名にフォールバックして表示する。
    init(dto: FavoriteRankingDTO, song: Song?) {
        songId = dto.songId
        count = dto.count
        title = song?.title ?? dto.songId
        brandId = song?.brandId
        artworkUrl = song?.artworkUrl
    }
}

// MARK: - Penlight Palette

struct PenlightPaletteEntry: Decodable, Identifiable {
    var id: String { colorHexRaw ?? name }
    /// "#FFFFFF" 等の生 hex 文字列。HexColor の strict バリデーションで配列全体の
    /// decode が失敗するケースを避けるため、生文字列で持って後で変換する。
    let colorHexRaw: String?
    let name: String
    let sortOrder: Int
    let note: String?

    var colorHex: HexColor? {
        colorHexRaw.flatMap { HexColor(rawValue: $0) }
    }

    enum CodingKeys: String, CodingKey {
        // 自動変換で "color_hex" → "colorHex" になるので rawValue を camelCase に。
        case colorHexRaw = "colorHex"
        case name
        case sortOrder
        case note
    }
}

// MARK: - Penlight Vote

struct PenlightColorSet: Identifiable {
    var id: String { key }
    let key: String
    let colors: [HexColor]
    let count: Int
}

struct PenlightVoteResult: Decodable {
    let topSets: [PenlightColorSetRaw]
    let totalVotes: Int
    let myVote: MyVoteRaw?

    var topColorSets: [PenlightColorSet] {
        topSets.map { PenlightColorSet(key: $0.key, colors: $0.hexColors, count: $0.count) }
    }

    var myColorSet: PenlightColorSet? {
        guard let mv = myVote else { return nil }
        return PenlightColorSet(key: mv.colorSetKey, colors: mv.hexColors, count: 0)
    }
}

struct PenlightColorSetRaw: Decodable {
    let key: String
    let colors: [String]
    let count: Int

    /// バリデーション済み HexColor 配列（無効値を除外）
    var hexColors: [HexColor] { colors.compactMap { HexColor(rawValue: $0) } }
}

struct MyVoteRaw: Decodable {
    let colorSetKey: String
    let colors: [String]

    var hexColors: [HexColor] { colors.compactMap { HexColor(rawValue: $0) } }
}

// MARK: - Favorite Toggle Response

struct FavoriteToggleResponse: Decodable {
    let songId: String
    let count: Int
}

// MARK: - Tag Enums

enum TagStatus: String, Codable, Sendable {
    case active
    case underReview = "under_review"
    case removed

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = TagStatus(rawValue: raw) ?? .removed
    }
}

enum TagCategory: String, Codable, Sendable {
    case mood
    case scene
    case special
    case free

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = TagCategory(rawValue: raw) ?? .free
    }
}

// MARK: - User Tags

struct CommunityTag: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let category: TagCategory?
    let color: HexColor?
    let createdBy: String?
    let createdAt: Date
    let updatedAt: Date?
    let isOfficial: Bool
    let status: TagStatus
    let totalUses: Int?

    /// APIClient の JSONDecoder は `convertFromSnakeCase` を効かせているため、
    /// ここの CodingKey の rawValue は camelCase で書く必要がある。 snake_case で
    /// 書くと変換後のキーと一致せず全件 keyNotFound でデコード失敗する。
    enum CodingKeys: String, CodingKey {
        case id, name, description, category, color, status
        case descriptionPreview
        case createdBy
        case createdAt
        case updatedAt
        case isOfficial
        case totalUses
    }

    init(from decoder: Decoder) throws {
        // /tags 一覧レスポンスは description_preview しか返さず、 updated_at /
        // is_official / status のキーも省略する。詳細 (/tags/:id) はすべて揃った
        // 形で返す。両方を 1 つの Codable で受けられるようにフォールバックする。
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        let fullDescription = try c.decodeIfPresent(String.self, forKey: .description)
        let previewDescription = try c.decodeIfPresent(String.self, forKey: .descriptionPreview)
        self.description = fullDescription ?? previewDescription
        self.category = try c.decodeIfPresent(TagCategory.self, forKey: .category)
        self.color = try c.decodeIfPresent(HexColor.self, forKey: .color)
        self.createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        // is_official は D1 (SQLite) が INTEGER 0/1 で返すため Bool 直デコードは typeMismatch になる。
        // /tags 一覧はこのキーを省くので一覧は通るが、/tags/:id 詳細は 0/1 を含むためデコード全体が失敗していた。
        // 数値・真偽どちらでも受けられるようにする。
        if let boolVal = try? c.decodeIfPresent(Bool.self, forKey: .isOfficial) {
            self.isOfficial = boolVal
        } else {
            self.isOfficial = (try c.decodeIfPresent(Int.self, forKey: .isOfficial) ?? 0) != 0
        }
        self.status = try c.decodeIfPresent(TagStatus.self, forKey: .status) ?? .active
        self.totalUses = try c.decodeIfPresent(Int.self, forKey: .totalUses)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encode(isOfficial, forKey: .isOfficial)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(totalUses, forKey: .totalUses)
    }
}

struct SongTagListResponse: Decodable, Sendable {
    let tags: [SongTagEntry]
    let myTagIds: [String]

    // APIClient の decoder が convertFromSnakeCase なので CodingKeys は不要
    // (省略すると derived の camelCase で自動マッチする)。
}

struct SongTagEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let color: HexColor?
    let category: TagCategory?
    let voteCount: Int
}

/// GET /songs/:id/similar — タグが似ている楽曲 (この曲が好きな人にはこれもおすすめ)。
struct SimilarSongsResponse: Decodable, Sendable {
    let songId: String
    let songs: [SimilarSongEntry]
}

struct SimilarSongEntry: Decodable, Identifiable, Hashable, Sendable {
    var id: String { songId }
    let songId: String
    /// この曲と共有しているタグ数 (近さの指標)。
    let sharedTags: Int
}

struct TagDetailResponse: Decodable, Sendable {
    let tag: CommunityTag
    let songs: [TagSongEntry]
}

struct TagSongEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String { songId }
    let songId: String
    let voteCount: Int
}

struct TagHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let description: String?
    let editedBy: String
    let editedAt: Date
}

struct TagCreateResponse: Decodable, Sendable {
    let tag: CommunityTag
    let created: Bool
}

struct SongTagApplyResponse: Decodable, Sendable {
    let songId: String
    let appliedTagIds: [String]
    // convertFromSnakeCase で自動マッチするので CodingKeys は省略
}

// MARK: - Community Polls

enum PollTargetType: String, Codable, Sendable {
    case song
    case idol
}

struct Poll: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String?
    let targetType: PollTargetType
    let createdBy: String
    let createdAt: Date
    let endsAt: Date
    let status: String
    let totalVotes: Int?
    let entryCount: Int?
}

struct PollEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String { entityId }
    let entityId: String
    let voteCount: Int
    let hasUserVoted: Bool
}

struct PollDetail: Codable, Sendable {
    let poll: Poll
    let entries: [PollEntry]
    let myVoteCount: Int
}

struct PollVoteResult: Codable, Sendable {
    let entityId: String
    let voteCount: Int
    let myVoteCount: Int
}

/// 終了お題の優勝者 (殿堂/結果一覧用)。
struct PollResult: Codable, Identifiable, Sendable {
    var id: String { pollId }
    let pollId: String
    let title: String
    let targetType: PollTargetType
    let endsAt: Date
    let entityId: String
    let voteCount: Int
}

/// ある曲/アイドルが終了お題で取った順位 (詳細バッジ用)。
struct PollAchievement: Codable, Identifiable, Sendable {
    var id: String { pollId }
    let pollId: String
    let title: String
    let targetType: PollTargetType
    let endsAt: Date
    let voteCount: Int
    let rnk: Int

    /// 「優勝」or「第N位」。
    var rankLabel: String { rnk == 1 ? "優勝" : "第\(rnk)位" }
}

struct TagsListResponse: Decodable, Sendable {
    let tags: [CommunityTag]
    let total: Int
}

// MARK: - Penlight / Tag Ack Types

struct PenlightVoteAck: Decodable, Sendable {
    let songId: String
    let colorSetKey: String
    let count: Int
}

struct PenlightCancelAck: Decodable, Sendable {
    let songId: String
    let cancelled: Bool
}

struct TagRemoveAck: Decodable, Sendable {
    let songId: String
    let tagId: String
    let removed: Bool
}

struct TagReportAck: Decodable, Sendable {
    let ok: Bool
    let totalReports: Int
}
