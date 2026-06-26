import SwiftUI
import UIKit

extension Notification.Name {
    /// 全タブ共通で発火させる「全体検索を開く」通知。
    /// 各タブの toolbar `globe` ボタンが post し、 ContentView の sheet が拾う。
    static let openGlobalSearch = Notification.Name("openGlobalSearch")
    /// 全タブ共通で発火させる「設定・マイページを開く」通知。
    /// 各タブの toolbar 歯車が post し、ContentView の sheet が拾う。
    static let openSettings = Notification.Name("openSettings")
}

struct ContentView: View {
    @State private var selectedTab: Int = {
        if let raw = ProcessInfo.processInfo.environment["INITIAL_TAB"], let idx = Int(raw) {
            return idx
        }
        return 0
    }()
    @State private var showSearch = false
    /// 個別検索から引き継いだ全体検索の初期クエリ。
    @State private var searchQuery = ""
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

    /// アプリ全体のアクセント tint。担当テーマ有効時のみ色を返し、無効時は nil
    /// (= 既定の AccentColor アセットにフォールバック)。
    private var themeTint: Color? {
        themeOshiColorHex.isEmpty ? nil : Color(hexString: themeOshiColorHex)
    }

    /// TabBar のアクティブ tint だけ .label にする (.tint(.primary) を View 階層に
    /// かけると配下の Color.accentColor まで上書きされて chip 系が真っ白になるため、
    /// SwiftUI の .tint() ではなく UITabBar.appearance() を使う。
    init() {
        UITabBar.appearance().tintColor = .label
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // 確定 IA: スケジュール / ライブ / 楽曲 / アイドル / プロデュース。
            // スケジュールがデフォルト着地点。マイ/設定はプロデュース右上の歯車から開く。
            CalendarView()
                .syncStatusBarInset()
                .tabItem { Label("スケジュール", systemImage: "calendar") }
                .tag(0)
            EventListView()
                .syncStatusBarInset()
                .tabItem { Label("ライブ", systemImage: "music.mic") }
                .tag(1)
            SongListView()
                .syncStatusBarInset()
                .tabItem { Label("楽曲", systemImage: "music.note.list") }
                .tag(2)
            IdolListView()
                .syncStatusBarInset()
                .tabItem { Label("アイドル", systemImage: "person.3") }
                .tag(3)
            ProduceTabView()
                .syncStatusBarInset()
                .tabItem { Label("プロデュース", systemImage: "star.fill") }
                .tag(4)
        }
        .tint(themeTint)
        .task { AppAnalytics.screen(Self.tabName(selectedTab)) }
        .onChange(of: selectedTab) { _, tab in AppAnalytics.screen(Self.tabName(tab)) }
        .environment(\.imasTextScale, textScale)
        // アプリ既定フォントを imas (スケール対応) にする。これで明示フォント未指定の Text や
        // Picker/Toggle 等コントロールのラベルも文字サイズ設定に追従する。
        // (ナビタイトル/タブバー等の UIKit chrome は OS 管轄なので対象外)
        .environment(\.font, .imasBody)
        .onReceive(NotificationCenter.default.publisher(for: .openGlobalSearch)) { note in
            searchQuery = (note.object as? String) ?? ""
            showSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSearch, onDismiss: presentPendingDeeplink) {
            GlobalSearchView(initialQuery: searchQuery)
        }
        .sheet(isPresented: $showSettings, onDismiss: presentPendingDeeplink) {
            MyPageView().environment(database).environment(syncEngine)
        }
        .onOpenURL { url in
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

    /// deeplink (Universal Links / imaslivedb://) を解決して該当ページへ遷移する。
    /// 対象外 URL は無視、未知 ID / DB エラーはアラート (クラッシュ・空白画面にしない)。
    /// アナリティクス用のタブ識別子 (確定 IA: 0=スケジュール / 1=ライブ / 2=楽曲 / 3=アイドル / 4=プロデュース)。
    private static func tabName(_ tab: Int) -> String {
        switch tab {
        case 0: return "schedule"
        case 1: return "events"
        case 2: return "songs"
        case 3: return "idols"
        case 4: return "produce"
        default: return "tab_\(tab)"
        }
    }

    private func handleDeeplink(_ url: URL) {
        guard let link = DeeplinkRouter.parse(url) else { return }
        // 着地タブはライブ (Events)。
        selectedTab = 1
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
        if showSearch || showSettings {
            // 開いている sheet を閉じる → onDismiss → presentPendingDeeplink で提示する。
            showSearch = false
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

/// 各タブ最上位の toolbar に置く「全体検索」ボタン。
/// タブ内検索 (このタブの一覧を絞り込む) とは役割が異なり、楽曲/アイドル/ライブを横断して探す。
struct GlobalSearchToolbarButton: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openGlobalSearch, object: nil)
        } label: {
            Image(systemName: "sparkle.magnifyingglass")
        }
        .accessibilityLabel("全体検索")
        .accessibilityHint("楽曲・アイドル・ライブを横断して検索します")
    }
}

/// タブ内検索で結果が無い時に表示する空状態。同じ語句で「全体検索」へ 1 タップで橋渡しする。
/// (タブ内検索=この一覧の絞り込み、全体検索=横断検索、という役割の違いを自然な導線で繋ぐ)
struct InTabSearchEmptyView: View {
    let query: String

    var body: some View {
        ContentUnavailableView {
            Label("見つかりません", systemImage: "magnifyingglass")
        } description: {
            Text("「\(query)」はこのタブにありません")
        } actions: {
            Button {
                NotificationCenter.default.post(name: .openGlobalSearch, object: query)
            } label: {
                Label("全体から検索", systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear { AppAnalytics.event("search_empty") }
    }
}
