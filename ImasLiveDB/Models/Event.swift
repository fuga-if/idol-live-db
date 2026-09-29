import Foundation
import GRDB

/// イベント種別（5カテゴリ）。
/// - `live`: アイマス主催ライブ（単独・MOIW等の合同を含む）
/// - `festival`: 外部主催フェスにアイマスがゲスト出演
/// - `releaseEvent`: リリイベ・発売記念・サイン会・上映会・トーク&ミニライブ等
/// - `radio`: ラジオ番組・公開録音・DJCD・P祭り等
/// - `stream`: YouTube歌枠・Vtuber配信・コラボ配信
///
/// EventListView（ライブタブ）は `live` / `festival` のみ表示。
/// 他カテゴリは別画面（イベント・配信タブ 等）で一覧する想定。
enum EventKind: String, Codable, Sendable, CaseIterable {
    case live
    case festival
    case releaseEvent = "release_event"
    case radio
    case stream
    /// 知らない種別の受け皿 (語彙の `other`)。コアは知らない種別をこれに寄せて絞る (Q-08l)。
    case other

    /// UI 表示用の短いラベル (語はコアの vocabulary)。
    var displayLabel: String {
        Vocab.eventKind(rawValue)?.shortLabel ?? rawValue
    }

    /// SF Symbol
    var iconName: String {
        switch self {
        case .live:         return "music.mic"
        case .festival:     return "party.popper"
        case .releaseEvent: return "opticaldisc"
        case .radio:        return "radio"
        case .stream:       return "play.tv"
        case .other:        return "ellipsis.circle"
        }
    }
}

/// 催しの性格 (`events.event_type`)。「初恋は、オケマスを除けば 10 年ぶり」「AS の周年では
/// 9th のみ」のような**除外・限定**を機械で出すための軸。
///
/// どの催しがどれかを決める規則は **imas-core 側**にある (docs/DATA_PIPELINE.md
/// 「events の種別 (event_type)」)。ここにあるのは画面に出す文言だけ。
/// 未分類のイベントは空文字なので `nil` になる。
///
/// 配信があったかどうかは**この軸ではない** (`shows.streamPlatform` が持つ)。
/// 「バースデー」と「配信」は直交するので、876 の BIRTHDAY ONLINE LIVE は birthday かつ配信。
/// 規模 (ミニライブかどうか) も軸に**しない** — 理由は docs/DATA_PIPELINE.md。
enum EventType: String, Codable, Sendable, CaseIterable {
    case anniversary
    case orchestra
    case externalEvent = "external_event"
    case birthday
    case releaseEvent = "release_event"
    case broadcast
    case live

    /// UI 表示用の短いラベル (語はコアの vocabulary)。
    var displayLabel: String {
        Vocab.eventType(rawValue)?.shortLabel ?? rawValue
    }
}

struct Event: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "events"

    var id: String
    var brandId: String?
    var name: String
    /// ライブ名の読み。漢字のライブ名をかなで引けるようにする (曲・アイドルと同じ扱い)。
    var nameKana: String?
    var eventType: String
    /// 互換のため残置。新コードからは参照しない。
    var isStreaming: Bool
    /// 互換のため残置。新コードからは参照しない。
    var isSolo: Bool
    /// イベント種別。5カテゴリ（EventKind）のいずれか。DBでは文字列で保持。
    var kind: String

    /// チケット先行受付の開始日 (YYYY-MM-DD)。締切とセットで「受付期間」をカレンダーに帯表示するために使う。
    var ticketOpenDate: String?
    /// チケット先行受付の締切日 (YYYY-MM-DD or 自由記述)
    var ticketDeadline: String?
    /// 当落発表日 (YYYY-MM-DD)
    var ticketLotteryDate: String?
    /// 公式チケットページ URL
    var ticketUrl: String?

    /// 合同ライブの追加ブランド ID をカンマ区切りで持つ (例: "ml" / "ml,cg")。
    /// nil の場合は単一ブランドライブ。 欠席判定の母集団 = primary brand のアイドル +
    /// この各ブランドのアイドル。 ハッチポッチ等の合同公演対応。
    var jointBrandIds: String?

    /// 配信実施の有無。nil=不明。show 側が nil のときのフォールバック元。
    var hasStreaming: Bool?
    /// ライブビューイング実施の有無。nil=未設定。明示 true のときだけ LV 参加を選択肢に出す。
    var hasLiveViewing: Bool?

    /// `joint_brand_ids` を配列にして返す。 nil/空文字列は空配列。
    var jointBrandIdList: [String] {
        guard let raw = jointBrandIds, !raw.isEmpty else { return [] }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `kind` 文字列を列挙型として返す。未知値は `.other` (コアの語彙と同じ寄せ方)。
    var eventKind: EventKind { EventKind(rawValue: kind) ?? .other }

    /// 既存呼び出し（CloudKit 等）との互換のため `kind` をデフォルト値付きにした明示 init。
    init(
        id: String,
        brandId: String?,
        name: String,
        nameKana: String? = nil,
        eventType: String,
        isStreaming: Bool,
        isSolo: Bool,
        kind: String = EventKind.live.rawValue,
        ticketOpenDate: String? = nil,
        ticketDeadline: String? = nil,
        ticketLotteryDate: String? = nil,
        ticketUrl: String? = nil,
        jointBrandIds: String? = nil,
        hasStreaming: Bool? = nil,
        hasLiveViewing: Bool? = nil
    ) {
        self.id = id
        self.brandId = brandId
        self.name = name
        self.nameKana = nameKana
        self.eventType = eventType
        self.isStreaming = isStreaming
        self.isSolo = isSolo
        self.kind = kind
        self.ticketOpenDate = ticketOpenDate
        self.ticketDeadline = ticketDeadline
        self.ticketLotteryDate = ticketLotteryDate
        self.ticketUrl = ticketUrl
        self.jointBrandIds = jointBrandIds
        self.hasStreaming = hasStreaming
        self.hasLiveViewing = hasLiveViewing
    }

    enum CodingKeys: String, CodingKey {
        case id
        case brandId = "brand_id"
        case name
        case eventType = "event_type"
        case isStreaming = "is_streaming"
        case isSolo = "is_solo"
        case kind
        case ticketOpenDate = "ticket_open_date"
        case ticketDeadline = "ticket_deadline"
        case ticketLotteryDate = "ticket_lottery_date"
        case ticketUrl = "ticket_url"
        case jointBrandIds = "joint_brand_ids"
        case hasStreaming = "has_streaming"
        case hasLiveViewing = "has_live_viewing"
        case nameKana = "name_kana"
    }

    // MARK: - Associations

    static let brand = belongsTo(Brand.self)
    static let shows = hasMany(Show.self)

    var brand: QueryInterfaceRequest<Brand> { request(for: Event.brand) }
    var shows: QueryInterfaceRequest<Show> { request(for: Event.shows) }
}
