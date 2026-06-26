#if DEBUG
import CloudKit
import os

/// Development環境でCloudKitスキーマを自動生成するためのワンショット関数
/// 各レコードタイプのダミーレコードを保存→削除してスキーマを定義する
enum CloudKitSchemaBootstrap {
    static func createSchema() async {
        let db = CKContainer(identifier: "iCloud.com.fugaif.ImasLiveDB").publicCloudDatabase

        // TODO: CloudKit Dashboard で各 record type の deletedAt フィールドを
        // Queryable/Sortable に手動設定すること（以下参照: docs/cloudkit-schema.md）
        let types: [(String, [String: any CKRecordValueProtocol])] = [
            ("Brand", ["name": "x", "shortName": "x", "color": "x", "sortOrder": 0]),
            ("Idol", ["brandId": "x", "name": "x", "nameKana": "x", "nameRomaji": "x", "color": "x", "sortOrder": 0, "birthday": "x", "bloodType": "x", "height": 0.0, "weight": 0.0, "birthPlace": "x", "age": 0, "bust": 0.0, "waist": 0.0, "hip": 0.0, "constellation": "x", "hobbies": "x", "talents": "x", "description": "x", "gender": "x", "handedness": "x", "debutDate": "x", "attribute": "x", "isExternal": 0]),
            ("CastMember", ["name": "x", "nameKana": "x", "nameRomaji": "x"]),
            ("Event", ["brandId": "x", "name": "x", "eventType": "x", "isStreaming": 0, "isSolo": 1, "kind": "live", "ticketOpenDate": "x", "ticketDeadline": "x", "ticketLotteryDate": "x", "ticketUrl": "x"]),
            ("Show", ["eventId": "x", "name": "x", "date": "x", "venue": "x", "venueCity": "x", "startTime": "x", "sortOrder": 0, "performerType": "x"]),
            ("Song", ["title": "x", "titleKana": "x", "brandId": "x", "songType": "x", "releaseDate": "x", "durationSec": 0, "composer": "x", "lyricist": "x", "arranger": "x", "cdSeries": "x", "cdTitle": "x", "artworkUrl": "x", "previewUrl": "x", "appleMusicId": "x", "appleMusicAlbumId": "x", "isrc": "x", "lyricsUrl": "x", "parentSongId": "x", "singerLabel": "x", "unitName": "x", "unitId": "x"]),
            ("ImasUnit", ["brandId": "x", "name": "x", "isPermanent": 0, "nameAlt": "x"]),
            ("SetlistItem", ["showId": "x", "songId": "x", "position": 0, "section": "x", "notes": "x", "unitName": "x"]),
                        ("SetlistPerformer", ["setlistItemId": "x", "idolId": "x"]),
            ("ShowCast", ["showId": "x", "idolId": "x"]),
            // CastMember / IdolCast は廃止 (idol.voiceActors に統合)。 ブートストラップ対象外。
            ("IdolBrand", ["idolId": "x", "brandId": "x", "isPrimary": 0]),
            ("SongArtist", ["songId": "x", "idolId": "x", "role": "x"]),
            ("UnitMember", ["unitId": "x", "idolId": "x"]),
            ("MetaData", ["value": "x"]),
            ("SongCall", ["songId": "x", "callText": "x", "sourceUrl": "x", "authorDisplayName": "x", "createdAt": Date()]),
            ("SongVideo", ["songId": "x", "youtubeUrl": "x", "videoTitle": "x", "note": "x", "authorDisplayName": "x", "createdAt": Date()]),
        ]

        for (typeName, fields) in types {
            let recordID = CKRecord.ID(recordName: "bootstrap-\(typeName)")
            let record = CKRecord(recordType: typeName, recordID: recordID)
            for (key, value) in fields {
                record[key] = value as? CKRecordValue
            }
            record["modifiedAt"] = Date()
            // deletedAt フィールドをスキーマに登録（soft delete 用）
            record["deletedAt"] = Date() as CKRecordValue

            do {
                try await db.save(record)
                try await db.deleteRecord(withID: recordID)
                Logger.cloudkit.info("schema_ok: \(typeName)")
            } catch {
                Logger.cloudkit.error("schema_failed: \(typeName) \(error.localizedDescription)")
            }
        }
        Logger.cloudkit.info("schema_done")
    }

    /// 結果をStringで返す版
    static func createSchemaWithStatus() async -> String {
        let db = CKContainer(identifier: "iCloud.com.fugaif.ImasLiveDB").publicCloudDatabase

        let typeNames = ["Brand", "Idol", "Event", "Show", "Song", "ImasUnit",
                         "SetlistItem", "SetlistPerformer", "ShowCast", "IdolBrand",
                         "SongArtist", "UnitMember", "MetaData", "SongCall", "SongVideo"]

        let sampleFields: [String: [String: any CKRecordValueProtocol]] = [
            "Brand": ["name": "x", "shortName": "x", "color": "x", "sortOrder": 0],
            "Idol": ["brandId": "x", "name": "x", "nameKana": "x", "nameRomaji": "x", "color": "x", "sortOrder": 0, "birthday": "x", "bloodType": "x", "height": 0.0, "weight": 0.0, "birthPlace": "x", "age": 0, "bust": 0.0, "waist": 0.0, "hip": 0.0, "constellation": "x", "hobbies": "x", "talents": "x", "description": "x", "gender": "x", "handedness": "x", "debutDate": "x", "attribute": "x", "isExternal": 0, "voiceActors": "x"],
            "CastMember": ["name": "x", "nameKana": "x", "nameRomaji": "x"],
            "Event": ["brandId": "x", "name": "x", "eventType": "x", "isStreaming": 0, "isSolo": 1, "kind": "live", "ticketOpenDate": "x", "ticketDeadline": "x", "ticketLotteryDate": "x", "ticketUrl": "x"],
            "Show": ["eventId": "x", "name": "x", "date": "x", "venue": "x", "venueCity": "x", "startTime": "x", "sortOrder": 0, "performerType": "x"],
            "Song": ["title": "x", "titleKana": "x", "brandId": "x", "songType": "x", "releaseDate": "x", "durationSec": 0, "composer": "x", "lyricist": "x", "arranger": "x", "cdSeries": "x", "cdTitle": "x", "artworkUrl": "x", "previewUrl": "x", "appleMusicId": "x", "appleMusicAlbumId": "x", "isrc": "x", "lyricsUrl": "x", "parentSongId": "x", "singerLabel": "x", "unitName": "x", "unitId": "x"],
            "ImasUnit": ["brandId": "x", "name": "x", "isPermanent": 0, "nameAlt": "x"],
            "SetlistItem": ["showId": "x", "songId": "x", "position": 0, "section": "x", "notes": "x", "unitName": "x"],
            "SetlistPerformer": ["setlistItemId": "x", "idolId": "x"],
            "ShowCast": ["showId": "x", "idolId": "x"],
            "IdolBrand": ["idolId": "x", "brandId": "x", "isPrimary": 0],
            "SongArtist": ["songId": "x", "idolId": "x", "role": "x"],
            "UnitMember": ["unitId": "x", "idolId": "x"],
            "MetaData": ["key": "x", "value": "x"],
            "SongCall": ["songId": "x", "callText": "x", "sourceUrl": "x", "authorDisplayName": "x", "createdAt": Date()],
            "SongVideo": ["songId": "x", "youtubeUrl": "x", "videoTitle": "x", "note": "x", "authorDisplayName": "x", "createdAt": Date()],
        ]

        var results: [String] = []
        var success = 0
        var failed = 0

        for typeName in typeNames {
            let recordID = CKRecord.ID(recordName: "bootstrap-\(typeName)")
            let record = CKRecord(recordType: typeName, recordID: recordID)
            if let fields = sampleFields[typeName] {
                for (key, value) in fields {
                    record[key] = value as? CKRecordValue
                }
            }
            record["modifiedAt"] = Date()
            // deletedAt フィールドをスキーマに登録（soft delete 用）
            record["deletedAt"] = Date() as CKRecordValue

            do {
                try await db.save(record)
                try await db.deleteRecord(withID: recordID)
                results.append("\(typeName) ✓")
                success += 1
            } catch {
                results.append("\(typeName) ✗ \(error.localizedDescription)")
                failed += 1
            }
        }

        return "\(success)/\(typeNames.count) 成功\n" + results.joined(separator: "\n")
    }
}
#endif
