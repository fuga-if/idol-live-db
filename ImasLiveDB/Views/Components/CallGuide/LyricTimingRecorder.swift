import Foundation
import Observation
import OSLog

/// 歌詞行の再生位置 (タイミング) を記録するモードの状態。
///
/// Apple Music のフル再生を聴きながら、歌い出しに合わせて行をタップしてもらう。
/// 記録はその場の再生位置を行に入れるだけで、保存 (`PUT /songs/{id}/timings`) するまで
/// サーバにも端末にも残さない。行の本文は持たない (行 ID と種別だけ)。
///
/// 「次にタップする行」の決め方はコア (`lyricNextRecordable`) が持つ。
@Observable
@MainActor
final class LyricTimingRecorder {
    enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)
    }

    let songId: String
    /// 表示順の行 ID。
    let lineIds: [String]
    /// 表示順の各行の種別 (`lyric` / `marker` / `blank`)。コアへ渡す。
    private let kinds: [String]
    /// 表示順の各行の開始 ms。
    private(set) var starts: [Int?]
    /// 次にタップしてほしい行の添字。最後まで記録したら nil。
    private(set) var cursor: Int?
    private(set) var saveState: SaveState = .idle

    private let original: [Int?]
    /// 取り消し用。記録 1 回ごとに「どの行が・前は何だったか・カーソルはどこだったか」を積む。
    private var history: [(index: Int, previous: Int?, cursor: Int?)] = []
    private let writer: any CallGuideWriting

    init(lyrics: Lyrics, songId: String,
         writer: any CallGuideWriting = AppContainer.shared.callGuideWriting) {
        self.songId = songId
        self.lineIds = lyrics.lines.map(\.id)
        self.kinds = lyrics.lines.map(\.kind.rawValue)
        let starts = lyrics.lines.map(\.startMs)
        self.starts = starts
        self.original = starts
        self.writer = writer
        self.cursor = lyricNextRecordable(kinds: kinds, after: nil).map(Int.init)
    }

    var isDirty: Bool { starts != original }
    var canUndo: Bool { !history.isEmpty }
    var cursorLineId: String? { cursor.map { lineIds[$0] } }

    func start(for lineId: String) -> Int? {
        lineIds.firstIndex(of: lineId).flatMap { starts[$0] }
    }

    /// 記録できる行か (空行は記録しない)。判定はコアの「次の行」と同じ規則に寄せる。
    func isRecordable(_ lineId: String) -> Bool {
        guard let index = lineIds.firstIndex(of: lineId) else { return false }
        let previous = index == 0 ? nil : UInt32(index - 1)
        return lyricNextRecordable(kinds: kinds, after: previous) == UInt32(index)
    }

    /// その行の歌い出しを今の再生位置で記録し、カーソルを次の行へ進める。
    func record(lineId: String, positionMs: Int) {
        guard let index = lineIds.firstIndex(of: lineId), isRecordable(lineId) else { return }
        history.append((index, starts[index], cursor))
        starts[index] = positionMs
        cursor = lyricNextRecordable(kinds: kinds, after: UInt32(index)).map(Int.init)
    }

    /// 直前の記録を取り消す (カーソルも戻す)。
    func undo() {
        guard let last = history.popLast() else { return }
        starts[last.index] = last.previous
        cursor = last.cursor
    }

    func save() async -> Bool {
        guard saveState != .saving else { return false }
        saveState = .saving
        let lines = zip(lineIds, starts).map { LyricTimingPayload.Line(id: $0, startMs: $1) }
        do {
            try await writer.updateLyricTimings(songId: songId, lines: lines)
            saveState = .idle
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Logger.database.error("lyric_timings_save_failed: \(message)")
            saveState = .failed(message)
            return false
        }
    }
}
