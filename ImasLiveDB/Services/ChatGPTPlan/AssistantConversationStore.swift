import Foundation
import Observation

/// 画面に出す 1 発言。
struct AssistantMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    var createdAt = Date()
    /// 失敗した応答 (画面で再送できるようにする)。
    var failed = false
    // 書き込みの提案 (参戦登録など) は、後の段階でここにカードとして足す。
}

/// 会話 1 本。`items` は Responses API の input 項目 (JSON) で、毎回これを積み直して送る
/// (store: false なのでサーバ側には何も残らない)。
struct AssistantConversation: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [AssistantMessage] = []
    var items: [String] = []
    /// キャラとのトークならアイドル id (普通のチャットは nil)。
    var idolID: String?
}

/// 会話を端末内 (Application Support) に保存する。ファイル 1 つに全会話。
@MainActor
@Observable
final class AssistantConversationStore {
    static let chat = AssistantConversationStore(fileName: "assistant_chat.json")
    static let talk = AssistantConversationStore(fileName: "assistant_talk.json")

    private(set) var conversations: [AssistantConversation] = []
    private let url: URL

    private init(fileName: String) {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        url = dir.appendingPathComponent("chatgpt_plan", isDirectory: true).appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([AssistantConversation].self, from: data) {
            conversations = saved
        }
    }

    /// 新しい順。
    var sorted: [AssistantConversation] { conversations.sorted { $0.updatedAt > $1.updatedAt } }

    func conversation(_ id: UUID) -> AssistantConversation? {
        conversations.first { $0.id == id }
    }

    func upsert(_ conversation: AssistantConversation) {
        var conversation = conversation
        conversation.updatedAt = Date()
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[i] = conversation
        } else {
            conversations.append(conversation)
        }
        save()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            // 保存できなくても会話は続けられる (次の保存で書き直す)。
        }
    }
}
