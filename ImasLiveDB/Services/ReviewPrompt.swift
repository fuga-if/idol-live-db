import Foundation

/// App Store のレビュー依頼を出すタイミングを決める。
///
/// 依頼そのものは SwiftUI の `@Environment(\.requestReview)` が出す。ここは
/// 「いつ声を掛けるか」だけを持ち、View から `shouldAsk()` で問い合わせる形にしてある
/// (`requestReview` は Environment のアクションなので View からしか呼べない)。
///
/// 設計の前提:
/// - **OS 側にも上限がある** (1年で3回まで) が、それは最後の砦であって、こちらが
///   むやみに呼んでよい理由にはならない。枠を浪費すると、本当に出したい場面で出ない。
/// - **作業の途中では聞かない**。参加ライブを登録した直後のような「一区切りついた瞬間」
///   に限る。入力中に被せると邪魔なだけで、評価も下がる。
/// - **初回起動では聞かない**。まだアプリの価値が分かっていない人に聞いても意味がない。
enum ReviewPrompt {
    /// 好機を何回踏んだら聞くか。1回目 (初めて参加ライブを登録した直後) は
    /// まだアプリを使い込んでいないので見送る。
    private static let requiredMilestones = 3
    /// 初回起動から何日経てば聞いてよいか。
    private static let requiredDays = 3
    /// 一度聞いたら次に聞くまでの最短日数。OS の上限 (年3回) より手前で自制する。
    private static let cooldownDays = 120

    private enum Key {
        static let firstLaunch = "review_prompt.first_launch_at"
        static let milestones = "review_prompt.milestone_count"
        static let lastAsked = "review_prompt.last_asked_at"
        static let lastAskedVersion = "review_prompt.last_asked_version"
    }

    private static var defaults: UserDefaults { .standard }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// アプリ起動時に呼ぶ。初回起動日を記録するだけ。
    static func registerLaunch() {
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.firstLaunch)
        }
    }

    /// 「一区切りついた」瞬間に呼ぶ (参加ライブの登録など)。
    /// ここでは数えるだけで、依頼は出さない。出すのは次に落ち着いた画面へ戻ったとき。
    static func noteMilestone() {
        defaults.set(defaults.integer(forKey: Key.milestones) + 1, forKey: Key.milestones)
    }

    /// 今レビューを依頼してよいか。`true` を返したときは「聞いた」ものとして記録する
    /// (呼び出し側が実際に `requestReview()` するのが前提)。
    ///
    /// ⚠️ OS が実際にダイアログを出したかは**アプリからは分からない**。出なかった場合も
    /// 「聞いた」扱いになるが、それでよい。ここで再挑戦を許すと、OS の上限に阻まれている
    /// 相手に何度も呼び続けることになり、枠が空いた瞬間に脈絡のない場面で出てしまう。
    static func shouldAsk() -> Bool {
        guard defaults.integer(forKey: Key.milestones) >= requiredMilestones else { return false }
        // 同じバージョンで二度は聞かない。
        guard defaults.string(forKey: Key.lastAskedVersion) != currentVersion else { return false }

        let now = Date().timeIntervalSince1970
        let firstLaunch = defaults.double(forKey: Key.firstLaunch)
        guard firstLaunch > 0, now - firstLaunch >= Double(requiredDays) * 86_400 else {
            return false
        }
        let lastAsked = defaults.double(forKey: Key.lastAsked)
        if lastAsked > 0, now - lastAsked < Double(cooldownDays) * 86_400 { return false }

        defaults.set(now, forKey: Key.lastAsked)
        defaults.set(currentVersion, forKey: Key.lastAskedVersion)
        return true
    }

    /// ユーザーが自分から「評価する」を選んだときに開く URL。
    ///
    /// この経路で `requestReview()` を使ってはいけない。OS の都合で無視されることがあり、
    /// **押しても何も起きないボタン**になる。自分から評価しに来た人には App Store の
    /// レビュー投稿画面をそのまま開く。
    static var writeReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreId)?action=write-review")
    }

    /// App Store の ID。`itunes.apple.com/lookup?bundleId=com.fugaif.ImasLiveDB` で確認した値。
    private static let appStoreId = "6763342297"
}
