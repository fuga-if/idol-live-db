//  年表 (ブランド史) 用のクエリ。
//  「節目 / ライブ / 楽曲シリーズ / その他」を 1 本の時間軸に載せるための素材を取る。
//  分割の意図は docs/ARCHITECTURE.md を参照。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: - Timeline Queries

    /// 年表の帯を全レーン分まとめて取る。`brandId` が nil なら全ブランド横断。
    func fetchTimelineBarsAsync(brandId: String?) async throws -> [TimelineBar] {
        try await dbQueue.read { db in try Self.fetchTimelineBarsQuery(db, brandId: brandId) }
    }

    private static func fetchTimelineBarsQuery(_ db: Database, brandId: String?) throws -> [TimelineBar] {
        let brandColors = try brandColorMap(db)
        return try milestoneBars(db, brandId: brandId, colors: brandColors)
            + eventBars(db, brandId: brandId, colors: brandColors)
            + seriesBars(db, brandId: brandId, colors: brandColors)
            + cdSeriesBars(db, brandId: brandId, colors: brandColors)
            + oneOffReleaseBars(db, brandId: brandId, colors: brandColors)
    }

    /// brand_id → カラー hex。帯の色シードに使う。
    private static func brandColorMap(_ db: Database) throws -> [String: String] {
        var map: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, color FROM brands WHERE IFNULL(color,'') != ''") {
            map[row["id"]] = row["color"]
        }
        return map
    }

    /// ブランド絞り込みの WHERE 断片と引数。nil なら全件。
    private static func brandFilter(_ column: String, _ brandId: String?) -> (sql: String, args: StatementArguments) {
        guard let brandId else { return ("", StatementArguments()) }
        return (" AND \(column) = ?", StatementArguments([brandId]))
    }

    // MARK: 節目 (anniversaries)

    private static func milestoneBars(_ db: Database, brandId: String?, colors: [String: String]) throws -> [TimelineBar] {
        let filter = brandFilter("brand_id", brandId)
        let sql = """
            SELECT id, brand_id, label, date, kind
            FROM anniversaries
            WHERE IFNULL(date,'') != ''\(filter.sql)
            ORDER BY date
            """
        return try Row.fetchAll(db, sql: sql, arguments: filter.args).compactMap { row in
            guard let date = TimelineDateParser.date(row["date"]) else { return nil }
            let brand: String? = row["brand_id"]
            return TimelineBar(
                id: "ms_\(row["id"] as String)",
                lane: .milestone,
                title: row["label"],
                start: date,
                end: date,
                marks: [date],
                seedHex: brand.flatMap { colors[$0] },
                categoryKey: row["kind"] ?? "milestone",
                badge: nil,
                target: .none
            )
        }
    }

    // MARK: ライブ / その他イベント (events + shows)

    /// events を公演日で束ね、初日〜千秋楽を 1 本の帯にする。公演日そのものは marks に入る。
    private static func eventBars(_ db: Database, brandId: String?, colors: [String: String]) throws -> [TimelineBar] {
        let filter = brandFilter("e.brand_id", brandId)
        let sql = """
            SELECT e.id, e.name, e.brand_id, e.kind,
                   MIN(s.date) AS first_date, MAX(s.date) AS last_date,
                   COUNT(s.id) AS show_count,
                   GROUP_CONCAT(s.date) AS dates
            FROM events e
            JOIN shows s ON s.event_id = e.id
            WHERE IFNULL(s.date,'') != ''\(filter.sql)
            GROUP BY e.id
            ORDER BY first_date
            """
        return try Row.fetchAll(db, sql: sql, arguments: filter.args).compactMap { row in
            guard let start = TimelineDateParser.date(row["first_date"]),
                  let end = TimelineDateParser.date(row["last_date"]) else { return nil }
            let kind: String = row["kind"] ?? "live"
            let brand: String? = row["brand_id"]
            let showCount: Int = row["show_count"] ?? 0
            return TimelineBar(
                id: "ev_\(row["id"] as String)",
                lane: Self.lane(forEventKind: kind),
                title: eventDisplayName(row["name"]),
                start: start,
                end: end,
                marks: TimelineDateParser.dates(row["dates"]),
                seedHex: brand.flatMap { colors[$0] },
                categoryKey: brand ?? kind,
                badge: showCount > 1 ? "\(showCount)公演" : nil,
                target: .event(id: row["id"])
            )
        }
    }

    /// events.kind → レーン。ライブ・フェスだけを主役の「ライブ」レーンに置き、
    /// リリイベ・ラジオ・配信は「その他」に落として主役の行を汚さない。
    private static func lane(forEventKind kind: String) -> TimelineLane {
        switch kind {
        case "live", "festival": return .live
        default: return .other
        }
    }

    // MARK: 楽曲シリーズ (songs.series_group)

    /// CD シリーズを 1 本の帯にする。初回〜最終リリースが帯、各リリース日が marks。
    /// 参照デザインの「LIVE THE@TER PERFORMANCE ━━━ 12曲」がこれにあたる。
    private static func seriesBars(_ db: Database, brandId: String?, colors: [String: String]) throws -> [TimelineBar] {
        let filter = brandFilter("brand_id", brandId)
        let sql = """
            SELECT series_group, brand_id,
                   COUNT(*) AS song_count,
                   MIN(release_date) AS first_date, MAX(release_date) AS last_date,
                   GROUP_CONCAT(DISTINCT release_date) AS dates
            FROM songs
            WHERE IFNULL(series_group,'') != '' AND IFNULL(release_date,'') != ''\(filter.sql)
            GROUP BY brand_id, series_group
            ORDER BY first_date
            """
        return try Row.fetchAll(db, sql: sql, arguments: filter.args).compactMap { row in
            guard let start = TimelineDateParser.date(row["first_date"]),
                  let end = TimelineDateParser.date(row["last_date"]) else { return nil }
            let series: String = row["series_group"]
            let brand: String? = row["brand_id"]
            let count: Int = row["song_count"] ?? 0
            return TimelineBar(
                id: "sg_\(brand ?? "-")_\(series)",
                lane: .music,
                title: series,
                start: start,
                end: end,
                marks: TimelineDateParser.dates(row["dates"]),
                // 色はブランドカラー基準。シリーズごとの塗り分けは色相ごと変えるのではなく
                // ブランド色のバリエーションで行う (View 側で categoryKey を使って振る)。
                seedHex: brand.flatMap { colors[$0] },
                categoryKey: series,
                badge: "\(count)曲",
                target: .seriesGroup(series)
            )
        }
    }

    /// `series_group` が未設定でも、同じ CD (`cd_series`) に 2 曲以上入っているものは
    /// 実質シリーズなので 1 本の帯にする。
    ///
    /// 以前はこれらを年ごとの「その他のリリース」に丸めていたが、帯を見ても中身が
    /// 分からず「これは何なのか」が伝わらなかった。CD 名で出せば、そのまま
    /// 「series_group を入れるべき塊」の一覧としても読める。
    private static func cdSeriesBars(_ db: Database, brandId: String?, colors: [String: String]) throws -> [TimelineBar] {
        let filter = brandFilter("brand_id", brandId)
        let sql = """
            SELECT cd_series, brand_id,
                   COUNT(*) AS song_count,
                   MIN(release_date) AS first_date, MAX(release_date) AS last_date,
                   GROUP_CONCAT(DISTINCT release_date) AS dates
            FROM songs
            WHERE IFNULL(series_group,'') = '' AND IFNULL(cd_series,'') != ''
              AND IFNULL(release_date,'') != ''\(filter.sql)
            GROUP BY brand_id, cd_series
            HAVING COUNT(*) >= 2
            ORDER BY first_date
            """
        return try Row.fetchAll(db, sql: sql, arguments: filter.args).compactMap { row in
            guard let start = TimelineDateParser.date(row["first_date"]),
                  let end = TimelineDateParser.date(row["last_date"]) else { return nil }
            let cdSeries: String = row["cd_series"]
            let brand: String? = row["brand_id"]
            let count: Int = row["song_count"] ?? 0
            return TimelineBar(
                id: "cds_\(brand ?? "-")_\(cdSeries)",
                lane: .music,
                title: cdSeries,
                start: start,
                end: end,
                marks: TimelineDateParser.dates(row["dates"]),
                seedHex: brand.flatMap { colors[$0] },
                categoryKey: cdSeries,
                badge: "\(count)曲",
                target: .cdSeries(cdSeries)
            )
        }
    }

    /// どのシリーズにも CD にも束ねられない単発リリース (タイアップ単曲・配信限定など)。
    /// 年ごとに 1 本へまとめる。ここを省くとシリーズ表記の薄いブランドで楽曲レーンが
    /// スカスカに見え、実態を誤って伝えてしまう。
    private static func oneOffReleaseBars(_ db: Database, brandId: String?, colors: [String: String]) throws -> [TimelineBar] {
        let filter = brandFilter("brand_id", brandId)
        // cd_series が空、または同じ cd_series が 1 曲しかないもの = 束ねる相手がいない曲。
        let sql = """
            SELECT STRFTIME('%Y', release_date) AS year,
                   brand_id,
                   COUNT(*) AS song_count,
                   MIN(release_date) AS first_date, MAX(release_date) AS last_date,
                   GROUP_CONCAT(DISTINCT release_date) AS dates
            FROM songs s
            WHERE IFNULL(s.series_group,'') = '' AND IFNULL(s.release_date,'') != ''
              AND (
                    IFNULL(s.cd_series,'') = ''
                 OR (SELECT COUNT(*) FROM songs t
                      WHERE IFNULL(t.series_group,'') = ''
                        AND t.brand_id IS s.brand_id
                        AND t.cd_series = s.cd_series
                        AND IFNULL(t.release_date,'') != '') = 1
                  )\(filter.sql)
            GROUP BY brand_id, year
            ORDER BY year
            """
        return try Row.fetchAll(db, sql: sql, arguments: filter.args).compactMap { row in
            guard let year: String = row["year"],
                  let start = TimelineDateParser.date(row["first_date"]),
                  let end = TimelineDateParser.date(row["last_date"]) else { return nil }
            let brand: String? = row["brand_id"]
            let count: Int = row["song_count"] ?? 0
            return TimelineBar(
                id: "oneoff_\(brand ?? "-")_\(year)",
                lane: .music,
                title: "単発リリース",
                start: start,
                end: end,
                marks: TimelineDateParser.dates(row["dates"]),
                seedHex: brand.flatMap { colors[$0] },
                categoryKey: "oneoff",
                badge: "\(count)曲",
                target: .releaseYear(year)
            )
        }
    }
}

// MARK: - 日付パース

/// DB の `YYYY-MM-DD` 文字列を Date に直す。年表はすべて JST の日付として扱う。
enum TimelineDateParser {
    /// 年表の座標計算に使うカレンダー (JST 固定)。端末のタイムゾーンで年境界がずれると
    /// 「1/1 のリリースが前年の帯に入る」ような表示崩れになるため、明示的に固定する。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return calendar
    }()

    static func date(_ text: String?) -> Date? {
        guard let text, text.count >= 10 else { return nil }
        let parts = text.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    /// `GROUP_CONCAT` のカンマ区切り日付を Date 配列に。重複は畳んで昇順で返す。
    static func dates(_ text: String?) -> [Date] {
        guard let text, !text.isEmpty else { return [] }
        let parsed = text.split(separator: ",").compactMap { date(String($0)) }
        return Array(Set(parsed)).sorted()
    }
}
