import SwiftUI

// MARK: - MonthCalendarView

/// フィット型の月グリッド。
/// 親から与えられた高さに 6 行 × 7 列を必ず収める (Apple 純正カレンダーと同方式)。
/// セル高 = (グリッド利用可能高 - 行間) / 6 で全セル均等割り付け。
/// 帯はセル高に収まる本数だけ表示し、残りは "+n" に集約するため、
/// どの月・どの端末サイズでもコンテンツがあふれない。
struct MonthCalendarView: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    let entriesByDate: [Date: [CalendarEntry]]
    @Environment(\.colorScheme) private var scheme

    /// チケット受付期間帯の装飾テーマ seed (iOS system indigo 相当。CalendarDayDetailView のチケット行と揃える)。
    private static let ticketSeed = "#5856D6"

    private let today = Calendar.current.startOfDay(for: Date())
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    private enum Layout {
        static let rowSpacing: CGFloat = DS.sp1
        static let columnSpacing: CGFloat = DS.sp2
        static let rowCount = 6
        static let columnCount = 7
    }

    private enum Swipe {
        static let minimumDistance: CGFloat = 50
        static let maxVerticalTolerance: CGFloat = 60
        static let cooldownNanoseconds: UInt64 = 300_000_000
    }

    @State private var swipeCooldown = false

    var body: some View {
        VStack(spacing: DS.sp3) {
            monthHeader
            weekdayHeader
            // 残り高さを GeometryReader で測り、6 行に均等割り付けする
            GeometryReader { geo in
                let cellHeight = max(
                    0,
                    (geo.size.height - Layout.rowSpacing * CGFloat(Layout.rowCount - 1)) / CGFloat(Layout.rowCount)
                )
                grid(days: gridDays, cellHeight: cellHeight)
            }
        }
    }

    private func grid(days: [Date], cellHeight: CGFloat) -> some View {
        VStack(spacing: Layout.rowSpacing) {
            ForEach(0..<Layout.rowCount, id: \.self) { row in
                let weekDays = weekSlice(days, row: row)
                // マスの高さは決まっているので帯は maxBandLanes 段まで。溢れた帯はその日の "+n" に数える。
                let packed = CalendarPeriodBand.packMonth(
                    weekDays: weekDays,
                    entriesByDate: entriesByDate,
                    calendar: Calendar.current,
                    maxLanes: MonthGridMetric.maxBandLanes
                )
                let bands = packed.bands
                let laneCount = CalendarPeriodBand.laneCount(of: bands)
                let bandInset = CGFloat(laneCount) * MonthGridMetric.bandSlot
                HStack(spacing: Layout.columnSpacing) {
                    ForEach(0..<Layout.columnCount, id: \.self) { column in
                        let index = row * Layout.columnCount + column
                        if days.indices.contains(index) {
                            dayCell(for: days[index], height: cellHeight, bandInset: bandInset,
                                    hiddenBands: packed.hiddenPerCol.indices.contains(column) ? packed.hiddenPerCol[column] : 0)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: cellHeight)
                // 受付期間などの日跨ぎ帯を、列をまたぐ 1 本の連続帯として上段に重ねる
                // (セル間スペースも塗るのでセグメントが切れず線が繋がる)。
                .overlay(alignment: .topLeading) {
                    GeometryReader { geo in
                        bandOverlay(bands, width: geo.size.width)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: Swipe.minimumDistance)
                .onEnded { value in
                    guard !swipeCooldown else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dy) < Swipe.maxVerticalTolerance, abs(dx) > Swipe.minimumDistance else { return }
                    swipeCooldown = true
                    advanceMonth(dx < 0 ? 1 : -1)
                    Task {
                        try? await Task.sleep(nanoseconds: Swipe.cooldownNanoseconds)
                        swipeCooldown = false
                    }
                }
        )
    }

    private func dayCell(for date: Date, height: CGFloat, bandInset: CGFloat, hiddenBands: Int) -> some View {
        DayCell(
            date: date,
            entries: entriesByDate[Calendar.current.startOfDay(for: date)] ?? [],
            isCurrentMonth: isCurrentMonth(date),
            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
            isToday: Calendar.current.isDate(date, inSameDayAs: today),
            height: height,
            bandInset: bandInset,
            hiddenBands: hiddenBands
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDate = Calendar.current.startOfDay(for: date)
        }
    }

    /// グリッドの 1 週 (行) ぶんの日付。
    private func weekSlice(_ days: [Date], row: Int) -> [Date] {
        let start = row * Layout.columnCount
        let end = min(start + Layout.columnCount, days.count)
        guard start < end else { return [] }
        return Array(days[start..<end])
    }

    /// 週行に重ねる連続帯。列スペースも塗って 1 本に繋げる。
    private func bandOverlay(_ bands: [CalendarPeriodBand], width: CGFloat) -> some View {
        let colSpacing = Layout.columnSpacing
        let cellW = (width - colSpacing * CGFloat(Layout.columnCount - 1)) / CGFloat(Layout.columnCount)
        let ticketAccent = ImasTheme.derive(seed: Self.ticketSeed, scheme: scheme).accent
        return ZStack(alignment: .topLeading) {
            ForEach(bands) { band in
                let x = CGFloat(band.startCol) * (cellW + colSpacing)
                let w = CGFloat(band.endCol - band.startCol) * (cellW + colSpacing) + cellW
                Text(band.roundLeading ? "受付 \(band.name)" : " ")
                    .imasText(.micro, color: ColorMath.onColor(ticketAccent))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, DS.sp1)
                    .frame(width: w, height: MonthGridMetric.bandHeight, alignment: .leading)
                    .background(
                        ticketAccent,
                        // 複数日にまたがる受付帯の、連続区間の両端だけを丸める形。DS の角丸トークンは
                        // 四隅一律が前提で「先頭/末尾だけ」を表せないため、月グリッドの固定要素として残す。
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: band.roundLeading ? 2 : 0,
                            bottomLeadingRadius: band.roundLeading ? 2 : 0,
                            bottomTrailingRadius: band.roundTrailing ? 2 : 0,
                            topTrailingRadius: band.roundTrailing ? 2 : 0,
                            style: .continuous
                        )
                    )
                    .offset(x: x, y: MonthGridMetric.bandTop + CGFloat(band.lane) * MonthGridMetric.bandSlot)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            navButton(systemImage: "chevron.left", label: "前の月") { advanceMonth(-1) }
            Spacer()
            Text(monthTitle)
                .font(.imasDisplay(17, weight: .bold))
                .foregroundStyle(DS.ink)
            Spacer()
            navButton(systemImage: "chevron.right", label: "次の月") { advanceMonth(1) }
        }
        .padding(.horizontal, DS.sp2)
    }

    private func navButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        ImasIconButton(systemImage: systemImage, label: label, size: .small, style: .tinted, action: action)
    }

    private var weekdayHeader: some View {
        HStack(spacing: Layout.columnSpacing) {
            ForEach(weekdaySymbols, id: \.self) { day in
                Text(day)
                    .imasText(.badge, color: DS.ink3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthTitle: String {
        let cal = Calendar.current
        let year = cal.component(.year, from: visibleMonth)
        let month = cal.component(.month, from: visibleMonth)
        return "\(year)年 \(month)月"
    }

    private var gridDays: [Date] {
        let cal = Calendar.current
        guard let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: visibleMonth)) else {
            return []
        }
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth) - 1
        let gridStart = cal.date(byAdding: .day, value: -weekdayOfFirst, to: firstOfMonth) ?? firstOfMonth
        return (0..<(Layout.rowCount * Layout.columnCount)).compactMap {
            cal.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    private func isCurrentMonth(_ date: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.month, from: date) == cal.component(.month, from: visibleMonth)
            && cal.component(.year, from: date) == cal.component(.year, from: visibleMonth)
    }

    private func advanceMonth(_ delta: Int) {
        let cal = Calendar.current
        if let newMonth = cal.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = cal.date(from: cal.dateComponents([.year, .month], from: newMonth)) ?? newMonth
        }
    }
}

// MARK: - 月グリッドの寸法 + 帯

/// 月グリッドの縦寸法。DayCell と週行の帯オーバーレイで共有し、両者の縦位置を必ず揃える。
private enum MonthGridMetric {
    /// 日番号ゾーン (今日サークル) の高さ
    static let numberZoneHeight: CGFloat = 26
    /// 日番号ゾーンと帯ゾーンの間隔
    static let zoneSpacing: CGFloat = 2
    /// 単日バー 1 本の高さ
    static let barHeight: CGFloat = 10
    /// バー同士・バーと "+n" の間隔
    static let barSpacing: CGFloat = 2
    /// "+n" 行の高さ
    static let overflowHeight: CGFloat = 10
    /// 1 週に描く受付期間の帯の段数の上限 (溢れた帯は日の "+n" に数える)
    static let maxBandLanes = 1
    /// 受付期間帯 1 本の高さ
    static let bandHeight: CGFloat = 11
    /// 帯 1 レーンぶんの縦送り
    static var bandSlot: CGFloat { bandHeight + barSpacing }
    /// 帯ゾーンの開始 Y (日番号ゾーンの直下)
    static var bandTop: CGFloat { numberZoneHeight + zoneSpacing }
}

// MARK: - DayCell

/// 月カレンダーの 1 日セル。日番号 + 単日バーを表示。受付期間の帯は週行オーバーレイ側で
/// 描くので、上部に bandInset (週のレーン数ぶん) を空けてバーが帯と重ならないようにする。
/// バーの表示本数はフィットグリッドが割り付けたセル高から逆算し、
/// 収まらない分は "+n" に集約する。
private struct DayCell: View {
    let date: Date
    let entries: [CalendarEntry]
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    /// フィットグリッドが割り付けたセル高
    let height: CGFloat
    /// 受付期間帯のために上部へ確保する高さ (この週のレーン数ぶん)
    let bandInset: CGFloat
    /// 段が溢れて描かなかった受付期間の帯の数 ("+n" に含める)
    var hiddenBands: Int = 0

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    private var numberColor: Color {
        if isToday { return DS.onSys }
        if !isCurrentMonth { return DS.ink3 }
        return DS.ink
    }

    /// 単日バーに使うエントリ。受付期間帯は overlay で描くのでここからは除外する。
    private var barEntries: [CalendarEntry] {
        entries
            .filter { if case .ticketPeriod = $0 { return false } else { return true } }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// バーゾーンの利用可能高 (帯ぶんを差し引く) から (表示本数, "+n" の n) を決める。
    private var barPlan: (visible: Int, overflow: Int) {
        let count = barEntries.count
        guard count > 0 else { return (0, hiddenBands) }
        let zone = max(0, height - MonthGridMetric.bandTop - bandInset)
        let allHeight = CGFloat(count) * MonthGridMetric.barHeight + CGFloat(count - 1) * MonthGridMetric.barSpacing
        if allHeight <= zone && hiddenBands == 0 { return (count, 0) }
        // "+n" の行ぶんを空けてから入る本数を数える (帯が溢れた日はバーが全部入っても "+n" が要る)。
        let slot = MonthGridMetric.barHeight + MonthGridMetric.barSpacing
        let fit = Int((zone - MonthGridMetric.overflowHeight) / slot)
        let visible = max(0, min(hiddenBands > 0 ? count : count - 1, fit))
        return (visible, count - visible + hiddenBands)
    }

    var body: some View {
        let plan = barPlan
        VStack(spacing: MonthGridMetric.zoneSpacing) {
            ZStack {
                ImasDateMark(isToday: isToday, isSelected: isSelected, size: MonthGridMetric.numberZoneHeight)
                Text("\(dayNumber)")
                    .font(.imasDisplay(13, weight: isToday ? .bold : .medium))
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(numberColor)
            }
            .frame(height: MonthGridMetric.numberZoneHeight)
            // 単日バー (帯ぶんだけ上を空ける)
            VStack(spacing: MonthGridMetric.barSpacing) {
                ForEach(barEntries.prefix(plan.visible)) { entry in
                    CalendarEntryBar(entry: entry, height: MonthGridMetric.barHeight)
                }
                if plan.overflow > 0 {
                    Text("+\(plan.overflow)")
                        .imasText(.micro)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: MonthGridMetric.overflowHeight)
                        .padding(.horizontal, DS.sp1)
                }
            }
            .padding(.top, bandInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // 日付セルの選択ハイライト地。`ImasDateMark` は丸 (今日/選択の印) 専用で、
        // セル全体を塗るこの背景とは別物のため、角丸はトークン (DS.rSM) のままここに残す。
        .background(
            RoundedRectangle(cornerRadius: DS.rSM, style: .continuous)
                .fill(isSelected && !isToday ? DS.fill : Color.clear)
        )
    }
}

// MARK: - CalendarEntryBar

/// 1 イベントの色帯。ブランド色背景 + 省スペーステキスト。
/// 月グリッドの日セルと週ビューの終日レーンで共有する。
struct CalendarEntryBar: View {
    let entry: CalendarEntry
    /// 帯の高さ。月セル=10pt / 週終日レーン=15pt 等、置き場所で変える。
    var height: CGFloat = 11
    @Environment(\.colorScheme) private var scheme

    private var label: String {
        switch entry {
        case .show(let row): return row.eventName
        case .release(_, let songs):
            return songs.first.map { $0.title } ?? "リリース"
        case .birthday(let idol, _):
            return idol.name
        case .staffBirthday(let staff, _):
            return staff.name
        case .anniversary(let ann, _):
            // 月セルは狭いので「ラベル」だけ。N周年は日詳細で見せる。
            return ann.label
        case .personal(let event):
            return event.title
        case .ticket(let row):
            return "\(row.kind.label)・\(row.eventName)"
        case .ticketPeriod(let row):
            return "受付・\(row.eventName)"
        }
    }

    var body: some View {
        Text(label)
            .imasText(.micro, color: entry.accentInk(scheme: scheme))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, DS.sp1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            // 色帯そのものの小さい角丸は、月グリッド/週ビューの固定要素として形を残す (GAPS.md §7)。
            .background(entry.accentColor(scheme: scheme), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}
