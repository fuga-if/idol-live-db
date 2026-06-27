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
    /// 0=今後の予定 / 1=開催済み。内部タブで時系列を分ける。
    @AppStorage("events_time_filter") private var timeFilter: Int = 0

    @State private var navPath = NavigationPath()
    @State private var vm = EventListViewModel()
    @State private var selectedBrandIds: Set<String> = []
    @State private var showFilterSheet = false
    @State private var searchText = ""
    @State private var isSearching = false
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
    }

    private var brandsKey: String {
        selectedBrandIds.isEmpty ? "all" : selectedBrandIds.sorted().joined(separator: ",")
    }

    /// フィルタ状態をまとめた識別子（task(id:) 用）
    private var filterKey: String {
        "\(brandsKey)_\(excludedKindsRaw)_\(showEmptyEvents)_\(searchText)_\(attendanceFilter)_\(requireFavorite)_\(requireNote)_\(timeFilter)"
    }

    /// 端末ローカルの今日 (YYYY-MM-DD)。今後/開催済みの境界。
    private var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// brand_id → ブランドカラー hex の引き当て表 (リードバーの seed 用)。
    private var brandColorMap: [String: String] {
        Dictionary(uniqueKeysWithValues: vm.brands.compactMap { brand in
            brand.color.map { (brand.id, $0) }
        })
    }

    /// brand_id → ブランド表示名 (フィルタチップのラベル用)。
    private var brandNameMap: [String: String] {
        Dictionary(uniqueKeysWithValues: vm.brands.map { ($0.id, $0.shortName) })
    }

    /// View 側の選択状態 + マーク集合 (UserMarkService 参照は @Observable 観測のため View 文脈) を
    /// 純粋 UseCase 用の絞り込み条件へまとめる。
    private var filterContext: EventFilterContext {
        let markService = UserMarkService.shared
        var ctx = EventFilterContext(
            selectedBrandIds: selectedBrandIds,
            excludedKinds: excludedKinds,
            searchText: searchText,
            attendanceFilter: attendanceFilter)
        if attendanceFilter != "all" {
            ctx.attendedEventIds = Set(markService.allMarked(kind: .attended, entity: .event))
        }
        if requireFavorite {
            ctx.requireFavorite = true
            ctx.favoriteIds = Set(markService.allMarked(kind: .favorite, entity: .event))
        }
        if requireNote {
            ctx.requireNote = true
            ctx.noteIds = Set(markService.allMarked(kind: .note, entity: .event))
        }
        return ctx
    }

    /// VM へ渡す問い合わせ条件 (絞り込み + 今後/開催済み + 端末today)。
    private var listQuery: EventListQuery {
        EventListQuery(filter: filterContext, upcoming: timeFilter == 0, todayKey: todayKey)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                if isSearching {
                    InTabSearchField(prompt: "ライブ名で検索", text: $searchText, isSearching: $isSearching)
                }
                ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ImasSegmented(labels: ["今後の予定", "開催済み"], selection: $timeFilter)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    activeFilterChips

                    ForEach(Array(vm.groupedByYear.enumerated()), id: \.element.id) { index, group in
                        VStack(alignment: .leading, spacing: 8) {
                            ImasSectionHeader(title: group.year, tight: true)
                                .padding(.horizontal, 16)

                            ImasListContainer {
                                ForEach(Array(group.events.enumerated()), id: \.element.id) { rowIndex, ew in
                                    if rowIndex > 0 {
                                        Divider().overlay(DS.sep).padding(.leading, 16)
                                    }
                                    NavigationLink(value: ew.event) {
                                        EventRowView(
                                            event: ew.event,
                                            dateText: ew.dateRange,
                                            seedHex: brandColorMap[ew.event.brandId ?? ""]
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, index == 0 && !hasActiveFilterChips ? 6 : 18)
                    }

                    if vm.groupedByYear.isEmpty {
                        emptyState
                    }

                    Color.clear.frame(height: 24)
                }
            }
            .background(DS.bg)
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                await syncEngine.performIncrementalSync(database: database)
                await vm.loadData(includeEmpty: showEmptyEvents, query: listQuery)
            }
            }
            .navigationTitle("ライブ")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                standardListToolbar(
                    onSearch: {
                        AppAnalytics.tap("event_list.search_open")
                        isSearching = true
                    },
                    filterBadge: activeFilterCount,
                    onFilter: {
                        AppAnalytics.tap("event_list.filter")
                        showFilterSheet = true
                    },
                    menuActions: eventMenuActions
                )
            }
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
            .sheet(isPresented: $showFilterSheet) {
                EventFilterSheet(
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
            .task { await vm.loadData(includeEmpty: showEmptyEvents, query: listQuery) }
            // フィルタ変化時のみ再計算
            .task(id: filterKey) {
                vm.rebuild(query: listQuery)
            }
            .trackScreen("event_list")
        }
    }

    // MARK: - Active filter chips (removable)

    /// アクティブなフィルタを横スクロールの removable chip 列で表示。
    /// 各チップのタップでそのフィルタだけを即時解除する (既存 AppStorage ロジックに配線)。
    private var hasActiveFilterChips: Bool { activeFilterCount > 0 }

    @ViewBuilder private var activeFilterChips: some View {
        if hasActiveFilterChips {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedBrandIds.sorted(), id: \.self) { bid in
                        removableChip(brandNameMap[bid] ?? bid, seed: brandColorMap[bid]) {
                            selectedBrandIds.remove(bid)
                        }
                    }
                    ForEach(Array(excludedKinds).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { kind in
                        removableChip("除外: \(kind.displayLabel)") {
                            removeExcludedKind(kind)
                        }
                    }
                    if attendanceFilter == "attended" {
                        removableChip("参加済み") { attendanceFilter = "all" }
                    } else if attendanceFilter == "not_attended" {
                        removableChip("未参加") { attendanceFilter = "all" }
                    }
                    if requireFavorite {
                        removableChip("お気に入り") { requireFavorite = false }
                    }
                    if requireNote {
                        removableChip("メモあり") { requireNote = false }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .padding(.top, 6)
        }
    }

    /// selected スタイルの removable chip。テキスト + 末尾 × を 1 つのピルに収め、
    /// タップで `onRemove`。design の `chip sel removable` 相当。
    private func removableChip(_ text: String, seed: String? = nil, onRemove: @escaping () -> Void) -> some View {
        ImasRemovableChip(text: text, seed: seed, onRemove: onRemove)
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
    }

    /// 除外 kind 集合から 1 件だけ外す (CSV へ書き戻す)。
    private func removeExcludedKind(_ kind: EventKind) {
        var set = excludedKinds
        set.remove(kind)
        excludedKindsRaw = set.map(\.rawValue).sorted().joined(separator: ",")
    }

    // MARK: - Empty state

    @ViewBuilder private var emptyState: some View {
        if !searchText.isEmpty {
            InTabSearchEmptyView(query: searchText)
                .padding(.top, 40)
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
            .padding(.top, 40)
        }
    }

}

// MARK: - Supporting types
// YearGroup は Domain/UseCases/EventGrouping.swift に移動 (純粋ロジックとして単体テスト対象)。

/// ライブ一覧の 1 行。行頭の細いリードバー (合同 = rainbow) + ライブ名 + 日付レンジ +
/// ★お気に入りトグル。エンティティ色は seed (ブランドカラー hex) で控えめに供給する。
private struct EventRowView: View {
    let event: Event
    var dateText: String? = nil
    /// ブランドカラー hex (リードバーの seed)。合同ライブのときは無視され rainbow になる。
    var seedHex: String? = nil

    /// joint_brand_ids を持つ = 合同ライブ → rainbow リードバー。
    private var isJoint: Bool { !event.jointBrandIdList.isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            ImasLeadBar(seed: seedHex, rainbow: isJoint)
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(eventDisplayName(event.name))
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                if let dateText, !dateText.isEmpty {
                    Text(dateText)
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            FavoriteToggleButton(entity: .event, id: event.id, size: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DS.surface)
        .contentShape(Rectangle())
    }
}

// MARK: - Event Search Screen

private struct EventSearchScreen: View {
    let eventsWithDate: [EventWithDate]

    var body: some View {
        SearchScreen(
            prompt: "ライブ名 / 会場で検索",
            historyScope: .events,
            searchAction: { query in
                // venue 一致を含めるため DB 経由で検索 (eventsWithDate には venue 情報がない)。
                // EventReading ポート経由。
                (try? await AppContainer.shared.eventReading.searchEventsByNameOrVenue(query: query, limit: 100)) ?? []
            },
            suggestionsAction: { query in
                let lower = query.lowercased()
                return eventsWithDate
                    .filter { $0.event.name.lowercased().contains(lower) }
                    .prefix(8)
                    .map { ew in
                        let subtitle = ew.firstDate.map { String($0.prefix(4)) + "年" }
                        return SearchSuggestionItem(text: ew.event.name, subtitle: subtitle, icon: "music.mic")
                    }
            }
        ) { event in
            NavigationLink(value: event) {
                EventSearchRowView(event: event)
            }
        }
        .navigationDestination(for: Event.self) { event in
            EventDetailView(event: event)
        }
    }
}

private struct EventSearchRowView: View {
    let event: Event

    var body: some View {
        HStack(spacing: 12) {
            ImasLeadBar(seed: nil, brand: nil, rainbow: !event.jointBrandIdList.isEmpty)
                .frame(height: 28)
            Text(eventDisplayName(event.name))
                .font(.imasSubhead.weight(.semibold))
                .foregroundStyle(DS.ink)
        }
    }
}
