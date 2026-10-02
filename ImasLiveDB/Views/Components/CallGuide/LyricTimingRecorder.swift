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
final class LyricTimingRecorder: Identifiable {
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
    /// 直前の履歴が「微調整」か。同じ行を続けて寄せている間は 1 回の取り消しにまとめる
    /// (つまみをなぞると 1 秒に何十回も値が変わるので、1 つずつ戻させない)。
    private var lastWasAdjust = false
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
        // 記録の途中から続けられるよう、まだ時刻の無い最初の行から始める。全部あれば先頭から。
        let kinds = self.kinds
        var candidate = lyricNextRecordable(kinds: kinds, after: nil).map(Int.init)
        let first = candidate
        while let index = candidate, starts[index] != nil {
            candidate = lyricNextRecordable(kinds: kinds, after: UInt32(index)).map(Int.init)
        }
        self.cursor = candidate ?? first
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
        lastWasAdjust = false
        starts[index] = positionMs
        cursor = lyricNextRecordable(kinds: kinds, after: UInt32(index)).map(Int.init)
    }

    /// 次の行 (カーソル) の歌い出しを今の再生位置で記録する (大きい記録ボタン)。
    func recordNext(positionMs: Int) {
        guard let id = cursorLineId else { return }
        record(lineId: id, positionMs: positionMs)
    }

    /// 行の歌い出しを指定の時刻にする (つまみ・微調整)。カーソルは動かさない。
    func adjust(lineId: String, toMs ms: Int) {
        guard let index = lineIds.firstIndex(of: lineId), isRecordable(lineId) else { return }
        if !(lastWasAdjust && history.last?.index == index) {
            history.append((index, starts[index], cursor))
        }
        starts[index] = max(0, ms)
        lastWasAdjust = true
    }

    /// 行の歌い出しを前後に寄せる (-0.1 秒 / +0.1 秒)。記録の無い行は動かさない。
    func nudge(lineId: String, byMs delta: Int) {
        guard let current = start(for: lineId) else { return }
        adjust(lineId: lineId, toMs: current + delta)
    }

    /// 表示順の各行の開始 ms (コアに渡す形)。
    var startsForCore: [Int64?] { starts.map { $0.map(Int64.init) } }

    /// 直前の記録を取り消す (カーソルも戻す)。
    func undo() {
        guard let last = history.popLast() else { return }
        lastWasAdjust = false
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
