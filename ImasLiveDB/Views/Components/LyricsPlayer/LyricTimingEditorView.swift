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
    @Environment(\.colorScheme) private var scheme

    let song: Song
    let seed: String?
    let lyrics: Lyrics
    let playback: LyricsPlayback
    @State var recorder: LyricTimingRecorder
    /// 保存できたら呼ぶ (歌詞を取り直す)。
    let onSaved: () -> Void
    /// パートの段で選ぶ歌唱者 (原唱者)。2 人以上のときだけパートの段を出す。
    var cast: LyricPartCast = .empty

    @State private var playheadMs = 0
    /// タイムラインをなぞっている間の位置。離したら再生位置をそこへ動かす。
    @State private var scrubMs: Int?
    @State private var selectedId: String?
    @State private var confirmDiscard = false
    @State private var saveError: String?
    @State private var startFailed = false
    @State private var recordToken = 0
    /// 歌詞をなぞってから少しの間は、曲に付いていくのを止める。
    @State private var followPausedUntil: Date = .distantPast
    /// パートの段で選んでいる字 (行の中のスカラー位置)。区切りを置く位置と、歌う人を付けるひと続きを決める。
    @State private var partCursor: Int?

    private var duration: Int {
        let lastStart = recorder.starts.compactMap { $0 }.max() ?? 0
        return playback.durationMs() ?? song.durationSec.map { $0 * 1000 } ?? lastStart + 8000
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp3)
            if lanes.count > 1 {
                ImasTabs(options: lanes,
                         selection: Binding(get: { recorder.lane }, set: { recorder.lane = $0 }),
                         seed: seed) { lane in
                    switch lane {
                    case .lines: "歌詞"
                    case .calls: "コール"
                    case .parts: "パート"
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.bottom, DS.sp3)
            }
            if recorder.lane == .lines {
                nowAndNext
                    .padding(.horizontal, DS.sp5)
                Spacer(minLength: DS.sp4)
            } else {
                // コールとパートは、歌詞を上下に動かして入れる行を選ぶ (曲に付いていくが、なぞると止まる)。
                laneLyrics
                    .frame(maxHeight: .infinity)
            }
            timeline
            selectionControls
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp3)
            transport
                .padding(.top, DS.sp4)
            if recorder.lane == .parts {
                partsBrush
                    .padding(.vertical, DS.sp4)
            } else {
                recordButton
                    .padding(.horizontal, DS.sp5)
                    .padding(.vertical, DS.sp4)
            }
        }
        .background(DS.bg)
        .task { if !playback.isFullLoaded { startFailed = !(await playback.startFull()) } }
        .task(id: playback.isFullLoaded) { await poll() }
        .sensoryFeedback(.impact(weight: .medium), trigger: recordToken)
        .onChange(of: partsTargetId) { partCursor = nil }
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

    /// 被せの行か (指定があればそれ、無ければ括弧で決める。判定はコア)。
    private func isOverlay(_ index: Int) -> Bool {
        let line = lyrics.lines[index]
        return line.kind != .blank && lyricIsOverlayLine(text: line.text, layer: recorder.layers[index])
    }

    /// メインの行だけに時刻を入れた並び (被せの行に今の行を取られないように)。
    private var mainStarts: [Int64?] {
        recorder.startsForCore.enumerated().map { isOverlay($0.offset) ? nil : $0.element }
    }

    /// 被せの行だけに時刻を入れた並び。
    private var overlayStarts: [Int64?] {
        recorder.startsForCore.enumerated().map { isOverlay($0.offset) ? $0.element : nil }
    }

    private var currentIndex: Int? {
        lyricActiveLine(starts: mainStarts, positionMs: Int64(shownMs)).map(Int.init)
    }

    /// 曲の順に並べたコール (ぶら下がる行の添字つき)。recorder.callIds と同じ並び。
    private var allCalls: [(call: LyricCall, line: Int)] {
        lyrics.lines.enumerated().flatMap { i, line in line.calls.map { ($0, i) } }
    }

    /// 段の並び。コールがあればコール、原唱者が 2 人以上ならパートを足す。
    private var lanes: [LyricTimingRecorder.Lane] {
        var result: [LyricTimingRecorder.Lane] = [.lines]
        if recorder.hasCalls { result.append(.calls) }
        if lyricPartsApplicable(originalArtistCount: UInt32(cast.artists.count)) { result.append(.parts) }
        return result
    }

    private var nowAndNext: some View { linesNowAndNext }

    // MARK: - コールとパートの段: 歌詞を動かして選ぶ

    private var laneLyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    if startFailed {
                        ImasNote(recorder.lane == .parts ? "パート分けには Apple Music でのフル再生が必要です。"
                                                         : "記録には Apple Music でのフル再生が必要です。",
                                 systemImage: "music.note")
                    }
                    Text(recorder.lane == .parts ? "行をタップして歌う人を付けます。字をタップすると、そこから歌う人を変えられます。"
                                                 : "コールをタップして選ぶと、前後に寄せられます。")
                        .imasText(.meta, color: DS.ink3)
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        laneRow(index: index, line: line)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp4)
            }
            .onChange(of: currentIndex) { _, index in
                guard let index, Date() >= followPausedUntil else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    proxy.scrollTo(lyrics.lines[index].id, anchor: UnitPoint(x: 0.5, y: 0.3))
                }
            }
            .modifier(PausesLyricsFollow(until: $followPausedUntil))
        }
    }

    @ViewBuilder
    private func laneRow(index: Int, line: LyricLine) -> some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: DS.sp1)
        case .marker:
            Text(line.text).imasText(.eyebrow, color: DS.ink3)
        case .lyric:
            let isCurrent = index == currentIndex
            switch recorder.lane {
            case .parts: partsLaneRow(line: line, isCurrent: isCurrent)
            default: callsLaneRow(index: index, line: line, isCurrent: isCurrent)
            }
        }
    }

    /// コールの段の 1 行。行の下にコールを並べ、タップで選ぶ (タイムラインと同じ選択)。
    private func callsLaneRow(index: Int, line: LyricLine, isCurrent: Bool) -> some View {
        let calls = allCalls
        let accent = ImasTheme.derive(seed: seed, scheme: scheme).accent
        return VStack(alignment: .leading, spacing: DS.sp1) {
            laneText(line.text, isCurrent: isCurrent)
            ForEach(line.calls) { call in
                let order = calls.firstIndex { $0.call.id == call.id }
                let isNext = order != nil && order == recorder.callCursor
                Button {
                    selectedId = selectedId == call.id ? nil : call.id
                } label: {
                    HStack(spacing: DS.sp2) {
                        ImasPlayerCallLine(marker: call.hasAnchor ? "↳" : "»", text: call.text,
                                           color: call.emphasis.color(accent: accent),
                                           isActive: selectedId == call.id || isNext)
                        if isNext { Text("次に記録").imasText(.meta, color: DS.ink2) }
                        if let ms = recorder.start(for: call.id) { ImasLyricTimeLabel(ms: ms, isEmphasized: false) }
                    }
                }
                .buttonStyle(.imasPress)
                .accessibilityAddTraits(selectedId == call.id ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// パートの段の 1 行。タップで付ける行に選び、選んだ行は字ごとに並べて区切りを置ける。
    @ViewBuilder
    private func partsLaneRow(line: LyricLine, isCurrent: Bool) -> some View {
        let segments = recorder.segments(for: line.id)
        let singers = segments.flatMap(\.singers)
        let isTarget = line.id == partsTargetId
        HStack(alignment: .top, spacing: DS.sp3) {
            ImasPartStripe(colors: cast.colors(lyricPartUnion(singers: singers, breaks: [])))
            VStack(alignment: .leading, spacing: DS.sp1) {
                if isTarget {
                    partCells(line: line, segments: segments)
                } else {
                    Button {
                        selectedId = line.id
                        partCursor = nil
                    } label: {
                        laneText(line.text, isCurrent: isCurrent)
                    }
                    .buttonStyle(.imasPress)
                }
                ImasPartNames(groups: segments.map { cast.names($0.singers) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 選んだ行を字ごとに並べる。タップした字が、歌う人を付けるひと続きと、区切りを置く位置になる。
    private func partCells(line: LyricLine, segments: [LyricPartSegment]) -> some View {
        // 振り仮名の記号と読みは字として並べない (区切りは親字と地の字にだけ置く)。
        let roles = ImasRubyText.roles(line.text).roles
        let cells = CallGuideText.cells(of: line.text).filter { cell in
            guard cell.scalarStart < roles.count, case .text = roles[cell.scalarStart] else { return false }
            return true
        }
        let cursor = partCursor ?? 0
        let active = segments.first { Int($0.start) <= cursor && cursor < Int($0.end) }
        return VStack(alignment: .leading, spacing: DS.sp2) {
            FlowLayout(spacing: 0, lineSpacing: DS.sp1) {
                ForEach(cells) { cell in
                    let isBreak = segments.contains { Int($0.start) == cell.scalarStart && $0.start > 0 }
                    let inActive = active.map { Int($0.start) <= cell.scalarStart && cell.scalarStart < Int($0.end) } ?? false
                    Button { partCursor = cell.scalarStart } label: {
                        HStack(spacing: 0) {
                            if isBreak { ImasPartBreakMark() }
                            Text(cell.text)
                                .imasText(.body, color: inActive ? DS.ink : DS.ink3)
                                .underline(cell.scalarStart == partCursor, color: DS.ink)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let at = partCursor, at > 0 {
                let isBreak = segments.contains { Int($0.start) == at }
                let head = CallGuideText.slice(line.text, start: at, end: min(at + 4, line.text.unicodeScalars.count)) ?? ""
                ImasButton(title: isBreak ? "「\(head)」の前の区切りを外す" : "「\(head)」から歌う人を変える",
                           systemImage: isBreak ? "minus" : "scissors", role: .plain, size: .small) {
                    AppAnalytics.tap("lyric_timing.toggle_part_break")
                    recorder.toggleBreak(lineId: line.id, at: at)
                    recordToken += 1
                }
            }
        }
    }

    /// 段の中の歌詞 1 行 (振り仮名は親字の上に)。
    @ViewBuilder
    private func laneText(_ text: String, isCurrent: Bool) -> some View {
        let color = isCurrent ? DS.ink : DS.ink3
        Group {
            if ImasRubyText.hasRuby(text) {
                ImasRubyLabel(attributed: ImasRubyText.attributed(text, font: Font.imasScaledUIFont(17), color: UIColor(color)))
            } else {
                Text(text).imasText(.body, color: color).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 歌う人を付けるひと続きの頭 (選んだ字を含むひと続き。字を選んでいなければ行の頭)。
    private var partsSegmentStart: Int {
        guard let id = partsTargetId, let cursor = partCursor else { return 0 }
        return recorder.segments(for: id).last { Int($0.start) <= cursor }.map { Int($0.start) } ?? 0
    }

    // MARK: - パート (誰が歌うか)

    /// パートを付ける行: タイムラインで選んだ行、選んでいなければいま歌っている行。
    private var partsTargetId: String? {
        if let selectedId, lyrics.lines.contains(where: { $0.id == selectedId && $0.kind == .lyric }) {
            return selectedId
        }
        // 見出し (「1番」など) には付けない。
        return currentIndex.flatMap { lyrics.lines[$0].kind == .lyric ? lyrics.lines[$0].id : nil }
    }

    /// 歌う人のアイコン。押すといまの行 (選んだ行) に付け外しする。
    private var partsBrush: some View {
        VStack(spacing: DS.sp3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    ForEach(cast.artists, id: \.id) { idol in
                        let segment = partsTargetId.flatMap { id in
                            recorder.segments(for: id).first { Int($0.start) == partsSegmentStart }
                        }
                        let isOn = segment?.singers.contains(idol.id) ?? false
                        Button {
                            guard let id = partsTargetId else { return }
                            AppAnalytics.tap("lyric_timing.toggle_part")
                            recorder.toggleSinger(lineId: id, segmentStart: partsSegmentStart, idolId: idol.id,
                                                  order: cast.artists.map(\.id))
                            recordToken += 1
                        } label: {
                            VStack(spacing: DS.sp1) {
                                IdolAvatarView(idol: idol, size: 48, isPick: isOn)
                                Text(idol.shortName).imasText(.meta, color: isOn ? DS.ink : DS.ink3)
                            }
                        }
                        .buttonStyle(.imasPress)
                        .disabled(partsTargetId == nil)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.horizontal, DS.sp5)
            }
            ImasButton(title: "前の行と同じ人にする", systemImage: "arrow.turn.down.right", role: .secondary,
                       size: .small) {
                guard let id = partsTargetId else { return }
                recorder.copyPreviousSingers(lineId: id)
                recordToken += 1
            }
            .disabled(partsTargetId == nil)
        }
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
        let spans = lyricLineSpans(starts: mainStarts, durationMs: Int64(duration))
        let overlayBlocks = lyricOverlaySpans(starts: overlayStarts, durationMs: Int64(duration)).map { sp in
            ImasTimingTimeline.Block(id: lyrics.lines[Int(sp.index)].id, startMs: Int(sp.startMs),
                                     endMs: Int(sp.endMs), label: lyrics.lines[Int(sp.index)].text)
        }
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
            blocks: blocks, subLanes: [overlayBlocks, callBlocks], playheadMs: shownMs, selectedId: selectedId, seed: seed,
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
                if let index = lyrics.lines.firstIndex(where: { $0.id == id }) {
                    // 被せ ⇄ メインの切り替え。括弧だけでは決めきれない行を人が決める。
                    let overlay = isOverlay(index)
                    ImasIconButton(systemImage: overlay ? "square.stack.fill" : "square.stack",
                                   label: overlay ? "メインに戻す" : "被せにする", size: .small) {
                        recorder.setOverlay(lineId: id, !overlay)
                    }
                }
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
