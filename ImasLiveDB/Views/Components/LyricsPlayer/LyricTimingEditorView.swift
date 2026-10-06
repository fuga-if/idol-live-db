import SwiftUI

/// 歌詞行の時刻 (タイミング) を付ける・直す画面。
///
/// 1. ざっくり付ける … 曲を流しながら、下の大きいボタンを歌い出しに合わせて押す
///    (歌詞の行を狙ってタップしなくてよい)。押すたびに「次の行」が進む。
///    次に記録する行は、歌詞の一覧で行をタップするか、上下の矢印で選び直せる。
/// 2. 直す … 横長のタイムラインで行の帯を選び、-0.1 / +0.1 秒で寄せるか、
///    帯の頭のつまみをなぞる。「再生位置に合わせる」で今の位置にくっつける。
///    タイムラインの地をなぞると再生位置が動く (ちょい戻し)。
/// 3. 途中から押し直す … 再生位置を動かすと「次に記録する行」がその位置の次の行へ移る。
///    記録済みの曲でも、直したいところへ戻して押せば、そこから先だけ上書きできる。
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
    /// パートの段の筆 (塗る歌う人。複数人を一度に塗れる)。nil なら原唱者の先頭 1 人。
    @State private var partsBrushIds: [String]?
    /// 消しゴムを持っているか (塗る代わりに、その字の歌う人をみな外す)。
    @State private var partsErasing = false
    /// 行をタップして次に記録する行を選んだ直後か (指の下の一覧を寄せない)。
    @State private var pickedByTap = false

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
                cursorBar
                    .padding(.horizontal, DS.sp5)
                    .padding(.bottom, DS.sp2)
            }
            // 歌詞を上下に動かして、記録する行・コールを入れる行・塗る行を選ぶ。
            laneLyrics
                .frame(maxHeight: .infinity)
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
        .task {
            // 曲の途中で開いたら、そこから押し直せるようにする (記録済みの曲を頭から押させない)。
            if playback.isFullLoaded, let ms = playback.positionMs(), ms > 0 { recorder.aim(atMs: ms) }
            if !playback.isFullLoaded { startFailed = !(await playback.startFull()) }
        }
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

    // MARK: - 段ごとの歌詞: 動かして選ぶ

    /// 歌詞の段の頭: 次に記録する行の状態と、1 行ずつ選び直す矢印。
    private var cursorBar: some View {
        HStack(spacing: DS.sp3) {
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text("次に記録する行").imasText(.eyebrow)
                Text(recorder.cursor == nil ? "最後まで記録しました。行をタップすると、そこから押し直せます。"
                     : recorder.cursorOverwrites ? "記録済み・押すと上書き" : "まだ時刻がありません")
                    .imasText(.meta, color: DS.ink3)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            ImasIconButton(systemImage: "chevron.up", label: "前の行にする", size: .small) {
                AppAnalytics.tap("lyric_timing.step_cursor")
                recorder.stepCursor(by: -1)
            }
            ImasIconButton(systemImage: "chevron.down", label: "次の行にする", size: .small) {
                AppAnalytics.tap("lyric_timing.step_cursor")
                recorder.stepCursor(by: 1)
            }
            .disabled(recorder.cursor == nil)
        }
    }

    private var laneLyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp4) {
                    if startFailed {
                        ImasNote(recorder.lane == .parts ? "パート分けには Apple Music でのフル再生が必要です。"
                                                         : "記録には Apple Music でのフル再生が必要です。",
                                 systemImage: "music.note")
                    }
                    Text(laneHint)
                        .imasText(.meta, color: DS.ink3)
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                        laneRow(index: index, line: line)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp4)
            }
            // 歌詞の段は次に記録する行に付いていく (押すたびに 1 行進む)。行をタップして選んだときは寄せない。
            .onChange(of: recorder.cursor) { _, cursor in
                guard recorder.lane == .lines, let cursor else { return }
                if pickedByTap { pickedByTap = false; return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    proxy.scrollTo(lyrics.lines[cursor].id, anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
            .onAppear {
                guard recorder.lane == .lines, let cursor = recorder.cursor else { return }
                proxy.scrollTo(lyrics.lines[cursor].id, anchor: UnitPoint(x: 0.5, y: 0.35))
            }
            .onChange(of: recorder.lane) { _, lane in
                guard lane == .lines, let cursor = recorder.cursor else { return }
                proxy.scrollTo(lyrics.lines[cursor].id, anchor: UnitPoint(x: 0.5, y: 0.35))
            }
            .onChange(of: currentIndex) { _, index in
                guard recorder.lane != .lines, let index, Date() >= followPausedUntil else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    proxy.scrollTo(lyrics.lines[index].id, anchor: UnitPoint(x: 0.5, y: 0.3))
                }
            }
            .modifier(PausesLyricsFollow(until: $followPausedUntil))
        }
    }

    private var laneHint: String {
        switch recorder.lane {
        case .lines: "行をタップすると、その行から記録します。押すたびに次の行へ進みます。"
        case .calls: "コールをタップして選ぶと、前後に寄せられます。"
        case .parts: "歌う人を選んでから行をタップすると、行まるごと塗れます。いま歌っている行 (選んだ行) は、語をタップするか長押しでなぞると、その字だけ塗れます。もう一度で外れます。"
        }
    }

    @ViewBuilder
    private func laneRow(index: Int, line: LyricLine) -> some View {
        if recorder.lane == .lines, line.kind != .blank {
            linesLaneRow(index: index, line: line, isCurrent: index == currentIndex)
        } else {
            otherLaneRow(index: index, line: line)
        }
    }

    /// 歌詞の段の 1 行。タップでその行を次に記録する行にする。記録した時刻を右に添える。
    private func linesLaneRow(index: Int, line: LyricLine, isCurrent: Bool) -> some View {
        let isNext = index == recorder.cursor
        let accent = ImasTheme.derive(seed: seed, scheme: scheme).accent
        return Button {
            AppAnalytics.tap("lyric_timing.pick_line")
            pickedByTap = recorder.cursor != index
            recorder.aim(at: line.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.sp3) {
                if line.kind == .marker {
                    Text(line.text).imasText(.eyebrow, color: DS.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    laneText(line.text, isCurrent: isCurrent || isNext)
                }
                VStack(alignment: .trailing, spacing: DS.sp1) {
                    if isNext { Text("次に記録").imasText(.meta, color: accent) }
                    ImasLyricTimeLabel(ms: recorder.start(for: line.id), isEmphasized: isNext)
                }
            }
            .padding(.vertical, DS.sp2)
            .padding(.horizontal, DS.sp3)
            .background(RoundedRectangle(cornerRadius: DS.rSM).fill(isNext ? accent.opacity(0.12) : .clear))
            .overlay(RoundedRectangle(cornerRadius: DS.rSM).strokeBorder(isNext ? accent.opacity(0.5) : .clear,
                                                                         lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.imasPress)
        .accessibilityAddTraits(isNext ? .isSelected : [])
        .accessibilityHint("この行から記録します")
    }

    @ViewBuilder
    private func otherLaneRow(index: Int, line: LyricLine) -> some View {
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

    /// パートの段の 1 行。歌う人 (筆) を選んでから、行をタップすると行まるごと塗る / 外す。
    /// 選んだ行 (いま歌っている行) は語をタップ・長押しでなぞると、その字だけ塗る / 外す。
    @ViewBuilder
    private func partsLaneRow(line: LyricLine, isCurrent: Bool) -> some View {
        let segments = recorder.segments(for: line.id)
        let isTarget = line.id == partsTargetId
        let marks = segments.compactMap { segment -> ImasRubyText.PartMark? in
            let colors = cast.colors(segment.singers).map { UIColor(ImasTheme.derive(seed: $0, scheme: scheme).accent) }
            return colors.isEmpty ? nil : .init(start: Int(segment.start), end: Int(segment.end), colors: colors)
        }
        VStack(alignment: .leading, spacing: DS.sp1) {
            if isTarget {
                // 塗った字には歌う人 (先頭の人) の色を敷く。語のタップ・なぞりはコール編集と同じ部品。
                CallGuideSelectableLine(
                    text: line.text,
                    highlights: segments.compactMap { segment in
                        cast.colors(segment.singers).first.map {
                            CallGuideText.Highlight(start: Int(segment.start), end: Int(segment.end),
                                                    color: ImasTheme.derive(seed: $0, scheme: scheme).accent)
                        }
                    },
                    onSelect: { start, end, _ in paint(line.id, start: start, end: end) }
                )
            } else {
                Button {
                    selectedId = line.id
                    paint(line.id, start: 0, end: line.text.unicodeScalars.count)
                } label: {
                    laneText(line.text, isCurrent: isCurrent, parts: marks)
                }
                .buttonStyle(.imasPress)
            }
            ImasPartNames(groups: segments.map { cast.names($0.singers) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// いまの筆 (選んでいなければ原唱者の先頭 1 人)。
    private var brush: [String] { partsBrushIds ?? cast.artists.first.map { [$0.id] } ?? [] }

    /// 筆の人たちを、行の字の範囲に塗る / 外す (範囲の字がみな筆の全員入りなら外す)。規則はコア。
    private func paint(_ lineId: String, start: Int, end: Int) {
        if partsErasing {
            AppAnalytics.tap("lyric_timing.erase_part")
            recorder.erase(lineId: lineId, start: start, end: end)
            recordToken += 1
            return
        }
        guard !brush.isEmpty else { return }
        AppAnalytics.tap("lyric_timing.paint_part")
        recorder.paint(lineId: lineId, start: start, end: end, idolIds: brush, order: cast.artists.map(\.id))
        recordToken += 1
    }

    /// 段の中の歌詞 1 行 (振り仮名は親字の上に)。
    @ViewBuilder
    private func laneText(_ text: String, isCurrent: Bool, parts: [ImasRubyText.PartMark] = []) -> some View {
        let color = isCurrent ? DS.ink : DS.ink3
        Group {
            if ImasRubyText.hasRuby(text) || !parts.isEmpty {
                ImasRubyLabel(attributed: ImasRubyText.attributed(text, font: Font.imasScaledUIFont(17), color: UIColor(color),
                                                                  parts: parts))
            } else {
                Text(text).imasText(.body, color: color).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 歌う人のアイコン (筆)。タップで筆に足す / 外す (何人でも)。「全員」で原唱者みんなを筆にする。
    private var partsBrush: some View {
        let everyone = cast.artists.map(\.id)
        let isEveryone = Set(brush) == Set(everyone)
        return VStack(spacing: DS.sp3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    // 消しゴム: 持っている間は、行や語をタップ・なぞると、その字の歌う人をみな外す。
                    VStack(spacing: DS.sp1) {
                        ImasIconButton(systemImage: "eraser", label: "消しゴム",
                                       style: partsErasing ? .filled : .plain) { partsErasing.toggle() }
                            .accessibilityAddTraits(partsErasing ? .isSelected : [])
                        Text("消しゴム").imasText(.meta, color: partsErasing ? DS.ink : DS.ink3)
                    }
                    ForEach(cast.artists, id: \.id) { idol in
                        let isOn = !partsErasing && brush.contains(idol.id)
                        Button {
                            if partsErasing {
                                // 消しゴムから筆に持ち替える (その人 1 人の筆にする)。
                                partsErasing = false
                                partsBrushIds = [idol.id]
                                return
                            }
                            var next = brush
                            if let i = next.firstIndex(of: idol.id) {
                                // 筆は 1 人は残す (空の筆では塗れない)。
                                if next.count > 1 { next.remove(at: i) }
                            } else {
                                next.append(idol.id)
                            }
                            partsBrushIds = cast.ordered(next)
                        } label: {
                            VStack(spacing: DS.sp1) {
                                IdolAvatarView(idol: idol, size: 48, isPick: isOn)
                                Text(idol.shortName).imasText(.meta, color: isOn ? DS.ink : DS.ink3)
                            }
                        }
                        .buttonStyle(.imasPress)
                        .accessibilityLabel("\(idol.shortName)で塗る")
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.horizontal, DS.sp5)
            }
            HStack(spacing: DS.sp2) {
                ImasButton(title: isEveryone ? "1 人に戻す" : "全員を選ぶ", systemImage: "person.3.fill",
                           role: .secondary, size: .small) {
                    partsErasing = false
                    partsBrushIds = isEveryone ? Array(everyone.prefix(1)) : everyone
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
                seek(ms)
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
                ImasIconButton(systemImage: "play.fill", label: "この行から再生して押し直す", size: .small) {
                    AppAnalytics.tap("lyric_timing.retake_from")
                    seek(max(0, start - 1500))
                    recorder.aim(at: id)
                    if !playback.isPlaying { playback.togglePlay() }
                }
            }
        } else {
            ImasNote("帯をタップして選ぶと、前後に寄せられます。地をなぞって戻すと、そこから押し直せます。",
                     systemImage: "hand.draw")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transport: some View {
        HStack(spacing: DS.sp8) {
            ImasIconButton(systemImage: "gobackward.5", label: "5 秒戻す") {
                seek(max(0, playheadMs - 5000))
            }
            ImasIconButton(systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                           label: playback.isPlaying ? "一時停止" : "再生", style: .filled) {
                playback.togglePlay()
            }
            ImasIconButton(systemImage: "goforward.5", label: "5 秒進める") {
                seek(min(duration, playheadMs + 5000))
            }
        }
    }

    private var recordButton: some View {
        ImasButton(title: recorder.laneCursor == nil ? "最後まで記録しました"
                   : recorder.lane == .lines ? (recorder.cursorOverwrites ? "歌い出しで押し直す" : "歌い出しで押す")
                   : (recorder.cursorOverwrites ? "コールの頭で押し直す" : "コールの頭で押す"),
                   systemImage: "hand.tap.fill", role: .primary, size: .large, fillsWidth: true) {
            guard let ms = playback.positionMs() else { return }
            recorder.recordNext(positionMs: ms)
            recordToken += 1
        }
        .disabled(recorder.laneCursor == nil || !playback.isFullLoaded)
    }

    // MARK: -

    /// 再生位置を動かす。次に記録するものも、その位置の次へ寄せる (途中から押し直せるように)。
    private func seek(_ ms: Int) {
        playheadMs = ms
        playback.seek(ms)
        recorder.aim(atMs: ms)
    }

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
