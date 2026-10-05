import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "lyric_annotations")

/// コールガイド・歌詞のタイミングがある曲の印を端末に覚えておく。
///
/// 絞り込みを押すたびに通信しないよう、`GET /lyrics/annotations` を全ページ取って
/// 曲 id の集合を UserDefaults に置く (歌詞ではなく曲 id だけなので置いてよい)。
/// 1 時間より古ければ次に使うときに取り直し、取り直せなければ古い分で絞る。
/// 自分がコール・タイミングを保存した曲は、取り直しを待たずに [mark] で印を付ける。
actor LyricAnnotationStore: LyricAnnotationProviding {
    static let shared = LyricAnnotationStore()

    private struct Snapshot: Codable {
        var calls: Set<String>
        var timings: Set<String>
        var parts: Set<String>
        var fetchedAt: Date
    }

    private let reader: any LyricAnnotationReading
    private let defaults: UserDefaults
    private let key: String
    private let maxAge: TimeInterval
    private var snapshot: Snapshot?
    /// 取り直しの最中なら、同時に来た呼び出しはそれを待つ (二重に全ページ取らない)。
    private var refreshing: Task<Snapshot, Error>?

    /// - Parameter suiteName: 置き場の UserDefaults (nil = 標準)。テストは別の置き場を渡す。
    init(reader: any LyricAnnotationReading = CallGuideAPI.shared,
         suiteName: String? = nil,
         // パート分けを足したので鍵を替える (古い置き場には parts が無い)。
         key: String = "lyric_annotations_v2",
         maxAge: TimeInterval = 60 * 60) {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.reader = reader
        self.defaults = defaults
        self.key = key
        self.maxAge = maxAge
        if let data = defaults.data(forKey: key) {
            snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        }
    }

    func songIds(_ kind: LyricAnnotationKind) async throws -> Set<String> {
        let current: Snapshot
        if let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < maxAge {
            current = snapshot
        } else {
            do {
                current = try await refresh()
            } catch {
                guard let snapshot else { throw error }
                logger.warning("refresh_failed_using_cache: \(error.localizedDescription)")
                current = snapshot
            }
        }
        switch kind {
        case .calls: return current.calls
        case .timings: return current.timings
        case .parts: return current.parts
        }
    }

    /// 自分が保存した曲に印を付ける / 外す (次の取り直しを待たない)。
    func mark(songId: String, _ kind: LyricAnnotationKind, _ on: Bool) {
        guard var s = snapshot else { return }
        switch (kind, on) {
        case (.calls, true): s.calls.insert(songId)
        case (.calls, false): s.calls.remove(songId)
        case (.timings, true): s.timings.insert(songId)
        case (.timings, false): s.timings.remove(songId)
        case (.parts, true): s.parts.insert(songId)
        case (.parts, false): s.parts.remove(songId)
        }
        save(s)
    }

    /// 全ページを取って覚え直す。
    private func refresh() async throws -> Snapshot {
        if let refreshing { return try await refreshing.value }
        let reader = reader
        let task = Task { () throws -> Snapshot in
            var calls = Set<String>()
            var timings = Set<String>()
            var parts = Set<String>()
            var after: String?
            // 曲数は 3,000 未満。ページの上限 (2,000) で数回。無限に回らないよう回数にも蓋。
            for _ in 0..<20 {
                let page = try await reader.lyricAnnotations(after: after, limit: 1000)
                for song in page.songs {
                    if song.calls { calls.insert(song.songId) }
                    if song.timings { timings.insert(song.songId) }
                    if song.parts { parts.insert(song.songId) }
                }
                guard let next = page.next else { break }
                after = next
            }
            return Snapshot(calls: calls, timings: timings, parts: parts, fetchedAt: Date())
        }
        refreshing = task
        defer { refreshing = nil }
        let fresh = try await task.value
        save(fresh)
        return fresh
    }

    private func save(_ s: Snapshot) {
        snapshot = s
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }
}
