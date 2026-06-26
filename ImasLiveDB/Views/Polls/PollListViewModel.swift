import Foundation
import Observation

/// お題一覧 (開催中 / 終了) の取得状態 (Presentation)。
/// データ取得は `CommunityVoting` プロトコル越しなのでフェイク注入で単体テストできる。
@MainActor
@Observable
final class PollListViewModel {
    private let voting: any CommunityVoting

    private(set) var activePolls: [Poll] = []
    private(set) var pastPolls: [Poll] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    nonisolated init(voting: any CommunityVoting) {
        self.voting = voting
    }

    func polls(active: Bool) -> [Poll] { active ? activePolls : pastPolls }

    func load(active: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await voting.polls(status: active ? "active" : "past")
            loadError = nil
            if active { activePolls = result } else { pastPolls = result }
        } catch {
            loadError = (error as? APIClientError)?.errorDescription ?? "通信エラー"
        }
    }

    /// 作成直後のお題を一覧へ即時反映する (開催中のみ先頭に差し込む)。
    func insertCreated(_ poll: Poll) {
        if poll.isActive { activePolls.insert(poll, at: 0) }
    }
}
