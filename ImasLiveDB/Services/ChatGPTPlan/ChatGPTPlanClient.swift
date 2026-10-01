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

    enum StreamEvent: Sendable {
        case delta(String)
        case completed
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

    static func stream(model: String, prompt: String, accessToken: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: responsesURL)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let body: [String: Any] = [
                        "model": model,
                        "input": [["role": "user", "content": prompt]],
                        "store": false,
                        "stream": true,
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
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
