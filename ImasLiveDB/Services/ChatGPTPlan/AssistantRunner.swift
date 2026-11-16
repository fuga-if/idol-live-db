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
        // 端末の側の事情 (足す先のプレイリスト・習熟度の段階の名前) を射影して渡す。決めるのはコア。
        let playlists = try await AppContainer.shared.playlists.summaries()
            .map { AiPlaylistRef(id: $0.playlist.id, name: $0.playlist.name) }
        let device = AiDeviceContext(playlists: playlists, masteryLabels: UserMarkService.shared.scale.labels)
        guard let request = assistantRequest(history: history, order: order, todayKey: today, device: device) else {
            throw ChatGPTPlanTaskRunner.RunnerError(message: "会話が長くなりました。新しい会話を始めてください")
        }
        let store = try await AppContainer.shared.coreSnapshot.loadedStore()
        return try await ChatGPTPlanTaskRunner.run(request: request, onProgress: onProgress) { input, items, text in
            let step = try store.assistantStep(input: input, outputItems: items, text: text, todayKey: today,
                                               device: device)
            return step.plan.map { .finished($0) } ?? .next(step.nextInput)
        }
    }
}
