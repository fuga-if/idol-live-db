import WidgetKit
import SwiftUI
import AppIntents
import UIKit

// MARK: - AppIntent によるアイドル選択

/// ウィジェット長押し → 編集 で表示する 1 アイドル。カタログ(App Group)から候補を出す。
struct OshiEntity: AppEntity {
    let id: String
    let name: String
    /// ブランド名 (副題に出して同名・大量候補の判別を助ける)。
    let brandName: String?

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "アイドル"
    var displayRepresentation: DisplayRepresentation {
        if let brandName, !brandName.isEmpty {
            DisplayRepresentation(title: "\(name)", subtitle: "\(brandName)")
        } else {
            DisplayRepresentation(title: "\(name)")
        }
    }
    static let defaultQuery = OshiEntityQuery()
}

/// `EntityStringQuery` 準拠で、ピッカーに検索ボックスを出す (候補が多くても名前/ブランドで絞れる)。
struct OshiEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [OshiEntity] {
        let ids = Set(identifiers)
        return WidgetShared.loadCatalog().filter { ids.contains($0.id) }.map(Self.entity)
    }
    /// ピッカーの検索文字列でアイドル名・ブランド名を部分一致フィルタ。
    func entities(matching string: String) async throws -> [OshiEntity] {
        let q = string.lowercased()
        guard !q.isEmpty else { return WidgetShared.loadCatalog().map(Self.entity) }
        return WidgetShared.loadCatalog()
            .filter { $0.name.lowercased().contains(q) || ($0.brandName?.lowercased().contains(q) ?? false) }
            .map(Self.entity)
    }
    func suggestedEntities() async throws -> [OshiEntity] {
        WidgetShared.loadCatalog().map(Self.entity)
    }
    func defaultResult() async -> OshiEntity? {
        WidgetShared.loadCatalog().first.map(Self.entity)
    }

    private static func entity(_ e: OshiWidgetEntry) -> OshiEntity {
        OshiEntity(id: e.id, name: e.name, brandName: e.brandName)
    }
}

struct SelectOshiIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "担当を選ぶ"
    static let description = IntentDescription("ウィジェットに表示するアイドルを選びます。")

    @Parameter(title: "アイドル")
    var oshi: OshiEntity?
}

/// ウィジェットをタップすると次の画像へ進めるインタラクティブ Intent。
struct NextOshiImageIntent: AppIntent {
    static let title: LocalizedStringResource = "次の画像"

    @Parameter(title: "idolId")
    var idolId: String

    init() {}
    init(idolId: String) { self.idolId = idolId }

    func perform() async throws -> some IntentResult {
        WidgetShared.advanceRotation(for: idolId)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Timeline

struct OshiEntry: TimelineEntry {
    let date: Date
    let imageData: Data?
    let name: String?
    let idolId: String?
}

struct OshiProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OshiEntry {
        OshiEntry(date: Date(), imageData: nil, name: nil, idolId: nil)
    }

    func snapshot(for configuration: SelectOshiIntent, in context: Context) async -> OshiEntry {
        let r = resolved(configuration)
        let data = r.images.first.flatMap { try? Data(contentsOf: $0) }
        return OshiEntry(date: Date(), imageData: data, name: r.name, idolId: r.id)
    }

    func timeline(for configuration: SelectOshiIntent, in context: Context) async -> Timeline<OshiEntry> {
        let r = resolved(configuration)
        guard !r.images.isEmpty, let id = r.id else {
            return Timeline(entries: [OshiEntry(date: Date(), imageData: nil, name: r.name, idolId: r.id)], policy: .never)
        }
        // 表示開始位置 = タップ/時間で進む手動オフセット。タップ時はこの base が +1 され、
        // reload で即座に次の画像になる。時間でも intervalMinutes ごとに先のエントリへ進む。
        let intervalMinutes = 30
        let base = WidgetShared.rotationIndex(for: id)
        let count = r.images.count
        let now = Date()
        // 画像はユニークインデックスごとに 1 回だけ読み込んで使い回す (メモリ節約)。
        var cache: [Int: Data] = [:]
        func data(at idx: Int) -> Data? {
            if let d = cache[idx] { return d }
            let d = try? Data(contentsOf: r.images[idx])
            cache[idx] = d
            return d
        }
        var entries: [OshiEntry] = []
        let steps = min(max(count, 8), 16)
        for i in 0..<steps {
            let date = Calendar.current.date(byAdding: .minute, value: i * intervalMinutes, to: now) ?? now
            let idx = ((base + i) % count + count) % count
            entries.append(OshiEntry(date: date, imageData: data(at: idx), name: r.name, idolId: id))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// 選択アイドル (未選択ならカタログ先頭) の id / 名前 / 画像 URL 群。
    private func resolved(_ configuration: SelectOshiIntent) -> (id: String?, name: String?, images: [URL]) {
        let catalog = WidgetShared.loadCatalog()
        guard let entry = catalog.first(where: { $0.id == configuration.oshi?.id }) ?? catalog.first else {
            return (nil, nil, [])
        }
        return (entry.id, entry.name, WidgetShared.imageURLs(for: entry.id, images: entry.images))
    }
}

// MARK: - View

struct OshiImageWidgetView: View {
    var entry: OshiProvider.Entry

    var body: some View {
        if let data = entry.imageData, let ui = UIImage(data: data) {
            // 画像のみ全面表示 (文字なし)。タップで次の画像へローテーション。
            Button(intent: NextOshiImageIntent(idolId: entry.idolId ?? "")) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            }
            .buttonStyle(.plain)
        } else {
            OshiPlaceholder(name: entry.name)
        }
    }
}

/// タップでアプリを開く launcher 版。画像は同じだが、タップ動作だけ異なる。
struct OshiLauncherWidgetView: View {
    var entry: OshiProvider.Entry

    var body: some View {
        if let data = entry.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .widgetURL(URL(string: "imaslivedb://open"))
        } else {
            OshiPlaceholder(name: entry.name)
        }
    }
}

/// 未選択 / 画像なし時の共通プレースホルダ。
struct OshiPlaceholder: View {
    let name: String?
    var body: some View {
        ZStack {
            LinearGradient(colors: [.pink.opacity(0.5), .purple.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                Text(name == nil ? "アプリで画像を追加" : "担当を選択")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(8)
        }
    }
}

// MARK: - Widgets

struct OshiImageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OshiImageWidget", intent: SelectOshiIntent.self, provider: OshiProvider()) { entry in
            OshiImageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("担当の画像（タップで切替）")
        .description("選んだアイドルの画像を表示。タップで次の画像に切り替わります。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct OshiLauncherWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OshiLauncherWidget", intent: SelectOshiIntent.self, provider: OshiProvider()) { entry in
            OshiLauncherWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("担当の画像（タップでアプリ）")
        .description("選んだアイドルの画像を表示。タップでアプリを開きます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct ImasLiveDBWidgetBundle: WidgetBundle {
    var body: some Widget {
        OshiImageWidget()
        OshiLauncherWidget()
        NextLiveWidget()
        TodaySongWidget()
        TicketDeadlineWidget()
    }
}
