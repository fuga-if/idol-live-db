import Foundation
import os

/// 画面に出す語 (曲種別・催しの種別と性格・参加形態・チケットの日付・タグのカテゴリ)。
///
/// 語はコア (imas-core `vocabulary`) が持つ。ここは起動後に 1 回だけ引いて、生値 → 語を
/// 引く口を並べるだけ (行ごとに FFI を呼ばない)。並びは選択肢に出す並び。
enum Vocab {
    static let table: Vocabulary = vocabulary()

    /// 曲種別。知らない値は nil (出さない)。古い値 (`group` / `original` / `unknown`) の読み方も
    /// コア (`song_type_term`)。一覧の行から引かれるので値ごとに覚える (種類は有界)。
    static func songType(_ raw: String?) -> VocabularyTerm? {
        guard let raw else { return nil }
        if let cached = songTypeCache.withLock({ $0[raw] }) { return cached }
        let term = songTypeTerm(value: raw)
        songTypeCache.withLock { $0[raw] = .some(term) }
        return term
    }

    private static let songTypeCache = OSAllocatedUnfairLock<[String: VocabularyTerm?]>(initialState: [:])

    static func eventKind(_ raw: String) -> VocabularyTerm? { term(in: table.eventKinds, raw) }
    static func eventType(_ raw: String) -> VocabularyTerm? { term(in: table.eventTypes, raw) }
    static func attendanceType(_ raw: String) -> VocabularyTerm? { term(in: table.attendanceTypes, raw) }
    /// チケットの日付の語。`value` は events の列名 (`ticket_deadline` 等)。
    static func ticketDate(_ column: String) -> VocabularyTerm? { term(in: table.ticketDates, column) }

    private static func term(in terms: [VocabularyTerm], _ value: String?) -> VocabularyTerm? {
        guard let value else { return nil }
        return terms.first { $0.value == value }
    }
}
