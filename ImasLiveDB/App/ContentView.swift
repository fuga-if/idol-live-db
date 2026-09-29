import SwiftUI
import UIKit

extension Notification.Name {
    /// 全タブ共通で発火させる「設定・マイページを開く」通知。
    /// 各タブの toolbar 歯車が post し、ContentView の sheet が拾う。
    static let openSettings = Notification.Name("openSettings")
}


struct ContentView: View {
    @State private var selection: AppDestination = {
        if let raw = ProcessInfo.processInfo.environment["INITIAL_TAB"], let idx = Int(raw),
           let tab = RootTab(rawValue: idx) {
            return tab.destination
        }
        return .schedule
    }()
    /// 行き先の一覧 (並び・見出し・タブバーに載るか) はコアが決める。
    private let navSections = appNavigationSections(lyricsAvailable: LyricsFeature.isAvailable)
    private var primaryItems: [NavItem] { navSections.flatMap(\.items).filter(\.inTabBar) }
    /// サイドバーだけに出る見出し。狭い画面ではタブバーに載らない。
    private var secondarySections: [NavSection] { navSections.filter { $0.title != nil } }
    /// タブを跨いだ検索の引き継ぎ (「他のタブに N 件」を押されたとき)。
    @State private var crossTab = CrossTabSearch.shared
    /// 設定・マイページ sheet (全タブ共通)。
    @State private var showSettings = false
    /// deeplink (Universal Links / imaslivedb://) で開く詳細 sheet。
    @State private var deeplinkDestination: DetailDestination?
    /// 他の sheet 提示中などで即時提示できなかった deeplink 遷移先。
    /// TabView レベルの sheet が閉じたタイミング (onDismiss) で再提示する。
    @State private var pendingDeeplinkDestination: DetailDestination?
    /// deeplink の ID がローカル DB に見つからなかった時のアラート。
    @State private var showDeeplinkNotFound = false
    /// deeplink 解決中に DB エラーが起きた時のアラート (not found とは別事象)。
    @State private var showDeeplinkLoadFailed = false

    /// 担当(推し)カラーをアプリ全体テーマに使う設定 (MyPage で解決済みの hex)。
    /// 空 = 無効 (既定の AccentColor を使う)。
    @AppStorage("theme_oshi_color") private var themeOshiColorHex: String = ""

    /// 文字サイズ設定 (極小 0.7 / 小 0.85 / 中 1.0)。環境に流して設定変更時に
    /// アプリ全体を再評価させ、スケール済みの Font トークンを反映する。
    @AppStorage("text_scale") private var textScale: Double = 1.0

    @Environment(AppDatabase.self) private var database
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    /// レビュー依頼。OS が出すかどうかを決めるので、呼んでも出ないことがある。
    @Environment(\.requestReview) private var requestReview

    /// アプリ全体のアクセント tint。担当テーマ有効時のみ色を返し、無効時は nil
    /// (= 既定の AccentColor アセットにフォールバック)。
    private var themeTint: Color? {
        themeOshiColorHex.isEmpty ? nil : Color(hexString: themeOshiColorHex)
    }

    /// 届いたリンク。アプリのルートが受けて渡してくる (受け口は 1 つ)。開いたら nil に戻す。
    @Binding private var incomingURL: URL?

    /// TabBar のアクティブ tint だけ .label にする。`.tint(.primary)` を View 階層にかけると
    /// 配下の tint 依存表示 (Toggle・Link 等の標準コントロール) まで巻き添えになるため、
    /// SwiftUI の `.tint()` ではなく UITabBar.appearance() を使う。
    /// (chip 系は既に Color.accentColor をやめ ImasTheme 由来に統一済みなので影響しない)
    init(incomingURL: Binding<URL?> = .constant(nil)) {
        _incomingURL = incomingURL
        UITabBar.appearance().tintColor = .label
    }

    var body: some View {
        rootTabs
            .background { destinationShortcuts }
        .tint(themeTint)
        // 再生中バーの引き直し。View ごとに持たせると 5 タブで 5 回引くので、
        // 状態が変わったとき 1 回だけここで回す。
        .task(id: MusicKitService.shared.playbackKey) { await NowPlayingModel.shared.refresh() }
        .task {
            AppAnalytics.screen(selection.analyticsKey)
            // 一覧やピッカーは Idol の配列しか持たないので、CV 名は辞書から引く。
            // 行ごとに DB を叩くと N+1 になる (300件程度なのでまとめて持つ)。
            await VoiceActorDirectory.shared.load()
            ReviewPrompt.registerLaunch()
            // 聞くのは「参加ライブを登録した次に立ち上げたとき」になる。作業の途中や
            // 登録直後に被せず、落ち着いてタブ画面を見ている場面で1度だけ出す。
            // 条件を満たしていなければ ReviewPrompt 側が false を返して何も起きない。
            if ReviewPrompt.shouldAsk() {
                AppAnalytics.tap("review_prompt.shown")
                requestReview()
            }
        }
        .onChange(of: selection) { _, dest in AppAnalytics.screen(dest.analyticsKey) }
        // 「他のタブに N 件」を押されたら、そのタブへ移る。語の受け渡しは
        // 移った先の一覧が `CrossTabSearch.take(for:)` で拾う。
        .onChange(of: crossTab.target) { _, target in
            if let target { selection = target.destination }
        }
        .environment(\.imasTextScale, textScale)
        // アプリ既定フォントを imas (スケール対応) にする。これで明示フォント未指定の Text や
        // Picker/Toggle 等コントロールのラベルも文字サイズ設定に追従する。
        // (ナビタイトル/タブバー等の UIKit chrome は OS 管轄なので対象外)
        .environment(\.font, .imasBody)
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        // 参加を付けた直後の「チケット代を記録しますか」。参加登録の入口は
        // 一覧のスワイプ・公演の参加シート・セトリ画面と複数あるので、
        // 出すのは**アプリのルート 1 箇所**にまとめる。
        .ticketExpensePrompt()
        .sheet(isPresented: $showSettings, onDismiss: presentPendingDeeplink) {
            MyPageView().environment(database).environment(syncEngine)
        }
        // 起動直後に届いたものも、開いている間に届いたものも、ここで 1 度だけ開く。
        .task(id: incomingURL) {
            guard let url = incomingURL else { return }
            incomingURL = nil
            handleDeeplink(url)
        }
        .sheet(item: $deeplinkDestination, onDismiss: presentPendingDeeplink) { dest in
            DetailSheetView(destination: dest)
                .environment(database)
                // 実際に提示できた時点で pending を消化する (提示に失敗した場合は残り、
                // 次の sheet dismiss 時に onDismiss → presentPendingDeeplink で復活する)。
                .onAppear { pendingDeeplinkDestination = nil }
        }
        .alert("リンク先が見つかりません", isPresented: $showDeeplinkNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("このイベント・公演はまだ同期されていない可能性があります。しばらくしてからもう一度お試しください。")
        }
        .alert("読み込みに失敗しました", isPresented: $showDeeplinkLoadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("リンク先の読み込み中にエラーが発生しました。もう一度お試しください。")
        }
    }

    // MARK: - 行き先 (タブバー / サイドバー)

    /// 狭い画面はタブバー、広い画面 (iPad / Mac) はサイドバーになる。
    /// 中身はどちらも同じ画面 — サイドバーだけに出る行き先も、狭い画面では
    /// プロデュースの入口カードから開くのと同じ View を使う (出し方を iPhone と揃える)。
    @ViewBuilder
    private var rootTabs: some View {
        if #available(iOS 18, *) {
            AdaptiveRootTabs(selection: $selection, primary: primaryItems, secondary: secondarySections)
        } else {
            TabView(selection: $selection) {
                ForEach(primaryItems, id: \.destination) { item in
                    DestinationScreen(destination: item.destination)
                        .tabItem { Label(item.label, systemImage: item.destination.systemImage) }
                        .tag(item.destination)
                }
            }
        }
    }

    /// ハードウェアキーボードの ⌘1〜⌘5。番号の割り当てはコアが決める。
    private var destinationShortcuts: some View {
        ForEach(navSections.flatMap(\.items).filter { $0.shortcutDigit != nil }, id: \.destination) { item in
            Button(item.label) { selection = item.destination }
                .keyboardShortcut(KeyEquivalent(Character(String(item.shortcutDigit!))), modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// deeplink (Universal Links / imaslivedb://) を解決して該当ページへ遷移する。
    /// 対象外 URL は無視、未知 ID / DB エラーはアラート (クラッシュ・空白画面にしない)。
    private func handleDeeplink(_ url: URL) {
        guard let link = DeeplinkRouter.parse(url) else { return }
        // 着地タブは対象の住所に合わせる (イベント/公演=ライブ、お題=プロデュース)。
        // シートを閉じた後に「元居た場所」として自然な一覧が残るようにする。
        selection = switch link {
        case .poll: .produce
        default: .events
        }
        let destination: DetailDestination?
        do {
            destination = try DeeplinkRouter.destination(for: link, database: database)
        } catch {
            showDeeplinkLoadFailed = true
            return
        }
        guard let destination else {
            showDeeplinkNotFound = true
            return
        }
        pendingDeeplinkDestination = destination
        if showSettings {
            // 開いている sheet を閉じる → onDismiss → presentPendingDeeplink で提示する。
            showSettings = false
        } else {
            presentPendingDeeplink()
        }
        // 起動シート (オンボーディング/今日の1曲) など TabView 外の modal と競合して
        // 即時提示が無反応に終わった場合の保険。pending が未消化なら一度だけ再試行する。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            presentPendingDeeplink()
        }
    }

    /// 未提示の deeplink 遷移先があれば sheet で提示する。提示失敗 (他 modal との競合)
    /// に備え、pending の消化は提示自体ではなく sheet content の onAppear で行う。
    private func presentPendingDeeplink() {
        guard let destination = pendingDeeplinkDestination else { return }
        deeplinkDestination = destination
    }
}

/// 各タブ最上位の toolbar に置く「設定・マイページ」ボタン (全タブ共通)。
/// ContentView の sheet を通知で開く。プロデュースタブ限定だった導線を全画面に広げる。
struct SettingsToolbarButton: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("設定・マイ")
    }
}

/// 行き先 1 つぶんの画面。タブバーでもサイドバーでも同じものを出す。
private struct DestinationScreen: View {
    let destination: AppDestination

    var body: some View {
        switch destination {
        case .schedule: CalendarView().bottomBarsInset()
        case .events: EventListView().bottomBarsInset()
        case .songs: SongListView().bottomBarsInset()
        case .idols: IdolListView().bottomBarsInset()
        case .produce: ProduceTabView().bottomBarsInset()
        // StatsView は自前の NavigationStack を持つ (プロデュースから push しても同じ)。
        case .stats: StatsView().bottomBarsInset()
        case .timeline: NavigationStack { BrandTimelineView() }.bottomBarsInset()
        case .polls:
            NavigationStack {
                PollListView()
                    .navigationDestination(for: PollRoute.self) { PollRouteView(route: $0) }
            }
            .bottomBarsInset()
        case .callGuide: NavigationStack { CallGuideDashboardView() }.bottomBarsInset()
        case .communityActivity: NavigationStack { RecentEditsView() }.bottomBarsInset()
        case .tagActivity: NavigationStack { TagActivityView() }.bottomBarsInset()
        case .games: NavigationStack { GamesHubView() }.bottomBarsInset()
        }
    }
}

/// iOS 18 以降のルート。狭い画面はタブバー、広い画面はサイドバーに自動で切り替わる。
@available(iOS 18, *)
private struct AdaptiveRootTabs: View {
    @Binding var selection: AppDestination
    let primary: [NavItem]
    let secondary: [NavSection]
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// サイドバーだけの行き先は狭い画面では載せない。`defaultVisibility(.hidden)` だけだと
    /// iPhone のタブバーが 5 枠を超えたと数えて「その他」に畳み、プロデュースが隠れる。
    private var sidebarSections: [NavSection] { sizeClass == .compact ? [] : secondary }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(primary, id: \.destination) { item in
                tab(item)
            }
            ForEach(sidebarSections, id: \.title) { section in
                TabSection(section.title ?? "") {
                    ForEach(section.items, id: \.destination) { item in
                        tab(item).defaultVisibility(.hidden, for: .tabBar)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // 広い画面は最初からサイドバーで開く (タブバーへの切替はツールバーのボタンで残る)。
        .defaultAdaptableTabBarPlacement(.sidebar)
        // iPad の画面分割などで狭くなったとき、サイドバーだけの行き先に居たら
        // 同じ画面の入口があるプロデュースへ戻す (空の選択を残さない)。
        .onChange(of: sizeClass) { _, newValue in
            if newValue == .compact, !primary.contains(where: { $0.destination == selection }) {
                selection = .produce
            }
        }
    }

    private func tab(_ item: NavItem) -> some TabContent<AppDestination> {
        Tab(item.label, systemImage: item.destination.systemImage, value: item.destination) {
            DestinationScreen(destination: item.destination)
        }
    }
}
