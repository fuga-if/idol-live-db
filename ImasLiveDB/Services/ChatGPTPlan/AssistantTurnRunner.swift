import Foundation

/// 利用者の発言 1 回ぶんを、関数呼び出しのループごと回す。
///
/// store: false の経路なので、モデルの出力項目 (推論・関数呼び出し・発言) と関数の結果は
/// こちらで覚えておき、次のリクエストの input に積み直す。ツールの中身はコア
/// (`SnapshotStore.assistantCallTool`、MCP と同じツール面) が持ち、ここは受け渡すだけ。
@MainActor
enum AssistantTurnRunner {
    enum Event {
        case delta(String)
        case toolStarted(label: String)
        case toolFinished
    }

    /// 1 回の発言で関数呼び出しを何往復まで許すか (無限ループ止め)。
    private static let maxRounds = 8

    /// - Parameters:
    ///   - history: これまでの input 項目 (今回の発言を含む)。
    /// - Returns: 今回増えた input 項目 (出力項目と関数の結果)。履歴の末尾に足して保存する。
    static func run(
        model: String,
        history: [String],
        instructions: String?,
        toolsJSON: String?,
        onEvent: (Event) -> Void
    ) async throws -> [String] {
        var added: [String] = []
        var includeReasoning = true

        for _ in 0..<maxRounds {
            let token = try await ChatGPTPlanSession.shared.validAccessToken()
            var outputItems: [[String: Any]] = []
            let request = ChatGPTPlanClient.Request(
                model: model,
                instructions: instructions,
                input: history + added,
                toolsJSON: toolsJSON,
                includeEncryptedReasoning: includeReasoning
            )
            do {
                for try await event in ChatGPTPlanClient.stream(request, accessToken: token) {
                    switch event {
                    case .delta(let text): onEvent(.delta(text))
                    case .toolCallStarted(let name): onEvent(.toolStarted(label: assistantToolProgressLabel(name: name)))
                    case .outputItem(let json): if let item = ChatGPTPlanClient.jsonObject(json) { outputItems.append(item) }
                    case .completed: break
                    }
                }
            } catch let ChatGPTPlanClient.ClientError.http(status, body, _)
                where includeReasoning && status == 400 && (body.contains("include") || body.contains("encrypted")) {
                // 推論の暗号化返却を受けない経路だったら、それ無しでやり直す。
                includeReasoning = false
                continue
            }

            // 止められたストリームはエラー無しで終わるので、ここで止める。
            try Task.checkCancellation()

            let calls = outputItems.filter { $0["type"] as? String == "function_call" }
            added += outputItems.compactMap(replayable(_:)).map(ChatGPTPlanClient.jsonString(_:))
            if calls.isEmpty { return added }

            let attended = attendedShows()
            for call in calls {
                guard let name = call["name"] as? String, let callID = call["call_id"] as? String else { continue }
                let arguments = call["arguments"] as? String ?? "{}"
                let output = await callTool(name: name, arguments: arguments, attended: attended)
                added.append(ChatGPTPlanClient.functionCallOutput(callID: callID, output: output))
            }
            onEvent(.toolFinished)
        }
        throw RunnerError.tooManyRounds
    }

    enum RunnerError: LocalizedError {
        case tooManyRounds
        var errorDescription: String? { "調べものが長くなりすぎたので止めました。質問を分けて聞いてみてください" }
    }

    /// 出力項目を次の input に積み直せる形にする。
    ///
    /// store: false では項目が保存されないので、`id` を残すと「その id の項目は無い」で弾かれる。
    /// 暗号化された中身の無い推論項目は積み直しても使えないので落とす。
    private static func replayable(_ item: [String: Any]) -> [String: Any]? {
        var item = item
        item.removeValue(forKey: "id")
        if item["type"] as? String == "reasoning", item["encrypted_content"] == nil { return nil }
        return item
    }

    /// 利用者の参加記録をコアに渡す形に射影する。
    private static func attendedShows() -> [AssistantAttendedShow] {
        let marks = UserMarkService.shared
        return marks.allMarked(kind: .attended, entity: .show).map { id in
            AssistantAttendedShow(showId: id, attendance: (marks.attendance(entity: .show, id: id) ?? .live).rawValue)
        }
    }

    private static func callTool(name: String, arguments: String, attended: [AssistantAttendedShow]) async -> String {
        do {
            let store = try await AppContainer.shared.coreSnapshot.loadedStore()
            return try await Task.detached(priority: .userInitiated) {
                try store.assistantCallTool(name: name, argumentsJson: arguments, attended: attended)
            }.value
        } catch {
            return ChatGPTPlanClient.jsonString(["error": "データベースを読めませんでした: \(error.localizedDescription)"])
        }
    }
}
