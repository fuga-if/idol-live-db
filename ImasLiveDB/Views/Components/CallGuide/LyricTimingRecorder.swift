import Foundation
import Observation
import OSLog

/// 歌詞行とコールの再生位置 (タイミング) を付ける・直す画面の状態。
///
/// 段は 2 本: 歌詞の行と、コール。どちらも「歌い出しで押す」で次の 1 つを記録し、
/// タイムラインで前後に寄せる。保存 (`PUT /songs/{id}/timings`) するまでサーバにも
/// 端末にも残さない。行の本文・コールの文言は持たない (id と種別だけ)。
///
/// 「次に記録する行」の決め方はコア (`lyricNextRecordable`) が持つ。
@Observable
@MainActor
final class LyricTimingRecorder: Identifiable {
    enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)
    }

    /// 記録する段。
    enum Lane: Hashable {
        case lines
        case calls
    }

    let songId: String
    /// 表示順の行 ID。
    let lineIds: [String]
    /// 曲の順 (行の順 → 行の中の順) に並べたコールの ID と、ぶら下がる行の添字。
    let callIds: [String]
    let callLineIndexes: [Int]
    /// 表示順の各行の種別 (`lyric` / `marker` / `blank`)。コアへ渡す。
    private let kinds: [String]
    /// 表示順の各行の開始 ms。
    private(set) var starts: [Int?]
    /// 曲の順の各コールの開始 ms。
    private(set) var callStarts: [Int?]
    /// いま記録している段。
    var lane: Lane = .lines
    /// 次に記録する行 / コールの添字。最後まで記録したら nil。
    private(set) var cursor: Int?
    private(set) var callCursor: Int?
    private(set) var saveState: SaveState = .idle

    private let originalStarts: [Int?]
    private let originalCallStarts: [Int?]
    /// 取り消し用。1 回ごとに「どの段のどれが・前は何だったか・カーソルはどこだったか」を積む。
    private var history: [(lane: Lane, index: Int, previous: Int?, cursor: Int?)] = []
    /// 直前の履歴が「微調整」か。同じものを続けて寄せている間は 1 回の取り消しにまとめる
    /// (つまみをなぞると 1 秒に何十回も値が変わるので、1 つずつ戻させない)。
    private var lastWasAdjust = false
    private let writer: any CallGuideWriting

    init(lyrics: Lyrics, songId: String,
         writer: any CallGuideWriting = AppContainer.shared.callGuideWriting) {
        self.songId = songId
        self.lineIds = lyrics.lines.map(\.id)
        let kinds = lyrics.lines.map(\.kind.rawValue)
        self.kinds = kinds
        let starts = lyrics.lines.map(\.startMs)
        self.starts = starts
        self.originalStarts = starts
        let calls = lyrics.lines.enumerated().flatMap { i, line in line.calls.map { (i, $0) } }
        self.callIds = calls.map(\.1.id)
        self.callLineIndexes = calls.map(\.0)
        let callStarts = calls.map(\.1.startMs)
        self.callStarts = callStarts
        self.originalCallStarts = callStarts
        self.writer = writer
        // 途中から続けられるよう、まだ時刻の無い最初のものから始める。全部あれば先頭から。
        self.cursor = Self.firstUntimed(starts) { lyricNextRecordable(kinds: kinds, after: $0) }
        self.callCursor = Self.firstUntimed(callStarts) { after in
            let next = after.map { Int($0) + 1 } ?? 0
            return next < callStarts.count ? UInt32(next) : nil
        }
    }

    private static func firstUntimed(_ starts: [Int?], next: (UInt32?) -> UInt32?) -> Int? {
        let first = next(nil).map(Int.init)
        var candidate = first
        while let index = candidate, starts[index] != nil {
            candidate = next(UInt32(index)).map(Int.init)
        }
        return candidate ?? first
    }

    var isDirty: Bool { starts != originalStarts || callStarts != originalCallStarts }
    var canUndo: Bool { !history.isEmpty }
    var hasCalls: Bool { !callIds.isEmpty }
    var cursorLineId: String? { cursor.map { lineIds[$0] } }

    /// 行またはコールの開始 ms (id で引く)。
    func start(for id: String) -> Int? {
        if let i = lineIds.firstIndex(of: id) { return starts[i] }
        if let i = callIds.firstIndex(of: id) { return callStarts[i] }
        return nil
    }

    /// 記録できる行か (空行は記録しない)。判定はコアの「次の行」と同じ規則に寄せる。
    func isRecordable(_ lineId: String) -> Bool {
        guard let index = lineIds.firstIndex(of: lineId) else { return false }
        let previous = index == 0 ? nil : UInt32(index - 1)
        return lyricNextRecordable(kinds: kinds, after: previous) == UInt32(index)
    }

    /// いま記録している段の「次」。
    var laneCursor: Int? { lane == .lines ? cursor : callCursor }

    /// いま記録している段の次の 1 つを、今の再生位置で記録する (大きい記録ボタン)。
    func recordNext(positionMs: Int) {
        switch lane {
        case .lines:
            guard let index = cursor else { return }
            history.append((.lines, index, starts[index], cursor))
            starts[index] = positionMs
            cursor = lyricNextRecordable(kinds: kinds, after: UInt32(index)).map(Int.init)
        case .calls:
            guard let index = callCursor else { return }
            history.append((.calls, index, callStarts[index], callCursor))
            callStarts[index] = positionMs
            callCursor = index + 1 < callIds.count ? index + 1 : nil
        }
        lastWasAdjust = false
    }

    /// 行またはコールの開始を指定の時刻にする (つまみ・微調整)。カーソルは動かさない。
    func adjust(id: String, toMs ms: Int) {
        let lane: Lane
        let index: Int
        if let i = lineIds.firstIndex(of: id), isRecordable(id) {
            (lane, index) = (.lines, i)
        } else if let i = callIds.firstIndex(of: id) {
            (lane, index) = (.calls, i)
        } else {
            return
        }
        let current = lane == .lines ? starts[index] : callStarts[index]
        if !(lastWasAdjust && history.last?.lane == lane && history.last?.index == index) {
            history.append((lane, index, current, lane == .lines ? cursor : callCursor))
        }
        if lane == .lines { starts[index] = max(0, ms) } else { callStarts[index] = max(0, ms) }
        lastWasAdjust = true
    }

    /// 前後に寄せる (-0.1 秒 / +0.1 秒)。記録の無いものは動かさない。
    func nudge(id: String, byMs delta: Int) {
        guard let current = start(for: id) else { return }
        adjust(id: id, toMs: current + delta)
    }

    /// 表示順の各行の開始 ms (コアに渡す形)。
    var startsForCore: [Int64?] { starts.map { $0.map(Int64.init) } }
    /// 曲の順の各コールの開始 ms (コアに渡す形)。
    var callStartsForCore: [Int64?] { callStarts.map { $0.map(Int64.init) } }

    /// 直前の記録を取り消す (カーソルも戻す)。
    func undo() {
        guard let last = history.popLast() else { return }
        lastWasAdjust = false
        switch last.lane {
        case .lines:
            starts[last.index] = last.previous
            cursor = last.cursor
        case .calls:
            callStarts[last.index] = last.previous
            callCursor = last.cursor
        }
    }

    func save() async -> Bool {
        guard saveState != .saving else { return false }
        saveState = .saving
        let lines = zip(lineIds, starts).map { LyricTimingPayload.Line(id: $0, startMs: $1) }
        let calls = zip(callIds, callStarts).map { LyricTimingPayload.Line(id: $0, startMs: $1) }
        do {
            try await writer.updateLyricTimings(songId: songId, lines: lines, calls: calls)
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
