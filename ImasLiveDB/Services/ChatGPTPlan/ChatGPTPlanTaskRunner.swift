import Foundation

/// 利用者の ChatGPT プランで回す仕事 1 回ぶんを、関数呼び出しの往復ごと回す。
///
/// 何を指示するか・どのツールを渡すか・何往復まで許すか・関数の実行・答えの検証は全部コア
/// (`agent::tools::plan_loop` と、仕事ごとの `natural_search` / `prep_dj`)。ここは HTTP を運び、
/// 1 往復ごとに `step` (コアの 1 呼び出し) を呼ぶだけ。
@MainActor
enum ChatGPTPlanTaskRunner {
    struct RunnerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 1 往復ぶんの結末。
    enum Outcome<Result: Sendable>: Sendable {
        case finished(Result)
        /// 次のリクエストの input。
        case next([String])
        /// 次のリクエストの input。この仕事の残りは、組み込みツール (Web 検索・画像の生成) を外して送る。
        case nextWithoutBuiltIns([String])
    }

    /// - Parameters:
    ///   - onProgress: いま何を調べているかの一言 (コアの文言)。
    ///   - step: この往復で送った input・応答で確定した出力項目・本文を受けて、コアに次を決めさせる。
    ///     メインスレッドの外で呼ぶ。
    static func run<Result: Sendable>(
        request: PlanTaskRequest,
        onProgress: (String) -> Void,
        step: @escaping @Sendable (_ input: [String], _ outputItems: [String], _ text: String) async throws -> Outcome<Result>
    ) async throws -> Result {
        let session = ChatGPTPlanSession.shared
        // モデル一覧の失敗で「ログインし直し」になったときのトークンの始末は session がやる。
        let model = try await session.resolvedModel()

        var input = request.input
        var toolsJson = request.toolsJson
        var includeReasoning = true
        var round: UInt32 = 0

        while round < request.maxRounds {
            let token = try await session.validAccessToken()
            let body = chatgptResponsesBody(
                model: model, instructions: request.instructions, inputItems: input,
                toolsJson: toolsJson, textFormatJson: request.textFormatJson,
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
            } catch is ChatGPTPlanClient.RetryWithoutBuiltInTools {
                // 外したものがある仕事だけ、1 回だけやり直す (往復には数えない)。
                guard let fallback = request.toolsWithoutBuiltInsJson, fallback != toolsJson else {
                    throw RunnerError(message: "ChatGPT とのやりとりに失敗しました")
                }
                toolsJson = fallback
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
            let outcome = try await Task.detached(priority: .userInitiated) {
                try await step(sent, items, answerText)
            }.value
            switch outcome {
            case .finished(let result): return result
            case .next(let next): input = next
            case .nextWithoutBuiltIns(let next):
                input = next
                if let plain = request.toolsWithoutBuiltInsJson { toolsJson = plain }
            }
        }
        throw RunnerError(message: request.tooManyRoundsMessage)
    }
}
