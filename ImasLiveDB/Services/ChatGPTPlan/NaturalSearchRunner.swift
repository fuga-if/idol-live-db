import Foundation

/// 自然文検索 1 回ぶんを、関数呼び出しの往復ごと回す。
///
/// 何を指示するか・どのツールを渡すか・何往復まで許すか・関数の実行・答えのどれを画面に
/// 出してよいかは全部コア (`agent::tools::natural_search`)。ここは HTTP を運び、1 往復ごとに
/// コアを 1 回呼ぶだけ。
@MainActor
enum NaturalSearchRunner {
    struct RunnerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// - Parameter onProgress: いま何を調べているかの一言 (コアの文言)。
    static func run(query: String, onProgress: (String) -> Void) async throws -> NaturalSearchAnswer {
        let today = JSTDay.today()
        guard let request = naturalSearchRequest(query: query, todayKey: today) else {
            throw RunnerError(message: "この長さの文は探せません")
        }
        let session = ChatGPTPlanSession.shared
        // モデル一覧の失敗で「ログインし直し」になったときのトークンの始末は session がやる。
        let model = try await session.resolvedModel()
        let store = try await AppContainer.shared.coreSnapshot.loadedStore()

        var input = request.input
        var includeReasoning = true
        var round: UInt32 = 0

        while round < request.maxRounds {
            let token = try await session.validAccessToken()
            let body = chatgptResponsesBody(
                model: model, instructions: request.instructions, inputItems: input,
                toolsJson: request.toolsJson, textFormatJson: request.textFormatJson,
                includeEncryptedReasoning: includeReasoning
            )
            var outputItems: [String] = []
            var text = ""
            do {
                for try await event in ChatGPTPlanClient.stream(body: body, includesReasoning: includeReasoning, accessToken: token) {
                    switch event {
                    case .delta(let piece): text += piece
                    case .toolCallStarted(let name): onProgress(naturalSearchProgressLabel(name: name))
                    case .outputItem(let json): outputItems.append(json)
                    }
                }
            } catch is ChatGPTPlanClient.RetryWithoutReasoning {
                // やり直すかどうかはコアが決めている (1 回だけ)。往復には数えない。
                includeReasoning = false
                continue
            } catch let error as ChatGPTPlanClient.Failure {
                session.settle(error.failure)
                throw error
            }
            round += 1

            // 止められたストリームはエラー無しで終わるので、ここで止める。
            try Task.checkCancellation()

            let sent = input
            let items = outputItems
            let answerText = text
            let step = try await Task.detached(priority: .userInitiated) {
                try store.naturalSearchStep(input: sent, outputItems: items, text: answerText, todayKey: today)
            }.value
            if let answer = step.answer { return answer }
            input = step.nextInput
        }
        throw RunnerError(message: request.tooManyRoundsMessage)
    }
}
