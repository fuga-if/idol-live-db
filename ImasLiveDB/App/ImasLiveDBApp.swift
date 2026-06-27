import Nuke
import SwiftUI
import UIKit

@main
struct ImasLiveDBApp: App {
    @State private var appDatabase = AppDatabase.shared
    @State private var syncEngine = CloudKitSyncEngine()

    /// オンボーディング (HelpView) を初回起動で 1 度だけ自動表示するためのフラグ。
    /// オープン編集モデルへの刷新に伴い v2 へ更新 (既存ユーザーにも新しい説明を 1 度再表示する)。
    private static let onboardingStorageKey = "has_seen_help_v2"
    /// 「今日の1曲」モーダルを 1 日 1 回だけ出すための最終表示日 (YYYY-MM-DD)。
    private static let dailyVoteKey = "daily_vote_last_date"

    /// 起動時に出すシート。オンボーディング優先、無ければ日替わりの今日の1曲。
    private enum LaunchSheet: Int, Identifiable { case onboarding, announcements, dailyVote; var id: Int { rawValue } }
    @State private var launchSheet: LaunchSheet?
    @State private var updateService = UpdateCheckService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // アナリティクス起動 (GoogleService-Info.plist がある時だけ Firebase 有効化。無ければ no-op)。
        AppAnalytics.start()

        // 曲アートワーク (mzstatic CDN のリモート URL) を永続ディスクキャッシュする。
        // 全 LazyImage は表示サイズへの Resize processor 付きなので、元 JPEG を保持しても
        // 肥大しすぎず、再起動後の再ダウンロードを回避できる。アイドル/ブランド画像は
        // ローカル file URL なので対象外 (キャッシュ不要)。
        ImagePipeline.shared = ImagePipeline {
            $0.dataCache = try? DataCache(name: "com.fugaif.ImasLiveDB.images")
            $0.dataCachePolicy = .automatic
        }

        if ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1" {
            UserDefaults.standard.set("grid", forKey: "idol_list_mode")
        }
        // ContentView の onAppear は TabView 内の遷移で再発火するため、
        // App init 時の 1 回だけ初期値を確定させる。
        let screenshot = ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
        let seen = UserDefaults.standard.bool(forKey: Self.onboardingStorageKey)
        if screenshot {
            _launchSheet = State(initialValue: nil)
        } else if !seen {
            _launchSheet = State(initialValue: .onboarding)
        } else if Self.shouldShowAnnouncementsOnUpdate() {
            // アプデ後の初回起動で未読のお知らせがあれば、新機能としてお知らせを開く。
            _launchSheet = State(initialValue: .announcements)
        } else {
            let today = DailySongVoteSheet.dayKey()
            if UserDefaults.standard.string(forKey: Self.dailyVoteKey) != today {
                UserDefaults.standard.set(today, forKey: Self.dailyVoteKey)
                _launchSheet = State(initialValue: .dailyVote)
            } else {
                _launchSheet = State(initialValue: nil)
            }
        }
    }

    /// アプリのバージョンが前回起動から変わっていて、かつ未読のお知らせがある時だけ true。
    /// 一度判定したらそのバージョンを記録し、同バージョンでは二度と自動表示しない。
    private static func shouldShowAnnouncementsOnUpdate() -> Bool {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lastSeen = UserDefaults.standard.string(forKey: AnnouncementDefaults.seenVersionKey)
        guard lastSeen != current else { return false }
        UserDefaults.standard.set(current, forKey: AnnouncementDefaults.seenVersionKey)
        // 初インストール (lastSeen == nil) はオンボーディングに任せ、お知らせは自動表示しない。
        guard lastSeen != nil else { return false }
        return AnnouncementDefaults.hasUnread()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDatabase)
                .environment(syncEngine)
                .task {
                    #if !targetEnvironment(simulator)
                    await MusicKitService.shared.requestAuthorization()
                    #endif
                    // CloudKit sync は fire-and-forget で fullSync が走っても UI が
                    // 待たされないようにする (既存ローカルデータはすぐ表示される)。
                    // 進捗は SyncEngine.state を見て UI 側で控えめバナー等に出せる。
                    Task.detached(priority: .utility) {
                        await syncEngine.performStartupSync(database: appDatabase)
                    }
                    // sessionToken / isAdmin を起動時に最新化。
                    // sessionToken が期限切れだった場合はここで再ログインを促す UI に切り替わる。
                    Task { await AuthService.shared.refreshMe() }
                    // ローカル通知を再スケジュール (既認可の場合のみ実行される)。
                    Task { await NotificationService.shared.rescheduleAll(database: appDatabase) }
                    // 担当画像ウィジェット用に App Group へギャラリーをミラー。
                    Task { await WidgetImageBridge.sync(database: appDatabase) }
                    // 情報ウィジェット(次のライブ/今日の1曲/チケット締切)用スナップショットを更新。
                    Task { await InfoWidgetBridge.sync(database: appDatabase) }
                    // App Store に新版が出ていたらお知らせ (iTunes Lookup で自動判定)。
                    Task { await updateService.check() }
                }
                .onChange(of: scenePhase) { _, phase in
                    // フォアグラウンド復帰で同期を再開/継続する。フルsyncが途中で中断されて
                    // いれば残りステップ/チャンクから再開、そうでなければ差分syncで最新化。
                    // (再入は SyncEngine 側でガード済みなので二重には走らない)
                    guard phase == .active else { return }
                    Task.detached(priority: .utility) {
                        await syncEngine.performStartupSync(database: appDatabase)
                    }
                }
                .onOpenURL { _ in
                    // deeplink 着地時は起動シート (オンボーディング/今日の1曲) を閉じて
                    // 詳細ページの提示 (ContentView 側の onOpenURL) を優先する。
                    // オンボーディング既読フラグは onDismiss で通常どおり確定される。
                    launchSheet = nil
                }
                .sheet(item: $launchSheet, onDismiss: {
                    // オンボーディングを見たフラグは閉じたら確定 (今日の1曲を閉じた場合は既に true)。
                    UserDefaults.standard.set(true, forKey: Self.onboardingStorageKey)
                }) { item in
                    switch item {
                    case .onboarding:
                        HelpView()
                    case .announcements:
                        InboxView()
                    case .dailyVote:
                        DailySongVoteSheet()
                            .environment(appDatabase)
                    }
                }
                .alert("新しいバージョンがあります", isPresented: Binding(
                    get: { updateService.shouldNotify },
                    set: { if !$0 { updateService.dismiss() } }
                )) {
                    Button("更新") {
                        if let u = updateService.storeURL { UIApplication.shared.open(u) }
                        updateService.dismiss()
                    }
                    Button("後で", role: .cancel) { updateService.dismiss() }
                } message: {
                    Text("バージョン \(updateService.availableVersion ?? "") が App Store で公開されています。")
                }
        }
    }
}
