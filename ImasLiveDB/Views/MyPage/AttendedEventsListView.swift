import SwiftUI

/// マイページから「参加したライブ 全て見る」で開く一覧。
/// 参加マーク (event/show-level attended) が付いた event を公演日降順で表示する。
/// 現地/配信でフィルタできる。既定は「回収に配信を含める」設定に追従
/// (含めない設定なら現地のみ表示。配信参加が混ざって見える違和感を防ぐ)。
struct AttendedEventsListView: View {
    let events: [EventWithDate]

    enum AttendanceFilter: Int, CaseIterable { case all, live, stream, liveViewing }

    @State private var filterIndex = 0
    @State private var liveSet: Set<String> = []
    @State private var streamSet: Set<String> = []
    @State private var liveViewingSet: Set<String> = []
    @State private var loaded = false

    private var filter: AttendanceFilter { AttendanceFilter(rawValue: filterIndex) ?? .all }

    /// LV参加が1件もなければLVタブは出さない (データ駆動)。
    private var showsLiveViewingTab: Bool { !liveViewingSet.isEmpty }

    private var segmentLabels: [String] {
        showsLiveViewingTab ? ["すべて", "現地", "配信", "LV"] : ["すべて", "現地", "配信"]
    }

    private var filteredEvents: [EventWithDate] {
        switch filter {
        case .all:         return events
        case .live:        return events.filter { liveSet.contains($0.event.id) }
        case .stream:      return events.filter { streamSet.contains($0.event.id) }
        case .liveViewing: return events.filter { liveViewingSet.contains($0.event.id) }
        }
    }

    private var emptyStateIcon: String {
        switch filter {
        case .stream:      return "play.tv"
        case .liveViewing: return "popcorn"
        default:           return "figure.wave"
        }
    }

    private var emptyStateTitle: String {
        switch filter {
        case .stream:      return "配信参加のライブがありません"
        case .liveViewing: return "ライブビューイング参加のライブがありません"
        default:           return "現地参加のライブがありません"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ImasSegmented(labels: segmentLabels, selection: $filterIndex)
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp3)

            List {
                Section {
                    ForEach(filteredEvents) { ew in
                        NavigationLink(value: ew.event) {
                            EventNameRow(event: ew.event, subtitle: ew.dateRange, showsChevron: false)
                        }
                        .listRowBackground(DS.surface)
                        .listRowSeparatorTint(DS.sep)
                    }
                } header: {
                    Text("\(filteredEvents.count)件")
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if filteredEvents.isEmpty {
                    ImasEmptyState(
                        systemImage: emptyStateIcon,
                        title: emptyStateTitle
                    )
                }
            }
        }
        .background(DS.bg)
        .navigationTitle("参加したライブ")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let sets = (try? await AppContainer.shared.eventReading.attendedEventTypeSets()) ?? (live: [], stream: [], liveViewing: [])
            liveSet = sets.live
            streamSet = sets.stream
            liveViewingSet = sets.liveViewing
            // 初回のみ、回収設定に追従して既定フィルタを決める。
            if !loaded {
                loaded = true
                let includeStream = UserDefaults.standard.bool(forKey: AppDatabase.collectionIncludeStreamKey)
                filterIndex = includeStream ? AttendanceFilter.all.rawValue : AttendanceFilter.live.rawValue
            }
        }
        .trackScreen("attended_events")
        // navigationDestination(for: Event.self) は親 (MyPageView の NavigationStack 直下)
        // に登録済み。ここで再登録すると同一スタックに同型 destination が二重になり、
        // 「一覧が再表示され、戻るで詳細に飛ぶ」遷移崩れを起こすため置かない。
    }
}
