import os
import SwiftUI

struct EventListView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    @AppStorage("events_show_empty") private var showEmptyEvents = false
    /// 除外する kind の rawValue を CSV で保存。デフォルトは全種類表示 (空文字列)。
    @AppStorage("events_excluded_kinds") private var excludedKindsRaw: String = ""
    /// 参加状態フィルタ ("all" / "attended" / "not_attended")
    @AppStorage("events_attendance_filter") private var attendanceFilter: String = "all"
    @AppStorage("events_require_favorite") private var requireFavorite: Bool = false
    @AppStorage("events_require_note") private var requireNote: Bool = false
    /// 会場絞り込み (venue_id。空 = 絞り込みなし)。会場は show 単位なので VM 側で event_id に逆引きされる。
    /// 名前ではなく ID で持つので、会場が改名しても絞り込みが外れない。
    @AppStorage("events_venue_id") private var venueFilter: String = ""
    /// 会場チップに現行名を出すためのマスタ。
    @State private var venueDirectory: VenueDirectory = .empty
    /// 0=今後の予定 / 1=開催済み。内部タブで時系列を分ける。
    @AppStorage("events_time_filter") private var timeFilter: Int = 0

    @State private var navPath = NavigationPath()
    @State private var vm = EventListViewModel()
    @State private var selectedBrandIds: Set<String> = []
    @State private var showFilterSheet = false
    @State private var searchText = ""
    /// タブを跨いだ検索の引き継ぎ (「他のタブに N 件」の受け側)。
    @State private var crossTab = CrossTabSearch.shared
    /// 絞り込みに実際に使う検索語 (searchText を落ち着いてから反映する)。
    ///
    /// 日本語 IME の変換中は 1 打鍵ごとに未確定文字が差し替わり、そのたびに
    /// 一覧が「全件 ⇄ 0 件 ⇄ 数件」と作り直される。年グループ (見出し + カード) を
    /// 伴うこの一覧はその振動で描画が破綻し、スクロールすると主スレッドが戻らなくなる。
    /// 変換が落ち着くまで作り直しを待たせてこの振動自体を消す。
    @State private var appliedSearchText = ""
    /// 新規イベント作成 sheet。
    @State private var showEventCreate = false
    /// 未ログイン時のログイン誘導 sheet。ログイン後に新規作成を再開する。
    @State private var showLoginPrompt = false

    private var excludedKinds: Set<EventKind> {
        Set(excludedKindsRaw.split(separator: ",")
            .compactMap { EventKind(rawValue: String($0)) })
    }

    private var activeFilterCount: Int {
        (selectedBrandIds.isEmpty ? 0 : 1)
        + (excludedKinds.isEmpty ? 0 : 1)
        + (attendanceFilter == "all" ? 0 : 1)
        + (requireFavorite ? 1 : 0)
        + (requireNote ? 1 : 0)
        + (venueFilter.isEmpty ? 0 : 1)
    }

    private var brandsKey: String {
        selectedBrandIds.isEmpty ? "all" : selectedBrandIds.sorted().joined(separator: ",")
    }

    /// フィルタ状態をまとめた識別子（task(id:) 用）
    /// 再計算のトリガーキー。絞り込み条件を足したらここにも必ず含める
    /// (含め忘れると、シートで条件を変えても一覧が旧い結果のまま残る)。
    private var filterKey: String {
        "\(brandsKey)_\(excludedKindsRaw)_\(showEmptyEvents)_\(appliedSearchText)_\(attendanceFilter)_\(requireFavorite)_\(requireNote)_\(timeFilter)_\(venueFilter)"
    }

    /// 端末ローカルの今日 (YYYY-MM-DD)。今後/開催済みの境界。
    /// 「今日」は JST 固定 (`JSTDay`)。公演日は日本のライブの開催日なので、
    /// 端末ローカル TZ で判定すると海外にいるユーザーだけ 1 日ずれる。
    private var todayKey: String { JSTDay.today() }

    /// 一覧の 1 行ぶんの表示単位。
    ///
    /// 以前は `ForEach(年グループ) { VStack { 見出し; ImasCardList { ForEach(行) } } }` と
    /// 入れ子にしていたが、この構造だと実機で一覧をスクロールした瞬間に主スレッドが
    /// 戻らなくなった (`LazyVStack` の中で、角丸クリップ付きコンテナに包まれた入れ子 `ForEach` の
    /// 高さ計算が破綻する)。楽曲・アイドル一覧が平坦な `ForEach` で無事だったこと、
    /// 見出しを外すと再現しなくなることの両方から特定した。
    ///
    /// 行を半券の形 (`ImasEventRow`) にしてからは、行どうしがカードへ入れ子にならず
    /// それぞれ自分の形を持つので、この平坦な並びがそのまま正しい組み方になった
    /// (先頭/末尾で角丸を描き分ける計算はもう要らない)。
    private enum EventListItem: Identifiable {
        case yearHeader(String)
        case row(EventWithDate)

        var id: String {
            switch self {
            case .yearHeader(let year): "header_\(year)"
            case .row(let ew): ew.id
            }
        }
    }

    /// 年の見出しの横に添える件数 (「14 件」)。`ImasDateHeader` の imprint 用。
    private func eventCount(forYear year: String) -> Int {
        vm.groupedByYear.first { $0.year == year }?.events.count ?? 0
    }

    /// 年グループを 1 本の並びへ畳む (グループの順序と行の順序はそのまま)。
    private var listItems: [EventListItem] {
        var items: [EventListItem] = []
        for group in vm.groupedByYear {
            items.append(.yearHeader(group.year))
            for ew in group.events {
                items.append(.row(ew))
            }
        }
        return items
    }

    /// brand_id → ブランドカラー hex / 表示名の引き当て表。
    ///
    /// ⚠️ 計算プロパティのままだと `ForEach` の中から引くたびに全ブランドから辞書を
    /// 作り直す (= 行数ぶん再構築されてスクロールが重くなる)。`vm.brands` が変わった
    /// ときだけ作り直すよう 1 つにまとめてキャッシュする。
    private struct BrandLookup {
        var color: [String: String] = [:]
        var name: [String: String] = [:]
    }
    @State private var brandLookup = BrandLookup()

    private var brandColorMap: [String: String] { brandLookup.color }
    private var brandNameMap: [String: String] { brandLookup.name }

    private func rebuildBrandLookup() {
        brandLookup = BrandLookup(
            color: Dictionary(uniqueKeysWithValues: vm.brands.compactMap { b in
                b.color.map { (b.id, $0) }
            }),
            name: Dictionary(uniqueKeysWithValues: vm.brands.map { ($0.id, $0.shortName) }))
    }

    /// View 側の選択状態 + マーク集合 (UserMarkService 参照は @Observable 観測のため View 文脈) を
    /// 純粋 UseCase 用の絞り込み条件へまとめる。
    private var filterContext: EventFilterContext {
        let markService = UserMarkService.shared
        var ctx = EventFilterContext(
            selectedBrandIds: selectedBrandIds,
            excludedKinds: excludedKinds,
            searchText: appliedSearchText,
            attendanceFilter: attendanceFilter)
        // attendedEventIds は VM.rebuild が show→event 逆引きで非同期解決するため、ここでは設定しない。
        if requireFavorite {
            ctx.requireFavorite = true
            ctx.favoriteIds = Set(markService.allMarked(kind: .favorite, entity: .event))
        }
        if requireNote {
            ctx.requireNote = true
            ctx.noteIds = Set(markService.allMarked(kind: .note, entity: .event))
        }
        // venueEventIds は VM.rebuild が show→event 逆引きで非同期解決するため、ここでは名前だけ渡す。
        ctx.venue = venueFilter
        return ctx
    }

    /// VM へ渡す問い合わせ条件 (絞り込み + 今後/開催済み + 端末today)。
    private var listQuery: EventListQuery {
        EventListQuery(filter: filterContext, upcoming: timeFilter == 0, todayKey: todayKey)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                // 同じ語が曲・アイドルに何件あるか (虫眼鏡を畳んだ代わりの導線)。
                CrossTabCountChips(query: appliedSearchText, from: .events)
                // ⚠️ ここは **List でなければならない**。公演行のスワイプ参加登録
                // (`eventAttendanceSwipe`) は List の行にしか効かず、ScrollView + LazyVStack
                // に付けても無言で消える (習熟度画面で一度踏んだ罠と同じ)。
                List {
                    ImasTabs(labels: ["今後の予定", "開催済み"], selection: $timeFilter)
                        .padding(.horizontal, DS.Space.screen)
                        .padding(.top, DS.Space.gapTight)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(DS.bg)
                        .listRowSeparator(.hidden)

                    if hasActiveFilterChips {
                        activeFilterChips
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(DS.bg)
                            .listRowSeparator(.hidden)
                    }

                    if vm.isLoading {
                        ImasListSkeleton(rows: 10, thumb: .none)
                            .padding(.horizontal, DS.Space.screen)
                            .padding(.top, DS.Space.gap)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(DS.bg)
                            .listRowSeparator(.hidden)
                    }

                    // 半券の行はそれぞれが自分の形 (角丸・切り取り欠き) を持つので、
                    // カードへの入れ子 (と、その入れ子が実機のスクロールで主スレッドを
                    // 固まらせていた既知の不具合) が要らなくなった。年の区切りと行を
                    // 1 本の ForEach にそのまま並べ、行の間は半券どうしの余白で空ける。
                    ForEach(listItems) { item in
                        switch item {
                        case .yearHeader(let year):
                            ImasDateHeader(big: year, imprint: "\(eventCount(forYear: year)) 件", isPast: timeFilter == 1)
                                .padding(.horizontal, DS.Space.screen)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(DS.bg)
                                .listRowSeparator(.hidden)

                        case .row(let ew):
                            NavigationLink(value: ew.event) {
                                ImasEventRow(
                                    event: ew.event,
                                    date: ew.firstDate,
                                    subtitle: ew.dateRange,
                                    rainbow: !ew.event.jointBrandIdList.isEmpty
                                )
                            }
                            .buttonStyle(.plain)
                            // イベントは公演 (show) を複数束ねることがあり、参加は show 単位でしか
                            // 保存できない。ここで「1 公演なら直接登録」等の判定を新設すると
                            // 出し分け規則の二重管理になるので、公演ごとの参加管理は既存の
                            // `EventAttendanceSheet` (EventDetailView と共有) にそのまま委ねる。
                            .eventAttendanceSwipe(
                                event: ew.event,
                                seed: brandColorMap[ew.event.brandId ?? ""]
                            )
                        }
                    }

                    if vm.groupedByYear.isEmpty && !vm.isLoading {
                        emptyState
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(DS.bg)
                            .listRowSeparator(.hidden)
                    }

                    Color.clear.frame(height: DS.Space.section)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(DS.bg)
                        .listRowSeparator(.hidden)
                }
                .imasList()
                .readableContentMargins()
                .environment(\.defaultMinListRowHeight, 0)
                .scrollDismissesKeyboard(.immediately)
                .refreshable {
                    await syncEngine.performIncrementalSync(database: database)
                    await vm.loadData(includeEmpty: showEmptyEvents, query: listQuery)
                }
            }
            .navigationTitle("ライブ")
            // 絞り込みフィールドはナビバーの中 (standardListToolbar の principal)。
            // 大タイトルを出すと 2 行になってしまうので inline 固定。
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 検索は一覧そのものを絞る (虫眼鏡のシートだと結果がそこで完結してしまい、
                // ブランド絞り込みや期間フィルタと合わせられなかった)。
                standardListToolbar(
                    filterBadge: activeFilterCount,
                    onFilter: {
                        AppAnalytics.tap("event_list.filter")
                        showFilterSheet = true
                    },
                    menuActions: eventMenuActions
                ) {
                    // 虫眼鏡アイコンが用途を示すので、文言は対象だけ。
                    // 「〜で絞り込み」まで書くと狭い欄で末尾が切れる。
                    ImasSearchField(prompt: "ライブ名・会場", text: $searchText)
                }
            }
            // 「他のタブに N 件」から飛んで来たら、その語で絞り込む。
            // 当たりが開催済みにしか無いなら、そちらへ着地する。件数を見せて誘って
            // おいて 0 件の画面を出すのは、この導線の趣旨に反する。
            .onChange(of: crossTab.target, initial: true) { _, _ in
                guard let handed = crossTab.take(for: .events) else { return }
                searchText = handed
                appliedSearchText = handed
                Task {
                    let sides = try? await AppContainer.shared.globalSearchReading
                        .eventSides(query: handed, todayKey: todayKey)
                    if let sides, sides.landsOnPast { timeFilter = 1 }
                }
            }
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
            .sheet(isPresented: $showFilterSheet) {
                EventFilterSheet(
                    venue: $venueFilter,
                    selectedBrandIds: $selectedBrandIds,
                    excludedKindsRaw: $excludedKindsRaw,
                    showEmptyEvents: $showEmptyEvents,
                    attendanceFilter: $attendanceFilter,
                    requireFavorite: $requireFavorite,
                    requireNote: $requireNote
                )
                .environment(database)
                .presentationDetents([.medium, .large])
                .onDisappear { Task { await vm.loadData(includeEmpty: showEmptyEvents, query: listQuery) } }
            }
            .sheet(isPresented: $showEventCreate, onDismiss: { Task { await vm.loadData(includeEmpty: showEmptyEvents, query: listQuery) } }) {
                EventEditView(newEventBrandId: selectedBrandIds.count == 1 ? selectedBrandIds.first : nil)
                    .environment(database)
            }
            .sheet(isPresented: $showLoginPrompt) {
                LoginToEditSheet(onSignedIn: { if EditPermission.canEdit { showEventCreate = true } })
            }
            .task {
                await vm.loadData(includeEmpty: showEmptyEvents, query: listQuery)
                rebuildBrandLookup()
            }
            // 変換中の未確定文字で一覧を作り直さない。打鍵が止まってから反映する。
            .task(id: searchText) {
                if searchText.isEmpty {
                    appliedSearchText = ""   // 消したときは即座に全件へ戻す
                    return
                }
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                appliedSearchText = searchText
            }
            // フィルタ変化時のみ再計算
            .task(id: filterKey) {
                await vm.rebuild(query: listQuery)
            }
            .task {
                venueDirectory = (try? await AppContainer.shared.showReading.venueDirectory()) ?? .empty
            }
            .trackScreen("event_list")
        }
    }

    // MARK: - Active filter chips (removable)

    /// アクティブなフィルタを `ImasFilterBar` で表示。各チップのタップでそのフィルタだけを
    /// 即時解除する (既存 AppStorage ロジックに配線)。2 つ以上効いていれば「すべて解除」も出す。
    private var hasActiveFilterChips: Bool { activeFilterCount > 0 }

    private var activeFilterItems: [ImasFilterBar.Item] {
        var items: [ImasFilterBar.Item] = []
        for bid in selectedBrandIds.sorted() {
            items.append(ImasFilterBar.Item(id: "brand_\(bid)", title: brandNameMap[bid] ?? bid, seed: brandColorMap[bid]) {
                selectedBrandIds.remove(bid)
            })
        }
        for kind in Array(excludedKinds).sorted(by: { $0.rawValue < $1.rawValue }) {
            items.append(ImasFilterBar.Item(id: "kind_\(kind.rawValue)", title: "除外: \(kind.displayLabel)") {
                removeExcludedKind(kind)
            })
        }
        if attendanceFilter == "attended" {
            items.append(ImasFilterBar.Item(id: "attendance", title: "参加済み") { attendanceFilter = "all" })
        } else if attendanceFilter == "not_attended" {
            items.append(ImasFilterBar.Item(id: "attendance", title: "未参加") { attendanceFilter = "all" })
        }
        if requireFavorite {
            items.append(ImasFilterBar.Item(id: "favorite", title: "お気に入り") { requireFavorite = false })
        }
        if requireNote {
            items.append(ImasFilterBar.Item(id: "note", title: "メモあり") { requireNote = false })
        }
        if !venueFilter.isEmpty {
            items.append(ImasFilterBar.Item(id: "venue", title: venueDirectory.venue(id: venueFilter)?.name ?? venueFilter) {
                venueFilter = ""
            })
        }
        return items
    }

    @ViewBuilder private var activeFilterChips: some View {
        ImasFilterBar(items: activeFilterItems, onClearAll: activeFilterItems.count >= 2 ? { clearAllFilters() } : nil)
    }

    /// 新規イベント作成導線。ログイン済みなら作成 sheet、未ログインならログイン誘導。
    private func startCreate() {
        if EditPermission.canEdit {
            showEventCreate = true
        } else {
            showLoginPrompt = true
        }
    }

    private var eventMenuActions: [ListToolbarAction] {
        var actions: [ListToolbarAction] = []
        if EditPermission.showEditAffordance {
            actions.append(ListToolbarAction(id: "add", title: "イベントを追加", systemImage: "plus") {
                AppAnalytics.tap("event_list.add")
                startCreate()
            })
        }
        if activeFilterCount > 0 {
            actions.append(ListToolbarAction(id: "clear", title: "フィルタを解除",
                                             systemImage: "xmark.circle", isDestructive: true) {
                AppAnalytics.tap("event_list.filter_clear")
                clearAllFilters()
            })
        }
        return actions
    }

    private func clearAllFilters() {
        selectedBrandIds = []
        excludedKindsRaw = ""
        attendanceFilter = "all"
        showEmptyEvents = false
        requireFavorite = false
        requireNote = false
        venueFilter = ""
    }

    /// 除外 kind 集合から 1 件だけ外す (CSV へ書き戻す)。
    private func removeExcludedKind(_ kind: EventKind) {
        var set = excludedKinds
        set.remove(kind)
        excludedKindsRaw = set.map(\.rawValue).sorted().joined(separator: ",")
    }

    // MARK: - Empty state

    @ViewBuilder private var emptyState: some View {
        if !appliedSearchText.isEmpty {
            ImasEmptyState(
                systemImage: "line.3.horizontal.decrease",
                title: "絞り込み結果がありません",
                message: "「\(appliedSearchText)」に一致するライブがありません",
                actionTitle: "絞り込みを解除",
                action: { searchText = ""; appliedSearchText = "" }
            )
            .padding(.top, DS.Space.section)
        } else {
            ImasEmptyState(
                systemImage: "music.mic",
                title: timeFilter == 0 ? "今後の予定はありません" : "開催済みのライブがありません",
                message: activeFilterCount > 0
                    ? "フィルタ条件に合うライブが見つかりませんでした。"
                    : (timeFilter == 0
                        ? "現在、登録されている今後のライブはありません。「開催済み」タブもご確認ください。"
                        : "開催済みのライブはまだ登録されていません。"),
                actionTitle: activeFilterCount > 0 ? "フィルタを解除" : nil,
                action: activeFilterCount > 0 ? { clearAllFilters() } : nil
            )
            .padding(.top, DS.Space.section)
        }
    }

}

// MARK: - Supporting types
// YearGroup は Domain/UseCases/EventGrouping.swift に移動 (純粋ロジックとして単体テスト対象)。
//
// ★行の見た目は `ImasEventRow` (半券) に一本化済み。以前はここに専用の `EventRowView`
// (リードバー + ライブ名 + 日付レンジ) を持っていたが、半券の行は行末の矢印を自分で
// 描かない・区切り線を自分の余白で表すなど、同じ事情をすべて `ImasEventRow` 側が
// 引き継いでいるので、この一覧専用の行は廃止した。
