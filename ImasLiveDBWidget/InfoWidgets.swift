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

/// 今日から date (YYYY-MM-DD) までの日数差。今日が 0、明日が 1。
private func daysUntil(_ dateStr: String) -> Int? {
    guard let target = parseDate(dateStr) else { return nil }
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let targetDay = cal.startOfDay(for: target)
    return cal.dateComponents([.day], from: today, to: targetDay).day
}

/// "YYYY-MM-DD" → "M/d" 表示形式。
private func shortDate(_ s: String) -> String {
    guard let d = parseDate(s) else { return s }
    let f = DateFormatter()
    f.dateFormat = "M/d"
    f.locale = Locale(identifier: "ja_JP")
    return f.string(from: d)
}

/// hex 文字列 → Color。失敗時は fallback。
private func hexColor(_ hex: String?, fallback: Color = .pink) -> Color {
    guard let hex, hex.count >= 6 else { return fallback }
    let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard let v = UInt64(raw.prefix(6), radix: 16) else { return fallback }
    return Color(
        red: Double((v >> 16) & 0xff) / 255,
        green: Double((v >> 8) & 0xff) / 255,
        blue: Double(v & 0xff) / 255
    )
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
        completion(NextLiveEntry(date: Date(), info: InfoWidgetSnapshot.load()?.nextShow))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextLiveEntry>) -> Void) {
        let snapshot = InfoWidgetSnapshot.load()
        let entry = NextLiveEntry(date: Date(), info: snapshot?.nextShow)
        // 翌日 0:00 に更新(日付が変わると「あと N 日」が変わるため)
        let nextMidnight = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
        ) ?? Date(timeIntervalSinceNow: 3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct NextLiveWidgetView: View {
    var entry: NextLiveEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let info = entry.info {
            let accent = hexColor(info.brandColorHex, fallback: .pink)
            let days = daysUntil(info.firstDate)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [accent.opacity(0.85), accent.opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                VStack(alignment: .leading, spacing: 4) {
                    Label("次のライブ", systemImage: "music.mic")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer(minLength: 0)
                    Text(info.eventName)
                        .font(.system(size: family == .systemSmall ? 13 : 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(family == .systemSmall ? 2 : 3)
                    HStack(spacing: 4) {
                        if let d = days {
                            Text(d == 0 ? "今日！" : "あと\(d)日")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.white)
                        }
                        Text(shortDate(info.firstDate))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(12)
            }
            .widgetURL(URL(string: "imaslivedb://events/\(info.eventId)"))
        } else {
            NextLivePlaceholder()
        }
    }
}

struct NextLivePlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: "music.mic")
                    .font(.title2)
                Text("次のライブ情報なし")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(8)
        }
    }
}

struct NextLiveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextLiveWidget", provider: NextLiveProvider()) { entry in
            NextLiveWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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
        let info = InfoWidgetSnapshot.load()?.todaySong
        completion(TodaySongEntry(date: Date(), info: info, artworkData: loadArtwork(info?.artworkUrl)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaySongEntry>) -> Void) {
        let snapshot = InfoWidgetSnapshot.load()
        let info = snapshot?.todaySong
        let entry = TodaySongEntry(date: Date(), info: info, artworkData: loadArtwork(info?.artworkUrl))
        let nextMidnight = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
        ) ?? Date(timeIntervalSinceNow: 3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
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
            let accent = hexColor(info.brandColorHex, fallback: .purple)
            HStack(spacing: 10) {
                // ジャケ写 (artworkUrl は mzstatic CDN 等の外部 URL なのでウィジェットでは
                // Data 読み込み済みのものだけ表示し、無ければシステムアイコンで代替)
                Group {
                    if let data = entry.artworkData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            accent.opacity(0.3)
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(accent)
                        }
                    }
                }
                .frame(width: family == .systemSmall ? 50 : 60, height: family == .systemSmall ? 50 : 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Label("今日の1曲", systemImage: "music.quarternote.3")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(info.title)
                        .font(.system(size: family == .systemSmall ? 12 : 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let label = info.artistLabel, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if family != .systemSmall { Spacer(minLength: 0) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(URL(string: "imaslivedb://open"))
        } else {
            TodaySongPlaceholder()
        }
    }
}

struct TodaySongPlaceholder: View {
    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 6) {
                Image(systemName: "music.quarternote.3")
                    .font(.title2)
                Text("今日の1曲を準備中")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(8)
        }
    }
}

struct TodaySongWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySongWidget", provider: TodaySongProvider()) { entry in
            TodaySongWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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
        let deadlines = InfoWidgetSnapshot.load()?.ticketDeadlines ?? []
        completion(TicketDeadlineEntry(date: Date(), deadlines: deadlines))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TicketDeadlineEntry>) -> Void) {
        let deadlines = InfoWidgetSnapshot.load()?.ticketDeadlines ?? []
        let entry = TicketDeadlineEntry(date: Date(), deadlines: deadlines)
        let nextMidnight = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
        ) ?? Date(timeIntervalSinceNow: 3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct TicketDeadlineWidgetView: View {
    var entry: TicketDeadlineEntry

    var body: some View {
        if entry.deadlines.isEmpty {
            TicketDeadlinePlaceholder()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("チケット締切", systemImage: "ticket")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                ForEach(entry.deadlines.prefix(3), id: \.eventId) { item in
                    HStack(spacing: 6) {
                        Text(shortDate(item.deadline))
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(.orange)
                            .frame(minWidth: 32, alignment: .leading)
                        Text(item.eventName)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "imaslivedb://open"))
        }
    }
}

struct TicketDeadlinePlaceholder: View {
    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 6) {
                Image(systemName: "ticket")
                    .font(.title2)
                Text("締切近いチケットなし")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(8)
        }
    }
}

struct TicketDeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TicketDeadlineWidget", provider: TicketDeadlineProvider()) { entry in
            TicketDeadlineWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("チケット締切")
        .description("チケット締切が近いイベントを最大3件表示します。")
        .supportedFamilies([.systemMedium])
    }
}
