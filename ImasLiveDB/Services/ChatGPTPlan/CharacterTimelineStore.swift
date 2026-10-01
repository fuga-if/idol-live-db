import Foundation
import Observation

/// キャラ機能 (トーク・タイムライン) のオプトイン。既定 OFF。設定の ChatGPT 連携画面で有効にする。
enum CharacterFeatures {
    static let enabledKey = "chatgpt_plan.character_features"
    /// 一言の断り。有効にするとき・各画面の上部に出す。
    static let disclaimer = "AI による非公式のなりきりで、公式の発言ではありません。"
}

/// タイムラインの投稿 1 件 (キャラの投稿と、その下のリプライ)。
struct TimelinePost: Codable, Identifiable, Hashable {
    struct Reply: Codable, Identifiable, Hashable {
        var id = UUID()
        /// nil は利用者 (プロデューサー) のリプライ。
        var idolID: String?
        var text: String
        var createdAt = Date()
    }

    var id = UUID()
    var idolID: String
    var text: String
    var createdAt = Date()
    var replies: [Reply] = []
}

/// タイムラインを端末内に保存し、ChatGPT プランで続きを生成する。
@MainActor
@Observable
final class CharacterTimelineStore {
    static let shared = CharacterTimelineStore()

    /// 新しい順。
    private(set) var posts: [TimelinePost] = []
    private(set) var isGenerating = false
    /// リプライを返している投稿。
    private(set) var replyingPostID: UUID?
    var errorMessage: String?
    var usageLimitHit = false

    private let url: URL
    private static let maxPosts = 200

    private init() {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        url = dir.appendingPathComponent("chatgpt_plan", isDirectory: true).appendingPathComponent("timeline.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([TimelinePost].self, from: data) {
            posts = saved
        }
    }

    /// 続きを生成して先頭に足す。顔ぶれと話題はコアが決める (担当がいればその子を中心に)。
    func generate(model: String) async {
        guard !isGenerating, !model.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let store = try await AppContainer.shared.coreSnapshot.loadedStore()
            let oshi = UserMarkService.shared.allMarked(kind: .myPick, entity: .idol)
            let previous = posts.prefix(12).map(\.text)
            let request = try store.assistantTimelineRequest(
                oshiIds: oshi, previousPosts: Array(previous), seed: UInt64.random(in: 1 ... .max)
            )
            let json = try await complete(ChatGPTPlanClient.Request(
                model: model,
                instructions: request.instructions,
                input: [ChatGPTPlanClient.userMessage(request.input)],
                textFormatJSON: request.textFormatJson,
                includeEncryptedReasoning: false
            ))
            let generated = try Self.parse(json, allowed: Set(request.castIds))
            guard !generated.isEmpty else { throw TimelineError.empty }
            // 新しい投稿ほど上。生成順に少しずつ時刻をずらして並びを保つ。
            let now = Date()
            let stamped = generated.enumerated().map { offset, post -> TimelinePost in
                var post = post
                post.createdAt = now.addingTimeInterval(-Double(offset) * 60)
                return post
            }
            posts = Array((stamped + posts).prefix(Self.maxPosts))
            save()
        } catch {
            handle(error)
        }
    }

    /// 利用者が投稿にリプライし、その投稿のキャラが返す。
    func reply(to postID: UUID, text: String, authorName: String, model: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard replyingPostID == nil, !text.isEmpty, !model.isEmpty,
              let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[index].replies.append(.init(idolID: nil, text: text))
        save()
        replyingPostID = postID
        errorMessage = nil
        defer { replyingPostID = nil }
        let post = posts[index]
        do {
            let store = try await AppContainer.shared.coreSnapshot.loadedStore()
            guard let instructions = try store.assistantTimelineReplyInstructions(idolId: post.idolID) else {
                throw TimelineError.unknownIdol
            }
            let answer = try await complete(ChatGPTPlanClient.Request(
                model: model,
                instructions: instructions,
                input: [ChatGPTPlanClient.userMessage(
                    assistantTimelineReplyInput(postAuthor: authorName, postText: post.text, userText: text)
                )],
                includeEncryptedReasoning: false
            ))
            guard let i = posts.firstIndex(where: { $0.id == postID }) else { return }
            posts[i].replies.append(.init(idolID: post.idolID, text: answer.trimmingCharacters(in: .whitespacesAndNewlines)))
            save()
        } catch {
            handle(error)
        }
    }

    func clear() {
        posts = []
        save()
    }

    // MARK: - 内部

    enum TimelineError: LocalizedError {
        case empty, malformed, unknownIdol
        var errorDescription: String? {
            switch self {
            case .empty: "投稿が生成されませんでした。もう一度引っ張ってみてください"
            case .malformed: "生成された内容を読み取れませんでした。もう一度試してください"
            case .unknownIdol: "このアイドルのデータが見つかりませんでした"
            }
        }
    }

    /// 1 リクエストを最後まで受けて、本文をつなげて返す。
    private func complete(_ request: ChatGPTPlanClient.Request) async throws -> String {
        let token = try await ChatGPTPlanSession.shared.validAccessToken()
        var text = ""
        for try await event in ChatGPTPlanClient.stream(request, accessToken: token) {
            if case .delta(let delta) = event { text += delta }
        }
        try Task.checkCancellation()
        return text
    }

    private func handle(_ error: Error) {
        if let clientError = error as? ChatGPTPlanClient.ClientError, clientError.isUsageLimit {
            usageLimitHit = true
        }
        errorMessage = error.localizedDescription
    }

    /// 構造化出力 `{"posts":[{"idol_id","text","replies":[{"idol_id","text"}]}]}` を読む。
    /// 顔ぶれ以外の id が来たら (型で縛ってあるが念のため) その行は捨てる。
    private static func parse(_ json: String, allowed: Set<String>) throws -> [TimelinePost] {
        guard let object = ChatGPTPlanClient.jsonObject(json), let rows = object["posts"] as? [[String: Any]] else {
            throw TimelineError.malformed
        }
        return rows.compactMap { row in
            guard let idol = row["idol_id"] as? String, allowed.contains(idol),
                  let text = row["text"] as? String, !text.isEmpty else { return nil }
            let replies = (row["replies"] as? [[String: Any]] ?? []).compactMap { reply -> TimelinePost.Reply? in
                guard let idol = reply["idol_id"] as? String, allowed.contains(idol),
                      let text = reply["text"] as? String, !text.isEmpty else { return nil }
                return .init(idolID: idol, text: text)
            }
            return TimelinePost(idolID: idol, text: text, replies: replies)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(posts).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            // 保存できなくても表示は続けられる。
        }
    }
}
