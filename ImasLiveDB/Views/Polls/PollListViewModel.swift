import Foundation
import Observation

/// お題一覧 (開催中 / 終了) の取得状態 (Presentation)。
/// データ取得は `CommunityVoting` プロトコル越しなのでフェイク注入で単体テストできる。
///
/// 開催中タブは締切の近い順に 20 件ずつ、末尾まで見たら続きを読む (一度に全件は読まない)。
/// 終了タブは月 (日本時間) ごとに読む。最初は新しい月だけ取り、末尾まで見たら 1 か月ずつさかのぼる
/// (件数で切ると古いお題が出なくなるため)。
@MainActor
@Observable
final class PollListViewModel {
    private let voting: any CommunityVoting

    /// 開催中タブの 1 ページの件数。
    static let activePageSize = 20
    /// サーバが 1 回に返す上限 (`GET /polls` の limit の最大)。
    private static let maxPageSize = 100

    private(set) var activePolls: [Poll] = []
    /// 開催中にまだ読んでいない続きがあるか (直前のページが満杯だった)。
    private(set) var hasMoreActive = false
    /// 終了したお題がある月 (新しい月から)。
    private(set) var pastMonths: [PollMonth] = []
    /// 読み込んだ月。`pastMonths` の先頭から順に埋まる。
    private(set) var pastSections: [PollMonthSection] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var loadError: String?

    nonisolated init(voting: any CommunityVoting) {
        self.voting = voting
    }

    func polls(active: Bool) -> [Poll] { active ? activePolls : pastSections.flatMap(\.polls) }

    /// まだ読んでいない古い月があるか。
    var hasMorePast: Bool { pastSections.count < pastMonths.count }

    func load(active: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            if active {
                // 詳細から戻ったときの読み直しで、読み進めたところまで畳まない。
                let limit = min(Self.maxPageSize, max(Self.activePageSize, activePolls.count))
                let page = try await voting.activePolls(offset: 0, limit: limit)
                activePolls = page
                hasMoreActive = page.count == limit
            } else {
                // 詳細から戻ったときの読み直しで、さかのぼった月を畳まない。
                let months = try await voting.pollMonths()
                let keep = months.prefix(max(1, pastSections.count))
                pastSections = try await sections(for: Array(keep))
                pastMonths = months
            }
            loadError = nil
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// 開催中タブの続きを読む。末尾の行が見えたときに呼ぶ。
    func loadMoreActive() async {
        guard hasMoreActive, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let offset = activePolls.count
        do {
            let page = try await voting.activePolls(offset: offset, limit: Self.activePageSize)
            // 待っている間に読み直しで中身が入れ替わっていたら付け足さない。
            guard activePolls.count == offset else { return }
            let known = Set(activePolls.map(\.id))
            activePolls += page.filter { !known.contains($0.id) }
            hasMoreActive = page.count == Self.activePageSize
            loadError = nil
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// 終了タブの次の (1 か月古い) 月を読む。末尾の行が見えたときに呼ぶ。
    func loadMorePast() async {
        guard hasMorePast, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let month = pastMonths[pastSections.count]
        do {
            let polls = try await voting.pastPolls(month: month.month)
            // 待っている間に読み直しで中身が入れ替わっていたら付け足さない。
            guard pastSections.count < pastMonths.count, pastMonths[pastSections.count] == month else { return }
            pastSections.append(PollMonthSection(month: month, polls: polls))
            loadError = nil
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// 作成直後のお題を一覧へ即時反映する (開催中のみ先頭に差し込む)。
    func insertCreated(_ poll: Poll) {
        if poll.isActive { activePolls.insert(poll, at: 0) }
    }

    private func sections(for months: [PollMonth]) async throws -> [PollMonthSection] {
        var result: [PollMonthSection] = []
        for month in months {
            result.append(PollMonthSection(month: month, polls: try await voting.pastPolls(month: month.month)))
        }
        return result
    }

    private static func message(for error: Error) -> String {
        (error as? APIClientError)?.errorDescription ?? "通信エラー"
    }
}
