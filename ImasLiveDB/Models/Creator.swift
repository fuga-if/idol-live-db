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
    /// 正規化した表記。曲側の揺れは `aliases` に持つ。
    var name: String
    var nameKana: String
    /// 曲側に現れる表記の揺れ (改行区切り)。
    ///
    /// 同じ人が社名の変遷と括弧の全角半角で最大 9 通りに割れていた
    /// (BNEI(佐藤貴文) / BNSI（佐藤貴文） / NBGI(佐藤貴文) / 佐藤貴文 …)。
    /// 曲から作家を引くときはここを見る。
    var aliases: String?

    enum CodingKeys: String, CodingKey {
        case id, name, aliases
        case nameKana = "name_kana"
    }

    /// 検索・突き合わせ対象になる表記の配列 (正規名 + 別表記)。
    var allSpellings: [String] {
        [name] + (aliases ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
