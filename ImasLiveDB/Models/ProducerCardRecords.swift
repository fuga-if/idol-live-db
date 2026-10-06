import Foundation
import GRDB

/// 自分の P名刺のうち、自分で書いた中身 (名前・ひとこと・P歴・リンク・外した項目)。
/// **端末ローカル唯一データ** (収支と同じ扱い、破壊的な移行はしない)。
///
/// 担当・記録の数・次の現場・参加公演はアプリの記録から交換のたびに作り直すので持たない
/// (持つと記録とずれる)。名刺の組み立て・QR の中身・リンクの正規化はコア (`domain/producer_card.rs`)。
struct MyProducerCard: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "my_producer_card"
    /// 自分の名刺は 1 枚だけ。
    static let singletonId = "me"

    var id: String
    var name: String
    var message: String
    /// P 歴の始まり (西暦)。
    var sinceYear: Int?
    /// リンクの保存の形 (`cardLinksToJson`)。
    var linksJson: String
    /// 名刺から外した項目 (`ProducerCardField` の rawValue をカンマで)。
    var hiddenFields: String
    var updatedAt: String
    /// 名刺のデザインの保存のキー (`cardDesignKey`)。空は既定のデザイン。書体を選んでいた頃の
    /// 書体のキーが残っていることもある (`cardDesignFromKey` が近いデザインに読み替える)。
    var design: String = ""
    /// 自分の QR の URL (正規化済み、`normalizeCardQrUrl`)。
    var qrUrl: String? = nil
    /// プロフィール帳の中身 (コアの保存の形 `profileSheetToJson`)。空はまだ作っていない。
    var profileJson: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, message
        case sinceYear = "since_year"
        case linksJson = "links_json"
        case hiddenFields = "hidden_fields"
        case updatedAt = "updated_at"
        case design
        case qrUrl = "qr_url"
        case profileJson = "profile_json"
    }

    static func empty() -> MyProducerCard {
        MyProducerCard(id: singletonId, name: "", message: "", sinceYear: nil,
                       linksJson: "[]", hiddenFields: "", updatedAt: "")
    }

    /// 名刺のデザイン (保存のキーが空・知らないものなら既定)。
    var cardDesign: CardDesign {
        get { cardDesignFromKey(key: design) ?? cardDesigns()[0].design }
        set { design = cardDesignKey(design: newValue) }
    }

    var links: [CardLink] {
        get { cardLinksFromJson(json: linksJson) }
        set { linksJson = cardLinksToJson(links: newValue) }
    }

    var hidden: Set<ProducerCardField> {
        get { Set(hiddenFields.split(separator: ",").compactMap { ProducerCardField(rawValue: String($0)) }) }
        set { hiddenFields = ProducerCardField.allCases.filter(newValue.contains).map(\.rawValue).joined(separator: ",") }
    }

    func shows(_ field: ProducerCardField) -> Bool { !hidden.contains(field) }

    /// プロフィール帳 (まだ作っていなければ既定の中身。壊れた保存も既定に戻す、規則はコア)。
    var profile: ProfileSheet {
        get { profileJson.isEmpty ? profileSheetDefault() : profileSheetFromJson(json: profileJson) }
        set { profileJson = profileSheetToJson(sheet: newValue) }
    }
}

/// 名刺に載せる項目のうち、1 つずつ外せるもの。rawValue は保存のキー (変えない)。
enum ProducerCardField: String, CaseIterable, Sendable {
    case oshi
    case message
    case since
    case links
    case showCount = "show_count"
    case songCount = "song_count"
    case next
    case attended

    var label: String {
        switch self {
        case .oshi: return "担当"
        case .message: return "ひとこと"
        case .since: return "P歴"
        case .links: return "リンク"
        case .showCount: return "参加公演数"
        case .songCount: return "回収曲数"
        case .next: return "次の現場"
        case .attended: return "参加した公演の一覧"
        }
    }
}

/// 受け取った P名刺 1 枚。**端末ローカル唯一データ**。
///
/// 名刺の中身は `#` の後ろ (`payload`) のまま持ち、表示のたびにコアで読み解く
/// (読み解き方が変わっても保存した名刺は壊れない)。紙の名刺もコアの `producerCardPayload` で
/// 同じ形にして入れる。写真・受け取った担当の画像は端末のファイル (`ProducerCardFiles`)。
struct ReceivedProducerCard: Codable, FetchableRecord, PersistableRecord, Hashable, Identifiable, Sendable {
    static let databaseTableName = "received_producer_cards"

    enum Source: String, Sendable {
        /// アプリの QR・名刺ファイル・近くの端末から。
        case app
        /// 紙の名刺を撮って取り込んだもの。
        case paper
    }

    var id: String
    var payload: String
    var source: String
    /// 受け取った公演。
    var showId: String?
    /// 受け取った公演の日付 (`YYYY-MM-DD`)。束ねるときに使う。
    var showDate: String?
    var memo: String?
    /// 受け取った日時 (ISO 8601)。
    var receivedAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, payload, source, memo
        case showId = "show_id"
        case showDate = "show_date"
        case receivedAt = "received_at"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let payload = Column(CodingKeys.payload)
        static let receivedAt = Column(CodingKeys.receivedAt)
    }

    var sourceValue: Source { Source(rawValue: source) ?? .app }

    /// 名刺の中身。読み解けなければ nil (画面は名前の無い名刺として出さずに飛ばす)。
    var card: ProducerCard? { decodeProducerCard(text: payload) }

    static func make(payload: String, source: Source, showId: String?, showDate: String?,
                     memo: String? = nil, now: Date = Date()) -> ReceivedProducerCard {
        let stamp = ISO8601DateFormatter.shared.string(from: now)
        return ReceivedProducerCard(
            id: UUID().uuidString, payload: payload, source: source.rawValue,
            showId: showId, showDate: showDate,
            memo: memo?.isEmpty == true ? nil : memo,
            receivedAt: stamp, updatedAt: stamp
        )
    }
}

/// 名刺に出す公演 1 件 (受け取った公演・共通点・次の現場)。
struct ProducerCardShowInfo: Hashable, Sendable {
    let id: String
    let eventId: String
    let date: String
    /// `showDisplayTitle` で組んだ表記。
    let label: String
    let venue: String?
    /// ライブのブランド (プロフィール帳の担当ブランド・職務経歴に使う)。
    var brandId: String? = nil
}
