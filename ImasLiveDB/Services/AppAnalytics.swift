import Foundation
import SwiftUI
import OSLog
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
import FirebaseCore   // FirebaseApp.configure() は FirebaseCore モジュール
#endif

/// アナリティクスの薄いファサード。プロバイダ (現在 Firebase Analytics) を差し替え可能にする。
///
/// 方針:
/// - **PII を送らない**。画面名・イベント名・非個人の軽量パラメータ (件数/種別/真偽) のみ。
/// - Firebase SDK 未リンク (`canImport` false) や未 configure 時は **OSLog にフォールバック**して
///   no-op にする。これで `GoogleService-Info.plist` 導入前でも計測コードを先に仕込める。
/// - 計測点 (screen / event) は呼び出し側に散らさず、ここと `View.trackScreen` に集約する。
enum AppAnalytics {
    private static let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "analytics")

    /// テスト実行中か。`XCTestConfigurationFilePath` は xcodebuild test が必ず入れる。
    ///
    /// テストの起動を計測に混ぜたくないのが第一の理由。加えて **CI では
    /// `GoogleService-Info.plist` がダミー**で (秘匿ファイルなので gitignore、
    /// ワークフローがプレースホルダを置いている)、その値で `FirebaseApp.configure()` を
    /// 呼ぶと `FIRInstallations` が NSException を投げて**テストが起動前に abort する**。
    /// Swift から ObjC の例外は捕まえられないので、呼ばないことでしか防げない。
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// アプリ起動時に1度呼ぶ。`GoogleService-Info.plist` がある時だけ Firebase を有効化する
    /// (無ければ計測は OSLog のみで no-op。クラッシュさせない)。
    static func start() {
        #if canImport(FirebaseAnalytics)
        guard !isRunningTests else {
            logger.info("analytics: テスト実行中 → 計測は OSLog のみ")
            return
        }
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            logger.info("analytics: Firebase configured")
        } else {
            logger.info("analytics: GoogleService-Info.plist なし → 計測は OSLog のみ")
        }
        #endif
    }

    /// 画面表示。`name` は安定したスクリーン識別子 (例 "events", "event_detail")。
    static func screen(_ name: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [AnalyticsParameterScreenName: name])
        #endif
        logger.debug("screen: \(name, privacy: .public)")
    }

    /// ボタン等のタップ計測。**単一イベント `button_tap` + `label` パラメータ**で送る
    /// (ボタン毎に別イベント名にすると Firebase のイベント名上限(500)を超えるため)。
    /// `label` は安定識別子 (例 "poll_detail.vote", "event_detail.share")。Button の action 内で呼ぶ。
    static func tap(_ label: String) {
        event("button_tap", ["label": label])
    }

    /// 任意イベント (フリクション計測等)。`params` は非個人の軽量値のみ。
    /// イベント名・キーは英小文字スネークケース (Firebase 制約)。
    static func event(_ name: String, _ params: [String: Any] = [:]) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(name, parameters: params.isEmpty ? nil : params)
        #endif
        logger.debug("event: \(name, privacy: .public)")
    }
}

extension View {
    /// この画面の表示を計測する (`onAppear` で `screen_view` を送る)。
    /// `name` は画面ごとに安定した識別子を渡す。
    func trackScreen(_ name: String) -> some View {
        onAppear { AppAnalytics.screen(name) }
    }
}
