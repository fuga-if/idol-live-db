import UIKit

/// アプリ内の会話 1 番ぶん。往復は `ChatGPTPlanTaskRunner`、判断はコア (`agent::tools::assistant`)。
///
/// 返るのは返事と「これからやること」の一覧で、ここでは何も実行しない。
/// 実行は利用者が一覧を見て押してから (`AssistantExecutor`)。
@MainActor
enum AssistantRunner {
    /// - Parameters:
    ///   - history: 前の番の `AssistantPlan.history` (最初は空)。
    ///   - images: 発言に添える画像 (この番にだけ送る。会話には持ち越さない)。
    static func run(history: [String], order: String, images: [UIImage] = [],
                    onProgress: (String) -> Void) async throws -> AssistantPlan {
        let today = JSTDay.today()
        // 縮めて JPEG にするのはコール表の読み取りと同じ口 (長辺の上限も同じ)。
        let encoded = images.isEmpty ? [] : await Task.detached(priority: .userInitiated) {
            images.compactMap(CallSheetRunner.jpegBase64)
        }.value
        try Task.checkCancellation()
        // 端末の側の事情 (足す先のプレイリスト・習熟度の段階の名前) を射影して渡す。決めるのはコア。
        let playlists = try await AppContainer.shared.playlists.summaries()
            .map { AiPlaylistRef(id: $0.playlist.id, name: $0.playlist.name) }
        let device = AiDeviceContext(playlists: playlists, masteryLabels: UserMarkService.shared.scale.labels)
        guard let request = assistantRequest(history: history, order: order, imagesBase64: encoded, todayKey: today, device: device) else {
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
