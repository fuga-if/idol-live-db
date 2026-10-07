import Foundation
import os

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "contribution_feedback")

/// データを入れた人への手応え (Good の新着・セトリの閲覧数) と、公演の奥付の状態。
///
/// - Good の新着: 最後に見た Good の時刻 (`lastSeenGoodAt`) より後のものを新着として数える。
///   「マイ投稿」を開いたら既読にする。
/// - 公演の閲覧: 公演ページを開いたら、1 端末 1 週 1 公演 1 回だけ送る (判定はコア `showViewDecision`)。
/// - 奥付に名前を載せるか: サーバの設定 (`/auth/me` の `creditOptIn`) の写しを持つ。
@Observable @MainActor
final class ContributionFeedbackStore {
    static let shared = ContributionFeedbackStore()

    private let api: any ContributionFeedbackReading
    private let defaults: UserDefaults

    private init(api: any ContributionFeedbackReading = AppContainer.shared.contributionFeedback,
                 defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        self.lastSeenGoodAt = Int64(defaults.integer(forKey: Keys.lastSeenGoodAt))
        self.creditOptIn = defaults.bool(forKey: Keys.creditOptIn)
    }

    private enum Keys {
        static let lastSeenGoodAt = "contribution_feedback_seen_good_at"
        static let creditOptIn = "contribution_credit_opt_in"
        static let viewWeek = "show_view_report_week"
        static let viewReported = "show_view_report_ids"
    }

    /// 最新の手応え。未ログイン・未取得は nil。
    private(set) var feedback: ContributionFeedback?
    /// 最後に見た Good の時刻 (epoch ミリ秒)。
    private(set) var lastSeenGoodAt: Int64
    /// 奥付に表示名を載せるか (既定は載せない)。
    private(set) var creditOptIn: Bool
    private var lastFetchedAt: Date?
    /// 同じ公演の奥付を開き直すたびに叩かない (サーバ側もエッジで 1 時間)。
    private var creditsCache: [String: ShowCredits] = [:]

    #if DEBUG
    private static let isFake = ProcessInfo.processInfo.environment["FAKE_FEEDBACK"] == "1"
    #else
    private static let isFake = false
    #endif

    /// まだ見ていない Good の数。
    var newGoodTotal: Int { feedback?.newGoodTotal ?? 0 }

    /// 手応えを取り直す。`force` でなければ 10 分以内の再取得はしない。
    func refresh(force: Bool = false) async {
        guard AuthService.shared.isSignedIn || Self.isFake else {
            feedback = nil
            return
        }
        if !force, let at = lastFetchedAt, Date().timeIntervalSince(at) < 600 { return }
        do {
            feedback = try await api.myFeedback(since: lastSeenGoodAt)
            lastFetchedAt = Date()
        } catch {
            logger.warning("feedback_fetch_failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 届いた Good を見た (「マイ投稿」を閉じた)。いまの新着を既読にし、手元の新着の数も 0 にする。
    func markGoodsSeen() {
        guard let current = feedback, let latest = current.goods.map(\.latestGoodAt).max(), latest > lastSeenGoodAt else { return }
        lastSeenGoodAt = latest
        defaults.set(Int(latest), forKey: Keys.lastSeenGoodAt)
        feedback = ContributionFeedback(
            goods: current.goods.map { $0.seen() },
            newGoodTotal: 0,
            setlistReach: current.setlistReach
        )
    }

    /// 公演ページを開いた。今週まだ送っていなければ送る (失敗したら覚えず、次に開いたとき送り直す)。
    func reportShowView(showId: String) async {
        let decision = showViewDecision(
            storedWeek: defaults.string(forKey: Keys.viewWeek) ?? "",
            reported: defaults.stringArray(forKey: Keys.viewReported) ?? [],
            showId: showId,
            nowEpochSeconds: Int64(Date().timeIntervalSince1970)
        )
        if decision.report {
            do {
                try await api.reportShowViews(showIds: [showId])
            } catch {
                logger.warning("show_view_report_failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        defaults.set(decision.week, forKey: Keys.viewWeek)
        defaults.set(decision.reportedAfter, forKey: Keys.viewReported)
    }

    /// 公演の奥付の行 (並びと「ほか N 人」はコア `showCreditLines`)。取れなければ空。
    func creditLines(showId: String) async -> [ShowCreditLine] {
        let credits: ShowCredits
        if let hit = creditsCache[showId] {
            credits = hit
        } else {
            do {
                credits = try await api.showCredits(showId: showId)
                creditsCache[showId] = credits
            } catch {
                logger.warning("show_credits_failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
        return showCreditLines(
            setlist: ShowCreditInput(names: credits.setlist.names, total: UInt32(max(credits.setlist.total, 0))),
            performers: ShowCreditInput(names: credits.performers.names, total: UInt32(max(credits.performers.total, 0)))
        )
    }

    /// サーバ (`/auth/me`) の設定を写す。
    func adoptCreditOptIn(_ isOn: Bool) {
        creditOptIn = isOn
        defaults.set(isOn, forKey: Keys.creditOptIn)
    }

    /// 奥付に名前を載せるかを切り替える。サーバが受け付けた値を写す。
    func setCreditOptIn(_ isOn: Bool) async throws {
        let saved = try await api.setCreditOptIn(isOn)
        adoptCreditOptIn(saved)
    }
}
