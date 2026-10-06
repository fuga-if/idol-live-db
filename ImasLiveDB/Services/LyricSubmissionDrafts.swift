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
        /// 読み取りに自信の無かった行 (見直してもらうために出す)。
        var doubtfulLines: [String] = []
        /// 読み仮名。本文 (`text`) には記法 (《》・｜) を入れず、ここに分けて持つ。送るときに合わせる。
        var rubies: [RubyMark] = []
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

    /// 本文を書き換える。記法 (親字《よみ》) が入ってきたら (読み取り・貼り付け・手で打った《》)、
    /// 本文から外して読み仮名の一覧へ移す。画面に記法を見せないため。
    func setText(_ songId: String, _ text: String) {
        update(songId) { d in
            var plain = text
            var added: [RubyMark] = []
            if text.contains("》") {
                let split = lyricRubySplit(text: text)
                plain = split.plain
                added = split.marks
            }
            // 書き換えで読み仮名の付いた字の何番目かがずれないよう、付け直してから足す。
            d.rubies = (d.rubies.isEmpty ? [] : lyricRubyRebase(oldPlain: d.text, newPlain: plain, marks: d.rubies)) + added
            d.text = plain
        }
    }
}
