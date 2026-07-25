import Foundation
import GRDB

/// ライブ会場 (施設)。
///
/// `shows.venue` は自由文字列で、同じ会場が最大 14 通りに割れていた
/// (幕張メッセ = `千葉・幕張メッセイベントホール` / `幕張イベントホール` / `幕張メッセ` …)。
/// 名前が変わる会場もある (武蔵野の森総合スポーツプラザ → 京王アリーナTOKYO) ため、
/// 名前ではなく **ID で同一性を持たせて** 履歴が分断されないようにする。
///
/// ホール/構成は `VenueHall` に分ける。「幕張メッセでやったライブ全部」を施設単位で
/// 串刺しできるようにするためと、キャパが構成で変わるため。
struct Venue: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "venues"

    var id: String
    /// 現行名。過去公演の表示には `VenueName` の当時名を使う。
    var name: String
    var nameKana: String?
    var prefecture: String?
    var city: String?
    /// 検索用の別名 (改行区切り)。旧名・通称を入れる。
    var aliases: String?
    /// 施設の代表キャパ (最大構成)。構成で変わる場合は `VenueHall.capacity` が優先。
    /// 出典が取れていない会場は nil のまま (推測値を入れない)。
    var capacity: Int?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, prefecture, city, aliases, capacity
        case nameKana = "name_kana"
        case sortOrder = "sort_order"
    }

    // MARK: - Associations

    static let names = hasMany(VenueName.self)
    static let halls = hasMany(VenueHall.self)
    static let shows = hasMany(Show.self)

    var names: QueryInterfaceRequest<VenueName> { request(for: Venue.names) }
    var halls: QueryInterfaceRequest<VenueHall> { request(for: Venue.halls) }

    // MARK: - Computed

    /// 検索対象になる別名の配列。
    var aliasList: [String] {
        (aliases ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// 「東京・日本武道館」のような地域つき表示。都道府県が無ければ名前だけ。
    var displayNameWithArea: String {
        guard let prefecture, !prefecture.isEmpty else { return name }
        return "\(prefecture)・\(name)"
    }

    /// 「14,500人」。キャパ未登録なら nil。
    var capacityLabel: String? {
        guard let capacity else { return nil }
        return "\(capacity.formatted(.number.grouping(.automatic)))人"
    }
}

/// 会場の名前と、その名前が有効だった期間。
///
/// 表示は「公演日時点の名前」にする。2021 年の公演は「武蔵野の森総合スポーツプラザ」、
/// 2026 年の公演は「京王アリーナTOKYO」と出す。チケットや当時の記憶と一致させるため。
struct VenueName: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "venue_names"

    var id: String
    var venueId: String
    var name: String
    /// nil = 開業時から。
    var validFrom: String?
    /// nil = 現在も使われている名前。
    var validTo: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case venueId = "venue_id"
        case validFrom = "valid_from"
        case validTo = "valid_to"
    }

    /// 指定日 (YYYY-MM-DD) にこの名前が有効だったか。
    /// 境界は `validFrom <= date < validTo` (改名日当日は新しい名前を採る)。
    func isValid(on date: String) -> Bool {
        if let validFrom, date < validFrom { return false }
        if let validTo, date >= validTo { return false }
        return true
    }
}

/// 会場のホール / 構成。
///
/// キャパは構成で変わる (さいたまスーパーアリーナ: スタジアムモード 37,000 /
/// アリーナモード 22,500) ため、施設ではなくこちら側で持てるようにする。
struct VenueHall: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "venue_halls"

    var id: String
    var venueId: String
    var name: String
    /// 出典が取れていないホールは nil のまま。
    var capacity: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, capacity
        case venueId = "venue_id"
    }
}

// MARK: - 名前の解決

extension Collection where Element == VenueName {
    /// 指定日時点で有効だった名前を返す。該当が無ければ最も新しい名前にフォールバックする
    /// (有効期間の抜けがあっても表示が空にならないようにするため)。
    func name(on date: String) -> String? {
        if let hit = first(where: { $0.isValid(on: date) }) { return hit.name }
        return self.max(by: { ($0.validFrom ?? "") < ($1.validFrom ?? "") })?.name
    }
}

// MARK: - VenueDirectory

/// 会場マスタ一式をメモリに載せた解決器。
///
/// 245施設 + 名前246件 + ホール40件と小さいので一括で読み、公演ごとの引き直し (N+1) を避ける。
/// 「公演日時点の名前」「その構成でのキャパ」の解決はここに集約する。
struct VenueDirectory: Sendable {
    let venues: [Venue]
    private let byId: [String: Venue]
    private let namesByVenue: [String: [VenueName]]
    private let hallsByVenue: [String: [VenueHall]]

    init(venues: [Venue], names: [VenueName], halls: [VenueHall]) {
        self.venues = venues
        self.byId = Dictionary(venues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.namesByVenue = Dictionary(grouping: names, by: \.venueId)
        self.hallsByVenue = Dictionary(grouping: halls, by: \.venueId)
    }

    static let empty = VenueDirectory(venues: [], names: [], halls: [])

    func venue(id: String?) -> Venue? {
        guard let id else { return nil }
        return byId[id]
    }

    func halls(of venueId: String) -> [VenueHall] { hallsByVenue[venueId] ?? [] }

    /// 公演日時点の会場名。改名前の公演には当時の名前を返す
    /// (2021年の公演は「武蔵野の森総合スポーツプラザ」、2025-05-01 以降は「京王アリーナTOKYO」)。
    func name(venueId: String, on date: String) -> String? {
        namesByVenue[venueId]?.name(on: date) ?? byId[venueId]?.name
    }

    /// 公演の会場表示名。会場が未解決 (配信のみ等) なら生文字列にフォールバックする。
    /// ホールがあれば「幕張メッセ 幕張イベントホール」のように併記する。
    func displayName(for show: Show) -> String? {
        guard let venueId = show.venueId, let base = name(venueId: venueId, on: show.date) else {
            return show.venue
        }
        guard let hall = show.hall, !hall.isEmpty else { return base }
        return "\(base) \(hall)"
    }

    /// 公演のキャパ。ホール指定があればホール側を優先する
    /// (さいたまスーパーアリーナはスタジアム37,000 / アリーナ22,500 と倍近く違う)。
    func capacity(for show: Show) -> Int? {
        guard let venueId = show.venueId else { return nil }
        if let hall = show.hall,
           let match = halls(of: venueId).first(where: { $0.name == hall }),
           let capacity = match.capacity {
            return capacity
        }
        return byId[venueId]?.capacity
    }
}
