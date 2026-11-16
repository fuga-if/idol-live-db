import Foundation

/// コール表の画像から読んだ中身の、曲ごとの置き場 (メモリだけ)。
///
/// 歌詞の無い曲では、先に歌詞を投稿してからでないとコールを付けられない。読んだコールを
/// ここに預けておき、歌詞が公開されたあとコールの編集で「入れる」を押すと当てる。
///
/// ⚠️ 中身には読んだ歌詞の字が入っているので、**メモリの外に出さない** (保存しない・送らない)。
@MainActor
@Observable
final class CallSheetDrafts {
    static let shared = CallSheetDrafts()

    private(set) var readings: [String: CallSheetReading] = [:]

    private init() {}

    func reading(for songId: String) -> CallSheetReading? { readings[songId] }
    func keep(_ reading: CallSheetReading, for songId: String) { readings[songId] = reading }
    func clear(_ songId: String) { readings[songId] = nil }
}
