import Foundation
import GRDB

struct Brand: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "brands"

    var id: String
    var name: String
    var shortName: String
    var color: String?
    var sortOrder: Int
    var iconUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case shortName = "short_name"
        case color
        case sortOrder = "sort_order"
        case iconUrl = "icon_url"
    }
}

// MARK: - Icon Text

extension Brand {
    /// アイコン円内に表示する短いテキスト (3-4 字)。
    /// 公式ロゴは版権 NG なので、ブランドカラー背景に「765」「ミリ」等を載せる。
    var iconText: String {
        switch id {
        case "765as":  return "765"
        case "961":    return "961"
        case "876":    return "876"
        case "cg":     return "デレ"
        case "ml":     return "ミリ"
        case "sidem":  return "SideM"
        case "sc":     return "シャニ"
        case "gakuen": return "学マス"
        case "valv":   return "ヴィ"
        case "other":  return "他"
        default:       return String(shortName.prefix(2))
        }
    }
}
