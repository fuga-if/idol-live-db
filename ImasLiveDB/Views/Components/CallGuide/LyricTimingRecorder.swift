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
        /// パート分け (誰が歌うか)。聴きながら、いま歌っている行に歌う人を付ける。
        case parts
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
    /// 表示順の各行の被せ指定 ("overlay" / "main" / nil = 括弧で決める)。
    private(set) var layers: [String?]
    private let originalLayers: [String?]
    /// 表示順の各行の歌唱者 (アイドル id)。パートの段で付け外しする。
    private(set) var singers: [[String]]
    private let originalSingers: [[String]]
    /// 表示順の各行の、途中で歌う人が変わるところ。
    private(set) var breaks: [[LyricLinePartBreak]]
    private let originalBreaks: [[LyricLinePartBreak]]
    /// 各行の本文のスカラー数 (区切りの位置の上限)。
    private let lengths: [Int]
    /// パートの取り消し用 (history の .parts と同じ順に、前の歌唱者と区切りを積む)。
    private var partsUndo: [(singers: [String], breaks: [LyricLinePartBreak])] = []
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
        let layers = lyrics.lines.map(\.layer)
        self.layers = layers
        self.originalLayers = layers
        let singers = lyrics.lines.map(\.singers)
        self.singers = singers
        self.originalSingers = singers
        let breaks = lyrics.lines.map(\.partBreaks)
        self.breaks = breaks
        self.originalBreaks = breaks
        self.lengths = lyrics.lines.map { $0.text.unicodeScalars.count }
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

    var isDirty: Bool {
        starts != originalStarts || callStarts != originalCallStarts || layers != originalLayers
            || partsChanged
    }

    private var partsChanged: Bool { singers != originalSingers || breaks != originalBreaks }

    /// 行のひと続き (頭が `segmentStart`) の歌唱者に `idolId` を付け外しする。
    /// 並びは `order` (原唱者の並び) にそろえる。`segmentStart` が 0 なら行の頭 (区切りが無ければ行まるごと)。
    func toggleSinger(lineId: String, segmentStart: Int = 0, idolId: String, order: [String]) {
        guard let i = lineIds.firstIndex(of: lineId), kinds[i] == "lyric" else { return }
        let k = breaks[i].firstIndex { $0.at == segmentStart }
        guard segmentStart == 0 || k != nil else { return }
        var list = k.map { breaks[i][$0].singers } ?? singers[i]
        pushPartsUndo(i)
        if let j = list.firstIndex(of: idolId) { list.remove(at: j) } else { list.append(idolId) }
        list.sort { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        if let k { breaks[i][k].singers = list } else { singers[i] = list }
    }

    /// 行の字の範囲 `start..end` から歌う人をみな外す (消しゴム)。規則はコア (`lyricPartErase`)。
    func erase(lineId: String, start: Int, end: Int) {
        guard let i = lineIds.firstIndex(of: lineId), kinds[i] == "lyric" else { return }
        pushPartsUndo(i)
        let erased = lyricPartErase(len: UInt32(lengths[i]), singers: singers[i], breaks: breaks[i].map(\.core),
                                    start: UInt32(max(0, start)), end: UInt32(max(0, end)))
        singers[i] = erased.singers
        breaks[i] = erased.breaks.map(LyricLinePartBreak.init)
    }

    /// 行の字の範囲 `start..end` に `idolIds` (筆。複数人を一度に) を塗る / 外す (範囲の字がみな筆の全員入りなら外す)。
    /// 区切りは塗った結果から作り直す。規則はコア (`lyricPartPaint`)。
    func paint(lineId: String, start: Int, end: Int, idolIds: [String], order: [String]) {
        guard let i = lineIds.firstIndex(of: lineId), kinds[i] == "lyric" else { return }
        pushPartsUndo(i)
        let painted = lyricPartPaint(len: UInt32(lengths[i]), singers: singers[i], breaks: breaks[i].map(\.core),
                                     start: UInt32(max(0, start)), end: UInt32(max(0, end)), idols: idolIds, order: order)
        singers[i] = painted.singers
        breaks[i] = painted.breaks.map(LyricLinePartBreak.init)
    }

    /// 行のスカラー位置 `at` に、歌う人の区切りを置く / 外す (置くとその位置の人を引き継ぐ)。規則はコア。
    func toggleBreak(lineId: String, at: Int) {
        guard let i = lineIds.firstIndex(of: lineId), kinds[i] == "lyric" else { return }
        pushPartsUndo(i)
        breaks[i] = lyricPartToggleBreak(len: UInt32(lengths[i]), singers: singers[i],
                                         breaks: breaks[i].map(\.core), at: UInt32(at)).map(LyricLinePartBreak.init)
    }

    /// 行のひと続き (区切りが無ければ行まるごと 1 つ)。
    func segments(for lineId: String) -> [LyricPartSegment] {
        guard let i = lineIds.firstIndex(of: lineId) else { return [] }
        return lyricPartSegments(len: UInt32(lengths[i]), singers: singers[i], breaks: breaks[i].map(\.core))
    }

    /// 行の歌唱者を、ひとつ前の歌詞の行と同じにする (同じ人が続く所を 1 タップで)。
    func copyPreviousSingers(lineId: String) {
        guard let i = lineIds.firstIndex(of: lineId),
              let prev = (0..<i).reversed().first(where: { kinds[$0] == "lyric" }) else { return }
        pushPartsUndo(i)
        // 前の行の終わりを歌っている人を、この行の頭に付ける。
        singers[i] = breaks[prev].last?.singers ?? singers[prev]
    }

    private func pushPartsUndo(_ index: Int) {
        history.append((.parts, index, nil, nil))
        partsUndo.append((singers[index], breaks[index]))
        lastWasAdjust = false
    }

    func singers(for lineId: String) -> [String] {
        lineIds.firstIndex(of: lineId).map { singers[$0] } ?? []
    }

    /// 行の被せ指定を切り替える (被せ ⇄ メイン)。括弧の判定より指定が勝つ。
    func setOverlay(lineId: String, _ overlay: Bool) {
        guard let i = lineIds.firstIndex(of: lineId) else { return }
        layers[i] = overlay ? "overlay" : "main"
    }

    func layer(for lineId: String) -> String? {
        lineIds.firstIndex(of: lineId).flatMap { layers[$0] }
    }
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
    var laneCursor: Int? {
        switch lane {
        case .lines: return cursor
        case .calls: return callCursor
        case .parts: return nil
        }
    }

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
        case .parts:
            return
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
        case .parts:
            let previous = partsUndo.popLast()
            singers[last.index] = previous?.singers ?? []
            breaks[last.index] = previous?.breaks ?? []
        }
    }

    func save() async -> Bool {
        guard saveState != .saving else { return false }
        saveState = .saving
        let lines = lineIds.indices.map {
            LyricTimingPayload.Line(id: lineIds[$0], startMs: starts[$0], layer: layers[$0], sendsLayer: true)
        }
        let calls = zip(callIds, callStarts).map { LyricTimingPayload.Line(id: $0, startMs: $1) }
        do {
            try await writer.updateLyricTimings(songId: songId, lines: lines, calls: calls)
            if partsChanged {
                let parts = lineIds.indices.compactMap { i in
                    singers[i].isEmpty && breaks[i].isEmpty
                        ? nil : LyricPartsPayload.Line(id: lineIds[i], singers: singers[i], breaks: breaks[i])
                }
                try await writer.updateLyricParts(songId: songId, lines: parts)
            }
            // 曲一覧の「タイミングがある曲のみ」に、取り直しを待たずに載せる。
            await LyricAnnotationStore.shared.mark(songId: songId, .timings, starts.contains { $0 != nil })
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
