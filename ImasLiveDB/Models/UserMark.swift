import Foundation
import GRDB
import SwiftUI

// MARK: - UserMarkEntity

enum UserMarkEntity: String, Codable, CaseIterable, Sendable {
    case song
    case idol
    case event
    case show
}

// MARK: - AttendanceType

/// 公演の参加種別 (.attended マークの text_value に保存)。nil(未保存)/旧bool参加は現地扱い。
enum AttendanceType: String, Codable, CaseIterable, Sendable {
    case live   // 現地参加
    case stream // 配信参加

    var label: String { self == .live ? "現地" : "配信" }
    var icon: String { self == .live ? "figure.wave" : "play.tv" }
}

// MARK: - UserMarkKind

enum UserMarkKind: String, Codable, CaseIterable, Sendable {
    case collected
    case favorite
    case myPick
    case attended
    case note
    case seat

    var label: String {
        switch self {
        case .collected: return "回収済"
        case .favorite:  return "お気に入り"
        case .myPick:    return "担当"
        case .attended:  return "参加"
        case .note:      return "メモ"
        case .seat:      return "座席"
        }
    }

    var icon: String {
        switch self {
        case .collected: return "checkmark.circle"
        case .favorite:  return "star"
        case .myPick:    return "heart"
        case .attended:  return "person.crop.circle.badge.checkmark"
        case .note:      return "note.text"
        case .seat:      return "chair"
        }
    }

    var activeIcon: String {
        switch self {
        case .collected: return "checkmark.circle.fill"
        case .favorite:  return "star.fill"
        case .myPick:    return "heart.fill"
        case .attended:  return "person.crop.circle.badge.checkmark"
        case .note:      return "note.text.badge.plus"
        case .seat:      return "chair.fill"
        }
    }

    var tint: Color {
        switch self {
        case .collected: return .green
        case .favorite:  return .yellow
        case .myPick:    return .pink
        case .attended:  return .blue
        case .note:      return .orange
        case .seat:      return .teal
        }
    }

    var applicableTo: Set<UserMarkEntity> {
        switch self {
        case .collected: return [.song]
        case .favorite:  return [.song, .idol, .event, .show]
        case .myPick:    return [.idol]
        case .attended:  return [.event, .show]
        case .note:      return [.song, .idol, .event, .show]
        case .seat:      return [.show, .event]
        }
    }
}

// MARK: - UserMark (GRDB Record)

struct UserMark: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "user_marks"

    var entityType: String
    var entityId: String
    var kind: String
    var boolValue: Bool
    var textValue: String?
    var updatedAt: String

    enum Columns {
        static let entityType = Column(CodingKeys.entityType)
        static let entityId   = Column(CodingKeys.entityId)
        static let kind       = Column(CodingKeys.kind)
        static let boolValue  = Column(CodingKeys.boolValue)
        static let textValue  = Column(CodingKeys.textValue)
        static let updatedAt  = Column(CodingKeys.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId   = "entity_id"
        case kind
        case boolValue  = "bool_value"
        case textValue  = "text_value"
        case updatedAt  = "updated_at"
    }
}
