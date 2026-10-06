import Foundation
import Observation

/// 歌詞の投稿の書きかけ (曲ごと)。投稿シートの外に置いて、シートや曲詳細が作り直されても
/// 入力が消えないようにする (同期の完了などで画面が組み直されると、シートの @State は消える)。
///
/// 端末のメモリにだけ置く (保存しない)。送れたとき・破棄したときに消す。
@MainActor @Observable
final class LyricSubmissionDrafts {
    static let shared = LyricSubmissionDrafts()

    struct Draft: Equatable {
        var text = ""
        var agreed = false
    }

    private(set) var drafts: [String: Draft] = [:]

    private init() {}

    func draft(for songId: String) -> Draft { drafts[songId] ?? Draft() }

    func update(_ songId: String, _ change: (inout Draft) -> Void) {
        var d = draft(for: songId)
        change(&d)
        drafts[songId] = d
    }

    func clear(_ songId: String) { drafts[songId] = nil }
}
