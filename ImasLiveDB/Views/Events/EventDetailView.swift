import os
import SwiftUI

struct EventDetailView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(\.colorScheme) private var scheme
    let event: Event
    /// DetailSheetView の NavigationStack 内に置かれた時に渡される push クロージャ。
    /// 非 nil なら遷移は自前 sheet/NavigationLink ではなく共有 path への push にする
    /// (sheet on sheet を避け、[DetailDestination] 型 path では効かない NavigationLink(value:) を回避)。
    /// nil の時 (タブ内 standalone) は従来どおり NavigationLink push / 自前 sheet。
    var navigate: ((DetailDestination) -> Void)? = nil
    @State private var vm = EventDetailViewModel()
    @State private var sheetDestination: DetailDestination?
    /// 公演単位の参加管理シート。
    @State private var showAttendanceSheet = false
    @State private var editEvent: Event?
    @State private var editShow: Show?
    /// 新規公演追加 sheet の表示フラグ。
    @State private var showShowCreate = false
    /// 未ログイン時のログイン誘導 sheet。ログイン後に `pendingIntent` を再開する。
    @State private var showLoginPrompt = false
    /// ログイン完了後に再開する編集意図。
    @State private var pendingIntent: EditIntent?
    /// 内部セグメント: 0=公演・セトリ / 1=出演 / 2=情報
    @State private var segment = 0

    /// この画面から開始しうる編集 / 作成の意図 (ログイン誘導の再開に使う)。
    private enum EditIntent: Equatable {
        case editEvent
        case editShow(Show)
        case createShow
    }

    /// 遷移の単一窓口。sheet 内 (navigate 非 nil) は共有 path に push、standalone は自前 sheet。
    private func go(_ dest: DetailDestination) {
        if let navigate {
            navigate(dest)
        } else {
            sheetDestination = dest
        }
    }

    /// 公演へ遷移。standalone はタブの NavigationStack へ push、sheet 内は共有 path へ。
    private func openShow(_ show: Show) {
        if let navigate {
            navigate(.show(show))
        } else {
            pushedShow = show
        }
    }

    /// standalone 用の navigationDestination push トリガ。
    @State private var pushedShow: Show?

    /// ヒーロー / セグメントがまとうエンティティ色。合同ライブは中立 (rainbow は別途リードバーで)。
    private var seed: String? { isJoint ? nil : vm.brand?.color }
    private var brandSeed: String? { vm.brand?.color }

    /// 合同ライブ判定 (複数ブランド名義)。
    private var isJoint: Bool { !event.jointBrandIdList.isEmpty }

    /// イベントの年（最初の公演日から導出）
    private var firstShowYear: Int? {
        guard let show = vm.shows.first, show.date.count >= 4 else { return nil }
        return Int(show.date.prefix(4))
    }

    /// 未来イベントかどうか（最初の公演日が今日以降）
    private var isFutureEvent: Bool {
        guard let firstShow = vm.shows.first else { return false }
        let today = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: .withFullDate
        )
        return firstShow.date >= today
    }

    /// 参加マーク済み公演の日付から導く「参加予定 (あとN日) / 参加済み」状態。
    /// 公演単位の `.attended` を集約し、最も早い未来公演があれば予定扱いにする。
    private var attendanceStatus: AttendanceStatus {
        let dates = vm.shows.filter { vm.attendedShowIds.contains($0.id) }.map(\.date)
        return AttendanceStatus.derive(attendedShowDates: dates)
    }

    /// ヒーローのサブ行 (日付レンジ ・ 会場)。
    private var heroSub: String {
        let dates = vm.shows.map(\.date).filter { !$0.isEmpty }
        let datePart: String?
        if let first = dates.first, let last = dates.last {
            datePart = first == last ? first : "\(first)–\(last)"
        } else {
            datePart = nil
        }
        let venues = Array(Set(vm.shows.compactMap(\.venue))).sorted()
        return [datePart, venues.first].compactMap { $0 }.joined(separator: " ・ ")
    }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brandSeed, scheme: scheme)
        VStack(spacing: 0) {
            // 常時固定: ヒーロー + UserMarkBar + 内部セグメント
            VStack(spacing: 0) {
                hero(t)

                UserMarkBar(
                    entity: .event,
                    entityId: event.id,
                    kinds: [.attended, .favorite, .note],
                    seed: seed,
                    brand: brandSeed,
                    onAttendedTap: { showAttendanceSheet = true },
                    attendedIsOn: !vm.attendedShowIds.isEmpty
                )
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp4)

                // 参加予定 (あとN日) / 参加済み のチップ。日付から導出。
                if attendanceStatus.isMarked {
                    HStack(spacing: 6) {
                        Image(systemName: attendanceStatus.systemImage)
                            .font(.imasScaled(12, weight: .semibold))
                        Text(attendanceStatus.label)
                            .font(.imasScaled(13, weight: .semibold))
                    }
                    .foregroundStyle(attendanceStatus.isPlanned ? t.onAccent : DS.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        attendanceStatus.isPlanned ? AnyShapeStyle(t.accent) : AnyShapeStyle(DS.fill),
                        in: Capsule()
                    )
                    .padding(.top, DS.sp3)
                }

                ImasSegmented(
                    labels: ["公演・セトリ", "出演", "情報"],
                    selection: $segment,
                    seed: seed,
                    brand: brandSeed
                )
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp4)
                .padding(.bottom, DS.sp3)
            }
            .background(DS.bg)
            .imasTheme(seed: seed, brand: brandSeed)

            // 内部だけスクロール
            ScrollView {
                Group {
                    switch segment {
                    case 0: showsPanel
                    case 1: castPanel
                    default: infoPanel
                    }
                }
                .padding(.top, DS.sp3)
                .padding(.bottom, DS.sp7)
            }
            .imasTheme(seed: seed, brand: brandSeed)
        }
        .background(DS.bg)
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // SNS シェア (Universal Links)。リンクを踏むとこのイベント詳細に直接着地する。
                ShareLink(
                    item: DeeplinkBuilder.shareText(
                        name: event.name,
                        url: DeeplinkBuilder.eventURL(id: event.id)
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("このイベントをシェア")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if EditPermission.showEditAffordance {
                        Button {
                            start(.editEvent)
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                    }
                    NavigationLink {
                        EditHistoryView(recordType: "Event", recordName: event.id, title: event.name)
                    } label: {
                        Label("編集履歴", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(item: $pushedShow) { show in
            SetlistView(show: show)
        }
        .sheet(item: $sheetDestination) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
        }
        .sheet(item: $editEvent) { ev in
            EventEditView(event: ev).environment(database)
        }
        .sheet(item: $editShow, onDismiss: { Task { await vm.loadData(event: event) } }) { sh in
            ShowEditView(show: sh).environment(database)
        }
        .sheet(isPresented: $showShowCreate, onDismiss: { Task { await vm.loadData(event: event) } }) {
            ShowEditView(newShowEventId: event.id, suggestedSortOrder: vm.shows.count)
                .environment(database)
        }
        .sheet(isPresented: $showLoginPrompt) {
            LoginToEditSheet(onSignedIn: { resumePendingIntent() })
        }
        .sheet(isPresented: $showAttendanceSheet) {
            EventAttendanceSheet(shows: vm.shows, seed: seed, brand: brandSeed) {
                vm.recomputeAttendedShows()
            }
        }
        .task { await vm.loadData(event: event) }
        .onAppear { RecentsService.shared.record(kind: .event, id: event.id, name: event.name) }
        .trackScreen("event_detail")
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(_ t: ImasTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ブランドバー (accent ピル)。合同ライブは虹色。
            RoundedRectangle(cornerRadius: DS.rPill, style: .continuous)
                .fill(isJoint
                      ? AnyShapeStyle(LinearGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple],
                            startPoint: .leading, endPoint: .trailing))
                      : AnyShapeStyle(t.accent))
                .frame(width: 44, height: 6)
                .padding(.bottom, DS.sp3)

            Text(event.name)
                .font(.imasTitle2.weight(.bold))
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !heroSub.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.imasScaled( 13, weight: .semibold))
                    Text(heroSub)
                    if isJoint {
                        Text("・ 合同").foregroundStyle(t.accent)
                    }
                }
                .font(.imasSubhead)
                .foregroundStyle(DS.ink2)
                .padding(.top, DS.sp2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.sp5)
        .padding(.top, DS.sp4)
        .padding(.bottom, DS.sp4)
        .background(t.heroSurface)
    }

    // MARK: - Panel 0: 公演・セトリ

    @ViewBuilder
    private var showsPanel: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack {
                ImasSectionHeader(title: "公演 ・ \(vm.shows.count) 公演 → セトリへ", tight: true)
                Spacer(minLength: 8)
                if EditPermission.showEditAffordance {
                    Button {
                        start(.createShow)
                    } label: {
                        Label("追加", systemImage: "plus.circle")
                            .font(.imasScaled( 13, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(seedAccent)
                    }
                }
            }
            .padding(.horizontal, DS.sp5)

            if vm.shows.isEmpty {
                ImasListContainer {
                    ImasEmptyState(
                        systemImage: "music.mic",
                        title: "公演がまだありません",
                        message: EditPermission.showEditAffordance ? "「追加」から公演を登録できます" : nil,
                        actionTitle: EditPermission.showEditAffordance ? "公演を追加" : nil,
                        action: EditPermission.showEditAffordance ? { start(.createShow) } : nil,
                        seed: seed, brand: brandSeed
                    )
                }
                .padding(.horizontal, DS.sp5)
            } else {
                ImasListContainer {
                    ForEach(Array(vm.shows.enumerated()), id: \.element.id) { idx, show in
                        if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                        showRow(show)
                    }
                }
                .padding(.horizontal, DS.sp5)
            }
        }
    }

    @ViewBuilder
    private func showRow(_ show: Show) -> some View {
        Button { openShow(show) } label: {
            HStack(spacing: DS.sp3) {
                ImasLeadBar(seed: seed, brand: brandSeed, rainbow: isJoint)
                    .frame(height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(show.name)
                        .font(.imasSubhead.weight(.semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    Text([show.venue, show.date].compactMap { $0 }.joined(separator: " ・ "))
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.imasScaled( 14, weight: .semibold))
                    .foregroundStyle(DS.ink3)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, DS.sp3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if EditPermission.showEditAffordance {
                Button {
                    start(.editShow(show))
                } label: {
                    Label("公演を編集", systemImage: "pencil")
                }
            }
        }
    }

    // MARK: - Panel 1: 出演

    @ViewBuilder
    private var castPanel: some View {
        if let attendance = vm.attendance, !attendance.brandIdols.isEmpty {
            AttendancePanel(
                attendance: attendance,
                unitIndex: vm.unitIndex,
                performedUnitIds: vm.performedUnitIds,
                seed: seed,
                brandSeed: brandSeed,
                navigate: { go($0) }
            )
            .padding(.horizontal, DS.sp5)
        } else {
            ImasListContainer {
                ImasEmptyState(
                    systemImage: "person.2",
                    title: "出演情報がありません",
                    message: "セトリ・出演者が登録されると表示されます",
                    seed: seed, brand: brandSeed
                )
            }
            .padding(.horizontal, DS.sp5)
        }
    }

    // MARK: - Panel 2: 情報

    @ViewBuilder
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: DS.sp5) {
            if let stats = vm.stats {
                EventStatsTiles(stats: stats, seed: seed, brand: brandSeed)
                    .padding(.horizontal, DS.sp5)
            }

            ticketInfoSection

            // ブランド / 年度メタ
            VStack(alignment: .leading, spacing: DS.sp2) {
                ImasListContainer {
                    if let brand = vm.brand {
                        Button {
                            go(.filteredEvents(.brand(id: brand.id, label: brand.shortName)))
                        } label: {
                            ImasLabeledRow(
                                key: "ブランド", value: brand.shortName,
                                showChevron: true, tappable: true,
                                seed: seed, brand: brandSeed
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if let year = firstShowYear {
                        if vm.brand != nil { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                        Button {
                            go(.filteredEvents(.year(year)))
                        } label: {
                            ImasLabeledRow(
                                key: "年度", value: "\(year)年",
                                showChevron: true, tappable: true,
                                seed: seed, brand: brandSeed
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DS.sp5)
        }
    }

    /// チケット情報の行種別 (divider を決定論的に挟むため列挙して扱う)。
    private enum TicketRow: Identifiable {
        case labeled(key: String, value: String)
        case link(URL)
        case placeholder
        var id: String {
            switch self {
            case .labeled(let k, _): return "labeled-\(k)"
            case .link: return "link"
            case .placeholder: return "placeholder"
            }
        }
    }

    private var ticketRows: [TicketRow] {
        var rows: [TicketRow] = []
        if let deadline = event.ticketDeadline, !deadline.isEmpty {
            rows.append(.labeled(key: "申込期限", value: deadline))
        }
        if let lottery = event.ticketLotteryDate, !lottery.isEmpty {
            rows.append(.labeled(key: "当落発表", value: lottery))
        }
        if let url = URL.safeHTTP(string: event.ticketUrl) {
            rows.append(.link(url))
        }
        if rows.isEmpty { rows.append(.placeholder) }
        return rows
    }

    /// チケット情報セクション。1 つでも値があれば表示、何もなければ「投稿で追加できる」サインだけ。
    @ViewBuilder
    private var ticketInfoSection: some View {
        let hasAny = (event.ticketDeadline?.isEmpty == false)
            || (event.ticketLotteryDate?.isEmpty == false)
            || (event.ticketUrl?.isEmpty == false)
        if hasAny || isFutureEvent {
            VStack(alignment: .leading, spacing: DS.sp2) {
                HStack(alignment: .firstTextBaseline) {
                    ImasSectionHeader(title: "チケット情報", tight: true)
                    Spacer(minLength: 12)
                    if EditPermission.showEditAffordance {
                        Button {
                            start(.editEvent)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: hasAny ? "pencil" : "plus").font(.imasScaled( 13, weight: .semibold))
                                Text(hasAny ? "編集" : "登録").font(.imasScaled( 14, weight: .semibold))
                            }
                            .foregroundStyle(seedAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.sp5)
                ImasListContainer {
                    ForEach(Array(ticketRows.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { Divider().overlay(DS.sep).padding(.leading, DS.sp5) }
                        ticketRowView(row)
                    }
                }
                .padding(.horizontal, DS.sp5)
            }
        }
    }

    @ViewBuilder
    private func ticketRowView(_ row: TicketRow) -> some View {
        switch row {
        case let .labeled(key, value):
            ImasLabeledRow(key: key, value: value, seed: seed, brand: brandSeed)
        case let .link(url):
            Link(destination: url) {
                HStack(spacing: DS.sp2) {
                    Image(systemName: "ticket").font(.imasScaled( 15, weight: .semibold))
                    Text("公式チケットページを開く").font(.imasSubhead.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(seedAccent)
                .padding(.horizontal, DS.sp4).padding(.vertical, 11)
                .background(DS.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .placeholder:
            if EditPermission.showEditAffordance {
                Button {
                    start(.editEvent)
                } label: {
                    HStack(spacing: DS.sp2) {
                        Image(systemName: "plus").font(.imasScaled( 15, weight: .semibold))
                        Text("チケット情報を登録").font(.imasSubhead.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(seedAccent)
                    .padding(.horizontal, DS.sp4).padding(.vertical, 11)
                    .background(DS.surface)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("チケット情報は未登録です")
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.sp4).padding(.vertical, 11)
                    .background(DS.surface)
            }
        }
    }

    private var seedAccent: Color {
        ImasTheme.derive(seed: seed, brand: brandSeed, scheme: scheme).accent
    }

    // MARK: - Intent / Data

    /// 編集 / 作成の意図を開始する。ログイン済みなら即 sheet、未ログインならログイン誘導 → ログイン後再開。
    private func start(_ intent: EditIntent) {
        guard EditPermission.canEdit else {
            pendingIntent = intent
            showLoginPrompt = true
            return
        }
        present(intent)
    }

    /// ログイン完了後に保留していた意図を再開する。
    private func resumePendingIntent() {
        guard let intent = pendingIntent, EditPermission.canEdit else {
            pendingIntent = nil
            return
        }
        pendingIntent = nil
        present(intent)
    }

    private func present(_ intent: EditIntent) {
        switch intent {
        case .editEvent: editEvent = event
        case .editShow(let show): editShow = show
        case .createShow: showShowCreate = true
        }
    }

}

// MARK: - EventStats タイル (情報パネル)

private struct EventStatsTiles: View {
    let stats: EventStats
    var seed: String?
    var brand: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DS.sp3) {
            ImasStatTile(systemImage: "music.mic", value: "\(stats.showCount)", label: "公演", seed: seed, brand: brand)
            ImasStatTile(systemImage: "music.note.list", value: "\(stats.totalSongs)", label: "曲（延べ）", seed: seed, brand: brand)
            ImasStatTile(systemImage: "music.note", value: "\(stats.uniqueSongs)", label: "ユニーク曲", seed: seed, brand: brand)
            ImasStatTile(systemImage: "person.2", value: "\(stats.castCount)", label: "キャスト", seed: seed, brand: brand)
        }
    }
}

// MARK: - 出演パネル (披露ユニット + DAY別グリッド)

private struct AttendancePanel: View {
    let attendance: EventAttendance
    let unitIndex: UnitIndex?
    /// この event のセトリで歌唱された unit_id 集合。
    let performedUnitIds: Set<String>
    var seed: String?
    var brandSeed: String?
    let navigate: (DetailDestination) -> Void
    @Environment(\.colorScheme) private var scheme

    /// 出演者集合 (ブランド全体 - 欠席者)
    private var presentIds: Set<String> {
        Set(attendance.presentIdols.map(\.id))
    }

    /// performer 集合を unit で被覆した結果 (実際に歌唱されたユニットのみ)。
    private var coveredUnits: [Unit] {
        guard let unitIndex, !performedUnitIds.isEmpty else { return [] }
        return unitIndex.coveringUnits(
            for: presentIds,
            requireSongs: true,
            restrictTo: performedUnitIds
        ).units
    }

    private var groups: [EventAttendance.Group] {
        attendance.grouped()
    }

    /// 主演アイドル (出演者集合に含まれるもののみ)。
    private var leadIdols: [Idol] {
        attendance.leadIdols.filter { presentIds.contains($0.id) }
    }

    /// ゲストアイドル (出演者集合に含まれるもののみ)。
    private var guestIdols: [Idol] {
        attendance.guestIdols.filter { presentIds.contains($0.id) }
    }

    /// 指定 show の役割アイドルを brandIdols 順で返す (allowed に含まれるものだけ)。
    private func roleIdols(_ byShow: [String: Set<String>], show: Show, allowed: [Idol]) -> [Idol] {
        let allow = Set(allowed.map(\.id))
        let ids = (byShow[show.id] ?? []).filter { allow.contains($0) }
        return attendance.brandIdols.filter { ids.contains($0.id) }
    }

    /// "2026-09-19" → "9/19(土)"。パース不能なら nil。
    private func shortDate(_ ymd: String) -> String? {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        if let date = cal.date(from: DateComponents(year: y, month: m, day: d)) {
            let wd = ["日", "月", "火", "水", "木", "金", "土"][cal.component(.weekday, from: date) - 1]
            return "\(m)/\(d)(\(wd))"
        }
        return "\(m)/\(d)"
    }

    private var panelAccent: Color {
        ImasTheme.derive(seed: seed, brand: brandSeed, scheme: scheme).accent
    }

    private let avatarColumns = [GridItem(.adaptive(minimum: 56, maximum: 76), spacing: DS.sp3)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp5) {
            // 0) 主演 (出演パネルの最上部で最優先に目立たせる)
            if !leadIdols.isEmpty {
                roleSection(
                    byShow: attendance.leadByShow,
                    allIdols: leadIdols,
                    titleBase: "主演",
                    chipText: "主演",
                    chipKind: .lead,
                    ringAccent: true
                )
            }

            // 0') ゲスト (主演の直下、 控えめに区別)
            if !guestIdols.isEmpty {
                roleSection(
                    byShow: attendance.guestByShow,
                    allIdols: guestIdols,
                    titleBase: "ゲスト",
                    chipText: "ゲスト",
                    chipKind: .guest,
                    ringAccent: false
                )
            }

            if attendance.isFullAttendance {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(DS.warning)
                    Text("全員集合！").font(.imasHeadline.weight(.bold)).foregroundStyle(DS.ink)
                    Spacer()
                    Text("\(attendance.brandIdols.count)/\(attendance.brandIdols.count) 名")
                        .font(.imasFootnote).foregroundStyle(DS.ink2)
                }
                .padding(.horizontal, DS.sp4).padding(.vertical, DS.sp3)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
            }

            // 1) 披露ユニット (披露曲を unit 完全一致で歌った unit のみ)
            if !coveredUnits.isEmpty {
                VStack(alignment: .leading, spacing: DS.sp3) {
                    ImasSectionHeader(
                        title: "披露ユニット ・ 全 \(attendance.presentIdols.count)/\(attendance.brandIdols.count) 名",
                        tight: true
                    )
                    VStack(spacing: DS.sp3) {
                        ForEach(coveredUnits) { unit in
                            unitBlock(unit: unit)
                        }
                    }
                }
            }

            // 2) DAY 別の個別アイドル一覧
            ForEach(groups) { group in
                groupView(group: group)
            }
        }
    }

    /// アバターを囲む accent リング (主演のみ表示)。
    @ViewBuilder
    private func roleAvatarRing(show: Bool) -> some View {
        if show {
            Circle().strokeBorder(
                ImasTheme.derive(seed: seed, brand: brandSeed, scheme: scheme).accent,
                lineWidth: 2
            )
        }
    }

    /// 役割セクション (主演 / ゲスト)。複数日公演では「どの DAY の主演か」が一目で分かるよう、
    /// DAY ごとに見出し付きのブロックへ分けて表示する。単一日では従来通りのフラット表示。
    /// 主演は accent リングで強く、 ゲストはリング無し + outline バッジで控えめに区別する。
    @ViewBuilder
    private func roleSection(
        byShow: [String: Set<String>],
        allIdols: [Idol],
        titleBase: String,
        chipText: String,
        chipKind: ImasTagChip.Kind,
        ringAccent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(
                title: allIdols.count > 1 ? "\(titleBase) ・ \(allIdols.count)名" : titleBase,
                tight: true
            )
            if attendance.shows.count > 1 {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    ForEach(Array(attendance.shows.enumerated()), id: \.element.id) { idx, show in
                        let dayIdols = roleIdols(byShow, show: show, allowed: allIdols)
                        if !dayIdols.isEmpty {
                            VStack(alignment: .leading, spacing: DS.sp2) {
                                dayHeader(index: idx, show: show)
                                ImasListContainer {
                                    roleGrid(idols: dayIdols, chipText: chipText,
                                             chipKind: chipKind, ringAccent: ringAccent)
                                        .padding(DS.sp4)
                                }
                            }
                        }
                    }
                }
            } else {
                ImasListContainer {
                    roleGrid(idols: allIdols, chipText: chipText,
                             chipKind: chipKind, ringAccent: ringAccent)
                        .padding(DS.sp4)
                }
            }
        }
    }

    /// DAY 見出し: 「DAY1」バッジ + 日付(M/D(曜)) + 公演名。
    @ViewBuilder
    private func dayHeader(index: Int, show: Show) -> some View {
        HStack(spacing: 6) {
            Text("DAY\(index + 1)")
                .font(.imasCaption.weight(.bold))
                .foregroundStyle(DS.onSys)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(panelAccent, in: Capsule())
            if let d = shortDate(show.date) {
                Text(d).font(.imasCaption.weight(.medium)).foregroundStyle(DS.ink2)
            }
            if !show.name.isEmpty, show.name != "DAY\(index + 1)" {
                Text(show.name).font(.imasCaption).foregroundStyle(DS.ink3).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// 役割アイドルのアバターグリッド (1 ブロック分)。
    @ViewBuilder
    private func roleGrid(idols: [Idol], chipText: String,
                          chipKind: ImasTagChip.Kind, ringAccent: Bool) -> some View {
        LazyVGrid(columns: avatarColumns, spacing: DS.sp4) {
            ForEach(idols) { idol in
                Button {
                    navigate(.idol(idol))
                } label: {
                    VStack(spacing: 4) {
                        IdolAvatarView(idol: idol, size: 56)
                            .overlay { roleAvatarRing(show: ringAccent) }
                        ImasTagChip(text: chipText, kind: chipKind, seed: seed, brand: brandSeed)
                        Text(idol.shortName)
                            .font(.imasCaption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(DS.ink)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func unitBlock(unit: Unit) -> some View {
        let memberIds = unitIndex?.memberIds[unit.id] ?? []
        let allMembers = attendance.brandIdols.filter { memberIds.contains($0.id) }
        let presentCount = allMembers.filter { presentIds.contains($0.id) }.count

        ImasListContainer {
            VStack(alignment: .leading, spacing: DS.sp3) {
                HStack(spacing: 6) {
                    ImasTagChip(text: unit.name, kind: .unit, seed: seed, brand: brandSeed)
                    Text("\(presentCount)/\(allMembers.count)")
                        .font(.imasCaption).foregroundStyle(DS.ink2)
                    Spacer()
                }
                avatarGrid(idols: allMembers, isAbsent: { !presentIds.contains($0.id) })
            }
            .padding(DS.sp4)
        }
    }

    @ViewBuilder
    private func groupView(group: EventAttendance.Group) -> some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(
                title: "\(group.label) ・ \(group.idols.count)名",
                tight: true
            )
            ImasListContainer {
                avatarGrid(idols: group.idols, isAbsent: { _ in group.label == "欠席" })
                    .padding(DS.sp4)
            }
        }
    }

    @ViewBuilder
    private func avatarGrid(idols: [Idol], isAbsent: @escaping (Idol) -> Bool) -> some View {
        LazyVGrid(columns: avatarColumns, spacing: DS.sp4) {
            ForEach(idols) { idol in
                let absent = isAbsent(idol)
                Button {
                    navigate(.idol(idol))
                } label: {
                    VStack(spacing: 4) {
                        IdolAvatarView(idol: idol, size: 48)
                            .grayscale(absent ? 0.5 : 0)
                            .opacity(absent ? 0.45 : 1)
                        Text(idol.shortName)
                            .font(.imasCaption)
                            .lineLimit(1)
                            .foregroundStyle(absent ? DS.ink3 : DS.ink)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
