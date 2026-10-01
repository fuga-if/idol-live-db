import WidgetKit
import SwiftUI

// MARK: - 共通ユーティリティ

/// "YYYY-MM-DD" → Date に変換するヘルパ。
private func parseDate(_ s: String) -> Date? {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "ja_JP")
    return f.date(from: s)
}

/// "YYYY-MM-DD" → "M/d" 表示形式。
private func shortDate(_ s: String) -> String {
    guard let d = parseDate(s) else { return s }
    let f = DateFormatter()
    f.dateFormat = "M/d"
    f.locale = Locale(identifier: "ja_JP")
    return f.string(from: d)
}

// MARK: - 次のライブウィジェット

struct NextLiveEntry: TimelineEntry {
    let date: Date
    let info: NextShowInfo?
}

struct NextLiveProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextLiveEntry {
        NextLiveEntry(date: Date(), info: NextShowInfo(
            eventId: "", eventName: "アイマス サマーライブ 2026",
            firstDate: "2026-08-01", brandColorHex: "#FF6699"
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextLiveEntry) -> Void) {
        completion(Self.entry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextLiveEntry>) -> Void) {
        let now = Date()
        // 翌日 0:00 (JST) に更新 (日付が変わると「あと N 日」が変わるため)
        completion(Timeline(entries: [Self.entry(now: now)], policy: .after(WidgetDay.nextMidnight(after: now))))
    }

    /// 今日作ったスナップショットの、まだ始まっていないライブだけを出す。
    private static func entry(now: Date) -> NextLiveEntry {
        let next = InfoWidgetSnapshot.loadCurrent(now: now)?.nextShow
        return NextLiveEntry(date: now, info: next.flatMap { $0.isUpcoming(from: now) ? $0 : nil })
    }
}

struct NextLiveWidgetView: View {
    var entry: NextLiveEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let info = entry.info {
            let accent = ImasWidgetColor.accent(info.brandColorHex)
            let days = info.daysUntilFirstShow(from: entry.date)
            ImasWidgetScaffold(alignment: .bottomLeading, accent: accent) {
                VStack(alignment: .leading, spacing: ImasWidgetSpace.gapTight) {
                    ImasWidgetEyebrow(systemImage: "music.mic", text: "次のライブ")
                    Text(info.eventName)
                        .imasWidgetText(.title(compact: family == .systemSmall))
                        .lineLimit(family == .systemSmall ? 2 : 3)
                    HStack(spacing: ImasWidgetSpace.gapTight) {
                        if let d = days {
                            ImasWidgetMetric(text: d == 0 ? "今日！" : "あと\(d)日", size: 13)
                        }
                        Text(shortDate(info.firstDate)).imasWidgetText(.meta)
                    }
                }
            }
            .widgetURL(URL(string: "imaslivedb://events/\(info.eventId)"))
        } else {
            ImasWidgetScaffold(alignment: .center) {
                ImasWidgetPlaceholder(systemImage: "music.mic", text: "次のライブ情報なし")
            }
        }
    }
}

struct NextLiveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextLiveWidget", provider: NextLiveProvider()) { entry in
            NextLiveWidgetView(entry: entry)
                // 省スペースのウィジェットはアクセシビリティ特大でレイアウトが破綻するため上限クランプ。
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .containerBackground(for: .widget) { ImasWidgetColor.paper }
        }
        .configurationDisplayName("次のライブ")
        .description("直近のライブまでのカウントダウンを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - 今日の1曲ウィジェット

struct TodaySongEntry: TimelineEntry {
    let date: Date
    let info: TodaySongInfo?
    let artworkData: Data?
}

struct TodaySongProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodaySongEntry {
        TodaySongEntry(
            date: Date(),
            info: TodaySongInfo(songId: "", title: "M@STERPIECE", artistLabel: "765PRO ALLSTARS", brandColorHex: "#FF6699"),
            artworkData: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodaySongEntry) -> Void) {
        completion(entry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaySongEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [entry(now: now)], policy: .after(WidgetDay.nextMidnight(after: now))))
    }

    /// 今日作ったスナップショットの曲だけを出す (昨日の曲を「今日の1曲」として出さない)。
    private func entry(now: Date) -> TodaySongEntry {
        let info = InfoWidgetSnapshot.loadCurrent(now: now)?.todaySong
        return TodaySongEntry(date: now, info: info, artworkData: loadArtwork(info?.artworkUrl))
    }

    private func loadArtwork(_ urlStr: String?) -> Data? {
        guard let urlStr, let url = URL(string: urlStr),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return data
    }
}

struct TodaySongWidgetView: View {
    var entry: TodaySongEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let info = entry.info {
            let accent = ImasWidgetColor.accent(info.brandColorHex)
            ImasWidgetScaffold(alignment: .leading) {
                HStack(spacing: ImasWidgetSpace.gapLoose) {
                    // ジャケ写 (artworkUrl は mzstatic CDN 等の外部 URL なのでウィジェットでは
                    // Data 読み込み済みのものだけ表示し、無ければ紙の面 + 音符で代替)
                    ImasWidgetArtwork(
                        image: entry.artworkData.flatMap(UIImage.init(data:)),
                        size: family == .systemSmall ? 50 : 60
                    )

                    VStack(alignment: .leading, spacing: ImasWidgetSpace.gapTight) {
                        ImasWidgetEyebrow(systemImage: "music.quarternote.3", text: "今日の1曲", accent: accent)
                        Text(info.title)
                            .imasWidgetText(.title(compact: family == .systemSmall))
                            .lineLimit(2)
                        if let label = info.artistLabel, !label.isEmpty {
                            Text(label).imasWidgetText(.meta).lineLimit(1)
                        }
                    }
                    if family != .systemSmall { Spacer(minLength: 0) }
                }
            }
            .widgetURL(URL(string: "imaslivedb://open"))
        } else {
            ImasWidgetScaffold(alignment: .center) {
                ImasWidgetPlaceholder(systemImage: "music.quarternote.3", text: "今日の1曲を準備中")
            }
        }
    }
}

struct TodaySongWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySongWidget", provider: TodaySongProvider()) { entry in
            TodaySongWidgetView(entry: entry)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .containerBackground(for: .widget) { ImasWidgetColor.paper }
        }
        .configurationDisplayName("今日の1曲")
        .description("日替わりで1曲をピックして表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - チケット締切ウィジェット

struct TicketDeadlineEntry: TimelineEntry {
    let date: Date
    let deadlines: [TicketDeadlineInfo]
}

struct TicketDeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TicketDeadlineEntry {
        TicketDeadlineEntry(date: Date(), deadlines: [
            TicketDeadlineInfo(eventId: "", eventName: "アイマス サマーライブ 2026", deadline: "2026-07-15"),
            TicketDeadlineInfo(eventId: "", eventName: "ミリオン 10th アニバーサリー", deadline: "2026-07-20"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (TicketDeadlineEntry) -> Void) {
        completion(Self.entry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TicketDeadlineEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [Self.entry(now: now)], policy: .after(WidgetDay.nextMidnight(after: now))))
    }

    /// 今日作ったスナップショットの、締切が過ぎていないものだけを出す。
    private static func entry(now: Date) -> TicketDeadlineEntry {
        let deadlines = InfoWidgetSnapshot.loadCurrent(now: now)?.ticketDeadlines ?? []
        return TicketDeadlineEntry(date: now, deadlines: deadlines.filter { $0.isOpen(from: now) })
    }
}

struct TicketDeadlineWidgetView: View {
    var entry: TicketDeadlineEntry

    var body: some View {
        if entry.deadlines.isEmpty {
            ImasWidgetScaffold(alignment: .center) {
                ImasWidgetPlaceholder(systemImage: "ticket", text: "締切近いチケットなし")
            }
        } else {
            ImasWidgetScaffold {
                VStack(alignment: .leading, spacing: ImasWidgetSpace.gap) {
                    ImasWidgetEyebrow(systemImage: "ticket", text: "チケット締切")
                    ForEach(entry.deadlines.prefix(3), id: \.id) { item in
                        ImasWidgetRow(
                            date: shortDate(item.deadline),
                            // M3: label はコアが組んだ "{event_name} ({sale_name})"。1 件のライブに
                            // 受付が複数あっても行が区別でき、見出しでライブ名も分かる。
                            title: item.displayLabel,
                            // M3: 見出し「チケット締切」の下に当落発表の行が締切と見分けられずに
                            // 混ざらないよう、当落発表の行だけ種別の語を添える。
                            tag: item.isAwaitingResult ? item.resolvedKindLabel : nil,
                            isEmphasized: !item.isAwaitingResult
                        )
                    }
                }
            }
            .widgetURL(URL(string: "imaslivedb://open"))
        }
    }
}

struct TicketDeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TicketDeadlineWidget", provider: TicketDeadlineProvider()) { entry in
            TicketDeadlineWidgetView(entry: entry)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .containerBackground(for: .widget) { ImasWidgetColor.paper }
        }
        .configurationDisplayName("チケット締切")
        .description("チケット締切が近いイベントを最大3件表示します。")
        .supportedFamilies([.systemMedium])
    }
}
