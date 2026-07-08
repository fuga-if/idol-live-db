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
    /// お題削除の進行中フラグ (連打防止)。投票の連打ガード (isVoting) とは独立に扱う。
    private(set) var isDeleting = false
    /// 削除失敗時のエラーメッセージ。投票エラー (errorMessage) とは表示箇所が異なるため分離する。
    var deleteErrorMessage: String?

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
            LocalPollVoteLog.shared.recordVote(pollId: self.pollId, entityId: entityId)
        }
    }

    /// 自分の票を取り消す。
    func unvote(entityId: String) async {
        await mutate(errorText: "取消できませんでした") {
            let result = try await self.voting.unvotePoll(pollId: self.pollId, entityId: entityId)
            self.applyVote(entityId: entityId, voteCount: result.voteCount, hasUserVoted: false, myVoteCount: result.myVoteCount)
            LocalPollVoteLog.shared.removeVote(pollId: self.pollId, entityId: entityId)
        }
    }

    /// ピッカーから新規候補へまとめて投票 (曲/アイドル共通の entityId 配列)。
    func voteForEntities(_ entityIds: [String]) async {
        await mutate(errorText: "投票できませんでした") {
            for id in entityIds {
                let result = try await self.voting.votePoll(pollId: self.pollId, entityId: id)
                self.applyVote(entityId: id, voteCount: result.voteCount, hasUserVoted: true, myVoteCount: result.myVoteCount)
                LocalPollVoteLog.shared.recordVote(pollId: self.pollId, entityId: id)
            }
        }
    }

    /// ピッカーで選択解除された既投票の候補をまとめて取り消す (曲/アイドル共通の entityId 配列)。
    func unvoteForEntities(_ entityIds: [String]) async {
        await mutate(errorText: "取消できませんでした") {
            for id in entityIds {
                let result = try await self.voting.unvotePoll(pollId: self.pollId, entityId: id)
                self.applyVote(entityId: id, voteCount: result.voteCount, hasUserVoted: false, myVoteCount: result.myVoteCount)
                LocalPollVoteLog.shared.removeVote(pollId: self.pollId, entityId: id)
            }
        }
    }

    /// お題を削除する。成否を返す (呼び出し元は成功時のみ pop する)。
    /// 連打防止のため isDeleting でガードし、失敗時は deleteErrorMessage にメッセージを立てる。
    @discardableResult
    func delete() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        deleteErrorMessage = nil
        do {
            try await voting.deletePoll(id: pollId)
            AppAnalytics.event("poll_delete")
            return true
        } catch {
            deleteErrorMessage = (error as? APIClientError)?.errorDescription ?? "削除に失敗しました。時間をおいて再試行してください。"
            AppAnalytics.event("poll_delete_failed")
            return false
        }
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
        // manual スコープは「指定候補のリストそのもの」が見えてないと選びようがないので、
        // 0 票になっても entries から削除せず 0 票エントリのまま残す。
        let keepZeroVote = detail.poll.scope == .manual
        var entries = detail.entries
        let updated = PollEntry(entityId: entityId, voteCount: voteCount, hasUserVoted: hasUserVoted)
        if let index = entries.firstIndex(where: { $0.entityId == entityId }) {
            if voteCount == 0 && !hasUserVoted && !keepZeroVote {
                entries.remove(at: index)
            } else {
                entries[index] = updated
            }
        } else if voteCount > 0 || keepZeroVote {
            entries.append(updated)
        }
        entries.sort { $0.voteCount > $1.voteCount }
        self.detail = PollDetail(poll: detail.poll, entries: entries, myVoteCount: myVoteCount)
    }
}
