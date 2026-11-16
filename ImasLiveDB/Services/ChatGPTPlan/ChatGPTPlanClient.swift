import Foundation

/// ChatGPT プランの経路の HTTP。
///
/// 何を送るか (フォーム・リクエスト本文) と、返ってきたものの読み方 (ストリームの行の意味・
/// 失敗の言い方・モデル一覧) は全部コア (`chatgpt_plan.rs`)。ここは運ぶだけ。
enum ChatGPTPlanClient {
    /// 推論の失敗。文言はコアが決めたもの。
    struct Failure: LocalizedError {
        let failure: ChatGptFailure
        var errorDescription: String? { failure.message }
    }

    /// 推論の暗号化返却を受けない経路だった。それ無しでやり直す。
    struct RetryWithoutReasoning: Error {}

    /// Web 検索のツールを受けない経路だった。それを外してやり直す (外したものが無い仕事なら失敗)。
    struct RetryWithoutBuiltInTools: Error {}

    enum StreamEvent: Sendable {
        case delta(String)
        /// 関数呼び出しが始まった (進行表示用)。
        case toolCallStarted(name: String)
        /// 出力項目 1 件が確定した (JSON)。
        case outputItem(String)
    }

    static func get(_ url: String) async throws -> String {
        guard let url = URL(string: url) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(decoding: data, as: UTF8.self)
    }

    static func postForm(_ url: String, body: String) async throws -> (status: UInt16, body: String) {
        guard let url = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (status(of: response), String(decoding: data, as: UTF8.self))
    }

    static func listModels(accessToken: String) async throws -> [ChatGptModel] {
        guard let url = URL(string: chatgptEndpoints().modelsUrl) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(decoding: data, as: UTF8.self)
        let status = status(of: response)
        guard (200..<300).contains(status) else {
            throw Failure(failure: chatgptHttpFailure(status: status, body: body))
        }
        return chatgptReadModels(body: body)
    }

    /// Responses API を 1 回呼び、ストリームを読む。正常に終われば finish、失敗は `Failure` を投げる。
    /// - Parameters:
    ///   - body: コアが組んだリクエスト本文 (`chatgptResponsesBody`)。
    ///   - includesReasoning: その本文に推論の暗号化返却を付けたか (失敗時にやり直すかの判断にコアが使う)。
    static func stream(body: String, includesReasoning: Bool, accessToken: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: chatgptEndpoints().responsesUrl) else { throw URLError(.badURL) }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = Data(body.utf8)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = status(of: response)
                    if !(200..<300).contains(status) {
                        var data = Data()
                        for try await byte in bytes.prefix(4000) { data.append(byte) }
                        let text = String(decoding: data, as: UTF8.self)
                        switch chatgptHttpErrorAction(status: status, body: text, includeEncryptedReasoning: includesReasoning) {
                        case .retryWithoutReasoning: throw RetryWithoutReasoning()
                        case .retryWithoutBuiltInTools: throw RetryWithoutBuiltInTools()
                        case .fail(let failure): throw Failure(failure: failure)
                        }
                    }

                    var completed = false
                    for try await line in bytes.lines {
                        switch chatgptReadStreamLine(line: line) {
                        case .ignored: continue
                        case .delta(let text): continuation.yield(.delta(text))
                        case .toolCallStarted(let name): continuation.yield(.toolCallStarted(name: name))
                        case .outputItem(let json): continuation.yield(.outputItem(json))
                        case .completed: completed = true
                        case .failed(let failure): throw Failure(failure: failure)
                        }
                    }
                    if !completed { throw Failure(failure: chatgptStreamCutOff()) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func status(of response: URLResponse) -> UInt16 {
        UInt16(clamping: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
