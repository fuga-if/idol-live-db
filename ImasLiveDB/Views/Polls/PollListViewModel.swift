import Foundation
import Observation

/// お題一覧 (開催中 / 終了) の取得状態 (Presentation)。
/// データ取得は `CommunityVoting` プロトコル越しなのでフェイク注入で単体テストできる。
///
/// 開催中タブは選んだ並び (既定は締切の近い順) で 20 件ずつ、末尾まで見たら続きを読む (一度に全件は読まない)。
/// 終了タブは月 (日本時間) ごとに読む。最初は新しい月だけ取り、末尾まで見たら 1 か月ずつさかのぼる
/// (件数で切ると古いお題が出なくなるため)。並びは月の中に効き、月の区切りは新しい月からのまま。
///
/// 並びはサーバが付ける (開催中は 20 件ずつしか読まないので、手元で並べ直すと 21 件目以降と食い違う)。
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
    /// 開催中 / 終了それぞれの並び。締切の既定の向きがタブで逆なので別々に持つ。
    private(set) var activeSort = PollListSort.standard(active: true)
    private(set) var pastSort = PollListSort.standard(active: false)
    /// 開催中 / 終了のお題の総数。開催中を読むたびに取り直す。取れていなければ nil。
    private(set) var counts: PollCounts?

    nonisolated init(voting: any CommunityVoting) {
        self.voting = voting
    }

    func polls(active: Bool) -> [Poll] { active ? activePolls : pastSections.flatMap(\.polls) }

    /// まだ読んでいない古い月があるか。
    var hasMorePast: Bool { pastSections.count < pastMonths.count }

    func sort(active: Bool) -> PollListSort { active ? activeSort : pastSort }

    /// 一覧の頭に出す総数。開催中は `GET /polls/counts`、終了は月ごとの件数の合計。
    /// 開催中の総数がまだ取れていなければ nil (読んだ件数を総数のように見せない)。
    func totalCount(active: Bool) -> Int? {
        if active { return counts?.active }
        return pastMonths.isEmpty ? nil : pastMonths.reduce(0) { $0 + $1.count }
    }

    /// - Parameter resetPaging: true なら読み進めた続きを捨てて先頭のページ (月) だけ読み直す (並びを変えたとき)。
    ///   false なら詳細から戻ったときの読み直しとして、読み進めたところまで畳まない。
    func load(active: Bool, resetPaging: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            if active {
                let sort = activeSort
                let limit = resetPaging
                    ? Self.activePageSize
                    : min(Self.maxPageSize, max(Self.activePageSize, activePolls.count))
                // 総数は一覧と並べて取る。取れなくても一覧は出す (並び替えの行に件数が出ないだけ)。
                let voting = self.voting
                async let newCounts = try? await voting.pollCounts()
                let page = try await voting.activePolls(offset: 0, limit: limit, sort: sort)
                let fetchedCounts = await newCounts
                // 待っている間に並びを変えられていたら、古い並びの結果で上書きしない。
                guard sort == activeSort else { return }
                activePolls = page
                hasMoreActive = page.count == limit
                if let fetchedCounts { counts = fetchedCounts }
            } else {
                let sort = pastSort
                let months = try await voting.pollMonths()
                let keep = months.prefix(resetPaging ? 1 : max(1, pastSections.count))
                let loaded = try await sections(for: Array(keep), sort: sort)
                guard sort == pastSort else { return }
                pastSections = loaded
                pastMonths = months
            }
            loadError = nil
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// 並びの軸を変える。向きはその軸の既定に戻す。前の軸で選んだ向きを持ち越すと、
    /// 「票数順」が少ない順から始まるような、選んだ直後に意図と逆の並びになる (曲一覧と同じ)。
    func changeSortKey(_ key: PollSortKey, active: Bool) async {
        await apply(PollListSort(key: key, ascending: key.defaultAscending(active: active)), active: active)
    }

    /// 並びの向き (昇順 / 降順) を変える。
    func changeSortAscending(_ ascending: Bool, active: Bool) async {
        var next = sort(active: active)
        next.ascending = ascending
        await apply(next, active: active)
    }

    private func apply(_ sort: PollListSort, active: Bool) async {
        guard sort != self.sort(active: active) else { return }
        if active { activeSort = sort } else { pastSort = sort }
        // 読み進めた続きは古い並びのものなので捨て、先頭から読み直す。読み直すまでは今の一覧を出しておく
        // (空にすると読み込み中の表示に切り替わって画面が跳ねる)。
        await load(active: active, resetPaging: true)
    }

    /// 開催中タブの続きを読む。末尾の行が見えたときに呼ぶ。
    func loadMoreActive() async {
        guard hasMoreActive, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let offset = activePolls.count
        let sort = activeSort
        do {
            let page = try await voting.activePolls(offset: offset, limit: Self.activePageSize, sort: sort)
            // 待っている間に読み直し・並び替えで中身が入れ替わっていたら付け足さない。
            guard activePolls.count == offset, sort == activeSort else { return }
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
        let sort = pastSort
        do {
            let polls = try await voting.pastPolls(month: month.month, sort: sort)
            // 待っている間に読み直し・並び替えで中身が入れ替わっていたら付け足さない。
            guard pastSections.count < pastMonths.count, pastMonths[pastSections.count] == month, sort == pastSort
            else { return }
            pastSections.append(PollMonthSection(month: month, polls: polls))
            loadError = nil
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// 作成直後のお題を一覧へ即時反映する (開催中のみ先頭に差し込む)。
    /// どの並びでも先頭に出す (作った直後に自分のお題が見えることを優先する。次の読み直しで並びの位置に戻る)。
    func insertCreated(_ poll: Poll) {
        guard poll.isActive else { return }
        activePolls.insert(poll, at: 0)
        if let counts { self.counts = PollCounts(active: counts.active + 1, past: counts.past) }
    }

    private func sections(for months: [PollMonth], sort: PollListSort) async throws -> [PollMonthSection] {
        var result: [PollMonthSection] = []
        for month in months {
            result.append(PollMonthSection(month: month, polls: try await voting.pastPolls(month: month.month, sort: sort)))
        }
        return result
    }

    private static func message(for error: Error) -> String {
        (error as? APIClientError)?.errorDescription ?? "通信エラー"
    }
}
