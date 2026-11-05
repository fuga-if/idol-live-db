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
    /// 「一緒に歌う」を持っているか (歌う人のタップが、持ち替えでなく筆に足す / 外すになる)。
    @State private var partsAdding = false
    /// 行をタップして次に記録する行を選んだ直後か (指の下の一覧を寄せない)。
    @State private var pickedByTap = false
    /// パートの段の見せ方。曲に付いていくか、歌詞を一覧で並べて落ち着いて塗るか。
    @State private var partsView: PartsView = .live

    enum PartsView: Hashable {
        /// 曲に付いていき、いま歌っている行に塗る (聴きながら)。
        case live
        /// 曲に付いていかない。タイムラインと再生の操作を畳んで、歌詞を広く並べる (聴かずに)。
        case list
    }

    /// パートを一覧で塗っているか (曲への追従と、再生まわりの操作を外す)。
    private var isPartsList: Bool { recorder.lane == .parts && partsView == .list }

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
            if recorder.lane == .parts {
                ImasSegmented(options: [PartsView.live, .list], selection: $partsView, seed: seed) { view in
                    switch view {
                    case .live: "リアルタイム"
                    case .list: "一覧"
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.bottom, DS.sp2)
            }
            // 歌詞を上下に動かして、記録する行・コールを入れる行・塗る行を選ぶ。
            laneLyrics
                .frame(maxHeight: .infinity)
            if !isPartsList {
                timeline
                selectionControls
                    .padding(.horizontal, DS.sp5)
                    .padding(.top, DS.sp3)
                transport
                    .padding(.top, DS.sp4)
            }
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
            // 鳴らせないなら、パートは一覧で塗る (曲に付いていけないので)。
            if startFailed { partsView = .list }
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
            ImasIconButton(systemImage: "arrow.uturn.forward", label: "やり直す", size: .small) {
                recorder.redo()
            }
            .disabled(!recorder.canRedo)
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
                    if startFailed, !isPartsList {
                        ImasNote(recorder.lane == .parts ? "聴きながら塗るには Apple Music でのフル再生が必要です。一覧なら聴かずに塗れます。"
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
                guard recorder.lane != .lines, !isPartsList, let index, Date() >= followPausedUntil else { return }
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
        case .parts where isPartsList:
            "行をタップして選び、語をタップ・なぞるか、括弧・コールの印か刷毛で塗ります。もう一度で外れます。"
        case .parts: "いま歌っている行を塗ります。過ぎた行はタップするとそこへ戻って聴き直せます。語をタップ・なぞるか、括弧・コールの印か刷毛で塗ります。"
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
            .padding(.leading, DS.sp3)
            // 次に記録する行は「ここを押す」の印 (薄い地)、いま鳴っている行は濃い地。
            .imasLyricLine(isNext ? .cursor : isCurrent ? .current : .normal, seed: seed)
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
            let isCurrent = !isPartsList && index == currentIndex
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

    /// パートの段の 1 行。行をタップすると塗る行に選ぶ (聴きながらなら、その行の頭へ戻して聴き直す)。
    /// 選んだ行 (いま歌っている行) は語をタップ・長押しでなぞると、その字だけ塗る / 外す。
    /// 右の刷毛で行まるごと、行の下のコールの印でそのコールの掛かる字だけ塗れる
    /// (コールの所だけみんなで歌う、を 1 タップで)。
    /// 塗ると前に歌っていた人と入れ替わる (パートチェンジ)。2 人で歌う所は筆に 2 人選んで塗る。
    @ViewBuilder
    private func partsLaneRow(line: LyricLine, isCurrent: Bool) -> some View {
        let segments = recorder.segments(for: line.id)
        // 色は空白に置かない (語と語のあいだに色の塊が浮く)。
        let ink = recorder.inkSegments(for: line.id, text: line.text)
        let isTarget = line.id == partsTargetId
        let marks = ink.compactMap { segment -> ImasRubyText.PartMark? in
            let colors = cast.colors(segment.singers).map { UIColor(ImasTheme.derive(seed: $0, scheme: scheme).accent) }
            return colors.isEmpty ? nil : .init(start: Int(segment.start), end: Int(segment.end), colors: colors)
        }
        VStack(alignment: .leading, spacing: DS.sp1) {
            if isTarget {
                HStack(alignment: .top, spacing: DS.sp2) {
                    // 塗った字には歌う人 (先頭の人) の色を敷く。語のタップ・なぞりはコール編集と同じ部品。
                    CallGuideSelectableLine(
                        text: line.text,
                        highlights: ink.compactMap { segment in
                            cast.colors(segment.singers).first.map {
                                CallGuideText.Highlight(start: Int(segment.start), end: Int(segment.end),
                                                        color: ImasTheme.derive(seed: $0, scheme: scheme).accent)
                            }
                        },
                        onSelect: { start, end, _ in paint(line.id, start: start, end: end) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ImasIconButton(systemImage: partsErasing ? "eraser.fill" : "paintbrush.fill",
                                   label: partsErasing ? "行まるごと消す" : "行まるごと塗る", size: .small) {
                        paint(line.id, start: 0, end: line.text.unicodeScalars.count)
                    }
                }
                // コールの掛かる字 (歌詞と同じ文字を一緒に歌う所など) と、括弧の中 (被せ・コーラス) を、
                // 範囲ぴったりに塗る。括弧は括弧ごと塗る (範囲はコアの lyricAsideSpans)。
                let anchored = line.calls.filter { $0.hasAnchor && !$0.isPenlight }
                let scalars = Array(line.text.unicodeScalars)
                let asides = lyricAsideSpans(text: line.text).filter { $0.end > $0.start && Int($0.end) <= scalars.count }
                if !anchored.isEmpty || !asides.isEmpty {
                    FlowLayout(spacing: DS.sp2, lineSpacing: DS.sp2) {
                        ForEach(Array(asides.enumerated()), id: \.offset) { _, span in
                            let shown = String(String.UnicodeScalarView(scalars[Int(span.start)..<Int(span.end)]))
                            ImasButton(title: shown, systemImage: partsErasing ? "eraser" : "paintbrush.fill",
                                       role: .secondary, size: .small) {
                                paint(line.id, start: Int(span.start), end: Int(span.end))
                            }
                            .accessibilityLabel("括弧の中「\(shown)」を\(partsErasing ? "消す" : "塗る")")
                        }
                        ForEach(anchored) { call in
                            ImasButton(title: call.anchorText.isEmpty ? call.text : call.anchorText,
                                       systemImage: partsErasing ? "eraser" : "megaphone.fill",
                                       role: .secondary, size: .small) {
                                paint(line.id, start: call.start, end: call.end)
                            }
                            .accessibilityLabel("コール「\(call.text)」の所を\(partsErasing ? "消す" : "塗る")")
                        }
                    }
                }
            } else {
                Button {
                    pickPartsLine(line)
                } label: {
                    laneText(line.text, isCurrent: isCurrent, parts: marks)
                }
                .buttonStyle(.imasPress)
            }
            ImasPartNames(groups: segments.map { cast.names($0.singers) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 塗る行を選ぶ。聴きながら塗っていて行に時刻があれば、その行の頭へ戻す
    /// (今の行がその行になるので、そのまま聴き直して塗れる。過ぎた行を塗り直すため)。
    private func pickPartsLine(_ line: LyricLine) {
        AppAnalytics.tap("lyric_timing.pick_part_line")
        // 被せの行は今の行にならない (今の行はメインの行で決まる) ので、選ぶだけにする。
        let isMain = lyrics.lines.firstIndex(where: { $0.id == line.id }).map { !isOverlay($0) } ?? false
        if !isPartsList, isMain, playback.isFullLoaded, let start = recorder.start(for: line.id) {
            selectedId = nil
            followPausedUntil = .distantPast
            seek(start)
        } else {
            selectedId = line.id
        }
    }

    /// いまの筆 (選んでいなければ原唱者の先頭 1 人)。
    private var brush: [String] { partsBrushIds ?? cast.artists.first.map { [$0.id] } ?? [] }

    /// 行の字の範囲を筆の人たちに塗り替える (前の人と入れ替え。範囲がもう筆の人たちちょうどなら外す)。規則はコア。
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
        // 一覧では、選んだ行だけ (曲に付いていかない)。見出し (「1番」など) には付けない。
        if isPartsList { return nil }
        return currentIndex.flatMap { lyrics.lines[$0].kind == .lyric ? lyrics.lines[$0].id : nil }
    }

    /// 筆をその人 1 人に持ち替える (消しゴムからも持ち替える)。
    private func pickBrush(_ id: String) {
        partsErasing = false
        partsBrushIds = [id]
    }

    /// 一緒に歌う人として筆に足す / 外す (筆は 1 人は残す。空の筆では塗れない)。
    private func toggleBrush(_ id: String) {
        recordToken += 1
        if partsErasing {
            pickBrush(id)
            return
        }
        var next = brush
        if let i = next.firstIndex(of: id) {
            if next.count > 1 { next.remove(at: i) }
        } else {
            next.append(id)
        }
        partsBrushIds = cast.ordered(next)
    }

    /// 歌う人のアイコン (筆)。タップでその人 1 人に持ち替え、「一緒に歌う」を持っているとき・長押しで足す / 外す。
    /// 「全員」で原唱者みんなを筆にする。
    private var partsBrush: some View {
        let everyone = cast.artists.map(\.id)
        let isEveryone = Set(brush) == Set(everyone)
        return VStack(spacing: DS.sp3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.sp3) {
                    // 消しゴム: 持っている間は、行や語をタップ・なぞると、その字の歌う人をみな外す。
                    VStack(spacing: DS.sp1) {
                        ImasIconButton(systemImage: "eraser", label: "消しゴム",
                                       style: partsErasing ? .filled : .plain) {
                            partsErasing.toggle()
                            partsAdding = false
                        }
                            .accessibilityAddTraits(partsErasing ? .isSelected : [])
                        Text("消しゴム").imasText(.meta, color: partsErasing ? DS.ink : DS.ink3)
                    }
                    // 一緒に歌う: 持っている間は、歌う人のタップで筆に足す / 外す (2 人以上で歌う所を塗る)。
                    VStack(spacing: DS.sp1) {
                        ImasIconButton(systemImage: "person.2.fill", label: "一緒に歌う",
                                       style: partsAdding ? .filled : .plain) {
                            partsAdding.toggle()
                            partsErasing = false
                        }
                            .accessibilityAddTraits(partsAdding ? .isSelected : [])
                        Text("一緒に歌う").imasText(.meta, color: partsAdding ? DS.ink : DS.ink3)
                    }
                    ForEach(cast.artists, id: \.id) { idol in
                        let isOn = !partsErasing && brush.contains(idol.id)
                        VStack(spacing: DS.sp1) {
                            IdolAvatarView(idol: idol, size: 48, isPick: isOn)
                            Text(idol.shortName).imasText(.meta, color: isOn ? DS.ink : DS.ink3)
                        }
                        .contentShape(Rectangle())
                        // タップはその人 1 人に持ち替える (パートチェンジ)。「一緒に歌う」を持っているとき・長押しは足す / 外す。
                        .onTapGesture { partsAdding ? toggleBrush(idol.id) : pickBrush(idol.id) }
                        .onLongPressGesture(minimumDuration: 0.35) { toggleBrush(idol.id) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(idol.shortName)で塗る")
                        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { pickBrush(idol.id) }
                        .accessibilityAction(named: "一緒に歌う人に足す・外す") { toggleBrush(idol.id) }
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
