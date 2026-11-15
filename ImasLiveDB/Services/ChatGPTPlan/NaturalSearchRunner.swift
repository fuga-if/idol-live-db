import Foundation

/// 自然文検索 1 回ぶん。往復は `ChatGPTPlanTaskRunner`、判断はコア (`agent::tools::natural_search`)。
@MainActor
enum NaturalSearchRunner {
    /// - Parameter onProgress: いま何を調べているかの一言 (コアの文言)。
    static func run(query: String, onProgress: (String) -> Void) async throws -> NaturalSearchAnswer {
        let today = JSTDay.today()
        guard let request = naturalSearchRequest(query: query, todayKey: today) else {
            throw ChatGPTPlanTaskRunner.RunnerError(message: "この長さの文は探せません")
        }
        let store = try await AppContainer.shared.coreSnapshot.loadedStore()
        return try await ChatGPTPlanTaskRunner.run(request: request, onProgress: onProgress) { input, items, text in
            let step = try store.naturalSearchStep(input: input, outputItems: items, text: text, todayKey: today)
            return step.answer.map { .finished($0) } ?? .next(step.nextInput)
        }
    }
}
