import Foundation
import GRDB

struct Idol: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "idols"

    var id: String
    var brandId: String
    var name: String
    var nameKana: String?
    var nameRomaji: String?
    var familyName: String?
    var givenName: String?
    var nickname: String?
    var color: String?
    var sortOrder: Int

    // プロフィール
    var birthday: String?
    var bloodType: String?
    var height: Double?
    var weight: Double?
    var birthPlace: String?
    var age: Int?
    var bust: Double?
    var waist: Double?
    var hip: Double?
    var constellation: String?
    var hobbies: String?
    var talents: String?
    var description: String?
    var gender: String?
    var handedness: String?

    /// 実装(初登場)日 ISO8601 (YYYY-MM-DD)。これより前のライブでは出席判定対象外。
    var debutDate: String?

    /// ブランド内サブカテゴリ属性。
    /// cg: cute/cool/passion, ml/765as: princess/fairy/angel,
    /// sidem: intelli/physical/mental, sc: sol/luna/stella, etc.
    var attribute: String?

    /// 外部ゲスト演者フラグ。アイラブ歌合戦のラブライブ側のように
    /// セトリ表示には出すが、アイドル一覧・検索・統計から除外したいキャラ用。
    var isExternal: Bool = false

    /// 別名 (ステージ名・通称・略称) のカンマ区切り。例: 伴田路子 の "ロコ"。
    /// 検索や画像インポートのキーマッチでも matched キーとして使う。
    var aliases: String?

    /// 担当声優のカンマ区切り。 先頭が現役、 以降は過去 CV (古い順)。
    /// 例: "中村繪里子" / "下田麻美" / "M・A・O,伊藤美来" (旧→現)。
    /// Cast テーブル廃止により idol 単体で声優情報を保持する設計に移行済み。
    var voiceActors: String?

    enum CodingKeys: String, CodingKey {
        case id, name, color, birthday, height, weight, age, bust, waist, hip
        case constellation, hobbies, talents, description, gender, handedness, nickname
        case brandId = "brand_id"
        case nameKana = "name_kana"
        case nameRomaji = "name_romaji"
        case familyName = "family_name"
        case givenName = "given_name"
        case sortOrder = "sort_order"
        case bloodType = "blood_type"
        case birthPlace = "birth_place"
        case debutDate = "debut_date"
        case attribute
        case isExternal = "is_external"
        case aliases
        case voiceActors = "voice_actors"
    }

    /// `aliases` カラムをカンマ区切りで分割した配列。空白 trim 済み。
    var aliasList: [String] {
        guard let aliases, !aliases.isEmpty else { return [] }
        return aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 担当声優一覧 (先頭が現役、 以降は過去 CV 古い順)。
    var voiceActorList: [String] {
        guard let voiceActors, !voiceActors.isEmpty else { return [] }
        return voiceActors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 現役声優名 (リストの先頭)。
    var currentVoiceActor: String? { voiceActorList.first }

    // MARK: - Computed

    /// 誕生日表示用（"--04-03" → "4月3日"）
    var birthdayDisplay: String? {
        guard let birthday, birthday.hasPrefix("--") else { return birthday }
        let parts = birthday.dropFirst(2).split(separator: "-")
        guard parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]) else { return birthday }
        return "\(m)月\(d)日"
    }

    /// 身長表示
    var heightDisplay: String? {
        guard let height else { return nil }
        return height.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(height))cm" : "\(height)cm"
    }

    /// スリーサイズ表示
    var threeSizeDisplay: String? {
        guard let bust, let waist, let hip else { return nil }
        return "B\(Int(bust)) W\(Int(waist)) H\(Int(hip))"
    }

    /// 誕生月（"--MM-DD" 形式から取得）
    var birthMonth: Int? {
        guard let birthday, birthday.hasPrefix("--") else { return nil }
        let parts = birthday.dropFirst(2).split(separator: "-")
        guard let first = parts.first, let month = Int(first) else { return nil }
        return month
    }

    // MARK: - Associations

    static let brand = belongsTo(Brand.self)
    static let songArtists = hasMany(SongArtist.self)
    static let songs = hasMany(Song.self, through: songArtists, using: SongArtist.song)

    var brand: QueryInterfaceRequest<Brand> { request(for: Idol.brand) }
    var songs: QueryInterfaceRequest<Song> { request(for: Idol.songs) }
}

// MARK: - shortName

extension Idol {
    /// 表示用の短縮名。優先順位: nickname > given_name > name。
    /// アルゴリズム推測は撤廃、DB カラム値を信頼する。
    var shortName: String {
        if let nick = nickname, !nick.isEmpty { return nick }
        if let given = givenName, !given.isEmpty { return given }
        return name
    }
}
