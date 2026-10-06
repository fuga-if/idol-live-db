import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "lyric_submission_api")

/// 歌詞の投稿 (`POST /songs/{song_id}/lyric-submissions`)。歌詞の無い曲ならその場で公開され、運営はあとから確認する。
/// 既に歌詞のある曲への投稿は上書きされず、直しの提案として預かられる。
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

    private struct Response: Decodable { let published: Bool }

    /// 送る。公開されたら true (歌詞の無い曲)、預かっただけなら false。
    func submit(songId: String, text: String) async throws -> Bool {
        do {
            let res: Response = try await client.request(
                "POST",
                path: "/songs/\(songId)/lyric-submissions",
                body: Body(agreedToGuideline: true, text: text),
                authorized: true
            )
            return res.published
        } catch {
            logger.warning("lyric_submission_failed: \(error.localizedDescription)")
            throw error
        }
    }
}
