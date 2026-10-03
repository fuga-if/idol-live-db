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
    /// チケット受付の編集対象 (nil = 非表示)。
    @State private var editTicketSale: TicketSale?
    /// 新規チケット受付追加 sheet の表示フラグ。
    @State private var showTicketSaleCreate = false
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
        case editTicketSale(TicketSale)
        case createTicketSale
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

    /// 未来イベントかどうか (最初の公演が今日以降)。判定はコアのヒーロー。
    private var isFutureEvent: Bool { vm.hero?.isUpcoming ?? false }

    /// 「参加予定 (あとN日) / 参加済み」の札。決め方と文言はコアのヒーロー。
    private var attendanceStatus: AttendanceStatus {
        vm.hero.map { AttendanceStatus($0.attendance) } ?? .none
    }

    /// ヒーローのサブ行 (開催期間 ・ 会場 ・ 合同)。組み方はコア + 合同の注記のみここで足す。
    private var heroSub: String {
        guard let sub = vm.hero?.subLine, !sub.isEmpty else { return "" }
        return isJoint ? "\(sub) ・ 合同" : sub
    }

    /// 頭の印字 (ブランド名)。合同ライブは下の行の「合同」で示すので出さない。
    /// 「LIVE」や色の点は、どのライブでも同じで何も伝えないので置かない。
    private var mastheadItems: [String] {
        isJoint ? [] : [vm.brand?.shortName ?? ""].filter { !$0.isEmpty }
    }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brandSeed, scheme: scheme)
        VStack(spacing: 0) {
            // 常時固定: 頭 + UserMarkBar + 内部セグメント
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if !mastheadItems.isEmpty {
                        ImasMasthead(items: mastheadItems)
                    }
                    Text(event.name)
                        .imasText(.heroTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.gapTight)
                        .imasCopyable(event.name, label: "ライブ名をコピー", key: "event_name")
                    if !heroSub.isEmpty {
                        ImasNote(heroSub, systemImage: "calendar")
                            .padding(.top, DS.Space.gapTight)
                    }
                }
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, DS.Space.gap)
                .padding(.bottom, DS.Space.gap)

                UserMarkBar(
                    entity: .event,
                    entityId: event.id,
                    kinds: [.attended, .favorite, .note],
                    seed: seed,
                    brand: brandSeed,
                    onAttendedTap: { showAttendanceSheet = true },
                    attendedIsOn: !vm.attendedShowIds.isEmpty
                )
                .padding(.horizontal, DS.Space.screen)

                // 参加予定 (あとN日) / 参加済み の札。日付から導出。
                if attendanceStatus.isMarked {
                    ImasBadge(
                        text: attendanceStatus.label,
                        kind: attendanceStatus.isPlanned ? .planned : .positive,
                        systemImage: attendanceStatus.systemImage
                    )
                    .padding(.horizontal, DS.Space.screen)
                    .padding(.top, DS.Space.gapTight)
                }

                ImasTabs(
                    labels: ["公演・セトリ", "出演", "情報"],
                    selection: $segment,
                    seed: seed,
                    brand: brandSeed
                )
                .padding(.horizontal, DS.Space.screen)
                .padding(.top, DS.Space.gap)
                .padding(.bottom, DS.Space.gapTight)
            }
            .background(DS.bg)
            .imasTheme(seed: seed, brand: brandSeed)

            // 内部だけスクロール。公演一覧 (segment 0) だけ List (スワイプ参加登録に必要)、
            // 他パネルは従来通り ScrollView。
            Group {
                if segment == 0 {
                    showsList
                } else {
                    ScrollView {
                        Group {
                            switch segment {
                            case 1: castPanel
                            default: infoPanel
                            }
                        }
                        .padding(.top, DS.Space.gap)
                        .padding(.bottom, DS.Space.section)
                    }
                }
            }
            .imasTheme(seed: seed, brand: brandSeed)
        }
        .background(DS.bg)
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ヒーローはスクロールせず常に全文を出すので、バーの 1 行タイトルは重複になる。
            // 合同ライブ名は「THE IDOLM@STER Sid…」と先頭ブランドが省略で消えるだけなので空にする。
            // navigationTitle 自体は戻るボタンの長押し履歴と VoiceOver のために残す。
            ToolbarItem(placement: .principal) { Text("").accessibilityHidden(true) }
            ToolbarItem(placement: .topBarTrailing) {
                // SNS シェア (Universal Links)。リンクを踏むとこのイベント詳細に直接着地する。
                ShareLink(item: shareEventText(eventId: event.id, eventName: event.name)) {
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
        .sheet(item: $editTicketSale, onDismiss: { Task { await vm.reloadTicketSales(eventId: event.id) } }) { sale in
            TicketSaleEditView(ticketSale: sale, eventShows: vm.shows)
        }
        .sheet(isPresented: $showTicketSaleCreate, onDismiss: { Task { await vm.reloadTicketSales(eventId: event.id) } }) {
            TicketSaleEditView(newSaleEventId: event.id, eventShows: vm.shows, suggestedSortOrder: vm.ticketSales.count)
        }
        .sheet(isPresented: $showLoginPrompt) {
            LoginToEditSheet(onSignedIn: { resumePendingIntent() })
        }
        .sheet(isPresented: $showAttendanceSheet) {
            EventAttendanceSheet(shows: vm.shows, event: event, seed: seed, brand: brandSeed) {
                vm.recomputeAttendedShows()
                Task { await vm.reloadHero(eventId: event.id) }
            }
        }
        .imasLoadAfterTransition { await vm.loadData(event: event) }
        .onAppear { RecentsService.shared.record(kind: .event, id: event.id, name: event.name) }
        .trackScreen("event_detail")
    }

    // MARK: - Panel 0: 公演・セトリ

    /// ⚠️ ここは **List でなければならない**。行をスワイプしての参加登録 (`attendanceSwipe`)
    /// は List の行にしか効かず、ScrollView + LazyVStack に付けても無言で消える
    /// (習熟度画面のスワイプが同じ理由で一度死んでいる)。見出し・空状態も
    /// 同じ理由で List の行として差す (`plainRow`)。
    @ViewBuilder
    private var showsList: some View {
        List {
            ImasSectionHeader("公演", count: "\(vm.shows.count) 公演 → セトリへ", style: .small)
                .plainRow(background: DS.bg)

            if vm.shows.isEmpty {
                ImasEmptyState(
                    systemImage: "music.mic",
                    title: "公演がまだありません",
                    message: EditPermission.showEditAffordance ? "「追加」から公演を登録できます" : nil,
                    actionTitle: EditPermission.showEditAffordance ? "公演を追加" : nil,
                    action: EditPermission.showEditAffordance ? { start(.createShow) } : nil,
                    seed: seed, brand: brandSeed
                )
                .plainRow(background: DS.bg)
            } else {
                ForEach(vm.shows) { show in
                    showRow(show)
                        .listRowInsets(EdgeInsets(top: 4, leading: DS.Space.screen, bottom: 4, trailing: DS.Space.screen))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .attendanceSwipe(show: show, event: event) {
                            vm.recomputeAttendedShows()
                            Task { await vm.reloadHero(eventId: event.id) }
                        }
                }
            }

            if EditPermission.showEditAffordance {
                ImasActionRow(title: "公演を追加", systemImage: "plus.circle") {
                    start(.createShow)
                }
                .plainRow(background: DS.bg)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.bg)
        .environment(\.defaultMinListRowHeight, 0)
    }

    @ViewBuilder
    private func showRow(_ show: Show) -> some View {
        Button { openShow(show) } label: {
            // 会場 ・ 日付 (年まで分かる形)。参加済みの特別な印は付けない (事実の札だけで示す)。
            ImasShowRow(
                date: show.date,
                title: show.name,
                subtitle: [show.venue, show.date].compactMap { $0 }.joined(separator: " ・ "),
                // 色の点は付けない (このライブの公演はみな同じブランドで、点は何も伝えない)。
                showsChevron: true
            )
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
                seed: seed,
                brandSeed: brandSeed,
                navigate: { go($0) }
            )
            .padding(.horizontal, DS.Space.screen)
        } else {
            ImasCardList {
                ImasEmptyState(
                    systemImage: "person.2",
                    title: "出演情報がありません",
                    message: "セトリ・出演者が登録されると表示されます",
                    seed: seed, brand: brandSeed
                )
            }
            .padding(.horizontal, DS.Space.screen)
        }
    }

    // MARK: - Panel 2: 情報

    @ViewBuilder
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: DS.Space.screen) {
            if let stats = vm.stats {
                ImasStatGrid(columns: 2) {
                    ImasStatTile(systemImage: "music.mic", value: "\(stats.showCount)", label: "公演", seed: seed, brand: brandSeed)
                    ImasStatTile(systemImage: "music.note.list", value: "\(stats.totalSongs)", label: "曲（延べ）", seed: seed, brand: brandSeed)
                    ImasStatTile(systemImage: "music.note", value: "\(stats.uniqueSongs)", label: "ユニーク曲", seed: seed, brand: brandSeed)
                    ImasStatTile(systemImage: "person.2", value: "\(stats.castCount)", label: "キャスト", seed: seed, brand: brandSeed)
                }
                .padding(.horizontal, DS.Space.screen)
            }

            ticketInfoSection

            // 衣装。行は衣装単位で、押すとイベントをまたいだ着用公演へ。
            if let costumes = vm.costumes {
                EventCostumesSection(costumes: costumes, seed: seed, brand: brandSeed) {
                    go(.costume($0))
                }
            }

            // 映像円盤 (BD/DVD) 所有チェック。event_releases があるイベントだけ表示。
            EventReleasesSection(eventId: event.id, seed: seed, brand: brandSeed)

            // ブランド / 年度メタ
            ImasCardList {
                if let brand = vm.brand {
                    Button {
                        go(.filteredEvents(.brand(id: brand.id, label: brand.shortName)))
                    } label: {
                        ImasValueRow(key: "ブランド", value: brand.shortName, isLink: true)
                    }
                    .buttonStyle(.plain)
                }
                if let year = firstShowYear {
                    Button {
                        go(.filteredEvents(.year(year)))
                    } label: {
                        ImasValueRow(key: "年度", value: "\(year)年", isLink: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.screen)
        }
    }

    /// チケット情報セクション: 受付 (`ticket_sales`) の一覧 + イベント全体の案内 URL。
    /// 受付の判定・並び・表示文字列はすべて共有コアの `TicketSale` (射影) が決め切って返す。
    @ViewBuilder
    private var ticketInfoSection: some View {
        let hasGuideUrl = URL.safeHTTP(string: event.ticketUrl) != nil
        if !vm.ticketSales.isEmpty || hasGuideUrl || isFutureEvent {
            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                ImasSectionHeader("チケット受付", style: .small)
                    .padding(.horizontal, DS.Space.screen)

                if vm.ticketSales.isEmpty {
                    ImasCardList {
                        ImasNote("チケット受付は未登録です")
                            .padding(.horizontal, DS.Space.rowH)
                            .padding(.vertical, DS.Space.rowVCompact)
                    }
                    .padding(.horizontal, DS.Space.screen)
                } else {
                    ImasCardList {
                        ForEach(Array(vm.ticketSales.enumerated()), id: \.element.id) { index, sale in
                            if index > 0 { ImasRowDivider(inset: DS.Space.rowH) }
                            ticketSaleRow(sale)
                        }
                    }
                    .padding(.horizontal, DS.Space.screen)

                    if EditPermission.showEditAffordance {
                        ImasActionRow(title: "受付を追加", systemImage: "plus.circle") {
                            start(.createTicketSale)
                        }
                        .padding(.horizontal, DS.Space.screen)
                    }
                }
                if vm.ticketSales.isEmpty, EditPermission.showEditAffordance {
                    ImasActionRow(title: "受付を追加", systemImage: "plus.circle") {
                        start(.createTicketSale)
                    }
                    .padding(.horizontal, DS.Space.screen)
                }

                if let url = URL.safeHTTP(string: event.ticketUrl) {
                    Link(destination: url) {
                        ImasNavRow(title: "公式チケットページを開く", systemImage: "ticket", iconTone: .themed)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.screen)
                }
            }
        }
    }

    /// 受付 1 件ぶんの行: 段階の札 + 受付名・種別 + 期間/当落 + 対象公演 + 申込リンク。
    ///
    /// M8: 以前は行全体が `Button` で、その `label` の中に申込リンクの `Link` が入れ子に
    /// なっていた。SwiftUI では外側の `Button` がタップを取ってしまい、申込リンクが実質
    /// 押せなくなる。編集への導線は行末の別ボタン (chevron) に分け、`Link` は
    /// どの `Button` の外にも置く。
    @ViewBuilder
    private func ticketSaleRow(_ sale: TicketSale) -> some View {
        let application = UserMarkService.shared.ticketApplication(saleId: sale.id)
        VStack(alignment: .leading, spacing: DS.Space.gapTight) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.gapTight) {
                ImasBadge(text: sale.stageLabel, kind: stageBadgeKind(sale.stage))
                if let application {
                    ImasBadge(text: ticketApplicationLabel(kind: sale.kind, application: application),
                              kind: ticketApplicationBadgeKind(application))
                }
                Text(sale.kindLabel).imasText(.meta)
                Spacer()
                if EditPermission.showEditAffordance {
                    Button {
                        start(.editTicketSale(sale))
                    } label: {
                        ImasRowChevron()
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(sale.name).imasText(.rowTitle)
            if let period = sale.periodLabel {
                Text(period).imasText(.note)
            }
            if let result = sale.resultLabel {
                Text("当落発表 \(result)").imasText(.note)
            }
            if !sale.showLabels.isEmpty {
                Text("対象: \(sale.showLabels.joined(separator: "・"))").imasText(.meta)
            }
            if let url = URL.safeHTTP(string: sale.url) {
                Link(destination: url) {
                    HStack(spacing: DS.Space.gapTight) {
                        Image(systemName: "arrow.up.right.square").font(ImasTextRole.note.font)
                        Text("申込ページを開く")
                    }
                    .imasText(.note, color: seedAccent)
                }
            }
            ticketApplicationMenu(sale, current: application)
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.gap)
        .contentShape(Rectangle())
    }

    /// 自分の申込の記録を付ける口。選べる段階 (当選・落選は当落発表の日から) はコアが決める。
    /// 端末にだけ残る本人の記録なので、ログインは要らない。
    private func ticketApplicationMenu(_ sale: TicketSale, current: TicketApplication?) -> some View {
        let choices = ticketApplicationChoices(
            kind: sale.kind, stage: sale.stage, resultAt: sale.resultAt, nowEpochSeconds: JSTDay.nowEpochSeconds()
        )
        return Menu {
            ForEach(choices, id: \.self) { choice in
                Button {
                    setTicketApplication(sale, choice)
                } label: {
                    if choice == current {
                        Label(ticketApplicationLabel(kind: sale.kind, application: choice), systemImage: "checkmark")
                    } else {
                        Text(ticketApplicationLabel(kind: sale.kind, application: choice))
                    }
                }
            }
            if current != nil {
                Button("記録を外す", role: .destructive) { setTicketApplication(sale, nil) }
            }
        } label: {
            HStack(spacing: DS.Space.gapTight) {
                Image(systemName: current == nil ? "ticket" : "ticket.fill").font(ImasTextRole.note.font)
                Text(current == nil ? "申込を記録" : "記録を変える")
            }
            .imasText(.note, color: seedAccent)
        }
        .sensoryFeedback(.selection, trigger: current)
    }

    private func setTicketApplication(_ sale: TicketSale, _ application: TicketApplication?) {
        do {
            try UserMarkService.shared.setTicketApplication(saleId: sale.id, application)
        } catch {
            Logger.database.error("save_failed ticket_application: \(error.localizedDescription)")
        }
    }

    /// 申込の記録の札。当選は自分の記録の塗り (§10.1 `.positive` が当選を例示)、落選は薄字、
    /// 申込済みは結果を待つ灰の線。
    private func ticketApplicationBadgeKind(_ application: TicketApplication) -> ImasBadge.Kind {
        switch application {
        case .applied: return .guest
        case .won: return .positive
        case .lost: return .negative
        }
    }

    /// 段階の札の種類。受付中/結果待ちは「墨の線」(§10.1 `.attention` が受付中を例示)、
    /// 受付前/終了は「灰」(`.neutral` が終了・未定を例示)。色の数を増やさない。
    private func stageBadgeKind(_ stage: TicketSaleStage) -> ImasBadge.Kind {
        switch stage {
        case .open, .awaitingResult: return .attention
        case .upcoming, .ended: return .neutral
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
        case .editTicketSale(let sale): editTicketSale = sale
        case .createTicketSale: showTicketSaleCreate = true
        }
    }

}

// MARK: - 出演パネル (披露ユニット + DAY別グリッド)

private struct AttendancePanel: View {
    let attendance: EventAttendance
    let unitIndex: UnitIndex?
    var seed: String?
    var brandSeed: String?
    let navigate: (DetailDestination) -> Void
    @Environment(\.colorScheme) private var scheme

    /// 出演者集合 (ブランド全体 - 欠席者)
    private var presentIds: Set<String> {
        Set(attendance.presentIdols.map(\.id))
    }

    /// 出演者を覆う、歌唱されたユニット (選び方はコア)。
    private var coveredUnits: [Unit] {
        guard let units = unitIndex?.units else { return [] }
        let byId = Dictionary(units.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return attendance.coveringUnitIds.compactMap { byId[$0] }
    }

    private var groups: [EventAttendance.Group] { attendance.groups }

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

    private let avatarColumns = [GridItem(.adaptive(minimum: 56, maximum: 76), spacing: DS.Space.card)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.screen) {
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
                ImasCard {
                    HStack(spacing: DS.Space.gapTight) {
                        Image(systemName: "sparkles").foregroundStyle(DS.warning)
                        Text("全員集合！").imasText(.cardTitle)
                        Spacer(minLength: DS.Space.gap)
                        Text("\(attendance.brandIdols.count)/\(attendance.brandIdols.count) 名").imasText(.note)
                    }
                }
            }

            // 1) 披露ユニット (披露曲を unit 完全一致で歌った unit のみ)
            if !coveredUnits.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.gap) {
                    ImasSectionHeader("披露ユニット", count: "全 \(attendance.presentIdols.count)/\(attendance.brandIdols.count) 名", style: .small)
                    VStack(spacing: DS.Space.gap) {
                        ForEach(coveredUnits) { unit in
                            unitBlock(unit: unit)
                        }
                    }
                }
            }

            // 2) 日付ごとの出演者 (複数日は DAY ごと、単日は「出演」) と欠席
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
    /// 主演は accent リングで強く、 ゲストはリング無し + outline の札で控えめに区別する。
    @ViewBuilder
    private func roleSection(
        byShow: [String: Set<String>],
        allIdols: [Idol],
        titleBase: String,
        chipText: String,
        chipKind: ImasBadge.Kind,
        ringAccent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            ImasSectionHeader(titleBase, count: allIdols.count > 1 ? "\(allIdols.count)名" : nil, style: .small)
            if attendance.shows.count > 1 {
                VStack(alignment: .leading, spacing: DS.Space.card) {
                    ForEach(Array(attendance.shows.enumerated()), id: \.element.id) { idx, show in
                        let dayIdols = roleIdols(byShow, show: show, allowed: allIdols)
                        if !dayIdols.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                                dayHeader(index: idx, show: show)
                                ImasCard {
                                    roleGrid(idols: dayIdols, chipText: chipText,
                                             chipKind: chipKind, ringAccent: ringAccent)
                                }
                            }
                        }
                    }
                }
            } else {
                ImasCard {
                    roleGrid(idols: allIdols, chipText: chipText,
                             chipKind: chipKind, ringAccent: ringAccent)
                }
            }
        }
    }

    /// DAY 見出し: 「DAY1」札 + 日付(M/D(曜)) + 公演名。
    @ViewBuilder
    private func dayHeader(index: Int, show: Show) -> some View {
        HStack(spacing: DS.Space.gapTight) {
            ImasBadge(text: "DAY\(index + 1)", kind: .lead)
            if let d = shortDate(show.date) {
                Text(d).imasText(.meta)
            }
            if !show.name.isEmpty, show.name != "DAY\(index + 1)" {
                Text(show.name).imasText(.meta).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// 役割アイドルのアバターグリッド (1 ブロック分)。
    @ViewBuilder
    private func roleGrid(idols: [Idol], chipText: String,
                          chipKind: ImasBadge.Kind, ringAccent: Bool) -> some View {
        LazyVGrid(columns: avatarColumns, spacing: DS.Space.card) {
            ForEach(idols) { idol in
                Button {
                    navigate(.idol(idol))
                } label: {
                    VStack(spacing: DS.Space.gapTight) {
                        // isPick は使わず roleAvatarRing で独自の accent リングを重ねるため、
                        // 担当リング分の外形余白は予約しない (可視アバターぴったりの size に戻す)。
                        IdolAvatarView(idol: idol, size: 56, reservesPickRing: false)
                            .overlay { roleAvatarRing(show: ringAccent) }
                        ImasBadge(text: chipText, kind: chipKind, seed: seed, brand: brandSeed)
                        Text(idol.shortName).imasText(.meta, color: DS.ink).lineLimit(1)
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

        ImasCard {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                HStack(spacing: DS.Space.gapTight) {
                    ImasBadge(text: unit.name, kind: .unit, seed: seed, brand: brandSeed)
                    Text("\(presentCount)/\(allMembers.count)").imasText(.meta)
                    Spacer()
                }
                avatarGrid(idols: allMembers, isAbsent: { !presentIds.contains($0.id) })
            }
        }
    }

    /// 塊 1 つ。日付ごとの塊は主演・ゲストと同じ DAY の見出し (札 + 日付 + 公演名) に人数を添える。
    @ViewBuilder
    private func groupView(group: EventAttendance.Group) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            if let showId = group.showId,
               let index = attendance.shows.firstIndex(where: { $0.id == showId }) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.gapTight) {
                    dayHeader(index: index, show: attendance.shows[index])
                    Text("\(group.idols.count)名").imasText(.meta)
                }
            } else {
                ImasSectionHeader(group.label, count: "\(group.idols.count)名", style: .small)
            }
            ImasCard {
                avatarGrid(idols: group.idols, isAbsent: { _ in group.label == "欠席" })
            }
        }
    }

    @ViewBuilder
    private func avatarGrid(idols: [Idol], isAbsent: @escaping (Idol) -> Bool) -> some View {
        LazyVGrid(columns: avatarColumns, spacing: DS.Space.card) {
            ForEach(idols) { idol in
                let absent = isAbsent(idol)
                Button {
                    navigate(.idol(idol))
                } label: {
                    VStack(spacing: DS.Space.gapTight) {
                        IdolAvatarView(idol: idol, size: 48)
                            .grayscale(absent ? 0.5 : 0)
                            .opacity(absent ? 0.45 : 1)
                        Text(idol.shortName).imasText(.meta, color: absent ? DS.ink3 : DS.ink).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
