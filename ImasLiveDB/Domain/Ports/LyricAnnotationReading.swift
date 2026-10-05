import Foundation

/// コールガイド・歌詞のタイミングがある曲の id をページで読むポート (`GET /lyrics/annotations`)。
///
/// 返るのは曲 id と 2 つの真偽だけ (歌詞もコールも時刻も含まない)。
protocol LyricAnnotationReading: Sendable {
    func lyricAnnotations(after: String?, limit: Int) async throws -> LyricAnnotationsPage
}

/// 1 ページぶん。`next` が nil なら最後。
struct LyricAnnotationsPage: Decodable, Sendable, Equatable {
    struct Song: Decodable, Sendable, Equatable {
        let songId: String
        let calls: Bool
        let timings: Bool
        /// パート分けがある。古い Worker・キャッシュは返さないので false に倒す。
        var parts: Bool = false

        private enum CodingKeys: String, CodingKey { case songId, calls, timings, parts }
        init(songId: String, calls: Bool, timings: Bool, parts: Bool = false) {
            self.songId = songId; self.calls = calls; self.timings = timings; self.parts = parts
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            songId = try c.decode(String.self, forKey: .songId)
            calls = try c.decode(Bool.self, forKey: .calls)
            timings = try c.decode(Bool.self, forKey: .timings)
            parts = try c.decodeIfPresent(Bool.self, forKey: .parts) ?? false
        }
    }
    let songs: [Song]
    let next: String?
}

/// 曲に付いた印の種類 (曲一覧の絞り込み)。
enum LyricAnnotationKind: Sendable {
    /// コールガイド (コール・手拍子) がある。
    case calls
    /// 歌詞のタイミング (行の再生位置) がある。
    case timings
    /// パート分け (誰が歌うか) がある。
    case parts
}

/// 曲一覧の絞り込みが「その印が付いた曲の id」を引く口。テストでは差し替える。
protocol LyricAnnotationProviding: Sendable {
    /// 印が付いた曲の id。端末に覚えている分が古ければ取り直す。
    /// 取り直せなくても覚えている分があればそれを返す。一度も取れていなければ throw。
    func songIds(_ kind: LyricAnnotationKind) async throws -> Set<String>
}
