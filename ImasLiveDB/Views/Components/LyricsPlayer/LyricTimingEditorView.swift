import SwiftUI

/// 歌詞行の時刻 (タイミング) を付ける・直す画面。
///
/// 1. ざっくり付ける … 曲を流しながら、下の大きいボタンを歌い出しに合わせて押す
///    (歌詞の行を狙ってタップしなくてよい)。押すたびに「次の行」が進む。
/// 2. 直す … 横長のタイムラインで行の帯を選び、-0.1 / +0.1 秒で寄せるか、
///    帯の頭のつまみをなぞる。「再生位置に合わせる」で今の位置にくっつける。
///    タイムラインの地をなぞると再生位置が動く (ちょい戻し)。
///
/// 保存するまでサーバにも端末にも残さない。行の本文は画面に出すだけで、送らない。
struct LyricTimingEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let song: Song
    let seed: String?
    let lyrics: Lyrics
    let playback: LyricsPlayback
    @State var recorder: LyricTimingRecorder
    /// 保存できたら呼ぶ (歌詞を取り直す)。
    let onSaved: () -> Void

    @State private var playheadMs = 0
    /// タイムラインをなぞっている間の位置。離したら再生位置をそこへ動かす。
    @State private var scrubMs: Int?
    @State private var selectedId: String?
    @State private var confirmDiscard = false
    @State private var saveError: String?
    @State private var startFailed = false
    @State private var recordToken = 0

    private var duration: Int {
        let lastStart = recorder.starts.compactMap { $0 }.max() ?? 0
        return playback.durationMs() ?? song.durationSec.map { $0 * 1000 } ?? lastStart + 8000
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp3)
            if recorder.hasCalls {
                ImasTabs(options: [LyricTimingRecorder.Lane.lines, .calls],
                         selection: Binding(get: { recorder.lane }, set: { recorder.lane = $0 }),
                         seed: seed) { $0 == .lines ? "歌詞" : "コール" }
                    .padding(.horizontal, DS.sp5)
                    .padding(.bottom, DS.sp3)
            }
            nowAndNext
                .padding(.horizontal, DS.sp5)
            Spacer(minLength: DS.sp4)
            timeline
            selectionControls
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp3)
            transport
                .padding(.top, DS.sp4)
            recordButton
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp4)
        }
        .background(DS.bg)
        .task { if !playback.isFullLoaded { startFailed = !(await playback.startFull()) } }
        .task(id: playback.isFullLoaded) { await poll() }
        .sensoryFeedback(.impact(weight: .medium), trigger: recordToken)
        .confirmationDialog("保存せずに閉じますか？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("保存せずに閉じる", role: .destructive) { dismiss() }
            Button("編集を続ける", role: .cancel) {}
        }
        .alert("保存できませんでした", isPresented: Binding(get: { saveError != nil },
                                                    set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .imasTheme(seed: seed)
    }

    // MARK: - 頭

    private var header: some View {
        HStack(spacing: DS.sp3) {
            ImasIconButton(systemImage: "xmark", label: "閉じる", size: .small) {
                if recorder.isDirty { confirmDiscard = true } else { dismiss() }
            }
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text("タイミング編集").imasText(.rowTitle)
                Text(song.title).imasText(.rowSubtitle).lineLimit(1)
            }
            Spacer(minLength: 0)
            ImasIconButton(systemImage: "arrow.uturn.backward", label: "取り消す", size: .small) {
                recorder.undo()
            }
            .disabled(!recorder.canUndo)
            ImasButton(title: "保存", role: .primary, size: .small, isLoading: recorder.saveState == .saving) {
                AppAnalytics.tap("lyric_timing.save")
                Task { await save() }
            }
            .disabled(!recorder.isDirty || recorder.saveState == .saving)
        }
    }

    // MARK: - 今の行と次の行

    private var shownMs: Int { scrubMs ?? playheadMs }

    private var currentIndex: Int? {
        lyricActiveLine(starts: recorder.startsForCore, positionMs: Int64(shownMs)).map(Int.init)
    }

    /// 曲の順に並べたコール (ぶら下がる行の添字つき)。recorder.callIds と同じ並び。
    private var allCalls: [(call: LyricCall, line: Int)] {
        lyrics.lines.enumerated().flatMap { i, line in line.calls.map { ($0, i) } }
    }

    @ViewBuilder
    private var nowAndNext: some View {
        if recorder.lane == .calls {
            callsNowAndNext
        } else {
            linesNowAndNext
        }
    }

    /// コールの段: いま出すコールと、次に記録するコール (どの行のコールかも添える)。
    private var callsNowAndNext: some View {
        let calls = allCalls
        let current = lyricActiveCall(starts: recorder.callStartsForCore, positionMs: Int64(shownMs)).map(Int.init)
        return VStack(alignment: .leading, spacing: DS.sp4) {
            if startFailed {
                ImasNote("記録には Apple Music でのフル再生が必要です。", systemImage: "music.note")
            }
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text("いまのコール").imasText(.eyebrow)
                ImasPlayerLyricLine(text: current.map { calls[$0].call.text } ?? "—", isCurrent: true, seed: seed)
                    .lineLimit(2)
            }
            if let next = recorder.callCursor {
                VStack(alignment: .leading, spacing: DS.sp2) {
                    Text("次に記録するコール").imasText(.eyebrow)
                    ForEach(next..<min(calls.count, next + 3), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(lyrics.lines[calls[index].line].text).imasText(.meta).lineLimit(1)
                            ImasPlayerLyricLine(text: calls[index].call.text, isCurrent: index == next, seed: seed)
                                .lineLimit(1)
                        }
                        .opacity(index == next ? 1 : 0.7)
                    }
                }
            } else {
                ImasNote("最後のコールまで記録しました。タイムラインの下の段で前後に寄せられます。",
                         systemImage: "checkmark")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var linesNowAndNext: some View {
        VStack(alignment: .leading, spacing: DS.sp4) {
            if startFailed {
                ImasNote("記録には Apple Music でのフル再生が必要です。", systemImage: "music.note")
            }
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text("いま").imasText(.eyebrow)
                ImasPlayerLyricLine(text: currentIndex.map { lyrics.lines[$0].text } ?? "（イントロ）",
                                    isCurrent: true, seed: seed)
                    .lineLimit(3)
            }
            if let next = recorder.cursor {
                VStack(alignment: .leading, spacing: DS.sp2) {
                    Text("次に記録する行").imasText(.eyebrow)
                    // 押す行の先も 2 行見せる (次の次が見えていると押す間合いを取りやすい)。
                    ForEach(Array(upcoming(from: next).enumerated()), id: \.element) { offset, index in
                        ImasPlayerLyricLine(text: lyrics.lines[index].text, isCurrent: offset == 0,
                                            isMarker: lyrics.lines[index].kind == .marker, seed: seed)
                            .lineLimit(2)
                            .opacity(offset == 0 ? 1 : 0.7)
                    }
                }
            } else {
                ImasNote("最後の行まで記録しました。タイムラインで帯を選ぶと前後に寄せられます。",
                         systemImage: "checkmark")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 次に記録する行と、その先の記録対象 2 行の添字。
    private func upcoming(from cursor: Int) -> [Int] {
        var result = [cursor]
        var after = UInt32(cursor)
        while result.count < 3,
              let next = lyricNextRecordable(kinds: lyrics.lines.map(\.kind.rawValue), after: after) {
            result.append(Int(next))
            after = next
        }
        return result
    }

    // MARK: - タイムライン

    private var timeline: some View {
        let spans = lyricLineSpans(starts: recorder.startsForCore, durationMs: Int64(duration))
        let blocks = spans.map { sp in
            ImasTimingTimeline.Block(id: lyrics.lines[Int(sp.index)].id, startMs: Int(sp.startMs),
                                     endMs: Int(sp.endMs), label: lyrics.lines[Int(sp.index)].text)
        }
        let calls = allCalls
        let callBlocks = lyricCallSpans(starts: recorder.callStartsForCore, durationMs: Int64(duration)).map { sp in
            ImasTimingTimeline.Block(id: calls[Int(sp.index)].call.id, startMs: Int(sp.startMs),
                                     endMs: Int(sp.endMs), label: calls[Int(sp.index)].call.text)
        }
        return ImasTimingTimeline(
            blocks: blocks, callBlocks: callBlocks, playheadMs: shownMs, selectedId: selectedId, seed: seed,
            onScrub: { scrubMs = $0 },
            onScrubEnd: { ms in
                scrubMs = nil
                playheadMs = ms
                playback.seek(ms)
            },
            onSelect: { id in selectedId = selectedId == id ? nil : id },
            onMoveStart: { id, ms in recorder.adjust(id: id, toMs: ms) }
        )
    }

    @ViewBuilder
    private var selectionControls: some View {
        if let id = selectedId, let start = recorder.start(for: id) {
            HStack(spacing: DS.sp2) {
                ImasLyricTimeLabel(ms: start, isEmphasized: true)
                Spacer(minLength: 0)
                ImasButton(title: "-0.1秒", role: .secondary, size: .small) {
                    recorder.nudge(id: id, byMs: -100)
                }
                ImasButton(title: "+0.1秒", role: .secondary, size: .small) {
                    recorder.nudge(id: id, byMs: 100)
                }
                ImasIconButton(systemImage: "arrow.right.to.line", label: "再生位置に合わせる", size: .small) {
                    recorder.adjust(id: id, toMs: playheadMs)
                }
                ImasIconButton(systemImage: "play.fill", label: "この行から再生", size: .small) {
                    playback.seek(max(0, start - 1500))
                    if !playback.isPlaying { playback.togglePlay() }
                }
            }
        } else {
            ImasNote("帯をタップして選ぶと、前後に寄せられます。地をなぞると再生位置が動きます。",
                     systemImage: "hand.draw")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transport: some View {
        HStack(spacing: DS.sp8) {
            ImasIconButton(systemImage: "gobackward.5", label: "5 秒戻す") {
                playback.seek(max(0, playheadMs - 5000))
            }
            ImasIconButton(systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                           label: playback.isPlaying ? "一時停止" : "再生", style: .filled) {
                playback.togglePlay()
            }
            ImasIconButton(systemImage: "goforward.5", label: "5 秒進める") {
                playback.seek(min(duration, playheadMs + 5000))
            }
        }
    }

    private var recordButton: some View {
        ImasButton(title: recorder.laneCursor == nil ? "最後まで記録しました"
                   : recorder.lane == .lines ? "歌い出しで押す" : "コールの頭で押す",
                   systemImage: "hand.tap.fill", role: .primary, size: .large, fillsWidth: true) {
            guard let ms = playback.positionMs() else { return }
            recorder.recordNext(positionMs: ms)
            recordToken += 1
        }
        .disabled(recorder.laneCursor == nil || !playback.isFullLoaded)
    }

    // MARK: -

    private func poll() async {
        while !Task.isCancelled {
            if scrubMs == nil, let ms = playback.positionMs(), ms != playheadMs { playheadMs = ms }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    private func save() async {
        if await recorder.save() {
            onSaved()
            dismiss()
        } else if case .failed(let message) = recorder.saveState {
            saveError = message
        }
    }
}
