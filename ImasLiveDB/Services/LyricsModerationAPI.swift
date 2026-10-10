import Foundation

/// 歌詞の報告と、モデレーターの公開状態の操作。どの応答にも歌詞の本文は含まれない。
actor LyricsModerationAPI {
    static let shared = LyricsModerationAPI()
    private init() {}

    private let client = APIClient.noDiskCache

    /// 報告の理由 (サーバの `LYRICS_REPORT_REASONS` と同じ鍵)。
    enum ReportReason: String, CaseIterable, Sendable {
        case copied, wrong, rights, other

        var label: String {
            switch self {
            case .copied: "歌詞サイト・他サービスからの転載"
            case .wrong: "歌詞の誤り"
            case .rights: "権利者としての削除の求め"
            case .other: "その他"
            }
        }
    }

    private struct ReportBody: Encodable { let reason: String; let note: String }

    /// `POST /songs/:id/lyrics-report`。運営の GitHub の issue になる。
    func report(songId: String, reason: ReportReason, note: String = "") async throws {
        try await client.requestVoid("POST", path: "/songs/\(songId)/lyrics-report",
                                     body: ReportBody(reason: reason.rawValue, note: note), authorized: true)
    }

    private struct StatusBody: Encodable { let songIds: [String]; let status: String }

    /// `POST /admin/lyrics/status`。公開 ⇄ 非公開 (本文は消さない)。
    func setPublished(songId: String, _ isPublished: Bool) async throws {
        try await client.requestVoid("POST", path: "/admin/lyrics/status",
                                     body: StatusBody(songIds: [songId], status: isPublished ? "published" : "draft"),
                                     authorized: true)
    }

    /// `POST /admin/lyrics/:id/restore`。投稿で上書きされる前の版に 1 つ戻す。
    func restorePrevious(songId: String) async throws {
        try await client.requestVoid("POST", path: "/admin/lyrics/\(songId)/restore", authorized: true)
    }
}
