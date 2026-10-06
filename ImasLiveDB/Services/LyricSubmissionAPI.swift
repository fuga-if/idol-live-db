import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "lyric_submission_api")

/// 歌詞の投稿 (`POST /songs/{song_id}/lyric-submissions`)。確認待ちで預かられ、公開はモデレーターの確認後。
///
/// 本文 (歌詞) を送るので、歌詞に触れるほかの経路と同じく `APIClient.noDiskCache` を通す。
actor LyricSubmissionAPI {
    static let shared = LyricSubmissionAPI()

    private let client = APIClient.noDiskCache

    private init() {}

    private struct Body: Encodable {
        let agreedToGuideline: Bool
        let text: String
    }

    func submit(songId: String, text: String) async throws {
        do {
            try await client.requestVoid(
                "POST",
                path: "/songs/\(songId)/lyric-submissions",
                body: Body(agreedToGuideline: true, text: text),
                authorized: true
            )
        } catch {
            logger.warning("lyric_submission_failed: \(error.localizedDescription)")
            throw error
        }
    }
}
