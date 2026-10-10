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
    /// 名刺入れの枚数。
    @State private var cardCaseCount: Int = 0
    @State private var collectedSongIds: [String] = []
    // ローカル履歴 (投稿・投票) は @Observable で参照するだけでカウントが見える。
    @State private var voteLog = LocalPollVoteLog.shared
    @State private var imageService = CustomImageService.shared
    @State private var contributionLog = LocalContributionLog.shared
    /// 自分の編集に付いた Good の新着と、自分が入れたセトリの先週の閲覧数。
    @State private var feedbackStore = ContributionFeedbackStore.shared

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
    /// タブバーの並び (外した画面は「そのほか」に出す)。
    @AppStorage(TabBarSettings.storageKey) private var tabBarOrder: String = ""
    /// 「そのほか」から開いた画面。
    @State private var otherDestination: AppDestination?

    /// タブバーから外した主な画面と AI チャット (並べ方はコア)。
    private var otherItems: [NavItem] {
        TabBarSettings.sections(tabBarOrder).first { $0.title == "そのほか" }?.items ?? []
    }
    @State private var discordErrorMessage: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack(path: $navPath) {
            ImasPage {
                oshiSection
                nextLiveSection
                featuredPollSection
                shortcutSection
                activitySection
                recentsSection
            }
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
            .imasErrorAlert("Discord と連携できませんでした", message: $discordErrorMessage)
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
                case .callGuide: CallGuideDashboardView()
                }
            }
            // みんなの投票 (PollListView) は自前スタックを持たず、ここ(親の1スタック)に
            // 遷移先を登録する。これで「一覧→詳細」の2階層目を同じスタック上に push できる。
            .navigationDestination(for: PollRoute.self) { PollRouteView(route: $0) }
            // タブバーから外した画面はシートで開く (画面ごと自前のナビゲーションを持つため、押し込まない)。
            .sheet(item: $otherDestination) { dest in
                DestinationScreen(destination: dest)
            }
            .sheet(item: $sheetDestination) { dest in
                DetailSheetView(destination: dest)
                    .environment(database)
            }
            .refreshable {
                await syncEngine.performIncrementalSync(database: database)
                await loadAll()
            }
            .task { await loadAll() }
            .onReceive(NotificationCenter.default.publisher(for: .producerCardsChanged)) { _ in
                Task { cardCaseCount = (try? await AppContainer.shared.producerCards.receivedCount()) ?? cardCaseCount }
            }
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
            // 投票一覧は値ベース (PollRoute.list) で push する。クロージャで PollListView() を
            // 直接 push すると中の値ベース NavigationLink(value: PollRoute.detail) と混ざり、
            // 詳細へ進むたびに PollList が二重 push される。
            ImasFeatureCard(
                eyebrow: "お題",
                title: poll.title,
                subtitle: "\(poll.totalVotes ?? 0)票 · \(poll.entryCount ?? 0)候補",
                metric: pollRemaining(poll.endsAt),
                primary: .init(title: "投票する", systemImage: "hand.thumbsup") {
                    if NavThrottle.allow() { navPath.append(PollRoute.detail(poll.id)) }
                },
                secondary: .init(title: "ほかのお題", systemImage: "list.bullet") {
                    if NavThrottle.allow() { navPath.append(PollRoute.list) }
                }
            )
        }
    }

    /// お題の残り時間 (カードの右上の数)。
    private func pollRemaining(_ endsAt: Date) -> ImasFeatureCard<EmptyView>.Metric {
        let secs = endsAt.timeIntervalSinceNow
        let days = Int(secs / 86400)
        if days >= 1 { return .init(prefix: "あと", value: "\(days)", unit: "日") }
        let hours = Int(secs / 3600)
        if hours >= 1 { return .init(prefix: "あと", value: "\(hours)", unit: "時間") }
        return .init(prefix: "まもなく終了", value: "")
    }

    private var oshiSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.gapLoose) {
            oshiPasses
            // 担当の入場証を 1 枚に広げた P名刺へ (会場での名刺交換)。
            ImasTicketRow(systemImage: "person.text.rectangle", title: "P名刺",
                          subtitle: "担当と参加の記録を 1 枚にして、会場で交換する") {
                if NavThrottle.allow() { navPath.append(ActivityRoute.producerCard) }
            }
        }
    }

    @ViewBuilder
    private var oshiPasses: some View {
        if pickIdols.isEmpty {
            ImasCard {
                ImasEmptyState(
                    systemImage: "heart",
                    title: "担当アイドルがいません",
                    message: "アイドル詳細の「担当」を付けると、ここに大きく出ます。"
                )
            }
        } else {
            ImasCarousel(data: pickIdols) { idol in
                let brand = brandsById[idol.brandId]
                ImasPass(
                    leftImprint: "PRODUCER PASS",
                    rightImprint: "担当",
                    title: idol.name,
                    subtitle: oshiMetaLine(idol, brand: brand),
                    seed: idol.color,
                    brand: brand?.color,
                    onOpen: { if NavThrottle.allow() { navPath.append(idol) } }
                ) {
                    // アイコンは写真か判子で必ず出す (担当なので二重の輪)。
                    ImasAvatar(label: idol.shortName, seed: idol.color, brand: brand?.color,
                               size: 60, isPick: true, imageURL: imageService.imageURL(for: idol.id))
                }
            }
        }
    }

    /// 担当カードの副題 (ブランド · CV)。
    private func oshiMetaLine(_ idol: Idol, brand: Brand?) -> String {
        var parts: [String] = []
        if let name = brand?.shortName, !name.isEmpty { parts.append(name) }
        if let cv = VoiceActorDirectory.shared.current(for: idol.id), !cv.isEmpty { parts.append("CV \(cv)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - あなたの活動 (StatTile グリッド)

    private var activitySection: some View {
        ImasSection("あなたの記録") {
            ImasStatGrid(columns: 4) {
                statTileLink(route: .attendedEvents) {
                    ImasStatTile(systemImage: "music.mic", value: numberString(attendedCount), label: "参加ライブ", seed: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myPredictions) {
                    ImasStatTile(systemImage: "sparkles", value: numberString(predictionCount), label: "予想", seed: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .favorites) {
                    ImasStatTile(systemImage: "star.fill", value: numberString(favoriteCount), label: "お気に入り", seed: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myContributions) {
                    ImasStatTile(systemImage: "square.and.pencil", value: numberString(contributionLog.total), label: "投稿", seed: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myVotes) {
                    ImasStatTile(systemImage: "chart.bar.doc.horizontal", value: numberString(voteLog.votedPollCount), label: "投票", seed: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .collectedSongs) {
                    ImasStatTile(systemImage: "music.note", value: numberString(collectedCount), label: "回収", seed: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .mastery) {
                    ImasStatTile(systemImage: "chart.bar.fill", value: numberString(masteryCount), label: "習熟度", seed: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .ledger) {
                    ImasStatTile(systemImage: "yensign.circle.fill", value: formatYen(amount: ledgerTotal), label: "収支", seed: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .cardCase) {
                    ImasStatTile(systemImage: "tray.full.fill", value: numberString(cardCaseCount), label: "名刺入れ", seed: pickBrandSeed, tappable: true)
                }
            }
            feedbackCards
            Button {
                if NavThrottle.allow() { navPath.append(ActivityRoute.playlists) }
            } label: {
                ImasNavRow(title: "プレイリスト", subtitle: "曲を並べて Apple Music で続けて聴く",
                           systemImage: "music.note.list")
            }
            .buttonStyle(.imasRow)
        }
    }

    /// 自分の編集への手応え。Good の新着と、先週セトリが見られた数 (どちらも 0 なら出さない)。
    /// 押すと「マイ投稿」へ (そこで新着を既読にする)。
    @ViewBuilder
    private var feedbackCards: some View {
        if feedbackStore.newLyricsCount > 0 {
            statTileLink(route: .myContributions) {
                ImasEntryCard(systemImage: "text.quote",
                              title: "あなたが投稿した歌詞が \(feedbackStore.newLyricsCount) 曲公開されました",
                              preview: (feedbackStore.feedback?.lyrics?.likeTotal ?? 0) > 0
                                  ? "ここ好き \(feedbackStore.feedback?.lyrics?.likeTotal ?? 0)" : nil,
                              seed: pickBrandSeed)
            }
        }
        if feedbackStore.newGoodTotal > 0 {
            statTileLink(route: .myContributions) {
                ImasEntryCard(systemImage: "hand.thumbsup.fill",
                              title: "あなたの編集に Good が \(feedbackStore.newGoodTotal) 件届きました",
                              preview: feedbackStore.feedback?.goods.first(where: { $0.newGoodCount > 0 })?.summary,
                              seed: pickBrandSeed)
            }
        }
        if let reach = feedbackStore.feedback?.setlistReach, reach.viewers > 0 {
            statTileLink(route: .myContributions) {
                ImasEntryCard(systemImage: "eye.fill",
                              title: "先週、あなたが入れたセトリが のべ \(reach.viewers) 人に見られました",
                              preview: "\(reach.shows) 公演のセトリ",
                              seed: pickBrandSeed)
            }
        }
    }

    /// あなたの活動タイルの遷移先。値ベース push にして二重 push をスロットルで防ぐ。
    enum ActivityRoute: Hashable {
        case attendedEvents, myPredictions, favorites, myVotes, myContributions, collectedSongs, mastery, ledger
        case playlists
        case producerCard, cardCase
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
        case .playlists: PlaylistsView().environment(database)
        case .producerCard: MyProducerCardView()
        case .cardCase: CardCaseView()
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
        .buttonStyle(.imasPress)
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
            ImasSection("最近見た") {
                ImasChipFlow {
                    ForEach(recents) { item in
                        Button { Task { await openRecent(item) } } label: {
                            ImasChip(text: item.name, systemImage: recentIcon(item.kind), style: .outlined)
                        }
                        .buttonStyle(.imasPress)
                    }
                }
            }
        }
    }

    private func recentIcon(_ kind: RecentKind) -> String {
        switch kind {
        case .event: return "music.mic"
        case .song: return "music.note"
        case .idol: return "person.fill"
        }
    }

    // MARK: - 次のライブ (参加予定 / お気に入りの直近公演)

    enum NextLiveRoute: Hashable {
        case prediction(Show)
        case callGuide
    }

    @ViewBuilder
    private var nextLiveSection: some View {
        if let next = nextLive {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                ImasTicket(
                    label: next.isPlanned ? "参加予定" : "お気に入り",
                    imprint: next.isPlanned ? "ADMIT ONE" : nil,
                    title: eventDisplayName(next.event.name),
                    metaImprint: dateLabel(date: next.show.date, today: JSTDay.today()),
                    meta: (!next.show.name.isEmpty && next.show.name != next.event.name) ? next.show.name : nil,
                    seed: next.event.brandId.flatMap { brandsById[$0]?.color } ?? pickBrandSeed,
                    countdown: next.daysUntil.map {
                        $0 == 0 ? .init(prefix: "", value: "今日", unit: "") : .init(value: "\($0)", unit: "DAYS")
                    },
                    onOpen: {
                        if NavThrottle.allow() { navPath.append(NextLiveRoute.prediction(next.show)) }
                    }
                )
                HStack(spacing: DS.Space.gap) {
                    Button {
                        AppAnalytics.tap("produce_tab.next_live_predict")
                        if NavThrottle.allow() { navPath.append(NextLiveRoute.prediction(next.show)) }
                    } label: {
                        Label("セトリを予想する", systemImage: "sparkles")
                    }
                    .buttonStyle(.imas(.primary, size: .medium))
                    if LyricsFeature.isAvailable {
                        Button {
                            if NavThrottle.allow() { navPath.append(NextLiveRoute.callGuide) }
                        } label: {
                            Label("コールを見る", systemImage: "hands.clap")
                        }
                        .buttonStyle(.imas(.secondary, size: .medium))
                    }
                }
            }
        }
    }

    // MARK: - 入口 (あそぶ / みんな / しらべる)

    private var shortcutSection: some View {
        VStack(spacing: DS.Space.section) {
            if !otherItems.isEmpty {
                ImasShortcutGroup("そのほか") {
                    ForEach(otherItems, id: \.analyticsKey) { item in
                        Button { otherDestination = item.destination } label: {
                            ImasShortcutTile(systemImage: item.destination.systemImage, label: item.label, seed: pickBrandSeed)
                        }
                    }
                }
            }

            ImasShortcutGroup("あそぶ") {
                if let s = resumeStore.latest {
                    NavigationLink {
                        QuizResumeDestination(suspended: s)
                    } label: {
                        ImasShortcutTile(
                            systemImage: "play.fill", label: "つづきから",
                            detail: "\(gameTitle(s.kind)) " + String(format: "Q.%02d", min(s.plays.count + 1, s.total)),
                            seed: pickBrandSeed
                        )
                    }
                }
                NavigationLink { IntroDonHomeView() } label: {
                    ImasShortcutTile(systemImage: "music.note.list", label: "イントロドン", seed: pickBrandSeed)
                }
                if LyricsFeature.isAvailable {
                    NavigationLink { LyricsQuizSetupView() } label: {
                        ImasShortcutTile(systemImage: "text.quote", label: "歌詞クイズ", seed: pickBrandSeed)
                    }
                }
                NavigationLink { SetlistQuizSetupView() } label: {
                    ImasShortcutTile(systemImage: "list.number", label: "セトリ当て", seed: pickBrandSeed)
                }
                NavigationLink { GamesHubView() } label: {
                    ImasShortcutTile(systemImage: "gamecontroller", label: "すべてのゲーム", seed: pickBrandSeed)
                }
            }

            ImasShortcutGroup("みんな") {
                NavigationLink { RecentEditsView() } label: {
                    ImasShortcutTile(systemImage: "person.2", label: "編集の動き", seed: pickBrandSeed)
                }
                NavigationLink { TagActivityView() } label: {
                    ImasShortcutTile(systemImage: "number", label: "タグ", seed: pickBrandSeed)
                }
                // 歌詞タブと同じ根拠 (JASRAC 許諾) で出し分ける。歌詞が出ないビルドでは
                // コールガイドを書く場所そのものが無いので、入口も出さない。
                if LyricsFeature.isAvailable {
                    NavigationLink { CallGuideDashboardView() } label: {
                        ImasShortcutTile(systemImage: "hands.clap", label: "コールガイド", seed: pickBrandSeed)
                    }
                }
                // 開催中のお題が無いと上の「ほかのお題」が出ないので、そのときだけここに置く。
                if activePoll == nil {
                    NavigationLink(value: PollRoute.list) {
                        ImasShortcutTile(systemImage: "chart.bar.doc.horizontal", label: "みんなの投票", seed: pickBrandSeed)
                    }
                }
                // 編集の協力者に Discord のロールを渡す入口。セッションで本人を確かめるので
                // ログイン中だけ出す (未ログインで押しても 401 になるだけ)。
                if AuthService.shared.isSignedIn {
                    Button {
                        Task { await openDiscordLink() }
                    } label: {
                        ImasShortcutTile(systemImage: "rosette", label: "Discord のロールを受け取る",
                                         seed: pickBrandSeed, isLoading: isLinkingDiscord)
                    }
                }
            }

            ImasShortcutGroup("しらべる") {
                NavigationLink { StatsView() } label: {
                    ImasShortcutTile(systemImage: "chart.bar.xaxis", label: "統計", seed: pickBrandSeed)
                }
                NavigationLink { BrandTimelineView(initialBrandId: pickIdols.first?.brandId) } label: {
                    ImasShortcutTile(systemImage: "calendar.day.timeline.left", label: "年表", seed: pickBrandSeed)
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

    /// 担当アイドルの代表色 (記録・入口の記号と、次のライブにブランドの色が無いときのペンライト)。
    private var pickBrandSeed: String? { pickIdols.first?.color ?? brandsById[pickIdols.first?.brandId ?? ""]?.color }

    // MARK: - Helpers

    private func numberString(_ value: Int) -> String {
        Self.decimal.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// 書式は作るのが重いので 1 つを使い回す (描き直しのたびに作らない)。
    private static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

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
            cardCaseCount = try await AppContainer.shared.producerCards.receivedCount()

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
            // 何日後かはコア (`attendanceStatus`)。お気に入りだけなら参加予定とは言わない。
            let status = attendanceStatus(attendedShowDates: [show.date], eventShowDates: [], eventMarked: false, today: today)
            nextLive = NextLive(show: show, event: event, isPlanned: planned, daysUntil: status.daysUntil)
        } catch {
            Logger.database.error("load_failed produce_next_live: \(error.localizedDescription)")
        }
    }

    /// サーバー指標 (予想数)。未ログインなら 0。
    /// 編集数 / 受Good は UI 上で出さなくなったため取得を停止 (badges API は別画面で必要なら再開)。
    private func loadServerActivity() async {
        await feedbackStore.refresh()
        guard AuthService.shared.isSignedIn else {
            predictionCount = 0
            return
        }
        if let predictions = try? await PredictionService.shared.myPredictions() {
            predictionCount = predictions.count
        }
    }
}

// MARK: - 次のライブ

/// 「次のライブ」カードに出す 1 公演。
struct NextLive: Equatable {
    let show: Show
    let event: Event
    /// 参加予定 (公演 / イベントの参加マーク)。false ならお気に入りのライブ。
    let isPlanned: Bool
    /// 公演まで何日か (0 = 今日)。日付が年・月までしか無い公演では nil。
    let daysUntil: UInt32?
}
