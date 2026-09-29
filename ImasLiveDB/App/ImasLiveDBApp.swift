import Nuke
import SwiftUI
import UIKit

@main
struct ImasLiveDBApp: App {
    /// 端末の DB を開く流れ。開けるまで ContentView は作らない (DB を読む画面が先に動かないように)。
    @State private var boot = DatabaseBoot()
    @State private var syncEngine = CloudKitSyncEngine()
    /// 届いたリンク (ウィジェット・共有されたリンク)。ContentView が開いたら nil に戻す。
    ///
    /// 受け口はここ 1 つにする。DB を開いている間は ContentView が居ないうえ、開き終えて
    /// ContentView に差し替わる途中に届くと、ContentView 側の `onOpenURL` がまだ無く、
    /// 取りこぼした (起動直後にリンクを開くと、何も起きないことがあった)。
    @State private var incomingURL: URL?

    /// オンボーディング (HelpView) を初回起動で 1 度だけ自動表示するためのフラグ。
    /// オープン編集モデルへの刷新に伴い v2 へ更新 (既存ユーザーにも新しい説明を 1 度再表示する)。
    private static let onboardingStorageKey = "has_seen_help_v2"
    /// 「今日の1曲」モーダルを 1 日 1 回だけ出すための最終表示日 (YYYY-MM-DD)。
    private static let dailyVoteKey = "daily_vote_last_date"

    /// 起動時に出すシート。オンボーディング優先、無ければ日替わりの今日の1曲。
    private enum LaunchSheet: Int, Identifiable { case onboarding, announcements, dailyVote; var id: Int { rawValue } }
    @State private var launchSheet: LaunchSheet?
    @State private var updateService = UpdateCheckService.shared
    /// 起動時 reseed が失敗したときに 1 度だけ出すアラートの表示フラグ。
    @State private var showReseedAlert = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // アナリティクス起動 (GoogleService-Info.plist がある時だけ Firebase 有効化。無ければ no-op)。
        AppAnalytics.start()

        // 端末にしか無いデータの書き込み失敗は、どの画面で起きてもアラートで知らせる。
        LocalWriteFailure.presenter = LocalWriteFailureAlert.present
        BrandColors.startObservingReloads()

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
            // 「今日はもう出したか」の判定はコア (game_progress) が持つ。リセットの単位は
            // 連続達成日数と同じ端末ローカル日なので、日付キーも `DailyPick` から渡す。
            let gate = gameProgressDailySheetGate(
                lastShownDay: UserDefaults.standard.string(forKey: Self.dailyVoteKey),
                todayKey: DailyPick.dayKey())
            // 出す/出さないに関わらず今日を書き戻す (書き忘れで同じ日に何度も出るのを防ぐ)。
            UserDefaults.standard.set(gate.lastShownDay, forKey: Self.dailyVoteKey)
            _launchSheet = State(initialValue: gate.shouldShow ? .dailyVote : nil)
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
            Group {
                switch boot.state {
                case .preparing:
                    DatabasePreparingView()
                case .failed(let detail):
                    DatabaseRecoveryView(detail: detail) {
                        Task { await boot.prepare() }
                    }
                case .ready(let database):
                    root(database)
                }
            }
            .task { await boot.prepare() }
            .onOpenURL { url in
                // deeplink 着地時は起動シート (オンボーディング/日替わりピック) を閉じて
                // 詳細ページの提示 (ContentView が incomingURL を開く) を優先する。
                // オンボーディング既読フラグは onDismiss で通常どおり確定される。
                launchSheet = nil
                incomingURL = url
            }
        }
    }

    /// DB を開けた後の画面。
    private func root(_ appDatabase: AppDatabase) -> some View {
        ContentView(incomingURL: $incomingURL)
            .environment(appDatabase)
            .environment(syncEngine)
            .task {
                // 起動時 reseed が失敗していれば、旧データで動作中であることをユーザーに知らせる。
                if appDatabase.reseedFailureMessage != nil {
                    showReseedAlert = true
                }
                // テストホストとして起動されたときは、外に出る副作用を起こさない。
                // DB の準備とスナップショットのロードは止めない (テストがそれを読む)。
                guard !ProcessInfo.processInfo.isRunningTests else { return }
                // MusicKit の認可は起動時には取らない。使う画面 (曲詳細・セトリ・イントロクイズ・
                // フル再生) が、使う直前に `MusicKitService.requestAuthorization()` で取る。
                // 以降はいずれも初回描画に不要な非緊急処理。 .utility の detached に落として
                // メインスレッド/協調プールの高優先度枠を初回レンダリングに明け渡す。
                // CloudKit sync は fire-and-forget で fullSync が走っても UI が
                // 待たされないようにする (既存ローカルデータはすぐ表示される)。
                // 進捗は SyncEngine.state を見て UI 側で控えめバナー等に出せる。
                Task.detached(priority: .utility) {
                    await syncEngine.performStartupSync(database: appDatabase)
                }
                // sessionToken / isAdmin を起動時に最新化。
                // sessionToken が期限切れだった場合はここで再ログインを促す UI に切り替わる。
                Task.detached(priority: .utility) { await AuthService.shared.refreshMe() }
                // ローカル通知を再スケジュール (既認可の場合のみ実行される)。
                Task.detached(priority: .utility) { await NotificationService.shared.rescheduleAll(database: appDatabase) }
                // 担当画像ウィジェット用に App Group へギャラリーをミラー。
                Task.detached(priority: .utility) { await WidgetImageBridge.sync(database: appDatabase) }
                // 情報ウィジェット(次のライブ/今日の1曲/チケット締切)用スナップショットを更新。
                Task.detached(priority: .utility) { await InfoWidgetBridge.sync() }
                // App Store に新版が出ていたらお知らせ (iTunes Lookup で自動判定)。
                Task.detached(priority: .utility) { await updateService.check() }
            }
            .onChange(of: scenePhase) { _, phase in
                // フォアグラウンド復帰で同期を再開/継続する。フルsyncが途中で中断されて
                // いれば残りステップ/チャンクから再開、そうでなければ差分syncで最新化。
                // (再入は SyncEngine 側でガード済みなので二重には走らない)
                guard phase == .active, !ProcessInfo.processInfo.isRunningTests else { return }
                Task.detached(priority: .utility) {
                    await syncEngine.performStartupSync(database: appDatabase)
                }
                // アプリを開かない日が続いた後でも、開いた時点で当日の内容に戻す。
                Task.detached(priority: .utility) { await InfoWidgetBridge.sync() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .coreSnapshotDidLoad)) { _ in
                // 同期やローカル編集でマスタが変わったら、情報ウィジェットの中身も作り直す。
                guard !ProcessInfo.processInfo.isRunningTests else { return }
                Task.detached(priority: .utility) { await InfoWidgetBridge.sync() }
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
                    DailyPickSheet()
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
            .alert("データ更新に失敗しました", isPresented: $showReseedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appDatabase.reseedFailureMessage ?? "")
            }
            // コールガイドの見た目確認用 (DEBUG のみ)。CALL_GUIDE_PREVIEW 未指定なら何も出ない。
            #if DEBUG
            .fullScreenCover(isPresented: .constant(CallGuidePreviewHarness.envMode != nil)) {
                CallGuidePreviewHarness(mode: CallGuidePreviewHarness.envMode ?? .view)
            }
            #endif
    }
}
