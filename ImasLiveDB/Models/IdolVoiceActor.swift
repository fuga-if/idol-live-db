import Foundation
import GRDB

/// アイドルの担当声優を**期間つき**で持つ。
///
/// 旧 `idols.voice_actors` は "現役,過去CV" のカンマ区切りで期間を持てず、
/// 交代すると前任者が消えていた (九十九一希の初代が実際に消えていた)。
/// 期間で持てば「2019年の楽曲は誰の声だったか」が辿れる。
///
/// 形は `venue_names` に倣う。`validTo == nil` が現任。
/// `validFrom` の初代はキャラの実装日 (`idols.debutDate`)。
///
/// ⚠️ CloudKit 同期の対象外。`anniversaries` と同じく同梱 master.sqlite の
///    data_version を上げた reseed で配る。声優の交代はごく稀なので、
///    レコード型を増やしてまで差分同期する必要がない。
struct IdolVoiceActor: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "idol_voice_actors"

    /// `<idol_id>__<name>`。
    var id: String
    var idolId: String
    var name: String
    /// 担当開始日。不明なら nil。
    var validFrom: String?
    /// 担当終了日。nil なら現任。
    var validTo: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case idolId = "idol_id"
        case validFrom = "valid_from"
        case validTo = "valid_to"
    }

    /// 現任かどうか。
    var isCurrent: Bool { validTo == nil }
}
