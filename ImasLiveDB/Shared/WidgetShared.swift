import Foundation

/// アプリ本体とウィジェット拡張で共有する App Group 上の置き場とモデル。
/// (このファイルは両ターゲットに含める。Foundation 以外に依存しないこと)
enum WidgetShared {
    static let appGroupId = "group.com.fugaif.ImasLiveDB"
    static let catalogFileName = "oshi_widget_catalog.json"
    static let imagesDirName = "widget_images"
    static let infoSnapshotFileName = "info_widget.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
    static var imagesDir: URL? {
        containerURL?.appendingPathComponent(imagesDirName, isDirectory: true)
    }
    static var catalogURL: URL? {
        containerURL?.appendingPathComponent(catalogFileName)
    }
    static var infoSnapshotURL: URL? {
        containerURL?.appendingPathComponent(infoSnapshotFileName)
    }

    /// カタログを App Group から読む (ウィスト/AppIntent から呼ぶ)。失敗時は空。
    static func loadCatalog() -> [OshiWidgetEntry] {
        guard let url = catalogURL,
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(OshiWidgetCatalog.self, from: data)
        else { return [] }
        return catalog.idols
    }

    /// 指定アイドルの画像ファイル URL 群 (順序付き、先頭=プライマリ)。
    static func imageURLs(for idolId: String, images: [String]) -> [URL] {
        guard let dir = imagesDir?.appendingPathComponent(idolId, isDirectory: true) else { return [] }
        return images.map { dir.appendingPathComponent($0) }
    }

    // MARK: - ローテーション位置 (タップ/時間で進める手動オフセット)

    private static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupId) }
    private static func rotationKey(_ idolId: String) -> String { "rotidx_\(idolId)" }

    /// 現在のローテーション基準インデックス。
    static func rotationIndex(for idolId: String) -> Int {
        sharedDefaults?.integer(forKey: rotationKey(idolId)) ?? 0
    }

    /// 1 つ進める (ウィジェットタップ時)。
    static func advanceRotation(for idolId: String) {
        let key = rotationKey(idolId)
        let next = (sharedDefaults?.integer(forKey: key) ?? 0) + 1
        sharedDefaults?.set(next, forKey: key)
    }
}

/// ウィジェットに供給する 1 アイドル分。images は `widget_images/{id}/` 配下の相対ファイル名。
struct OshiWidgetEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: String?
    let images: [String]
    /// ブランド表示名 (ピッカーの副題・絞り込み用)。旧カタログ互換のため optional。
    var brandName: String? = nil
    /// 読み。ウィジェット設定のピッカーを かなで引くために持つ。
    /// 旧カタログ互換のため optional (無い間は名前だけで当たる)。
    var nameKana: String? = nil
}

struct OshiWidgetCatalog: Codable {
    var idols: [OshiWidgetEntry]
}

// MARK: - 情報ウィジェット用スナップショット

/// 次のライブ情報。
struct NextShowInfo: Codable, Sendable {
    var eventId: String
    var eventName: String
    /// 最初の公演日 (YYYY-MM-DD)
    var firstDate: String
    var brandColorHex: String?
}

/// 今日の1曲。ブランドごとの最初の1曲を代表として渡す。
struct TodaySongInfo: Codable, Sendable {
    var songId: String
    var title: String
    var artistLabel: String?
    var artworkUrl: String?
    var brandColorHex: String?
}

/// チケット締切が近いイベント。
struct TicketDeadlineInfo: Codable, Sendable {
    var eventId: String
    var eventName: String
    /// 締切日 (YYYY-MM-DD)
    var deadline: String
}

extension NextShowInfo {
    /// 初日まであと何日か (今日が 0)。日付が読めなければ nil。
    func daysUntilFirstShow(from now: Date) -> Int? {
        WidgetDay.daysUntil(firstDate, from: now)
    }

    /// 初日が過ぎていないか。過ぎたものは出さない (「あと-2日」を出さない)。
    func isUpcoming(from now: Date) -> Bool {
        (daysUntilFirstShow(from: now) ?? 0) >= 0
    }
}

extension TicketDeadlineInfo {
    /// 締切が過ぎていないか。日付として読めない締切 (自由記述) は落とさない。
    func isOpen(from now: Date) -> Bool {
        (WidgetDay.daysUntil(deadline, from: now) ?? 0) >= 0
    }
}

/// アプリ側が書き出し、ウィジェット拡張が読み取る情報スナップショット。
struct InfoWidgetSnapshot: Codable, Sendable {
    var nextShow: NextShowInfo?
    var todaySong: TodaySongInfo?
    var ticketDeadlines: [TicketDeadlineInfo]
    /// スナップショット生成日 (JST の YYYY-MM-DD)。当日以外なら stale 扱い。
    var generatedDate: String

    static func load() -> InfoWidgetSnapshot? {
        guard let url = WidgetShared.infoSnapshotURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(InfoWidgetSnapshot.self, from: data)
    }

    /// 今日 (JST) 作ったものだけを返す。アプリを開かない日が続いても、古い内容
    /// (過ぎたライブや締切) を出し続けない。
    static func loadCurrent(now: Date = Date()) -> InfoWidgetSnapshot? {
        load().flatMap { $0.isCurrent(now: now) ? $0 : nil }
    }

    func isCurrent(now: Date) -> Bool {
        generatedDate == WidgetDay.key(now)
    }

    func save() {
        guard let url = WidgetShared.infoSnapshotURL,
              let data = try? JSONEncoder().encode(self)
        else { return }
        try? data.write(to: url)
    }
}

// MARK: - ウィジェットの「今日」(JST)

/// ウィジェットの日付の基準。アプリ本体の「今日」(`JSTDay` = コアの jst_today) と同じく
/// **JST で切る** (端末の地域設定に左右されない)。
///
/// ウィジェット拡張はコアをリンクしない。リンクすると拡張の実行ファイルが 5MB あまり
/// 増える (Release・arm64 で計測: strip 後 0.30MB → 5.65MB) ので、日付の表記と日数だけを
/// ここで出す。表記がコアと食い違わないことはアプリのテスト (`WidgetDayTests`) が見る。
enum WidgetDay {
    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// `date` の JST の日付 ("yyyy-MM-dd")。
    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `now` の JST の日付から `day` ("yyyy-MM-dd") までの日数。今日が 0、昨日が -1。
    /// 日付として読めなければ nil。
    static func daysUntil(_ day: String, from now: Date) -> Int? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let target = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: target).day
    }

    /// `now` の次の JST の 0 時。日付が変わると「あと N 日」と古さの判定が変わるので、そこで引き直す。
    static func nextMidnight(after now: Date) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(3600)
    }
}
