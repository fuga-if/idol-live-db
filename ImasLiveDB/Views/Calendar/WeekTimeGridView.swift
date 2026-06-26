import SwiftUI

// MARK: - WeekTimeGridView

/// Google カレンダー風の時間グリッド週ビュー。
/// 上から: 週送りヘッダ / 曜日+日付ヘッダ / 終日・時刻未定レーン / 時間グリッド (縦スクロール)。
/// 列幅は (全体幅 - 時刻ガター) / 7 の固定値、時間軸も固定スケールのため、
/// 週送りやイベント数の増減でレイアウトが変動しない。
struct WeekTimeGridView: View {
    @Binding var selectedDate: Date
    let entriesByDate: [Date: [CalendarEntry]]
    /// タイムブロック / 終日帯タップ → 親が既存の詳細シートを開く。
    let onSelectEntry: (CalendarEntry) -> Void
    /// 終日レーンの "+n" タップ → 親が日詳細シートを開く。
    let onShowDay: (Date) -> Void

    private let cal = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    // MARK: - レイアウト定数

    private enum Metric {
        /// 時間軸の表示範囲 (6:00 〜 24:00)
        static let startHour = 6
        static let endHour = 24
        /// 1 時間あたりの高さ
        static let hourHeight: CGFloat = 44
        /// 左端の時刻ラベル列の幅
        static let gutterWidth: CGFloat = 44
        /// 終了時刻データが無い公演に与える仮の長さ (分)
        static let defaultShowDurationMinutes = 120
        /// ブロックの最小高さ (短すぎてタップ不能になるのを防ぐ)
        static let minBlockHeight: CGFloat = 20
        static var gridHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }
    }

    /// 終日レーンに表示する最大帯数 (超過分は +n)
    private let maxAllDayBands = 2

    private enum Swipe {
        static let minimumDistance: CGFloat = 50
        static let maxVerticalTolerance: CGFloat = 60
        static let cooldownNanoseconds: UInt64 = 300_000_000
    }

    @State private var swipeCooldown = false

    // MARK: - 週の導出

    /// 選択日を含む週の開始日（日曜）
    private var weekStart: Date {
        let weekday = cal.component(.weekday, from: selectedDate) - 1  // 0=Sun
        return cal.date(byAdding: .day, value: -weekday, to: cal.startOfDay(for: selectedDate)) ?? selectedDate
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekRangeTitle: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.month().day())) 〜 \(end.formatted(.dateTime.month().day()))"
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let dayWidth = (geo.size.width - Metric.gutterWidth) / 7
            VStack(spacing: DS.sp2) {
                weekHeader
                dayHeaderRow(dayWidth: dayWidth)
                periodBandLane(dayWidth: dayWidth)
                allDayLane(dayWidth: dayWidth)
                Rectangle().fill(DS.sep).frame(height: 0.5)
                timeGrid(dayWidth: dayWidth)
            }
            .simultaneousGesture(weekSwipeGesture)
        }
    }

    // MARK: - 週送りヘッダ

    private var weekHeader: some View {
        HStack {
            navButton(systemImage: "chevron.left") { advanceWeek(-1) }
            Spacer()
            Text(weekRangeTitle)
                .font(.imasDisplay(15, weight: .bold))
                .foregroundStyle(DS.ink)
            Spacer()
            navButton(systemImage: "chevron.right") { advanceWeek(1) }
        }
        .padding(.horizontal, DS.sp2)
    }

    private func navButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.imasScaled( 15, weight: .semibold))
                .foregroundStyle(DS.ink2)
                .frame(width: 34, height: 34)
                .background(DS.fill, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func advanceWeek(_ delta: Int) {
        if let newDate = cal.date(byAdding: .weekOfYear, value: delta, to: selectedDate) {
            selectedDate = cal.startOfDay(for: newDate)
        }
    }

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: Swipe.minimumDistance)
            .onEnded { value in
                guard !swipeCooldown else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dy) < Swipe.maxVerticalTolerance, abs(dx) > Swipe.minimumDistance else { return }
                swipeCooldown = true
                advanceWeek(dx < 0 ? 1 : -1)
                Task {
                    try? await Task.sleep(nanoseconds: Swipe.cooldownNanoseconds)
                    swipeCooldown = false
                }
            }
    }

    // MARK: - 曜日 + 日付ヘッダ

    private func dayHeaderRow(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Metric.gutterWidth, height: 1)
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, date in
                let isToday = cal.isDate(date, inSameDayAs: today)
                let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
                VStack(spacing: 2) {
                    Text(weekdaySymbols[idx])
                        .font(.imasScaled( 10, weight: .semibold))
                        .foregroundStyle(isToday ? DS.ink : DS.ink3)
                    ZStack {
                        if isToday {
                            Circle().fill(DS.sys)
                        } else if isSelected {
                            Circle().strokeBorder(DS.sys, lineWidth: 1.5)
                        }
                        Text("\(cal.component(.day, from: date))")
                            .font(.imasDisplay(14, weight: isToday ? .bold : .medium))
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(isToday ? DS.onSys : DS.ink)
                    }
                    .frame(width: 28, height: 28)
                }
                .frame(width: dayWidth)
                .contentShape(Rectangle())
                .onTapGesture { selectedDate = cal.startOfDay(for: date) }
            }
        }
    }

    // MARK: - 受付期間の連続帯レーン (列をまたぐ)

    private enum BandMetric {
        static let height: CGFloat = 16
        static let gap: CGFloat = 2
    }

    /// この週に重なる受付期間スパンを列範囲へ落とし込み、重ならないようレーン詰めする。
    /// 列インデックス算出 + レーン詰めは月グリッドと共通 (CalendarPeriodBand.pack)。
    private var weekPeriodBands: [CalendarPeriodBand] {
        CalendarPeriodBand.pack(weekDays: weekDays, entriesByDate: entriesByDate, calendar: cal)
    }

    @ViewBuilder
    private func periodBandLane(dayWidth: CGFloat) -> some View {
        let bands = weekPeriodBands
        let laneCount = CalendarPeriodBand.laneCount(of: bands)
        let h = BandMetric.height, gap = BandMetric.gap
        ZStack(alignment: .topLeading) {
            ForEach(bands) { band in
                let x = Metric.gutterWidth + CGFloat(band.startCol) * dayWidth
                let w = CGFloat(band.endCol - band.startCol + 1) * dayWidth
                Button {
                    onSelectEntry(band.entry)
                } label: {
                    Text("受付 \(band.name)")
                        .font(.imasScaled( 10, weight: .semibold))
                        .foregroundStyle(ColorMath.onColor(.indigo))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .frame(width: max(0, w - 2), height: h, alignment: .leading)
                        .background(
                            Color.indigo,
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: band.roundLeading ? 4 : 0,
                                bottomLeadingRadius: band.roundLeading ? 4 : 0,
                                bottomTrailingRadius: band.roundTrailing ? 4 : 0,
                                topTrailingRadius: band.roundTrailing ? 4 : 0,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .offset(x: x + 1, y: CGFloat(band.lane) * (h + gap))
            }
        }
        .frame(height: laneCount > 0 ? CGFloat(laneCount) * (h + gap) - gap : 0, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 終日 / 時刻未定レーン

    private var allDayLaneHeight: CGFloat {
        CGFloat(maxAllDayBands) * 15 + CGFloat(maxAllDayBands - 1) * 2 + 13
    }

    private func allDayLane(dayWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("終日")
                .font(.imasScaled( 9, weight: .semibold))
                .foregroundStyle(DS.ink3)
                .frame(width: Metric.gutterWidth)
            ForEach(weekDays, id: \.self) { date in
                allDayCell(for: date)
                    .frame(width: dayWidth, alignment: .top)
            }
        }
        .frame(height: allDayLaneHeight, alignment: .top)
    }

    @ViewBuilder
    private func allDayCell(for date: Date) -> some View {
        let entries = allDayEntries(on: date)
        VStack(spacing: 2) {
            ForEach(entries.prefix(maxAllDayBands)) { entry in
                Button {
                    onSelectEntry(entry)
                } label: {
                    CalendarEntryBar(entry: entry, height: 15)
                }
                .buttonStyle(.plain)
            }
            if entries.count > maxAllDayBands {
                Button {
                    onShowDay(date)
                } label: {
                    Text("+\(entries.count - maxAllDayBands)")
                        .font(.imasDisplay(9, weight: .semibold))
                        .foregroundStyle(DS.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 1)
    }

    // MARK: - 時間グリッド

    private func timeGrid(dayWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    hourRows
                    verticalSeparators(dayWidth: dayWidth)
                    eventBlocks(dayWidth: dayWidth)
                    nowIndicator(dayWidth: dayWidth)
                }
                .padding(.top, DS.sp3)
                .padding(.bottom, DS.sp4)
            }
            .onAppear { scrollToStart(proxy) }
            .onChange(of: weekStart) { _, _ in scrollToStart(proxy) }
        }
    }

    /// 1 時間ごとの罫線 + 時刻ラベル。各行に .id(時) を振り初期スクロールの基準にする。
    private var hourRows: some View {
        VStack(spacing: 0) {
            ForEach(Metric.startHour..<Metric.endHour, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(DS.sep)
                        .frame(height: 0.5)
                        .padding(.leading, Metric.gutterWidth)
                    Text("\(hour):00")
                        .font(.imasDisplay(10, weight: .medium))
                        .foregroundStyle(DS.ink3)
                        .frame(width: Metric.gutterWidth - 6, alignment: .trailing)
                        .offset(y: -5)
                }
                .frame(height: Metric.hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func verticalSeparators(dayWidth: CGFloat) -> some View {
        ForEach(0...7, id: \.self) { i in
            Rectangle()
                .fill(DS.sep)
                .frame(width: 0.5, height: Metric.gridHeight)
                .offset(x: Metric.gutterWidth + CGFloat(i) * dayWidth)
        }
    }

    /// 初期スクロール位置: 週内の最初のイベント時刻、無ければ 9:00。
    private func scrollToStart(_ proxy: ScrollViewProxy) {
        let firstMinutes = weekDays
            .flatMap { timedBlocks(on: $0) }
            .map(\.startMinutes)
            .min()
        let hour = firstMinutes.map { max(Metric.startHour, min($0 / 60, Metric.endHour - 1)) } ?? 9
        proxy.scrollTo(hour, anchor: .top)
    }

    // MARK: - 現在時刻インジケータ

    @ViewBuilder
    private func nowIndicator(dayWidth: CGFloat) -> some View {
        if let todayIndex = weekDays.firstIndex(where: { cal.isDate($0, inSameDayAs: today) }) {
            TimelineView(.everyMinute) { context in
                let comps = cal.dateComponents([.hour, .minute], from: context.date)
                let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                if minutes >= Metric.startHour * 60 && minutes <= Metric.endHour * 60 {
                    HStack(spacing: 0) {
                        Circle().fill(DS.danger).frame(width: 7, height: 7)
                        Rectangle().fill(DS.danger).frame(height: 1.5)
                    }
                    .frame(width: dayWidth + 3.5, height: 7)
                    .offset(
                        x: Metric.gutterWidth + CGFloat(todayIndex) * dayWidth - 3.5,
                        y: yPosition(forMinutes: minutes) - 3.5
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - イベントブロック

    private func eventBlocks(dayWidth: CGFloat) -> some View {
        ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, date in
            let layout = layoutTimedBlocks(timedBlocks(on: date))
            let originX = Metric.gutterWidth + CGFloat(idx) * dayWidth

            ForEach(layout.visible) { block in
                let width = block.isHalfWidth ? (dayWidth - 2) / 2 : dayWidth - 2
                let x = originX + 1 + (block.isHalfWidth ? CGFloat(block.lane) * (dayWidth - 2) / 2 : 0)
                blockView(block)
                    .frame(width: width, height: blockHeight(block))
                    .offset(x: x, y: yPosition(forMinutes: block.startMinutes))
            }

            // 2 列に収まらなかった分は "+n" バッジで集約 (タップ → 日詳細シート)
            ForEach(layout.overflow, id: \.startMinutes) { item in
                Button {
                    onShowDay(date)
                } label: {
                    Text("+\(item.count)")
                        .font(.imasDisplay(9, weight: .bold))
                        .foregroundStyle(DS.onSys)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(DS.sys, in: Capsule())
                }
                .buttonStyle(.plain)
                .offset(
                    x: originX + dayWidth - 22,
                    y: yPosition(forMinutes: item.startMinutes) + 2
                )
            }
        }
    }

    private func blockView(_ block: TimedBlock) -> some View {
        Button {
            onSelectEntry(block.entry)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(blockTitle(block.entry))
                    .font(.imasScaled( 10, weight: .semibold))
                    .lineLimit(2)
                Text(timeLabel(forMinutes: block.startMinutes))
                    .font(.imasDisplay(9, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(block.entry.accentInk)
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(block.entry.accentColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func blockTitle(_ entry: CalendarEntry) -> String {
        switch entry {
        case .show(let row): return row.eventName
        case .release(_, let songs): return songs.first?.title ?? "リリース"
        case .birthday(let idol): return idol.name
        case .personal(let event): return event.title
        case .ticket(let row): return "\(row.kind.label)・\(row.eventName)"
        case .ticketPeriod(let row): return "受付・\(row.eventName)"
        }
    }

    // MARK: - 時刻 → 座標

    private func yPosition(forMinutes minutes: Int) -> CGFloat {
        let y = CGFloat(minutes - Metric.startHour * 60) / 60 * Metric.hourHeight
        return min(max(y, 0), Metric.gridHeight)
    }

    private func blockHeight(_ block: TimedBlock) -> CGFloat {
        let h = yPosition(forMinutes: block.endMinutes) - yPosition(forMinutes: block.startMinutes)
        return max(h, Metric.minBlockHeight)
    }

    private func timeLabel(forMinutes minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - エントリ振り分け

    private func entries(on date: Date) -> [CalendarEntry] {
        let key = cal.startOfDay(for: date)
        return (entriesByDate[key] ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 終日レーン行き: 時刻情報を持たないエントリ。受付期間の帯は列をまたぐ連続帯として
    /// 別レイヤー (periodBands) で描くので、各日セルからは除外する。
    private func allDayEntries(on date: Date) -> [CalendarEntry] {
        entries(on: date).filter { entry in
            if case .ticketPeriod = entry { return false }
            return timedMinutes(of: entry, on: date) == nil
        }
    }

    /// 時間グリッド行き: 開始時刻を持つエントリをブロック化する。
    private func timedBlocks(on date: Date) -> [TimedBlock] {
        entries(on: date).compactMap { entry in
            guard let range = timedMinutes(of: entry, on: date) else { return nil }
            return TimedBlock(
                id: entry.id,
                entry: entry,
                startMinutes: range.start,
                endMinutes: range.end
            )
        }
    }

    /// エントリの (開始分, 終了分)。時刻データが無いものは nil (終日レーン行き)。
    /// 日をまたぐマイ予定はその日の 0:00〜24:00 でクリップする。
    private func timedMinutes(of entry: CalendarEntry, on date: Date) -> (start: Int, end: Int)? {
        switch entry {
        case .show(let row):
            guard let start = Self.parseTimeMinutes(row.show.startTime) else { return nil }
            // 終了時刻データは無いため仮に 2 時間ぶんの高さで描画する
            return (start, min(start + Metric.defaultShowDurationMinutes, 24 * 60))
        case .release, .birthday, .ticket, .ticketPeriod:
            return nil
        case .personal(let event):
            guard !event.isAllDay else { return nil }
            let dayStart = cal.startOfDay(for: date)
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let start = max(event.start, dayStart)
            let end = min(event.end, dayEnd)
            guard end > start else { return nil }
            let startMin = Int(start.timeIntervalSince(dayStart) / 60)
            let endMin = Int(end.timeIntervalSince(dayStart) / 60)
            return (startMin, max(endMin, startMin + 15))
        }
    }

    /// "HH:MM" → 0:00 からの経過分。
    static func parseTimeMinutes(_ time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    // MARK: - 重なりレイアウト

    private struct TimedBlock: Identifiable {
        let id: String
        let entry: CalendarEntry
        let startMinutes: Int
        let endMinutes: Int
        var lane = 0
        var isHalfWidth = false
    }

    private struct OverflowBadge {
        let startMinutes: Int
        let count: Int
    }

    /// 同時刻の重なりを最大 2 列に振り分け、収まらない分を +n に集約する。
    private func layoutTimedBlocks(_ blocks: [TimedBlock]) -> (visible: [TimedBlock], overflow: [OverflowBadge]) {
        let sorted = blocks.sorted { ($0.startMinutes, $0.endMinutes) < ($1.startMinutes, $1.endMinutes) }
        var visible: [TimedBlock] = []
        var hidden: [TimedBlock] = []
        var laneEnds = [Int.min, Int.min]  // 各レーンの最終終了分

        for var block in sorted {
            if let lane = laneEnds.firstIndex(where: { $0 <= block.startMinutes }) {
                block.lane = lane
                laneEnds[lane] = block.endMinutes
                visible.append(block)
            } else {
                hidden.append(block)
            }
        }

        // 他の可視ブロックと時間帯が重なるものだけ半分幅にする
        for i in visible.indices {
            let a = visible[i]
            visible[i].isHalfWidth = visible.contains { b in
                b.id != a.id && a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes
            }
        }

        let overflow = Dictionary(grouping: hidden, by: \.startMinutes)
            .map { OverflowBadge(startMinutes: $0.key, count: $0.value.count) }
            .sorted { $0.startMinutes < $1.startMinutes }
        return (visible, overflow)
    }
}
