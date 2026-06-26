import Foundation
import Observation

/// 殿堂 (終了お題の優勝者一覧) の取得状態 (Presentation)。
/// 取得は `CommunityVoting` プロトコル越し。曲/アイドルへの遷移解決 (master 参照) は View 側に残す。
@MainActor
@Observable
final class PollHallOfFameViewModel {
    private let voting: any CommunityVoting

    private(set) var results: [PollResult] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    nonisolated init(voting: any CommunityVoting) {
        self.voting = voting
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await voting.pollResults()
            loadError = nil
        } catch {
            loadError = (error as? APIClientError)?.errorDescription ?? "通信エラー"
        }
    }
}
