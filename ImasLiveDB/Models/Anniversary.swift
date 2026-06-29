import Foundation
import GRDB

/// ブランド/アプリの記念日 (サービス開始・アプリ稼働・アニメ放映・劇場版公開等)。
/// date は YYYY-MM-DD (年あり)。毎年同じMM-DDで再点灯し、表示時に当該年からN周年を計算する。
struct Anniversary: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "anniversaries"

    var id: String
    var brandId: String
    /// 表示テキスト (例: "アーケード版稼働", "デレステ配信開始")。
    var label: String
    /// 起点日 'YYYY-MM-DD'。
    var date: String
    /// AnniversaryKind raw value。
    var kind: String
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, label, date, kind
        case brandId = "brand_id"
        case sortOrder = "sort_order"
    }

    /// 起点年 (date の YYYY 部分)。
    var startYear: Int? {
        Int(date.prefix(4))
    }

    /// 指定年における周年数 (起点年含めない: 2005-07-26 → 2026年で21周年)。
    /// 起点より前の年は nil。
    func anniversaryYears(in year: Int) -> Int? {
        guard let startYear else { return nil }
        let n = year - startYear
        return n >= 0 ? n : nil
    }
}

enum AnniversaryKind: String, CaseIterable {
    case serviceStart = "service_start"
    case appStart = "app_start"
    case animeStart = "anime_start"
    case movieRelease = "movie_release"
    case cdDebut = "cd_debut"

    /// 表示アイコン (SF Symbol)。
    var systemImage: String {
        switch self {
        case .serviceStart: return "sparkles"
        case .appStart: return "iphone"
        case .animeStart: return "tv"
        case .movieRelease: return "film"
        case .cdDebut: return "opticaldisc"
        }
    }
}
