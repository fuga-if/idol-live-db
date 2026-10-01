import os
import SwiftUI

/// プロデュース (tab4・担当ダッシュボード)。
/// 担当アイドル → 次のライブ → 投票受付中 → 入口 (あそぶ・みんな・しらべる) →
/// あなたの記録 → 最近見た の縦 1 枚構成。予定と新しい機能の入口を上に置き、
/// 記録 (タイル) から先は奥の画面で見る。同じ行き先の入口は 1 か所にする
/// (マイ予想・投票一覧・参加ライブ一覧はタイル / お題見出しから行く)。
struct ProduceTabView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    private var userMarks: UserMarkService { UserMarkService.shared }

    // 担当アイドル (マイピック)。各カードが自色をまとうヒーロー。
    @State private var pickIdols: [Idol] = []
    /// brandId → Brand。ヒーローのブランド名・色フォールバックに使う。
    @State private var brandsById: [String: Brand] = [:]

    // あなたの活動サマリ。
    @State private var attendedCount: Int = 0
    @State private var predictionCount: Int = 0
    @State private var favoriteCount: Int = 0    // 曲+アイドル+ライブの合計
    @State private var collectedCount: Int = 0
    /// 習熟度を 1 段でも付けた曲数 (タイルの数字)。集計は core、ここは件数だけ。
    private var masteryCount: Int { userMarks.masteryCounts().reduce(0, +) }
    /// 収支の合計。タイルには金額を出す — 件数では「いくら使ったか」が読めない。
    @State private var ledgerTotal: Int64 = 0
    @State private var collectedSongIds: [String] = []
    // ローカル履歴 (投稿・投票) は @Observable で参照するだけでカウントが見える。
    @State private var voteLog = LocalPollVoteLog.shared
    @State private var contributionLog = LocalContributionLog.shared

    // 参加したライブ (タイル「参加ライブ」の遷移先に渡す)。
    @State private var attendedEvents: [EventWithDate] = []
    /// 参加予定 / お気に入りの直近の未来公演。無ければカードを出さない。
    @State private var nextLive: NextLive?
    @State private var resumeStore = QuizResumeStore.shared

    /// 「最近見た」タップ時の詳細遷移先。
    @State private var sheetDestination: DetailDestination?
    @State private var navPath = NavigationPath()
    /// プロデュース先頭に出す「開催中のお題」(最も票が集まっているもの)。
    @State private var activePoll: Poll?
    @State private var showInbox = false
    @State private var inboxStore = AnnouncementStore.shared
    /// Discord ロール受け取り: 認可 URL を発行してもらっている間 true (二度押し防止 + くるくる)。
    @State private var isLinkingDiscord = false
    @State private var discordErrorMessage: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp6) {
                    oshiSection
                    nextLiveSection
                    featuredPollSection
                    shortcutSection
                    activitySection
                    recentsSection
                }
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp4)
                .padding(.bottom, DS.sp7)
            }
            .background(DS.bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("プロデュース")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton()
                }
                if ChatGPTPlanSession.isPrototypeVisible {
                    ToolbarItem(placement: .topBarTrailing) {
                        AssistantToolbarButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppAnalytics.tap("produce_tab.open_inbox")
                        showInbox = true
                    } label: {
                        Image(systemName: inboxStore.unreadCount > 0 ? "bell.badge.fill" : "bell")
                            .symbolRenderingMode(inboxStore.unreadCount > 0 ? .multicolor : .monochrome)
                    }
                    .accessibilityLabel(inboxStore.unreadCount > 0 ? "お知らせ (未読\(inboxStore.unreadCount)件)" : "お知らせ")
                }
            }
            .sheet(isPresented: $showInbox) {
                InboxView()
            }
            .alert("エラー", isPresented: Binding(
                get: { discordErrorMessage != nil },
                set: { if !$0 { discordErrorMessage = nil } }
            )) {
                Button("OK") { discordErrorMessage = nil }
            } message: {
                Text(discordErrorMessage ?? "")
            }
            .navigationDestination(for: Idol.self) { idol in
                IdolDetailView(idol: idol)
            }
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
            .navigationDestination(for: ActivityRoute.self) { route in
                activityDestination(route)
            }
            .navigationDestination(for: NextLiveRoute.self) { route in
                switch route {
                case .prediction(let show): SetlistView(show: show, opensPrediction: true)
                }
            }
            // みんなの投票 (PollListView) は自前スタックを持たず、ここ(親の1スタック)に
            // 遷移先を登録する。これで「一覧→詳細」の2階層目を同じスタック上に push できる。
            .navigationDestination(for: PollRoute.self) { PollRouteView(route: $0) }
            .sheet(item: $sheetDestination) { dest in
                DetailSheetView(destination: dest)
                    .environment(database)
            }
            .refreshable {
                await syncEngine.performIncrementalSync(database: database)
                await loadAll()
            }
            .task { await loadAll() }
            .onChange(of: syncEngine.state) {
                if case .completed = syncEngine.state {
                    Task { await loadAll() }
                }
            }
            .trackScreen("produce_tab")
        }
    }

    // MARK: - 担当アイドル (ヒーロー横スクロール)

    // MARK: - 開催中のお題 (投票導線)

    @ViewBuilder
    private var featuredPollSection: some View {
        if let poll = activePoll {
            VStack(alignment: .leading, spacing: DS.sp3) {
                // 投票一覧は値ベース (PollRoute.list) で push する。クロージャで PollListView() を
                // 直接 push すると中の値ベース NavigationLink(value: PollRoute.detail) と混ざり、
                // 詳細へ進むたびに PollList が二重 push される。
                ImasSectionHeader(title: "投票受付中", seeAll: {
                    if NavThrottle.allow() { navPath.append(PollRoute.list) }
                }, tight: true, seeAllTitle: "ほかのお題")
                NavigationLink(value: PollRoute.detail(poll.id)) {
                    VStack(alignment: .leading, spacing: DS.sp3) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.doc.horizontal.fill")
                            Text("お題").font(.imasCaption.bold())
                            Spacer()
                            Text(pollRemainingLabel(poll.endsAt)).font(.imasCaption)
                        }
                        .foregroundStyle(.white.opacity(0.95))

                        Text(poll.title)
                            .font(.imasTitle3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: DS.sp4) {
                            Label("\(poll.totalVotes ?? 0)票", systemImage: "hand.thumbsup.fill")
                            Label("\(poll.entryCount ?? 0)候補", systemImage: "list.number")
                            Spacer()
                            Text("投票する").font(.imasSubhead.bold())
                            Image(systemName: "arrow.right")
                        }
                        .font(.imasCaption)
                        .foregroundStyle(.white)
                    }
                    .padding(DS.sp5)
                    .background(
                        LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.55),
                                                Color(red: 0.55, green: 0.35, blue: 0.95)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// お題の残り時間ラベル。
    private func pollRemainingLabel(_ endsAt: Date) -> String {
        let secs = endsAt.timeIntervalSinceNow
        if secs <= 0 { return "まもなく終了" }
        let days = Int(secs / 86400)
        if days >= 1 { return "あと\(days)日" }
        let hours = Int(secs / 3600)
        return hours >= 1 ? "あと\(hours)時間" : "まもなく終了"
    }

    @ViewBuilder
    private var oshiSection: some View {
        if pickIdols.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "担当アイドル", tight: true)
                ImasEmptyState(
                    systemImage: "heart",
                    title: "担当アイドルがいません",
                    message: "アイドル詳細の「担当」マークを付けると、ここに大きく表示されます。"
                )
            }
        } else {
            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "担当アイドル", count: "\(pickIdols.count)人", tight: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.sp3) {
                        ForEach(pickIdols) { idol in
                            HeroIdolCard(idol: idol, brand: brandsById[idol.brandId])
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, DS.sp1)
                }
            }
        }
    }

    // MARK: - あなたの活動 (StatTile グリッド)

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "あなたの記録", tight: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: 3), spacing: DS.sp3) {
                statTileLink(route: .attendedEvents) {
                    ImasStatTile(systemImage: "music.mic", value: numberString(attendedCount), label: "参加ライブ", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myPredictions) {
                    ImasStatTile(systemImage: "sparkles", value: numberString(predictionCount), label: "予想", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .favorites) {
                    ImasStatTile(systemImage: "star.fill", value: numberString(favoriteCount), label: "お気に入り", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myContributions) {
                    ImasStatTile(systemImage: "square.and.pencil", value: numberString(contributionLog.total), label: "投稿", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myVotes) {
                    ImasStatTile(systemImage: "chart.bar.doc.horizontal", value: numberString(voteLog.votedPollCount), label: "投票", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .collectedSongs) {
                    ImasStatTile(systemImage: "music.note", value: numberString(collectedCount), label: "回収", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .mastery) {
                    ImasStatTile(systemImage: "chart.bar.fill", value: numberString(masteryCount), label: "習熟度", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .ledger) {
                    ImasStatTile(systemImage: "yensign.circle.fill", value: formatYen(amount: ledgerTotal), label: "収支", brand: pickBrandSeed, tappable: true)
                }
            }
        }
    }

    /// あなたの活動タイルの遷移先。値ベース push にして二重 push をスロットルで防ぐ。
    enum ActivityRoute: Hashable {
        case attendedEvents, myPredictions, favorites, myVotes, myContributions, collectedSongs, mastery, ledger
    }

    @ViewBuilder
    private func activityDestination(_ route: ActivityRoute) -> some View {
        switch route {
        case .attendedEvents: AttendedEventsListView(events: attendedEvents)
        case .myPredictions: MyPredictionsView()
        case .favorites: FavoritesListView().environment(database)
        case .myVotes: MyVotesView().environment(database)
        case .myContributions: MyContributionsView()
        case .collectedSongs: songListDestination(ids: collectedSongIds, title: "回収した楽曲")
        case .mastery: MasteryView().environment(database)
        case .ledger: LedgerView().environment(database)
        }
    }

    /// StatTile を奥の画面へ push する共通ラッパ。直接 append は throttle binding を
    /// 経由しないため、NavThrottle で明示的に二重タップをガードする。
    private func statTileLink<Label: View>(
        route: ActivityRoute,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            if NavThrottle.allow() { navPath.append(route) }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    /// お気に入り / 記録曲タイルの遷移先。楽曲をタップすると詳細シートを開く。
    private func songListDestination(ids: [String], title: String) -> some View {
        FilteredSongsView(criterion: .songIds(ids, title: title)) { dest in
            sheetDestination = dest
        }
        .environment(database)
    }

    // MARK: - 最近見た (RecentsService)

    @ViewBuilder
    private var recentsSection: some View {
        let recents = RecentsService.shared.items
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "最近見た", tight: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.sp2) {
                        ForEach(recents) { item in
                            Button { Task { await openRecent(item) } } label: { RecentChip(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, DS.sp1)
                }
            }
        }
    }

    // MARK: - 次のライブ (参加予定 / お気に入りの直近公演)

    enum NextLiveRoute: Hashable {
        case prediction(Show)
    }

    @ViewBuilder
    private var nextLiveSection: some View {
        if let next = nextLive {
            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "次のライブ", tight: true)
                NextLiveCard(
                    next: next,
                    seed: next.event.brandId.flatMap { brandsById[$0]?.color } ?? pickBrandSeed,
                    showsCallGuide: LyricsFeature.isAvailable,
                    onPredict: {
                        AppAnalytics.tap("produce_tab.next_live_predict")
                        if NavThrottle.allow() { navPath.append(NextLiveRoute.prediction(next.show)) }
                    }
                )
            }
        }
    }

    // MARK: - 入口 (あそぶ / みんな / しらべる)

    private var shortcutSection: some View {
        VStack(spacing: DS.sp3) {
            ProduceShortcutGroup(title: "あそぶ") {
                if let s = resumeStore.latest {
                    NavigationLink {
                        QuizResumeDestination(suspended: s)
                    } label: {
                        HStack(spacing: 2) {
                            Text("つづきから: \(gameTitle(s.kind)) " + String(format: "Q.%02d", min(s.plays.count + 1, s.total)))
                                .lineLimit(1)
                            Image(systemName: "chevron.right").font(.imasScaled(11, weight: .semibold))
                        }
                        .font(.imasScaled(13, weight: .medium))
                        .foregroundStyle(DS.ink2)
                    }
                    .buttonStyle(.plain)
                }
            } items: {
                NavigationLink { IntroDonHomeView() } label: {
                    ProduceShortcutIcon(systemImage: "music.note.list", label: "イントロ", seed: pickBrandSeed)
                }
                NavigationLink { LyricsQuizSetupView() } label: {
                    ProduceShortcutIcon(systemImage: "text.quote", label: "歌詞", seed: pickBrandSeed)
                }
                NavigationLink { SetlistQuizSetupView() } label: {
                    ProduceShortcutIcon(systemImage: "list.number", label: "セトリ当て", seed: pickBrandSeed)
                }
                NavigationLink { GamesHubView() } label: {
                    ProduceShortcutIcon(systemImage: "gamecontroller.fill", label: "すべて", seed: pickBrandSeed)
                }
            }

            ProduceShortcutGroup(title: "みんな") {
                EmptyView()
            } items: {
                NavigationLink { RecentEditsView() } label: {
                    ProduceShortcutIcon(systemImage: "person.2.fill", label: "動き", seed: secondaryBrandSeed)
                }
                NavigationLink { TagActivityView() } label: {
                    ProduceShortcutIcon(systemImage: "flame.fill", label: "タグ", seed: secondaryBrandSeed)
                }
                // 歌詞タブと同じ根拠 (JASRAC 許諾) で出し分ける。歌詞が出ないビルドでは
                // コールガイドを書く場所そのものが無いので、入口も出さない。
                if LyricsFeature.isAvailable {
                    NavigationLink { CallGuideDashboardView() } label: {
                        ProduceShortcutIcon(systemImage: "hands.clap.fill", label: "コール", seed: secondaryBrandSeed)
                    }
                }
                // 開催中のお題が無いと上の「ほかのお題」が出ないので、そのときだけここに置く。
                if activePoll == nil {
                    NavigationLink(value: PollRoute.list) {
                        ProduceShortcutIcon(systemImage: "chart.bar.doc.horizontal", label: "お題", seed: secondaryBrandSeed)
                    }
                }
                // 編集の協力者に Discord のロールを渡す入口。セッションで本人を確かめるので
                // ログイン中だけ出す (未ログインで押しても 401 になるだけ)。
                if AuthService.shared.isSignedIn {
                    Button {
                        Task { await openDiscordLink() }
                    } label: {
                        ProduceShortcutIcon(systemImage: "rosette", label: "Discord", seed: secondaryBrandSeed,
                                            isLoading: isLinkingDiscord)
                    }
                }
            }

            ProduceShortcutGroup(title: "しらべる") {
                EmptyView()
            } items: {
                NavigationLink { StatsView() } label: {
                    ProduceShortcutIcon(systemImage: "chart.bar.xaxis", label: "統計", seed: pickBrandSeed)
                }
                NavigationLink { BrandTimelineView(initialBrandId: pickIdols.first?.brandId) } label: {
                    ProduceShortcutIcon(systemImage: "calendar.day.timeline.left", label: "年表", seed: pickBrandSeed)
                }
            }
        }
    }

    /// つづきからの見出しに出すゲーム名 (ゲーム一覧と同じ呼び方)。
    private func gameTitle(_ kind: GameKind) -> String {
        switch kind {
        case .idolQuiz: "アイドル当て"
        case .songSingerQuiz: "ソロ曲クイズ"
        case .lyricsQuiz: "歌詞クイズ"
        case .setlistQuiz: "セトリ当て"
        case .introDon: "イントロドン"
        case .colorMatch: "メンバーカラー合わせ"
        }
    }

    /// Worker から 1 回限りの Discord 認可 URL をもらってブラウザで開く。
    /// ロール付与の結果は Worker のページが出すので、ここは開くところまで。
    private func openDiscordLink() async {
        guard !isLinkingDiscord else { return }
        AppAnalytics.tap("produce_tab.discord_link")
        isLinkingDiscord = true
        defer { isLinkingDiscord = false }
        do {
            let url = try await DiscordLinkService.authorizeURL()
            openURL(url)
        } catch {
            discordErrorMessage = DiscordLinkService.errorMessage(for: error)
        }
    }

    // MARK: - Derived

    /// 担当アイドルの代表色 (StatTile/EntryCard の控えめなティント用)。
    private var pickBrandSeed: String? { pickIdols.first?.color ?? brandsById[pickIdols.first?.brandId ?? ""]?.color }
    private var secondaryBrandSeed: String? {
        if pickIdols.count > 1 { return pickIdols[1].color ?? brandsById[pickIdols[1].brandId]?.color }
        return nil
    }

    // MARK: - Helpers

    private func numberString(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// 最近見た項目を local カタログから解決して詳細シートを開く。見つからなければ何もしない。
    private func openRecent(_ item: RecentItem) async {
        switch item.kind {
        case .event:
            if let event = try? await AppContainer.shared.eventReading.event(id: item.entityId) { sheetDestination = .event(event) }
        case .song:
            if let song = try? await AppContainer.shared.songReading.song(id: item.entityId) { sheetDestination = .song(song) }
        case .idol:
            if let idol = try? await AppContainer.shared.idolReading.idol(id: item.entityId) { sheetDestination = .idol(idol) }
        }
    }

    // MARK: - Data Loading

    private func loadAll() async {
        await loadLocal()
        await loadNextLive()
        await loadServerActivity()
        await loadActivePoll()
    }

    /// 開催中のお題から1件を先頭カードに出す (誰でも閲覧可)。
    /// ユーザーがまだ投票していないお題を優先し、その中からランダムで選ぶ
    /// (毎回違うお題に触れてもらう導線)。全部投票済み/匿名なら全体からランダム。
    private func loadActivePoll() async {
        let polls = (try? await AppContainer.shared.communityVoting.polls(status: "active")) ?? []
        // 全票(3票)使い切ったお題はバナーに出さない。残票のあるものだけ対象。
        // (匿名は myVoteCount=nil=0 扱いなので常に対象)
        let votable = polls.filter { CommunityVoteLimit.remaining(myVoteCount: $0.myVoteCount ?? 0) > 0 }
        // 未投票を優先、その中からランダム。全部投票済みなら非表示 (nil)。
        let unvoted = votable.filter { ($0.myVoteCount ?? 0) == 0 }
        activePoll = (unvoted.isEmpty ? votable : unvoted).randomElement()
    }

    /// ローカル DB から担当・活動・参加ライブを読む。
    private func loadLocal() async {
        do {
            let brands = try await AppContainer.shared.brandReading.brands()
            brandsById = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0) })

            let mark = AppContainer.shared.markReading
            let pickIds = try await mark.markedEntityIds(entity: .idol, kind: .myPick)
            pickIdols = try await AppContainer.shared.idolReading.idols(ids: pickIds)

            // イベント参加 ∪ 公演参加→所属イベント を重複なしで。カウントとリストを一致させる。
            attendedEvents = try await AppContainer.shared.eventReading.attendedEventsWithDate()
            attendedCount = attendedEvents.count

            collectedSongIds = Array(try await mark.autoCollectedSongIds())
            collectedCount = collectedSongIds.count

            // お気に入りは曲・アイドル・ライブの全種別合算 (FavoritesListView 側で内訳タブ)。
            let songFav = try await mark.markedEntityIds(entity: .song, kind: .favorite).count
            let idolFav = try await mark.markedEntityIds(entity: .idol, kind: .favorite).count
            let eventFav = try await mark.markedEntityIds(entity: .event, kind: .favorite).count
            favoriteCount = songFav + idolFav + eventFav

            // 合計はコアに出させる (画面で足し算しない)。
            let expenses = try await AppContainer.shared.ledgerReading.expenses().map {
                ExpenseEntry(id: $0.id, date: $0.date, category: $0.categoryValue,
                             amount: $0.amount, showId: $0.showId, eventId: $0.eventId,
                             showLabel: nil, note: $0.note)
            }
            ledgerTotal = buildLedgerSummary(
                entries: expenses,
                period: .all,
                filter: LedgerFilter(year: "", categories: [], linkage: .all, eventId: "")
            ).total
        } catch {
            Logger.database.error("load_failed produce_local: \(error.localizedDescription)")
        }
    }

    /// 参加予定 (公演 / イベントの参加マーク) かお気に入りのイベントのうち、
    /// 今日以降でいちばん早い公演を 1 件。「今日以降でいちばん早い」はコア (`nextShowIndex`)。
    private func loadNextLive() async {
        let c = AppContainer.shared
        let today = JSTDay.today()
        do {
            let attendedShowIds = Set(try await c.markReading.markedEntityIds(entity: .show, kind: .attended))
            let attendedEventIds = Set(try await c.markReading.markedEntityIds(entity: .event, kind: .attended))
            let wholeEventIds = attendedEventIds.union(try await c.markReading.markedEntityIds(entity: .event, kind: .favorite))
            let showEventIds = try await c.showReading.eventIds(forShows: Array(attendedShowIds))
            // 過去のイベントの公演は読まない (参加済みが数百あっても未来のものだけ開く)。
            let events = try await c.eventReading.eventsByIds(Array(wholeEventIds.union(showEventIds)))
                .filter { nextShowIndex(dates: [$0.lastDate ?? $0.firstDate ?? ""], todayKey: today) != nil }
            var candidates: [(show: Show, event: Event)] = []
            for ew in events {
                let whole = wholeEventIds.contains(ew.event.id)
                for show in try await c.showReading.shows(eventId: ew.event.id)
                where whole || attendedShowIds.contains(show.id) {
                    candidates.append((show, ew.event))
                }
            }
            guard let i = nextShowIndex(dates: candidates.map(\.show.date), todayKey: today) else {
                nextLive = nil
                return
            }
            let (show, event) = candidates[Int(i)]
            let planned = attendedShowIds.contains(show.id) || attendedEventIds.contains(event.id)
            // 札の文言 (参加予定・あと3日 / 今日) はコア。お気に入りだけなら参加予定とは言わない。
            let status = planned
                ? attendanceStatus(attendedShowDates: [show.date], eventShowDates: [], eventMarked: false, today: today).label
                : "お気に入り"
            nextLive = NextLive(show: show, event: event, statusLabel: status)
        } catch {
            Logger.database.error("load_failed produce_next_live: \(error.localizedDescription)")
        }
    }

    /// サーバー指標 (予想数)。未ログインなら 0。
    /// 編集数 / 受Good は UI 上で出さなくなったため取得を停止 (badges API は別画面で必要なら再開)。
    private func loadServerActivity() async {
        guard AuthService.shared.isSignedIn else {
            predictionCount = 0
            return
        }
        if let predictions = try? await PredictionService.shared.myPredictions() {
            predictionCount = predictions.count
        }
    }
}

// MARK: - HeroIdolCard (担当ヒーロー)

/// 担当アイドルのヒーローカード。自色をまとい、IdolAvatar (二重輪) + 名前 + ブランド・CV +
/// 担当 chip + 詳細/出演ライブ ボタン。
private struct HeroIdolCard: View {
    let idol: Idol
    let brand: Brand?
    @Environment(\.colorScheme) private var scheme

    private var brandColor: String? { brand?.color }
    private var brandName: String { brand?.shortName ?? "" }

    var body: some View {
        let t = ImasTheme.derive(seed: idol.color, brand: brandColor, scheme: scheme)
        VStack(alignment: .leading, spacing: DS.sp4) {
            HStack(alignment: .top, spacing: DS.sp3) {
                IdolAvatarView(idol: idol, size: 56, isPick: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(idol.name)
                        .font(.imasHeadline.weight(.bold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    Text(metaLine)
                        .font(.imasFootnote)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                    ImasChip(text: "担当", systemImage: "heart.fill", style: .themed, seed: idol.color, brand: brandColor)
                        .padding(.top, DS.sp1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: DS.sp2) {
                NavigationLink(value: idol) {
                    Text("詳細")
                        .font(.imasSubhead.weight(.semibold))
                        .foregroundStyle(t.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(t.accent, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                }
                .buttonStyle(.plain)

                NavigationLink(value: idol) {
                    Label("出演ライブ", systemImage: "music.mic")
                        .font(.imasSubhead.weight(.semibold))
                        .foregroundStyle(t.chipText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(t.chipBg, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.sp4)
        .frame(width: 270, alignment: .leading)
        .background(t.heroSurface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rLG, style: .continuous)
                .strokeBorder(t.separator, lineWidth: 1)
        )
    }

    private var metaLine: String {
        var parts: [String] = []
        if !brandName.isEmpty { parts.append(brandName) }
        if let cv = VoiceActorDirectory.shared.current(for: idol.id), !cv.isEmpty { parts.append("CV \(cv)") }
        return parts.joined(separator: " ・ ")
    }
}

// MARK: - 次のライブ

/// 「次のライブ」カードに出す 1 公演。
struct NextLive: Equatable {
    let show: Show
    let event: Event
    /// `参加予定・あと2日` / `お気に入り`。
    let statusLabel: String
}

/// 次のライブ。札 + ライブ名 + 公演日 と、「セトリを予想」「コールを見る」。
private struct NextLiveCard: View {
    let next: NextLive
    var seed: String?
    var showsCallGuide: Bool
    let onPredict: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var title: String { eventDisplayName(next.event.name) }
    private var subLine: String {
        var parts = [next.show.date]
        if !next.show.name.isEmpty, next.show.name != next.event.name { parts.append(next.show.name) }
        return parts.joined(separator: " ・ ")
    }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: nil, scheme: scheme)
        VStack(alignment: .leading, spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(next.statusLabel)
                    .font(.imasCaption.weight(.bold))
                    .foregroundStyle(t.chipText)
                Text(title)
                    .font(.imasHeadline.weight(.bold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(2)
                Text(subLine)
                    .font(.imasFootnote)
                    .foregroundStyle(DS.ink2)
                    .lineLimit(1)
            }
            HStack(spacing: DS.sp2) {
                Button(action: onPredict) {
                    Text("セトリを予想")
                        .font(.imasSubhead.weight(.semibold))
                        .foregroundStyle(t.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(t.accent, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                }
                .buttonStyle(.plain)
                if showsCallGuide {
                    NavigationLink {
                        CallGuideDashboardView()
                    } label: {
                        Text("コールを見る")
                            .font(.imasSubhead.weight(.semibold))
                            .foregroundStyle(t.chipText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(t.chipBg, in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DS.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rLG, style: .continuous))
    }
}

// MARK: - 入口のまとまり (あそぶ / みんな / しらべる)

/// 見出し 1 行 + アイコン 4 つずつの並び。入口を同じ大きさのカードで縦に積まず、
/// 種類ごとに 1 枚にまとめる。
private struct ProduceShortcutGroup<Accessory: View, Items: View>: View {
    let title: String
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let items: () -> Items

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.imasSubhead.weight(.bold)).foregroundStyle(DS.ink)
                Spacer(minLength: DS.sp3)
                accessory()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.sp2), count: 4), spacing: DS.sp3) {
                items()
            }
            .buttonStyle(.plain)
        }
        .padding(DS.sp4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rMD, style: .continuous))
    }
}

/// 入口のアイコン 1 つ。ImasEntryCard と同じ色の角丸アイコン + 短い名前。
private struct ProduceShortcutIcon: View {
    let systemImage: String
    let label: String
    var seed: String?
    var isLoading = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: nil, scheme: scheme)
        VStack(spacing: DS.sp2) {
            ZStack {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.imasScaled(20, weight: .regular))
                        .foregroundStyle(t.chipText)
                }
            }
            .frame(width: 44, height: 44)
            .background(t.chipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(label)
                .font(.imasCaption)
                .foregroundStyle(DS.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - RecentChip (最近見た)

/// 「最近見た」横スクロールのチップ。エンティティ色のリードドット + 種別アイコン + 名前。
private struct RecentChip: View {
    let item: RecentItem

    private var icon: String {
        switch item.kind {
        case .event: return "music.mic"
        case .song: return "music.note"
        case .idol: return "person.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.imasScaled( 12, weight: .semibold))
                .foregroundStyle(DS.ink3)
            Text(item.name)
                .font(.imasSubhead)
                .lineLimit(1)
                .foregroundStyle(DS.ink)
        }
        .padding(.horizontal, DS.sp3)
        .padding(.vertical, DS.sp2)
        .background(DS.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.sep, lineWidth: 1))
        .frame(maxWidth: 200)
    }
}
