import Foundation

/// ChatGPT プランで推論する Responses API の最小クライアント (試作)。
///
/// このフローでは `store: false` / `stream: true` 必須、`input` は配列、
/// temperature 等のサンプリング系パラメータは送れない (preview-limitations)。
/// 成功は `response.completed` を受け取ったときだけ。
enum ChatGPTPlanClient {
    static let modelsURL = URL(string: "https://api.openai.com/v1/models")!
    static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!

    struct Model: Decodable, Identifiable, Hashable, Sendable {
        let slug: String
        let displayName: String?
        let visibility: String?
        var id: String { slug }
        var label: String { displayName ?? slug }

        enum CodingKeys: String, CodingKey {
            case slug
            case displayName = "display_name"
            case visibility
        }
    }

    /// Responses API の 1 リクエスト。`input` の各要素は JSON 1 項目ぶんの文字列
    /// (store: false なので会話の履歴は毎回ここに積み直す)。
    struct Request: Sendable {
        var model: String
        var instructions: String?
        var input: [String]
        /// `tools` に入れる配列 (JSON)。
        var toolsJSON: String?
        /// `text.format` に入れる構造化出力の指定 (JSON)。
        var textFormatJSON: String?
        /// 推論項目を暗号化して返してもらい、次のリクエストに積み直せるようにする。
        var includeEncryptedReasoning = true
    }

    enum StreamEvent: Sendable {
        case delta(String)
        /// 関数呼び出しが始まった (名前だけ先に分かる)。
        case toolCallStarted(name: String)
        /// 出力項目 1 つが確定した (JSON)。次のリクエストの input に積み直す材料。
        case outputItem(String)
        case completed
    }

    /// ユーザー発言 1 件の input 項目。
    static func userMessage(_ text: String) -> String {
        jsonString(["role": "user", "content": text])
    }

    /// 関数の実行結果の input 項目。
    static func functionCallOutput(callID: String, output: String) -> String {
        jsonString(["type": "function_call_output", "call_id": callID, "output": output])
    }

    static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func jsonObject(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    enum ClientError: LocalizedError {
        case http(status: Int, body: String, requestID: String?)
        case responseFailed(code: String?, message: String?)
        case incomplete(reason: String?)
        case endedWithoutCompletion

        var errorDescription: String? {
            switch self {
            case .http(let status, let body, let requestID):
                "\(Self.explain(status: status, body: body))\n(HTTP \(status)\(requestID.map { ", request \($0)" } ?? ""))\n\(body)"
            case .responseFailed(let code, let message):
                "\(Self.explain(code: code))\n(\(code ?? "unknown_error"))\(message.map { "\n\($0)" } ?? "")"
            case .incomplete(let reason):
                "応答が途中で終わりました (\(reason ?? "理由不明"))"
            case .endedWithoutCompletion:
                "response.completed を受け取る前にストリームが切れました"
            }
        }

        /// ChatGPT プランの利用上限に当たったか (画面は「Manage usage」を主ボタンにして案内する)。
        var isUsageLimit: Bool {
            switch self {
            case .responseFailed(let code, _): code == "subscription_sharing_usage_limit_exceeded"
            case .http(let status, let body, _): status == 429 || body.contains("subscription_sharing_usage_limit_exceeded")
            default: false
            }
        }

        /// errors-and-recovery の表のうち、利用者に伝わる言い方が要るものだけ訳す。
        private static func explain(code: String?) -> String {
            switch code {
            case "subscription_sharing_user_not_eligible":
                "このアカウントでは ChatGPT プランを使えません (Plus / Pro が必要です)"
            case "subscription_sharing_usage_limit_exceeded":
                "ChatGPT プランの利用上限に達しました。ChatGPT の設定 → 使用状況 で確認できます"
            case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
                "ChatGPT 側で一時的に利用状況を確認できません。時間をおいて試してください"
            case "subscription_sharing_invalid_user":
                "アカウントを確認できませんでした。サインインし直してください"
            default:
                "応答の生成に失敗しました"
            }
        }

        private static func explain(status: Int, body: String) -> String {
            for code in ["subscription_sharing_user_not_eligible", "subscription_sharing_usage_limit_exceeded",
                         "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable",
                         "subscription_sharing_invalid_user"] where body.contains(code) {
                return explain(code: code)
            }
            switch status {
            case 401: return "認証が通りませんでした (アカウントか scope を確認)"
            case 403: return "権限または地域の制限で弾かれました"
            case 503: return "ChatGPT プランの経路が使えません (一時的な可能性あり)"
            default: return "リクエストに失敗しました"
            }
        }
    }

    static func listModels(accessToken: String) async throws -> [Model] {
        var request = URLRequest(url: modelsURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, body: data)
        struct Envelope: Decodable { let models: [Model] }
        // 表示用は visibility == "list" だけ。並びはサーバの順を保つ。
        return try JSONDecoder().decode(Envelope.self, from: data).models.filter { $0.visibility == "list" }
    }

    static func stream(_ request: Request, accessToken: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: responsesURL)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    // サンプリング系 (temperature 等) はこの経路では送れない。
                    var body: [String: Any] = [
                        "model": request.model,
                        "input": request.input.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) },
                        "store": false,
                        "stream": true,
                    ]
                    if let instructions = request.instructions { body["instructions"] = instructions }
                    if let tools = request.toolsJSON, let parsed = try? JSONSerialization.jsonObject(with: Data(tools.utf8)) {
                        body["tools"] = parsed
                    }
                    if let format = request.textFormatJSON, let parsed = try? JSONSerialization.jsonObject(with: Data(format.utf8)) {
                        body["text"] = ["format": parsed]
                    }
                    if request.includeEncryptedReasoning { body["include"] = ["reasoning.encrypted_content"] }
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        try check(response, body: data)
                    }

                    var completed = false
                    // SSE は 1 行 1 フィールド。ここで要るのは data 行の JSON の type だけ。
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard payload != "[DONE]",
                              let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                              let type = object["type"] as? String
                        else { continue }

                        switch type {
                        case "response.output_text.delta":
                            if let delta = object["delta"] as? String { continuation.yield(.delta(delta)) }
                        case "response.output_item.added":
                            if let item = object["item"] as? [String: Any], item["type"] as? String == "function_call",
                               let name = item["name"] as? String {
                                continuation.yield(.toolCallStarted(name: name))
                            }
                        case "response.output_item.done":
                            if let item = object["item"] { continuation.yield(.outputItem(jsonString(item))) }
                        case "response.completed":
                            completed = true
                            continuation.yield(.completed)
                        case "response.failed":
                            let error = (object["response"] as? [String: Any])?["error"] as? [String: Any]
                            throw ClientError.responseFailed(code: error?["code"] as? String, message: error?["message"] as? String)
                        case "response.incomplete":
                            let details = (object["response"] as? [String: Any])?["incomplete_details"] as? [String: Any]
                            throw ClientError.incomplete(reason: details?["reason"] as? String)
                        case "error":
                            throw ClientError.responseFailed(code: object["code"] as? String, message: object["message"] as? String)
                        default:
                            continue
                        }
                    }
                    if !completed { throw ClientError.endedWithoutCompletion }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(
                status: http.statusCode,
                body: String(decoding: body.prefix(2000), as: UTF8.self),
                requestID: http.value(forHTTPHeaderField: "x-request-id")
            )
        }
    }
}
