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

/// アプリ側が書き出し、ウィジェット拡張が読み取る情報スナップショット。
struct InfoWidgetSnapshot: Codable, Sendable {
    var nextShow: NextShowInfo?
    var todaySong: TodaySongInfo?
    var ticketDeadlines: [TicketDeadlineInfo]
    /// スナップショット生成日 (YYYY-MM-DD)。当日以外なら stale 扱い。
    var generatedDate: String

    static func load() -> InfoWidgetSnapshot? {
        guard let url = WidgetShared.infoSnapshotURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(InfoWidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = WidgetShared.infoSnapshotURL,
              let data = try? JSONEncoder().encode(self)
        else { return }
        try? data.write(to: url)
    }
}
