import Foundation
import CloudKit

enum CKRecordMapper {

    // MARK: - Core Entities

    static func brand(from record: CKRecord) -> Brand? {
        let id = record["id"] as? String ?? record.recordID.recordName
        guard !id.isEmpty else { return nil }
        let name = record["name"] as? String ?? ""
        guard !name.isEmpty else { return nil }
        let color = validatedHex(record["color"] as? String)
        return Brand(
            id: id,
            name: name,
            shortName: record["shortName"] as? String ?? "",
            color: color,
            sortOrder: intValue(record["sortOrder"]),
            iconUrl: record["iconUrl"] as? String
        )
    }

    static func idol(from record: CKRecord) -> Idol? {
        let id = record["id"] as? String ?? record.recordID.recordName
        guard !id.isEmpty else { return nil }
        let name = record["name"] as? String ?? ""
        guard !name.isEmpty else { return nil }
        let color = validatedHex(record["color"] as? String)
        return Idol(
            id: id,
            brandId: record["brandId"] as? String ?? "",
            name: name,
            nameKana: record["nameKana"] as? String,
            nameRomaji: record["nameRomaji"] as? String,
            familyName: record["familyName"] as? String,
            givenName: record["givenName"] as? String,
            nickname: record["nickname"] as? String,
            color: color,
            sortOrder: intValue(record["sortOrder"]),
            birthday: record["birthday"] as? String,
            bloodType: record["bloodType"] as? String,
            height: record["height"] as? Double,
            weight: record["weight"] as? Double,
            birthPlace: record["birthPlace"] as? String,
            age: optionalIntValue(record["age"]),
            bust: record["bust"] as? Double,
            waist: record["waist"] as? Double,
            hip: record["hip"] as? Double,
            constellation: record["constellation"] as? String,
            hobbies: record["hobbies"] as? String,
            talents: record["talents"] as? String,
            description: record["description"] as? String,
            gender: record["gender"] as? String,
            handedness: record["handedness"] as? String,
            debutDate: record["debutDate"] as? String,
            attribute: record["attribute"] as? String,
            isExternal: (record["isExternal"] as? Int64 ?? 0) != 0,
            aliases: record["aliases"] as? String,
            voiceActors: record["voiceActors"] as? String
        )
    }

    // Cast テーブル廃止: CastMember レコードは取り込まない。 旧 CK スキーマに存在する
    // CastMember レコードは CloudKitSyncEngine 側で無視する。

    static func event(from record: CKRecord) -> Event? {
        let id = record["id"] as? String ?? record.recordID.recordName
        guard !id.isEmpty else { return nil }
        let name = record["name"] as? String ?? ""
        guard !name.isEmpty else { return nil }
        let kind = record["kind"] as? String ?? EventKind.live.rawValue
        return Event(
            id: id,
            brandId: record["brandId"] as? String,
            name: name,
            eventType: record["eventType"] as? String ?? "live",
            isStreaming: boolValue(record["isStreaming"]),
            isSolo: boolValue(record["isSolo"], default: true),
            kind: kind,
            ticketOpenDate: record["ticketOpenDate"] as? String,
            ticketDeadline: record["ticketDeadline"] as? String,
            ticketLotteryDate: record["ticketLotteryDate"] as? String,
            ticketUrl: record["ticketUrl"] as? String,
            jointBrandIds: record["jointBrandIds"] as? String
        )
    }

    static func show(from record: CKRecord) -> Show? {
        let id = record["id"] as? String ?? record.recordID.recordName
        guard !id.isEmpty else { return nil }
        let eventId = record["eventId"] as? String ?? ""
        guard !eventId.isEmpty else { return nil }
        let date = record["date"] as? String ?? ""
        guard !date.isEmpty else { return nil }
        return Show(
            id: id,
            eventId: eventId,
            name: record["name"] as? String ?? "",
            date: date,
            venue: record["venue"] as? String,
            venueCity: record["venueCity"] as? String,
            startTime: record["startTime"] as? String,
            sortOrder: intValue(record["sortOrder"]),
            performerType: record["performerType"] as? String
        )
    }

    static func song(from record: CKRecord) -> Song? {
        let id = record["id"] as? String ?? record.recordID.recordName
        guard !id.isEmpty else { return nil }
        let title = record["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        return Song(
            id: id,
            title: title,
            titleKana: record["titleKana"] as? String,
            brandId: record["brandId"] as? String,
            songType: record["songType"] as? String ?? "solo",
            releaseDate: record["releaseDate"] as? String,
            durationSec: optionalIntValue(record["durationSec"]),
            composer: record["composer"] as? String,
            lyricist: record["lyricist"] as? String,
            arranger: record["arranger"] as? String,
            cdSeries: record["cdSeries"] as? String,
            cdTitle: record["cdTitle"] as? String,
            artworkUrl: record["artworkUrl"] as? String,
            previewUrl: record["previewUrl"] as? String,
            appleMusicId: record["appleMusicId"] as? String,
            appleMusicAlbumId: record["appleMusicAlbumId"] as? String,
            isrc: record["isrc"] as? String,
            lyricsUrl: record["lyricsUrl"] as? String,
            parentSongId: record["parentSongId"] as? String,
            singerLabel: record["singerLabel"] as? String,
            unitName: record["unitName"] as? String,
            unitId: record["unitId"] as? String
        )
    }

    static func unit(from record: CKRecord) -> Unit? {
        let id = record["id"] as? String ?? record.recordID.recordName
        guard !id.isEmpty else { return nil }
        let name = record["name"] as? String ?? ""
        guard !name.isEmpty else { return nil }
        return Unit(
            id: id,
            brandId: record["brandId"] as? String ?? "",
            name: name,
            isPermanent: boolValue(record["isPermanent"], default: true),
            nameAlt: record["nameAlt"] as? String
        )
    }

    // MARK: - Junction Tables

    // IdolCast 廃止: idol.voiceActors に統合済み、 旧 CK レコードは無視する。

    static func idolBrand(from record: CKRecord) -> IdolBrand? {
        let idolId = record["idolId"] as? String ?? ""
        let brandId = record["brandId"] as? String ?? ""
        guard !idolId.isEmpty, !brandId.isEmpty else { return nil }
        return IdolBrand(
            idolId: idolId,
            brandId: brandId,
            isPrimary: boolValue(record["isPrimary"])
        )
    }

    static func songArtist(from record: CKRecord) -> SongArtist? {
        let songId = record["songId"] as? String ?? ""
        let idolId = record["idolId"] as? String ?? ""
        guard !songId.isEmpty, !idolId.isEmpty else { return nil }
        return SongArtist(
            songId: songId,
            idolId: idolId,
            role: record["role"] as? String ?? "original"
        )
    }

    static func unitMember(from record: CKRecord) -> UnitMember? {
        let unitId = record["unitId"] as? String ?? ""
        let idolId = record["idolId"] as? String ?? ""
        guard !unitId.isEmpty, !idolId.isEmpty else { return nil }
        return UnitMember(
            unitId: unitId,
            idolId: idolId
        )
    }

    static func showCast(from record: CKRecord) -> ShowCast? {
        let showId = record["showId"] as? String ?? ""
        // 新スキーマは idolId フィールド。 旧 CK レコードの castId は廃止 (取り込まない)。
        guard let idolId = record["idolId"] as? String, !showId.isEmpty, !idolId.isEmpty else {
            return nil
        }
        return ShowCast(
            showId: showId,
            idolId: idolId,
            castRole: CastRole(rawValue: record["castRole"] as? String ?? "member") ?? .member
        )
    }

    static func setlistItem(from record: CKRecord) -> SetlistItem? {
        let id = record["id"] as? String ?? record.recordID.recordName
        guard !id.isEmpty else { return nil }
        let showId = record["showId"] as? String ?? ""
        let songId = record["songId"] as? String ?? ""
        guard !showId.isEmpty, !songId.isEmpty else { return nil }
        return SetlistItem(
            id: id,
            showId: showId,
            songId: songId,
            position: intValue(record["position"]),
            section: record["section"] as? String,
            notes: record["notes"] as? String,
            unitName: record["unitName"] as? String
        )
    }

    static func setlistPerformer(from record: CKRecord) -> SetlistPerformer? {
        let setlistItemId = record["setlistItemId"] as? String ?? ""
        guard let idolId = record["idolId"] as? String, !setlistItemId.isEmpty, !idolId.isEmpty else {
            return nil
        }
        return SetlistPerformer(setlistItemId: setlistItemId, idolId: idolId)
    }

    // MARK: - Community Content

    static func songCall(from record: CKRecord) -> SongCall? {
        let songId = record["songId"] as? String ?? ""
        let callText = record["callText"] as? String ?? ""
        guard !songId.isEmpty, !callText.isEmpty else { return nil }
        return SongCall(
            id: record.recordID.recordName,
            songId: songId,
            callText: callText,
            sourceUrl: record["sourceUrl"] as? String,
            createdAt: createdAtString(from: record),
            authorDisplayName: record["authorDisplayName"] as? String
        )
    }

    static func songVideo(from record: CKRecord) -> SongVideo? {
        let songId = record["songId"] as? String ?? ""
        let youtubeUrl = record["youtubeUrl"] as? String ?? ""
        guard !songId.isEmpty, !youtubeUrl.isEmpty else { return nil }
        return SongVideo(
            id: record.recordID.recordName,
            songId: songId,
            youtubeUrl: youtubeUrl,
            videoTitle: record["videoTitle"] as? String,
            note: record["note"] as? String,
            createdAt: createdAtString(from: record),
            authorDisplayName: record["authorDisplayName"] as? String
        )
    }

    // MARK: - Soft Delete

    static func deletedAt(from record: CKRecord) -> Date? {
        record["deletedAt"] as? Date
    }

    // MARK: - Helpers

    private static func createdAtString(from record: CKRecord) -> String {
        let date = record["createdAt"] as? Date ?? Date()
        return ISO8601DateFormatter.shared.string(from: date)
    }

    /// HEXカラー文字列のバリデーション。HexColor.init(rawValue:) 経由で 6/8 桁に統一。
    private static func validatedHex(_ value: String?) -> String? {
        guard let value else { return nil }
        return HexColor(rawValue: value)?.rawValue
    }

    /// CKRecordのInt64値をIntに変換
    private static func intValue(_ value: Any?) -> Int {
        if let int64 = value as? Int64 { return Int(int64) }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }

    /// CKRecordのOptional Int64値をOptional Intに変換
    private static func optionalIntValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let int64 = value as? Int64 { return Int(int64) }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    /// CKRecordのBool値を変換
    private static func boolValue(_ value: Any?, default defaultValue: Bool = false) -> Bool {
        if let bool = value as? Bool { return bool }
        if let int64 = value as? Int64 { return int64 != 0 }
        if let int = value as? Int { return int != 0 }
        if let number = value as? NSNumber { return number.boolValue }
        return defaultValue
    }
}
