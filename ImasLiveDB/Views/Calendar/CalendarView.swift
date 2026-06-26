import os
import SwiftUI

struct CalendarView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine

    @AppStorage("calendar_show_shows") private var showShows = true
    @AppStorage("calendar_show_releases") private var showReleases = true
    @AppStorage("calendar_show_birthdays") private var showBirthdays = false
    @AppStorage("calendar_show_tickets") private var showTickets = true
    /// 端末カレンダーのマイ予定オーバーレイ (オプトイン、デフォルト OFF)
    @AppStorage("calendar_show_personal") private var showPersonal = false
    /// 0 = 月表示, 1 = 週表示
    @AppStorage("calendar_display_mode") private var displayMode = 0

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var visibleMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()
    @State private var allEntriesByDate: [Date: [CalendarEntry]] = [:]
    /// 端末カレンダー由来のマイ予定 (DB エントリとは別管理、表示時にマージ)
    @State private var personalEntriesByDate: [Date: [CalendarEntry]] = [:]
    @State private var filteredEntriesByDate: [Date: [CalendarEntry]] = [:]
    @State private var sheetDestination: DetailDestination?
    /// 「今日の1曲」シート。ゲームからスケジュールタブへ導線を移設。
    @State private var showDailySong = false
    @State private var daySheet: DaySheet?
    /// マイ予定の簡易詳細シート (DetailDestination を持たないため別経路で表示)
    @State private var personalDetail: PersonalCalendarEvent?
    @State private var isLoading = false
    @State private var showPersonalPermissionAlert = false
    @State private var personalErrorMessage: String?
    /// chip 列のスクロール状態 (エッジフェード判定用)
    @State private var chipContentFrame: CGRect = .zero
    @State private var chipViewportWidth: CGFloat = 0

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    /// 月表示の縦空間配分。グリッドはフィット型なので、ここで決めた高さに必ず収まる。
    private enum MonthLayout {
        /// 月グリッド (月送りヘッダ + 曜日ヘッダ込み) に割り当てる縦空間の割合
        static let gridFraction: CGFloat = 0.62
        /// iPad 等の大画面でグリッドだけが間延びしないための上限
        static let maxGridHeight: CGFloat = 520
    }

    private var selectedDayEntries: [CalendarEntry] {
        entries(on: selectedDate)
    }

    private func rebuildFiltered() {
        var result = allEntriesByDate.mapValues { entries in
            entries.filter { entry in
                switch entry {
                case .show: return showShows
                case .release: return showReleases
                case .birthday: return showBirthdays
                case .ticket, .ticketPeriod: return showTickets
                case .personal: return false  // マイ予定は personalEntriesByDate 側で管理
                }
            }
        }
        if showPersonal {
            for (day, entries) in personalEntriesByDate {
                result[day, default: []].append(contentsOf: entries)
            }
        }
        filteredEntriesByDate = result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // カテゴリ chip + 月/週 切替
                topBar

                if displayMode == 0 {
                    // 月グリッド + 選択日の予定リスト。
                    // GeometryReader で利用可能高を測り、月グリッドには固定割合を割り付ける
                    // (グリッド側はフィット型なので、与えた高さに 6 行が必ず収まる)。
                    // 残りは選択日リストが取り、リストは内部スクロールするためあふれない。
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            MonthCalendarView(
                                visibleMonth: $visibleMonth,
                                selectedDate: $selectedDate,
                                entriesByDate: filteredEntriesByDate
                            )
                            .padding(.horizontal, DS.sp5)
                            .padding(.top, DS.sp2)
                            .frame(height: min(geo.size.height * MonthLayout.gridFraction, MonthLayout.maxGridHeight))

                            // 選択日の小見出し
                            selectedDayHeader
                                .padding(.horizontal, DS.sp5)
                                .padding(.top, DS.sp4)
                                .padding(.bottom, DS.sp2)

                            // 選択日の予定リスト（この領域のみ内部スクロール）
                            selectedDayList
                        }
                    }
                } else {
                    // 時間グリッド週ビュー（Google カレンダー風、画面いっぱい）
                    WeekTimeGridView(
                        selectedDate: $selectedDate,
                        entriesByDate: filteredEntriesByDate,
                        onSelectEntry: { openEntryDetail($0) },
                        onShowDay: { daySheet = DaySheet(date: $0) }
                    )
                    .padding(.horizontal, DS.sp3)
                    .padding(.top, DS.sp2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(DS.bg)
            .navigationTitle("スケジュール")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppAnalytics.tap("calendar.daily_song")
                        showDailySong = true
                    } label: {
                        Image(systemName: "music.note.house.fill")
                    }
                    .accessibilityLabel("今日の1曲")
                    .accessibilityHint("各ブランドの日替わり1曲を試聴・タグ投票します")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    GlobalSearchToolbarButton()
                }
            }
            .sheet(isPresented: $showDailySong) {
                DailySongVoteSheet().environment(database)
            }
            .sheet(item: $sheetDestination) { dest in
                DetailSheetView(destination: dest)
                    .environment(database)
            }
            .sheet(item: $daySheet) { sheet in
                CalendarDayDetailView(
                    entries: entries(on: sheet.date),
                    selectedDate: sheet.date,
                    // 二重 sheet 不可のため、日詳細を閉じてから次の sheet を開く
                    onSelect: { dest in dismissDaySheetThen { sheetDestination = dest } },
                    onSelectPersonal: { event in dismissDaySheetThen { personalDetail = event } }
                )
                .environment(database)
                .presentationDetents([.medium, .large])
            }
            // マイ予定の簡易詳細 (表示のみ・編集不可)
            .sheet(item: $personalDetail) { event in
                PersonalEventDetailView(event: event)
                    .presentationDetents([.medium])
            }
            .task {
                await loadEntries(for: visibleMonth)
                // 過去に ON にしたまま起動した場合: 権限が生きていれば静かに復元、
                // 設定で剥奪されていれば chip を OFF に戻す (アラートは出さない)
                if showPersonal {
                    if CalendarImportService.shared.hasReadAccess {
                        loadPersonalEvents()
                        rebuildFiltered()
                    } else {
                        showPersonal = false
                    }
                }
            }
            .onChange(of: visibleMonth) { _, newMonth in
                Task { await loadEntries(for: newMonth) }
            }
            .onChange(of: selectedDate) { _, newDate in
                // 週モードで月をまたいだ場合はデータを追加ロード
                if displayMode == 1, monthStart(of: newDate) != monthStart(of: visibleMonth) {
                    visibleMonth = monthStart(of: newDate)
                }
            }
            .onChange(of: showShows) { _, _ in rebuildFiltered() }
            .onChange(of: showReleases) { _, _ in rebuildFiltered() }
            .onChange(of: showBirthdays) { _, _ in rebuildFiltered() }
            .onChange(of: showTickets) { _, _ in rebuildFiltered() }
            .onChange(of: showPersonal) { _, isOn in
                if isOn {
                    Task { await enablePersonalOverlay() }
                } else {
                    rebuildFiltered()
                }
            }
            // マイ予定: 権限拒否 → 設定アプリ誘導
            .alert("カレンダーへのアクセスが必要です", isPresented: $showPersonalPermissionAlert) {
                Button("設定を開く") {
                    if let url = CalendarImportService.shared.settingsURL {
                        UIApplication.shared.open(url)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("マイ予定を重ねて表示するには、設定アプリでカレンダーへの「フルアクセス」を許可してください。")
            }
            // マイ予定: 権限リクエスト等のエラー表示
            .alert(
                "マイ予定を読み込めませんでした",
                isPresented: Binding(
                    get: { personalErrorMessage != nil },
                    set: { if !$0 { personalErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(personalErrorMessage ?? "")
            }
            .trackScreen("calendar")
        }
    }

    // MARK: - マイ予定 (端末カレンダー取り込み)

    /// chip ON 時のフロー: 権限確認 (必要ならリクエスト) → 取得 → マージ。
    /// 拒否されたら chip を OFF に戻して設定誘導アラートを出す。
    private func enablePersonalOverlay() async {
        do {
            let granted = try await CalendarImportService.shared.ensureFullAccess()
            guard granted else {
                showPersonal = false
                showPersonalPermissionAlert = true
                return
            }
            loadPersonalEvents()
            rebuildFiltered()
        } catch {
            showPersonal = false
            personalErrorMessage = error.localizedDescription
        }
    }

    /// 表示中レンジ (月グリッドの 42 日間 = 週ビューの範囲も内包) のマイ予定を取得。
    private func loadPersonalEvents() {
        let interval = monthGridInterval(for: visibleMonth)
        let events = CalendarImportService.shared.events(in: interval)
        personalEntriesByDate = groupPersonalByDate(events, in: interval)
    }

    /// 日をまたぐ予定は該当する各日に展開する (表示レンジでクリップ)。
    private func groupPersonalByDate(_ events: [PersonalCalendarEvent], in interval: DateInterval) -> [Date: [CalendarEntry]] {
        var result: [Date: [CalendarEntry]] = [:]
        for event in events {
            var day = calendar.startOfDay(for: max(event.start, interval.start))
            let lastDay = calendar.startOfDay(for: min(event.end, interval.end))
            repeat {
                result[day, default: []].append(.personal(event))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            } while day < lastDay || (day == lastDay && event.end > lastDay)
        }
        return result
    }

    // MARK: - トップバー（カテゴリ chip + 月/週 切替）

    private var topBar: some View {
        HStack(spacing: DS.sp3) {
            // カテゴリ chip (収まらない分は横スクロール + エッジフェードで「続きがある」ことを示す)
            chipScroller
            Spacer(minLength: DS.sp2)
            // 月/週 切替
            ImasSegmented(labels: ["月", "週"], selection: $displayMode)
                .frame(width: 80)
        }
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp3)
    }

    /// chip 列の横スクロール。スクロール位置と内容幅を測り、
    /// 「先に続きがある」側だけグラデーションでフェードさせる。
    /// 先頭にいる時は leading フェードを消すので、初期表示で先頭 chip が欠けて見えることはない。
    private var chipScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.sp3) {
                CalendarFilterChip(label: "公演", systemImage: "music.mic", color: Color(hexString: "#3E6DD6"), isOn: $showShows)
                CalendarFilterChip(label: "リリース", systemImage: "opticaldisc", color: DS.warning, isOn: $showReleases)
                CalendarFilterChip(label: "誕生日", systemImage: "gift", color: .pink, isOn: $showBirthdays)
                CalendarFilterChip(label: "チケット", systemImage: "ticket", color: DS.danger, isOn: $showTickets)
                CalendarFilterChip(label: "マイ予定", systemImage: "person.crop.circle", color: DS.sys, isOn: $showPersonal)
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(ChipScroll.coordinateSpace))
            } action: { frame in
                chipContentFrame = frame
            }
        }
        .coordinateSpace(name: ChipScroll.coordinateSpace)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            chipViewportWidth = width
        }
        .mask(chipFadeMask)
        // 次の chip が完全に画面外でフェードに掛かるピクセルが無い場合でも
        // 「先がある」と分かるよう、小さな chevron を端に重ねる
        .overlay(alignment: .trailing) {
            if showsTrailingChipFade {
                Image(systemName: "chevron.compact.right")
                    .font(.imasScaled( 14, weight: .semibold))
                    .foregroundStyle(DS.ink3)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showsLeadingChipFade)
        .animation(.easeInOut(duration: 0.15), value: showsTrailingChipFade)
    }

    private enum ChipScroll {
        static let coordinateSpace = "calendarChipScroll"
        /// フェード帯の幅
        static let fadeWidth: CGFloat = 18
        /// 端判定の許容誤差
        static let edgeTolerance: CGFloat = 2
    }

    /// 左端より先に chip が隠れているか (スクロール済みか)
    private var showsLeadingChipFade: Bool {
        chipContentFrame.minX < -ChipScroll.edgeTolerance
    }

    /// 右端より先に chip が隠れているか
    private var showsTrailingChipFade: Bool {
        chipContentFrame.maxX > chipViewportWidth + ChipScroll.edgeTolerance
    }

    /// 続きがある側だけ透明に落とすアルファマスク (色は不可視なので固定黒で問題ない)。
    private var chipFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(showsLeadingChipFade ? 0 : 1), .black],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: ChipScroll.fadeWidth)
            Rectangle().fill(.black)
            LinearGradient(
                colors: [.black, .black.opacity(showsTrailingChipFade ? 0 : 1)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: ChipScroll.fadeWidth)
        }
    }

    // MARK: - エントリ → 詳細遷移

    /// 週グリッドのブロック/帯タップから既存の詳細シートへ。
    /// DayEntryRow と同じ解決ロジック (show は親イベント詳細へ)。
    private func openEntryDetail(_ entry: CalendarEntry) {
        switch entry {
        case .show(let row):
            Task {
                if let event = try? await AppContainer.shared.eventReading.event(id: row.show.eventId) {
                    sheetDestination = .event(event)
                }
            }
        case .release(let dateStr, let songs):
            // 単曲 → 曲詳細 / 複数曲 → その日の日詳細シートで一覧から選ばせる
            if songs.count == 1, let song = songs.first {
                sheetDestination = .song(song)
            } else if let date = AppDatabase.parseDate(dateStr) {
                daySheet = DaySheet(date: calendar.startOfDay(for: date))
            } else if let first = songs.first {
                sheetDestination = .song(first)
            }
        case .birthday(let idol):
            sheetDestination = .idol(idol)
        case .personal(let event):
            personalDetail = event
        case .ticket(let row):
            Task {
                if let event = try? await AppContainer.shared.eventReading.event(id: row.eventId) {
                    sheetDestination = .event(event)
                }
            }
        case .ticketPeriod(let row):
            Task {
                if let event = try? await AppContainer.shared.eventReading.event(id: row.eventId) {
                    sheetDestination = .event(event)
                }
            }
        }
    }

    private func entries(on date: Date) -> [CalendarEntry] {
        let key = calendar.startOfDay(for: date)
        return (filteredEntriesByDate[key] ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 日詳細 sheet を閉じ、閉じ切るのを待ってから次の sheet 提示を実行する。
    /// SwiftUI は二重 sheet を提示できないため、dismiss アニメーション分だけ遅延させる。
    private func dismissDaySheetThen(_ present: @escaping () -> Void) {
        daySheet = nil
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            present()
        }
    }

    // MARK: - 選択日の見出し

    private var selectedDayHeader: some View {
        let isToday = calendar.isDate(selectedDate, inSameDayAs: today)
        let dateText = selectedDate.formatted(.dateTime.month().day().weekday(.short))
        let suffix = isToday ? " ・ 今日" : ""
        let countText = "\(selectedDayEntries.count)件"
        return ImasSectionHeader(title: "\(dateText)\(suffix) ・ \(countText)", tight: true)
    }

    // MARK: - 選択日のリスト（内部スクロールのみ）

    @ViewBuilder
    private var selectedDayList: some View {
        let entries = selectedDayEntries
        if entries.isEmpty {
            VStack {
                ImasEmptyState(
                    systemImage: "calendar",
                    title: "予定なし",
                    message: "この日はライブ・リリース・誕生日の記録がありません"
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(entries) { entry in
                    DayEntryRow(
                        entry: entry,
                        onSelect: { dest in sheetDestination = dest },
                        onSelectPersonal: { event in personalDetail = event }
                    )
                    .environment(database)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(DS.surface)
                    .listRowSeparatorTint(DS.sep)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DS.bg)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable {
                await syncEngine.performIncrementalSync(database: database)
                await loadEntries(for: visibleMonth)
            }
        }
    }

    // MARK: - Loading

    private func loadEntries(for month: Date) async {
        let interval = monthGridInterval(for: month)
        isLoading = true
        defer { isLoading = false }

        do {
            let entries = try await AppContainer.shared.calendarReading.calendarEntries(in: interval)
            allEntriesByDate = groupByDate(entries, in: interval)
            // 月送り/週送りでレンジが変わったらマイ予定も追従して再取得
            if showPersonal && CalendarImportService.shared.hasReadAccess {
                loadPersonalEvents()
            }
            rebuildFiltered()
        } catch {
            Logger.database.error("load_failed calendar: \(error.localizedDescription)")
        }
    }

    /// 指定日が属する月の 1 日 0:00。
    private func monthStart(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func monthGridInterval(for month: Date) -> DateInterval {
        let firstOfMonth = monthStart(of: month)
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth) - 1  // 0=Sun
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOfFirst, to: firstOfMonth) ?? firstOfMonth
        let gridEnd = calendar.date(byAdding: .day, value: 42, to: gridStart) ?? gridStart
        return DateInterval(start: gridStart, end: gridEnd)
    }

    private func groupByDate(_ entries: [CalendarEntry], in interval: DateInterval) -> [Date: [CalendarEntry]] {
        var result: [Date: [CalendarEntry]] = [:]
        for entry in entries {
            // 受付期間の帯は被覆する各日に複製して入れる (月セルのセグメント帯 / 週の連続帯の素)。
            if case .ticketPeriod(let row) = entry {
                for day in coveredDays(start: row.start, end: row.end, in: interval) {
                    result[day, default: []].append(entry)
                }
                continue
            }
            guard let date = entryDate(entry, in: interval) else { continue }
            let key = calendar.startOfDay(for: date)
            result[key, default: []].append(entry)
        }
        return result
    }

    /// [start, end] (両端含む) を interval 内にクリップした日付一覧。
    private func coveredDays(start: String, end: String, in interval: DateInterval) -> [Date] {
        guard let startDate = AppDatabase.parseDate(start),
              let endDate = AppDatabase.parseDate(end),
              endDate >= startDate else { return [] }
        // interval.end は排他境界なので前日までを対象にする。
        let lastInclusive = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        var day = calendar.startOfDay(for: max(startDate, interval.start))
        let last = calendar.startOfDay(for: min(endDate, lastInclusive))
        var days: [Date] = []
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private func entryDate(_ entry: CalendarEntry, in interval: DateInterval) -> Date? {
        switch entry {
        case .show(let row):
            return AppDatabase.parseDate(row.show.date)
        case .release(let dateStr, _):
            return AppDatabase.parseDate(dateStr)
        case .birthday(let idol):
            guard let birthday = idol.birthday, birthday.hasPrefix("--") else { return nil }
            let parts = birthday.dropFirst(2).split(separator: "-")
            guard parts.count == 2,
                  let month = Int(parts[0]),
                  let day = Int(parts[1]) else { return nil }
            var jstCalendar = Calendar(identifier: .gregorian)
            jstCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let year = jstCalendar.component(.year, from: interval.start)
            if let date = jstCalendar.date(from: DateComponents(year: year, month: month, day: day)) { return date }
            // 非閏年の 2/29 → 2/28 にフォールバック
            if month == 2 && day == 29 {
                return jstCalendar.date(from: DateComponents(year: year, month: 2, day: 28))
            }
            return nil
        case .personal(let event):
            // マイ予定は groupPersonalByDate で別管理 (ここには通常来ない)
            return event.start
        case .ticket(let row):
            return AppDatabase.parseDate(row.date)
        case .ticketPeriod(let row):
            // 帯は groupByDate で被覆日へ展開済み。アンカーは開始日。
            return AppDatabase.parseDate(row.start)
        }
    }
}

// MARK: - DaySheet

/// 日詳細シートのプレゼン用ラッパー (Date を Identifiable にする)。
private struct DaySheet: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - CalendarFilterChip

private struct CalendarFilterChip: View {
    let label: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.imasScaled( 13, weight: .semibold))
                Text(label).font(.imasScaled( 13.5, weight: .semibold))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? ColorMath.onColor(color) : DS.ink2)
            .background(isOn ? AnyShapeStyle(color) : AnyShapeStyle(DS.fill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "表示" : "非表示")
    }
}
