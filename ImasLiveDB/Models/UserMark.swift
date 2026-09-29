import Foundation
import GRDB
import SwiftUI

// MARK: - UserMarkEntity

enum UserMarkEntity: String, Codable, CaseIterable, Sendable {
    case song
    case idol
    case event
    case show
    case release  // 映像円盤 (event_releases)
}

// MARK: - AttendanceType

/// 公演の参加種別 (.attended マークの text_value に保存)。nil(未保存)/旧bool参加は現地扱い。
/// 選択肢は「そのライブに実在した形態だけ」UIに出す (開催形態フラグで出し分け)。
enum AttendanceType: String, Codable, CaseIterable, Sendable {
    case live        // 現地参加
    case stream      // 配信参加
    case liveViewing = "live_viewing" // ライブビューイング参加

    /// 語はコアの vocabulary (券の形態も同じ語)。
    var label: String {
        Vocab.attendanceType(rawValue)?.shortLabel ?? rawValue
    }

    var icon: String {
        switch self {
        case .live:        return "figure.wave"
        case .stream:      return "play.tv"
        case .liveViewing: return "popcorn"
        }
    }
}

// MARK: - UserMarkKind

enum UserMarkKind: String, Codable, CaseIterable, Sendable {
    case collected
    case favorite
    case myPick
    case attended
    case note
    case seat
    case owned
    /// 楽曲の習熟度 (段階)。`text_value` に序数 "0".."8" を入れる。
    /// bool 系マークと違って**順序がある**ので、ラベルはユーザー設定から引く。
    case mastery

    var label: String {
        switch self {
        case .collected: return "回収済"
        case .favorite:  return "お気に入り"
        case .myPick:    return "担当"
        case .attended:  return "参加"
        case .note:      return "メモ"
        case .seat:      return "座席"
        case .owned:     return "所有"
        case .mastery:   return "習熟度"
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
        // 円盤 (release) だけでなくカード (song) にも付くようになったため、
        // 円盤専用の見た目 (opticaldisc) から「所有物」を表す中立なアイコンに変更。
        case .owned:     return "shippingbox"
        case .mastery:   return "chart.bar"
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
        case .owned:     return "shippingbox.fill"
        case .mastery:   return "chart.bar.fill"
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
        case .owned:     return .purple
        case .mastery:   return .indigo
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
        // 円盤所有と同じ器を KAMISABI カード所持にも使う。`user_marks` は CloudKit には
        // 乗らない (端末ローカル唯一データ) が、`UserMarkBackup` 経由の iCloud KVS
        // バックアップ (機種変・再インストール復元用) はそのまま効く。
        case .owned:     return [.release, .song]
        case .mastery:   return [.song]
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

    /// バックアップとコアに渡す射影。
    var backupRecord: BackupUserMarkRecord {
        BackupUserMarkRecord(
            entityType: entityType, entityId: entityId, kind: kind,
            boolValue: boolValue, textValue: textValue, updatedAt: updatedAt)
    }

    /// 付いている行だけを残す (フラグが立っているか、空白以外の文字がある)。
    ///
    /// 規則はコア (`backupMeaningfulMarkIndices`) 1 本で、iCloud KVS に載せる行と同じ。
    /// 習熟度・メモ・座席はフラグを立てずに中身を文字で持つので、フラグだけで絞ると落ちる。
    static func meaningful(_ marks: [UserMark]) -> [UserMark] {
        backupMeaningfulMarkIndices(marks: marks.map(\.backupRecord)).map { marks[Int($0)] }
    }
}
