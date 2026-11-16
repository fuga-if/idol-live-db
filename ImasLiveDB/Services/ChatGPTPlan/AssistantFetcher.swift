import Foundation

/// チャットのモデルが読みたいと言ったもの (X のポスト) を、端末が取りに行く。
///
/// どこへ行くか (`AssistantFetch.url`) はコアが組む。ここは GET して、状態と本文をそのまま返すだけ
/// (本文をモデルに渡す形に削るのもコアの `assistantFetched`)。
enum AssistantFetcher {
    /// 本文の上限 (バイト)。一覧 1 ページぶんには十分で、これを越えるものは読まない。
    private static let maxBytes = 600_000

    static func fetch(_ fetches: [AssistantFetch]) async -> [AssistantFetched] {
        await withTaskGroup(of: AssistantFetched.self) { group in
            for fetch in fetches {
                group.addTask { await get(fetch) }
            }
            var results: [AssistantFetched] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    private static func get(_ fetch: AssistantFetch) async -> AssistantFetched {
        // 通信できなかったときは状態 0 (文言はコアが決める)。
        let failed = AssistantFetched(callId: fetch.callId, status: 0, body: "")
        guard let url = URL(string: fetch.url) else { return failed }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 利用者や端末を識別できるものは付けない。
        request.setValue("idol-live-db-app", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, data.count <= maxBytes else { return failed }
        return AssistantFetched(callId: fetch.callId, status: UInt16(clamping: http.statusCode),
                                body: String(decoding: data, as: UTF8.self))
    }
}
