import Foundation
import Observation

/// お題詳細・投票の状態とビジネスロジック (Presentation)。
///
/// 投票/取消/まとめ投票の楽観的更新・多重リクエスト防止 (連打ガード)・エラー表示を担う。
/// データ取得は `CommunityVoting` プロトコル越しなので、フェイクを注入して単体テストできる。
/// 曲/アイドル名の解決 (master 参照) は表示時の責務として View 側に残す (Repository 化は別フェーズ)。
@MainActor
@Observable
final class PollDetailViewModel {
    let pollId: String
    private let voting: any CommunityVoting

    private(set) var detail: PollDetail?
    private(set) var isLoading = true
    /// いずれかの投票/取消が進行中。連打・複数候補同時タップを直列化するガード。
    private(set) var isVoting = false
    var errorMessage: String?

    /// View の init (nonisolated) から生成できるよう init も nonisolated にする。
    nonisolated init(pollId: String, voting: any CommunityVoting) {
        self.pollId = pollId
        self.voting = voting
    }

    var poll: Poll? { detail?.poll }

    /// 残り投票可能数 (1人3票まで)。
    var remaining: Int { detail.map { max(0, 3 - $0.myVoteCount) } ?? 0 }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await voting.poll(id: pollId)
    }

    /// 既存候補へワンタップ投票。
    func vote(entityId: String) async {
        await mutate(errorText: "投票できませんでした") {
            let result = try await self.voting.votePoll(pollId: self.pollId, entityId: entityId)
            self.applyVote(entityId: entityId, voteCount: result.voteCount, hasUserVoted: true, myVoteCount: result.myVoteCount)
        }
    }

    /// 自分の票を取り消す。
    func unvote(entityId: String) async {
        await mutate(errorText: "取消できませんでした") {
            let result = try await self.voting.unvotePoll(pollId: self.pollId, entityId: entityId)
            self.applyVote(entityId: entityId, voteCount: result.voteCount, hasUserVoted: false, myVoteCount: result.myVoteCount)
        }
    }

    /// ピッカーから新規候補へまとめて投票 (曲/アイドル共通の entityId 配列)。
    func voteForEntities(_ entityIds: [String]) async {
        await mutate(errorText: "投票できませんでした") {
            for id in entityIds {
                let result = try await self.voting.votePoll(pollId: self.pollId, entityId: id)
                self.applyVote(entityId: id, voteCount: result.voteCount, hasUserVoted: true, myVoteCount: result.myVoteCount)
            }
        }
    }

    func delete() async {
        try? await voting.deletePoll(id: pollId)
    }

    // MARK: - Private

    /// 投票系の共通ガード。多重実行を弾き、エラー時にメッセージを立てる。
    private func mutate(errorText: String, _ body: () async throws -> Void) async {
        guard !isVoting else { return }
        isVoting = true
        defer { isVoting = false }
        errorMessage = nil
        do {
            try await body()
            AppAnalytics.event("poll_vote")
        } catch {
            errorMessage = errorText
            AppAnalytics.event("poll_vote_failed")
        }
    }

    /// エントリの票数/投票状態をローカルで楽観的更新し、票数降順で並べ替える。
    private func applyVote(entityId: String, voteCount: Int, hasUserVoted: Bool, myVoteCount: Int) {
        guard let detail else { return }
        var entries = detail.entries
        let updated = PollEntry(entityId: entityId, voteCount: voteCount, hasUserVoted: hasUserVoted)
        if let index = entries.firstIndex(where: { $0.entityId == entityId }) {
            if voteCount == 0 && !hasUserVoted {
                entries.remove(at: index)
            } else {
                entries[index] = updated
            }
        } else if voteCount > 0 {
            entries.append(updated)
        }
        entries.sort { $0.voteCount > $1.voteCount }
        self.detail = PollDetail(poll: detail.poll, entries: entries, myVoteCount: myVoteCount)
    }
}
