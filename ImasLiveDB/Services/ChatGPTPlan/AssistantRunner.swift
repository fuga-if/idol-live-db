import Foundation

/// アプリ内の会話 1 番ぶん。往復は `ChatGPTPlanTaskRunner`、判断はコア (`agent::tools::assistant`)。
///
/// 返るのは返事と「これからやること」の一覧で、ここでは何も実行しない。
/// 実行は利用者が一覧を見て押してから (`AssistantExecutor`)。
@MainActor
enum AssistantRunner {
    /// - Parameter history: 前の番の `AssistantPlan.history` (最初は空)。
    static func run(history: [String], order: String, onProgress: (String) -> Void) async throws -> AssistantPlan {
        let today = JSTDay.today()
        guard let request = assistantRequest(history: history, order: order, todayKey: today) else {
            throw ChatGPTPlanTaskRunner.RunnerError(message: "会話が長くなりました。新しい会話を始めてください")
        }
        let store = try await AppContainer.shared.coreSnapshot.loadedStore()
        // 「〜に足して」の足す先は、コアが名前から決める。端末にあるプレイリストを射影して渡す。
        let playlists = try await AppContainer.shared.playlists.summaries()
            .map { AiPlaylistRef(id: $0.playlist.id, name: $0.playlist.name) }
        return try await ChatGPTPlanTaskRunner.run(request: request, onProgress: onProgress) { input, items, text in
            let step = try store.assistantStep(input: input, outputItems: items, text: text, todayKey: today,
                                               playlists: playlists)
            return step.plan.map { .finished($0) } ?? .next(step.nextInput)
        }
    }
}
