import os
import SwiftUI

/// プロデュース (tab4・担当ダッシュボード)。
/// 新デザインシステムへ移植。担当アイドルのヒーロー横スクロール → あなたの活動グリッド →
/// 最近見た → 参加したライブ → 入口カード (調べる / みんなの動き) の縦 1 枚構成。
/// 既存の遷移 (RecentEdits / Calendar / IntroDon / MyPredictions / Leaderboard) と
/// 統計ブロック (loadStats) は全て維持する。
struct ProduceTabView: View {
    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine

    // 担当アイドル (マイピック)。各カードが自色をまとうヒーロー。
    @State private var pickIdols: [Idol] = []
    /// brandId → Brand。ヒーローのブランド名・色フォールバックに使う。
    @State private var brandsById: [String: Brand] = [:]

    // あなたの活動サマリ。
    @State private var attendedCount: Int = 0
    @State private var editCount: Int = 0
    @State private var receivedGoodCount: Int = 0
    @State private var predictionCount: Int = 0
    @State private var favoriteCount: Int = 0
    @State private var collectedCount: Int = 0
    /// お気に入り / 記録曲タイルのタップ遷移先で表示する楽曲ID。
    @State private var favoriteSongIds: [String] = []
    @State private var collectedSongIds: [String] = []

    // 参加したライブ。
    @State private var attendedEvents: [EventWithDate] = []

    // 統計 (既存 StatsView 由来)。「調べる」入口カードのプレビューに使う最新公演。
    @State private var latestShow: Show?

    /// 「最近見た」タップ時の詳細遷移先。
    @State private var sheetDestination: DetailDestination?
    @State private var navPath = NavigationPath()
    /// プロデュース先頭に出す「開催中のお題」(最も票が集まっているもの)。
    @State private var activePoll: Poll?
    @State private var showInbox = false
    @State private var inboxStore = AnnouncementStore.shared

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp6) {
                    oshiSection
                    featuredPollSection
                    activitySection
                    recentsSection
                    attendedSection
                    entrySection
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
            .navigationDestination(for: Idol.self) { idol in
                IdolDetailView(idol: idol)
            }
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
            .navigationDestination(for: ActivityRoute.self) { route in
                activityDestination(route)
            }
            // みんなの投票 (PollListView) は自前スタックを持たず、ここ(親の1スタック)に
            // 遷移先を登録する。これで「一覧→詳細」の2階層目を同じスタック上に push できる。
            .navigationDestination(for: PollRoute.self) { route in
                switch route {
                case .list:
                    PollListView()
                case let .detail(pollId):
                    PollDetailView(pollId: pollId)
                case .hallOfFame:
                    PollHallOfFameView()
                }
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
            NavigationLink(value: PollRoute.detail(poll.id)) {
                VStack(alignment: .leading, spacing: DS.sp3) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                        Text("投票受付中").font(.imasCaption.bold())
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
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - あなたの活動 (StatTile グリッド)

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasSectionHeader(title: "あなたの活動", tight: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.sp3), count: 3), spacing: DS.sp3) {
                statTileLink(route: .attendedEvents) {
                    ImasStatTile(systemImage: "music.mic", value: numberString(attendedCount), label: "参加ライブ", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myEdits) {
                    ImasStatTile(systemImage: "square.and.pencil", value: numberString(editCount), label: "編集", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myEdits) {
                    ImasStatTile(systemImage: "hands.clap.fill", value: numberString(receivedGoodCount), label: "受Good", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .myPredictions) {
                    ImasStatTile(systemImage: "sparkles", value: numberString(predictionCount), label: "予想", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .favoriteSongs) {
                    ImasStatTile(systemImage: "star.fill", value: numberString(favoriteCount), label: "お気に入り", brand: pickBrandSeed, tappable: true)
                }
                statTileLink(route: .collectedSongs) {
                    ImasStatTile(systemImage: "music.note", value: numberString(collectedCount), label: "記録曲", brand: pickBrandSeed, tappable: true)
                }
            }
        }
    }

    /// あなたの活動タイルの遷移先。値ベース push にして二重 push をスロットルで防ぐ。
    enum ActivityRoute: Hashable {
        case attendedEvents, myEdits, myPredictions, favoriteSongs, collectedSongs
    }

    @ViewBuilder
    private func activityDestination(_ route: ActivityRoute) -> some View {
        switch route {
        case .attendedEvents: AttendedEventsListView(events: attendedEvents)
        case .myEdits: MyEditsView()
        case .myPredictions: MyPredictionsView()
        case .favoriteSongs: songListDestination(ids: favoriteSongIds, title: "お気に入りの楽曲")
        case .collectedSongs: songListDestination(ids: collectedSongIds, title: "記録した楽曲")
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
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 参加したライブ (EventRow 一覧)

    @ViewBuilder
    private var attendedSection: some View {
        if !attendedEvents.isEmpty {
            VStack(alignment: .leading, spacing: DS.sp3) {
                ImasSectionHeader(title: "参加したライブ", count: "\(attendedEvents.count)")
                ImasListContainer {
                    ForEach(Array(attendedEvents.prefix(5).enumerated()), id: \.element.id) { index, ew in
                        if index > 0 {
                            Divider().background(DS.sep).padding(.leading, DS.sp4)
                        }
                        NavigationLink(value: ew.event) {
                            ProduceEventRow(
                                event: ew.event,
                                dateText: ew.dateRange,
                                seedHex: ew.event.brandId.flatMap { brandsById[$0]?.color }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if attendedEvents.count > 5 {
                    NavigationLink {
                        AttendedEventsListView(events: attendedEvents)
                    } label: {
                        Text("全て見る (\(attendedEvents.count)件)")
                            .font(.imasSubhead.weight(.medium))
                            .foregroundStyle(DS.sys)
                            .padding(.horizontal, DS.sp2)
                    }
                }
            }
        }
    }

    // MARK: - 入口カード (調べる / みんなの動き) + その他導線

    private var entrySection: some View {
        VStack(spacing: DS.sp3) {
            NavigationLink {
                StatsView()
            } label: {
                ImasEntryCard(
                    systemImage: "chart.bar.xaxis",
                    title: "調べる",
                    preview: statsEntryPreview,
                    brand: pickBrandSeed
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                RecentEditsView()
            } label: {
                ImasEntryCard(
                    systemImage: "person.2.fill",
                    title: "みんなの動き",
                    preview: "コーレス・参考動画など最近のコミュニティ投稿",
                    brand: secondaryBrandSeed
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                GamesHubView()
            } label: {
                ImasEntryCard(
                    systemImage: "gamecontroller.fill",
                    title: "クイズ・ゲーム",
                    preview: "イントロドン・アイドル当て・カラー合わせ",
                    brand: pickBrandSeed
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MyPredictionsView()
            } label: {
                ImasEntryCard(
                    systemImage: "checklist",
                    title: "マイ予想",
                    preview: predictionCount > 0 ? "投票した予想 \(predictionCount)件" : "セトリを予想して的中を狙おう"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                PollListView()
                    .environment(database)
            } label: {
                ImasEntryCard(
                    systemImage: "chart.bar.doc.horizontal",
                    title: "みんなの投票",
                    preview: "お題に推しを投票・ランキング",
                    brand: pickBrandSeed
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Derived

    /// 担当アイドルの代表色 (StatTile/EntryCard の控えめなティント用)。
    private var pickBrandSeed: String? { pickIdols.first?.color ?? brandsById[pickIdols.first?.brandId ?? ""]?.color }
    private var secondaryBrandSeed: String? {
        if pickIdols.count > 1 { return pickIdols[1].color ?? brandsById[pickIdols[1].brandId]?.color }
        return nil
    }

    private var statsEntryPreview: String {
        if let show = latestShow {
            return "最新公演 \(show.name) ほか"
        }
        return "披露回数・お気に入り・出演ランキング…"
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
        await loadStats()
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
        let votable = polls.filter { ($0.myVoteCount ?? 0) < 3 }
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

            favoriteSongIds = try await mark.markedEntityIds(entity: .song, kind: .favorite)
            let idolFav = try await mark.markedEntityIds(entity: .idol, kind: .favorite).count
            let eventFav = try await mark.markedEntityIds(entity: .event, kind: .favorite).count
            favoriteCount = favoriteSongIds.count + idolFav + eventFav
        } catch {
            Logger.database.error("load_failed produce_local: \(error.localizedDescription)")
        }
    }

    private func loadStats() async {
        do {
            latestShow = try await AppContainer.shared.showReading.latestShow()
        } catch {
            Logger.database.error("load_failed produce_stats: \(error.localizedDescription)")
        }
    }

    /// サーバー指標 (編集数 / 受 Good / 予想数)。未ログインなら 0。
    private func loadServerActivity() async {
        guard AuthService.shared.isSignedIn else {
            editCount = 0
            receivedGoodCount = 0
            predictionCount = 0
            return
        }
        if let badges = await BadgeService.shared.currentUserBadges() {
            editCount = badges.editCount
            receivedGoodCount = badges.goodsReceived
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
                        .padding(.top, 2)
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
        if let cv = idol.currentVoiceActor, !cv.isEmpty { parts.append("CV \(cv)") }
        return parts.joined(separator: " ・ ")
    }
}

// MARK: - ProduceEventRow (参加したライブ行)

/// 参加したライブの行。リードバー (合同は虹) + ライブ名 + 日付 + chevron。
/// 共有の EventRowView が private のため、同等レイアウトをここで構成する。
private struct ProduceEventRow: View {
    let event: Event
    var dateText: String? = nil
    var seedHex: String? = nil

    private var isJoint: Bool { !event.jointBrandIdList.isEmpty }

    var body: some View {
        HStack(spacing: DS.sp3) {
            ImasLeadBar(seed: seedHex, rainbow: isJoint)
                .frame(height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(eventDisplayName(event.name))
                    .font(.imasSubhead.weight(.semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                if let dateText, !dateText.isEmpty {
                    Text(dateText)
                        .font(.imasCaption)
                        .foregroundStyle(DS.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.imasScaled( 13, weight: .semibold))
                .foregroundStyle(DS.ink3)
        }
        .padding(.horizontal, DS.sp4)
        .padding(.vertical, DS.sp3)
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
