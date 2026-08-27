import Foundation
import GRDB

/// 作詞・作曲・編曲の表記と、その読み。
///
/// 読みは**人 (表記) の属性**であって曲の属性ではない。同じ作家が数十曲に出るので、
/// 曲側に持たせると同じ読みが何十行にも複製され、直すときに全部を追うことになる。
/// 会場をまとめた `Venue` と同じ理由で別表にする。
///
/// `name` は `songs.composer` / `lyricist` / `arranger` に入っている**表記そのもの**で、
/// 区切り文字では割らない。割ると括弧の内側で壊れるため
/// (「BNEI(中川浩二、上田夢人)」が「BNEI(中川浩二」と「上田夢人)」になる)。
/// 検索は表記まるごとの読みに対して部分一致するので、割らなくても
/// 「うえだ」で当たる。
struct Creator: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "creators"

    var id: String
    var name: String
    var nameKana: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case nameKana = "name_kana"
    }
}
