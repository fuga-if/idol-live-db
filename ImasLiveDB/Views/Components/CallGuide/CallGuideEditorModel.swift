import Foundation
import OSLog

/// コールガイド編集モードの状態。
///
/// 元の `Lyrics` は不変なので、編集中は行のコピーをここに持ち、保存に成功したら
/// 呼び出し側が束ね取得をやり直して差し替える (サーバが付け直した id / stale を反映するため)。
///
/// ⚠️ ここに載るのは歌詞本文を含む `LyricLine` なので、**メモリの外に出さないこと**。
/// 保存時は歌詞本文を持たない `CallGuidePayload` に詰め替えて送る。
@MainActor
@Observable
final class CallGuideEditorModel {
    enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)
    }

    let songId: String
    private(set) var lines: [LyricLine]
    private(set) var saveState: SaveState = .idle

    /// 読み込み時のスナップショット (行 id → 手拍子 / コール)。差分の判定に使う。
    private let original: [String: (clap: LyricClap?, calls: [LyricCall])]

    private let writer: any CallGuideWriting

    init(lyrics: Lyrics,
         songId: String,
         writer: any CallGuideWriting = AppContainer.shared.callGuideWriting) {
        self.songId = songId
        self.lines = lyrics.lines
        self.original = Dictionary(
            lyrics.lines.map { ($0.id, (clap: $0.clap, calls: $0.calls)) },
            uniquingKeysWith: { first, _ in first }
        )
        self.writer = writer
    }

    // MARK: - 参照

    func line(id: String) -> LyricLine? { lines.first { $0.id == id } }

    /// 「歌詞が編集されてアンカーがズレた」コール。編集モードの先頭で目立たせ、選び直させる。
    var staleCalls: [(line: LyricLine, call: LyricCall)] {
        lines.flatMap { line in line.calls.filter(\.isStale).map { (line, $0) } }
    }

    var isDirty: Bool { !changedLineIds.isEmpty }

    // MARK: - 編集

    func setClap(lineId: String, clap: LyricClap?) {
        mutate(lineId) { $0.clap = clap }
    }

    /// 選択範囲に新しいコールを足す。同一アンカーに複数並ぶことがあるので、既存は消さない。
    /// 配列順が表示順なので**末尾に足す**。
    func addCall(lineId: String, start: Int, end: Int, anchorText: String,
                 text: String, emphasis: CallEmphasis) {
        mutate(lineId) {
            $0.calls.append(LyricCall(id: Self.newCallId(), start: start, end: end,
                                      anchorText: anchorText, text: text,
                                      emphasis: emphasis, stale: nil))
        }
    }

    func updateCall(lineId: String, callId: String, text: String, emphasis: CallEmphasis) {
        mutate(lineId) { line in
            guard let index = line.calls.firstIndex(where: { $0.id == callId }) else { return }
            line.calls[index].text = text
            line.calls[index].emphasis = emphasis
        }
    }

    func deleteCall(lineId: String, callId: String) {
        mutate(lineId) { $0.calls.removeAll { $0.id == callId } }
    }

    /// ズレたコールのアンカーを選び直す。選び直した時点で `stale` の印は落とす。
    ///
    /// 歌詞が編集されると、掛かっていた語が**別の行へ移っている**ことがあるので、
    /// 行をまたいだ付け替えも受ける (同じ行なら並び順を保ったまま書き換える)。
    func reanchor(callId: String, from sourceLineId: String, to targetLineId: String,
                  start: Int, end: Int, anchorText: String) {
        guard let sourceIndex = lines.firstIndex(where: { $0.id == sourceLineId }),
              let callIndex = lines[sourceIndex].calls.firstIndex(where: { $0.id == callId })
        else { return }

        if sourceLineId == targetLineId {
            lines[sourceIndex].calls[callIndex].start = start
            lines[sourceIndex].calls[callIndex].end = end
            lines[sourceIndex].calls[callIndex].anchorText = anchorText
            lines[sourceIndex].calls[callIndex].stale = nil
            return
        }

        var moved = lines[sourceIndex].calls.remove(at: callIndex)
        moved.start = start
        moved.end = end
        moved.anchorText = anchorText
        moved.stale = nil
        guard let targetIndex = lines.firstIndex(where: { $0.id == targetLineId }) else {
            // 付け替え先が見つからないなら元に戻す (取りこぼしでコールを消さない)。
            lines[sourceIndex].calls.insert(moved, at: callIndex)
            return
        }
        lines[targetIndex].calls.append(moved)
    }

    private func mutate(_ lineId: String, _ body: (inout LyricLine) -> Void) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        body(&lines[index])
    }

    /// 端末側で採番する暫定 id。サーバは保存時に正規の id を付け直してよい
    /// (保存後に束ねを取り直すので、こちらの id は残らなくても構わない)。
    private static func newCallId() -> String {
        "c_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    }

    // MARK: - 保存

    /// 送信する行。
    ///
    /// **変更のあった行 ∪ 現在コール指定を持つ行**を送る。サーバ側が
    /// 「載っていない行はそのまま」と解釈しても「載っていない行は消す」と解釈しても
    /// 同じ結果になる (前者は消した行が空の指定で載っているので消え、後者は残す行が
    /// 全部載っているので消えない)。どちらの契約でも壊れない形をあえて選んでいる。
    private var linesToSend: [CallGuidePayload.Line] {
        let changed = changedLineIds
        return lines
            .filter { changed.contains($0.id) || $0.clap != nil || !$0.calls.isEmpty }
            .map { line in
                CallGuidePayload.Line(
                    id: line.id,
                    clap: line.clap?.rawValue,
                    calls: line.calls.map(CallGuidePayload.Call.init)
                )
            }
    }

    private var changedLineIds: Set<String> {
        var result: Set<String> = []
        for line in lines {
            let before = original[line.id]
            if before?.clap != line.clap || (before?.calls ?? []) != line.calls {
                result.insert(line.id)
            }
        }
        return result
    }

    /// 保存する。成功したら true (呼び出し側で束ねを取り直す)。
    func save() async -> Bool {
        guard saveState != .saving else { return false }
        saveState = .saving
        do {
            try await writer.updateCallGuide(songId: songId, lines: linesToSend)
            saveState = .idle
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Logger.database.error("call_guide_save_failed: \(message)")
            saveState = .failed(message)
            return false
        }
    }
}
