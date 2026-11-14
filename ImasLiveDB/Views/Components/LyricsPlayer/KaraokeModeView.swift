import SwiftUI
import UIKit

/// カラオケモード。カラオケの部屋で、鳴っているカラオケ音源に合わせて歌詞・コール・歌い分けを流す。
///
/// 合わせ方:
/// - 耳 (本線): マイクで聞いて Shazam のカタログと照合し、曲の位置を拾う (`KaraokeListener`)。
///   合ってからも 30 秒おきに聞き直してずれを直す。
/// - 手: 合わせる画面で行を選び、その行の歌い出しで大きな面をタップ。歌っている間は行をタップで
///   「いまこの行」、左右スワイプで 0.1 秒ずつずらす。
///
/// 時計はコア (`karaoke*`) の計算を `KaraokeClockModel` が持つ。行の追従・コール・歌い分けの色は
/// 歌詞プレイヤーと同じ部品・同じ判定 (`lyricActiveLine` など) を使う。
///
/// 部屋は暗いので、いつも暗い地。画面は消さない。
///
/// ⚠️ 歌詞の本文はメモリだけ (`Models/Lyrics.swift` 冒頭)。端末に残すのは曲 id → 選んだパートの id だけ。
/// 本文にテキスト選択・コピー・共有の口を付けないこと。
struct KaraokeModeView: View {
    @Environment(\.dismiss) private var dismiss

    let song: Song
    let seed: String?
    let artistLine: String?
    let artworkURL: URL?
    let lyrics: Lyrics
    let cast: LyricPartCast
    #if DEBUG
    /// 見た目確認用 (`CallGuidePreviewHarness` からだけ渡る)。`sing` = 合わせた後、`parts` = パートのシート。
    var debugState: String? = nil
    #endif

    @State private var clock = KaraokeClockModel()
    @State private var listener = KaraokeListener()
    /// 合わせる画面で選んでいる行。
    @State private var anchorLineId: String?
    /// 自分のパート (アイドルの id)。
    @State private var mine: [String] = []
    @State private var showsParts = false

    @State private var positionMs: Int?
    @State private var activeLineId: String?
    @State private var activeOverlayId: String?
    @State private var activeCallIndex: Int?
    @State private var turn: KaraokeTurn?
    @State private var lane: [ImasKaraokeLane.Span] = []
    @State private var followPausedUntil: Date = .distantPast
    @State private var callPulse = 0
    @State private var tickPulse = 0
    @State private var nudgePulse = 0
    @State private var syncPulse = 0
    /// 手で合わせた・ずらしたときに、下の状態の文を少しの間それに替える。
    @State private var flash: (text: String, until: Date)?
    @AppStorage("lyrics.call_haptics") private var callHaptics = true

    private static let laneWindowMs: Int64 = 20_000

    // MARK: - 行の並び (歌詞プレイヤーと同じ判定)

    private var mainStarts: [Int64?] { lyrics.lines.map { $0.isOverlay ? nil : $0.startMs.map(Int64.init) } }
    private var overlayStarts: [Int64?] { lyrics.lines.map { $0.isOverlay ? $0.startMs.map(Int64.init) : nil } }
    private var allCalls: [LyricCall] { lyrics.lines.flatMap(\.calls) }
    private var callStarts: [Int64?] { allCalls.map { $0.startMs.map(Int64.init) } }
    private var activeCallId: String? { activeCallIndex.flatMap { $0 < allCalls.count ? allCalls[$0].id : nil } }
    /// 各行を歌う人 (原唱者にいる人だけ。帯と数えに使う)。
    private var singersByLine: [[String]] {
        let known = Set(cast.artists.map(\.id))
        return lyrics.lines.map { line in line.isOverlay ? [] : line.allSingers.filter(known.contains) }
    }
    private var hasParts: Bool { cast.artists.count >= 2 }
    /// 合わせられる行 (時刻のあるメインの行)。
    private var firstAnchorId: String? {
        lyrics.lines.first { $0.kind == .lyric && !$0.isOverlay && $0.startMs != nil }?.id
            ?? lyrics.lines.first { !$0.isOverlay && $0.startMs != nil }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp4)
                .padding(.bottom, DS.sp3)
            if clock.isSynced, hasParts {
                ImasKaraokeLane(spans: lane, seconds: Int(Self.laneWindowMs / 1000))
                    .padding(.horizontal, DS.sp5)
                    .padding(.bottom, DS.sp3)
            }
            if clock.isSynced { singing } else { aligning }
        }
        .background(DS.bg)
        .imasTheme(seed: seed)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .onAppear {
            mine = KaraokePartStore.load(songId: song.id).filter { id in cast.artists.contains { $0.id == id } }
            anchorLineId = anchorLineId ?? firstAnchorId
            UIApplication.shared.isIdleTimerDisabled = true
            #if DEBUG
            applyDebugState()
            #endif
            AppAnalytics.tap("karaoke.open")
            listener.start(song: song) { songMs, at in
                let wasSynced = clock.isSynced
                clock.heard(songMs: songMs, at: at)
                if !wasSynced, clock.isSynced {
                    AppAnalytics.tap("karaoke.heard_sync")
                    syncPulse += 1
                }
            }
        }
        .onDisappear {
            listener.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task { await poll() }
        .onChange(of: mine) { _, ids in KaraokePartStore.save(ids, songId: song.id) }
        .sensoryFeedback(.impact(weight: .heavy), trigger: callPulse)
        .sensoryFeedback(.impact(weight: .light), trigger: tickPulse)
        .sensoryFeedback(.selection, trigger: nudgePulse)
        .sensoryFeedback(.success, trigger: syncPulse)
        .sheet(isPresented: $showsParts) {
            KaraokePartSheet(lyrics: lyrics, cast: cast, mine: $mine)
        }
    }

    #if DEBUG
    private func applyDebugState() {
        guard let debugState else { return }
        if debugState == "sing" || debugState == "parts" {
            mine = cast.artists.dropFirst().prefix(1).map(\.id)
        }
        if debugState == "sing" {
            // 自分の行の 1 つ前の行 (自分でない) の途中にいる所 = 数えが見える所。
            let timed = lyrics.lines.filter { !$0.isOverlay && $0.startMs != nil }
            let k = timed.indices.dropFirst(3).first { k in
                k + 1 < timed.count && timed[k + 1].allSingers.contains(mine.first ?? "")
                    && !timed[k].allSingers.contains(mine.first ?? "")
            }
            if let k, let start = timed[k + 1].startMs {
                // 数秒後に撮るので、自分の行の 7 秒前から始める。
                clock.tap(lineStartMs: start - 7_000)
                clock.nudge(300)
            }
        }
        if debugState == "parts" { showsParts = true }
    }
    #endif

    // MARK: - 頭

    private var header: some View {
        HStack(spacing: DS.sp3) {
            ImasArtwork(title: song.title, seed: seed, size: 44, imageURL: artworkURL)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(song.title).imasText(.rowTitle).lineLimit(1)
                if let subtitle = headerSubtitle {
                    Text(subtitle).imasText(.rowSubtitle).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if hasParts {
                ImasIconButton(systemImage: mine.isEmpty ? "person.2" : "person.2.fill",
                               label: "歌うパートを選ぶ", size: .small, style: .glass) {
                    AppAnalytics.tap("karaoke.open_parts")
                    showsParts = true
                }
            }
            ImasIconButton(systemImage: "xmark", label: "カラオケモードを閉じる", size: .small, style: .glass) {
                dismiss()
            }
        }
    }

    private var headerSubtitle: String? {
        let names = cast.names(mine)
        return names.isEmpty ? artistLine : "あなた: " + names.joined(separator: "・")
    }

    // MARK: - ① 合わせる

    private var aligning: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.sp4) {
                        ForEach(lyrics.lines) { line in
                            if line.kind != .blank, !line.isOverlay {
                                alignRow(line).id(line.id)
                            }
                        }
                    }
                    .padding(.horizontal, DS.sp5)
                    .padding(.vertical, DS.sp5)
                }
                .onAppear {
                    if let id = anchorLineId { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.3)) }
                }
            }
            VStack(spacing: DS.sp3) {
                if let status = listenStatus {
                    ImasKaraokeStatus(systemImage: status.symbol, text: status.text)
                }
                ImasKaraokeTapPad(title: "歌い出しでタップ", subtitle: "選んだ行が始まった瞬間に") {
                    guard let line = lyrics.lines.first(where: { $0.id == anchorLineId }),
                          let start = line.startMs else { return }
                    AppAnalytics.tap("karaoke.tap_sync")
                    clock.tap(lineStartMs: start)
                    syncPulse += 1
                }
            }
            .padding(.horizontal, DS.sp5)
            .padding(.top, DS.sp3)
            .padding(.bottom, DS.sp4)
        }
    }

    private func alignRow(_ line: LyricLine) -> some View {
        let isAnchor = line.id == anchorLineId
        let ids = cast.ordered(line.allSingers)
        return ImasKaraokeRow(colors: cast.colors(ids), isHighlighted: isAnchor) {
            if isAnchor || !ids.isEmpty {
                ImasKaraokeSingerLabel(names: cast.names(ids), colors: cast.colors(ids),
                                       isMine: karaokeIsMine(singers: line.allSingers, mine: mine),
                                       pin: isAnchor ? "この行で合わせる" : nil)
            }
            ImasPlayerLyricLine(text: lyricOverlaySplit(text: line.text).main.isEmpty ? line.text : lyricOverlaySplit(text: line.text).main,
                                isCurrent: isAnchor, isMarker: line.kind == .marker, seed: seed)
        }
        .opacity(line.startMs == nil ? 0.4 : 1)
        .onTapGesture {
            guard line.startMs != nil else { return }
            anchorLineId = line.id
        }
        .accessibilityAddTraits(isAnchor ? .isSelected : [])
        .accessibilityHint(line.startMs == nil ? "" : "この行で合わせる")
    }

    // MARK: - ② 歌っている

    private var singing: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp5) {
                    ForEach(lyrics.lines) { line in
                        if let turn, Int(turn.index) < lyrics.lines.count, lyrics.lines[Int(turn.index)].id == line.id {
                            ImasKaraokeCountdown(remainingMs: Int(turn.inMs), lit: Int(turn.lit), seed: turnColor)
                        }
                        singRow(line).id(line.id)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp8)
            }
            .onChange(of: activeLineId) { _, id in
                guard let id, Date() >= followPausedUntil else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.32))
                }
            }
            .onAppear {
                if let id = activeLineId { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.32)) }
            }
            .modifier(PausesLyricsFollow(until: $followPausedUntil))
        }
        // 左右スワイプで 0.1 秒ずつずらす (縦のスクロールとは向きで分ける)。
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let w = value.translation.width
                    guard abs(w) > 60, abs(w) > abs(value.translation.height) * 2 else { return }
                    AppAnalytics.tap("karaoke.nudge")
                    clock.nudge(w > 0 ? 100 : -100)
                    nudgePulse += 1
                    flash = (ImasKaraokeOffsetBadge.label(clock.nudgeMs) + "ずらしました", Date().addingTimeInterval(2))
                }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: DS.sp2) {
                footer
                Text("行をタップ: いまこの行 ／ 左右スワイプ: 0.1秒ずらす")
                    .imasText(.micro, color: DS.ink3)
            }
            .padding(.horizontal, DS.sp4)
            .padding(.vertical, DS.sp3)
            .imasFloatingChrome()
            .padding(.horizontal, DS.sp3)
            .padding(.bottom, DS.sp2)
        }
    }

    @ViewBuilder
    private func singRow(_ line: LyricLine) -> some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: DS.sp2)
        case .lyric, .marker:
            let ids = cast.ordered(line.allSingers)
            let isCurrent = line.isOverlay ? line.id == activeOverlayId : line.id == activeLineId
            ImasKaraokeRow(colors: cast.colors(ids)) {
                if !ids.isEmpty || line.clap != nil {
                    ImasKaraokeSingerLabel(names: cast.names(ids), colors: cast.colors(ids),
                                           clap: line.clap?.symbol,
                                           isMine: !line.isOverlay && karaokeIsMine(singers: line.allSingers, mine: mine))
                }
                lineText(line, isCurrent: isCurrent)
                calls(line)
            }
            .onTapGesture {
                guard let start = line.startMs else { return }
                AppAnalytics.tap("karaoke.tap_line")
                clock.tap(lineStartMs: start)
                followPausedUntil = .distantPast
                syncPulse += 1
                flash = (clock.lastChange == .rateFixed ? "この行に合わせて、速さも直しました" : "この行に合わせました",
                         Date().addingTimeInterval(2))
            }
            .accessibilityHint(line.startMs == nil ? "" : "いまこの行として合わせ直す")
        }
    }

    @ViewBuilder
    private func lineText(_ line: LyricLine, isCurrent: Bool) -> some View {
        if line.isOverlay {
            let overlay = lyricOverlaySplit(text: line.text).overlay
            ImasPlayerOverlayLine(text: overlay ?? line.text, isCurrent: isCurrent, seed: seed)
        } else {
            let split = lyricOverlaySplit(text: line.text)
            let mainText = split.main.isEmpty ? line.text : split.main
            ImasPlayerLyricLine(
                text: mainText, isCurrent: isCurrent, isMarker: line.kind == .marker,
                echoes: line.calls.filter { line.echoes($0) }.compactMap { call in
                    lyricMainRange(text: line.text, start: UInt32(call.start), end: UInt32(call.end))
                        .map { .init(start: Int($0.start), end: Int($0.end)) }
                },
                parts: cast.marks(line, scheme: .dark, mapRange: mainText == line.text ? nil : { start, end in
                    lyricMainRange(text: line.text, start: UInt32(start), end: UInt32(end))
                        .map { (Int($0.start), Int($0.end)) }
                }),
                seed: seed)
            if let overlay = split.overlay, !split.main.isEmpty {
                ImasPlayerOverlayLine(text: overlay, isCurrent: isCurrent, seed: seed)
            }
        }
    }

    @ViewBuilder
    private func calls(_ line: LyricLine) -> some View {
        let shown = line.calls.filter { !line.echoes($0) }
        let penlights = shown.filter(\.isPenlight)
        let shouts = shown.filter { !$0.isPenlight }
        if !shouts.isEmpty {
            let accent = ImasTheme.derive(seed: seed, scheme: .dark).accent
            FlowLayout(spacing: DS.sp2) {
                ForEach(shouts) { call in
                    ImasKaraokeCallTag(text: call.text, color: call.emphasis.color(accent: accent),
                                       isActive: call.id == activeCallId)
                }
            }
        }
        ForEach(penlights) { call in
            if let penlight = call.penlight {
                let look = PenlightLook(penlight: penlight, cast: cast)
                ImasPlayerPenlightLine(marker: call.hasAnchor ? "↳" : "»", fill: look.fill,
                                       note: penlight.note, description: look.description,
                                       isActive: call.id == activeCallId)
            }
        }
    }

    /// 自分の番の数えの色 (その行で歌う、自分のパートの最初の人)。
    private var turnColor: String? {
        guard let turn, Int(turn.index) < lyrics.lines.count else { return nil }
        let singers = lyrics.lines[Int(turn.index)].allSingers
        return cast.artists.first { mine.contains($0.id) && singers.contains($0.id) }?.color
    }

    // MARK: - 下の操作

    private var footer: some View {
        HStack(spacing: DS.sp3) {
            ImasIconButton(systemImage: clock.isPaused ? "play.fill" : "pause.fill",
                           label: clock.isPaused ? "続ける" : "止める", size: .small, style: .glass) {
                AppAnalytics.tap("karaoke.toggle_pause")
                if clock.isPaused { clock.resume() } else { clock.pause() }
            }
            if clock.nudgeMs != 0 {
                ImasKaraokeOffsetBadge(ms: clock.nudgeMs)
            }
            if let status = footerStatus {
                ImasKaraokeStatus(systemImage: status.symbol, text: status.text)
            }
            Spacer(minLength: 0)
            if !allCalls.isEmpty {
                ImasIconButton(systemImage: callHapticsSymbol,
                               label: callHaptics ? "コールで震わせる: オン" : "コールで震わせる: オフ",
                               size: .small, style: .glass) {
                    callHaptics.toggle()
                }
            }
            ImasIconButton(systemImage: "arrow.counterclockwise", label: "はじめから合わせ直す",
                           size: .small, style: .glass) {
                AppAnalytics.tap("karaoke.reset")
                clock.reset()
                activeLineId = nil
                turn = nil
            }
        }
    }

    private var callHapticsSymbol: String {
        if #available(iOS 18.0, *) {
            return callHaptics ? "apple.haptics.and.music.note" : "apple.haptics.and.music.note.slash"
        }
        return callHaptics ? "iphone.radiowaves.left.and.right" : "iphone.slash"
    }

    private struct Status {
        let symbol: String
        let text: String
    }

    private var footerStatus: Status? {
        if let flash, flash.until > Date() { return Status(symbol: "hand.tap", text: flash.text) }
        if clock.isPaused { return Status(symbol: "pause", text: "止めています") }
        return listenStatus
    }

    /// 耳で合わせている様子。
    private var listenStatus: Status? {
        switch listener.state {
        case .idle: return nil
        case .listening: return Status(symbol: "mic", text: clock.isSynced ? "聞いて直しています" : "耳で合わせています")
        case .matched: return Status(symbol: "waveform", text: "耳で合わせました")
        case .otherSong: return Status(symbol: "mic", text: "別の曲が聞こえます")
        case .notFound: return Status(symbol: "mic", text: clock.isSynced ? "聞き取れませんでした" : "まだ聞き取れません")
        case .denied: return Status(symbol: "mic.slash", text: "マイクが使えないので、タップで合わせます")
        case .unavailable: return Status(symbol: "mic.slash", text: "耳では合わせられません。タップで合わせます")
        }
    }

    // MARK: - 時計の読み

    private func poll() async {
        while !Task.isCancelled {
            tick()
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    private func tick() {
        guard let ms = clock.positionMs() else {
            if positionMs != nil { positionMs = nil }
            return
        }
        positionMs = ms
        let position = Int64(ms)
        let index = lyricActiveLine(starts: mainStarts, positionMs: position).map(Int.init)
        let id = index.map { lyrics.lines[$0].id }
        if id != activeLineId { activeLineId = id }
        let overlay = lyricActiveOverlay(starts: overlayStarts, positionMs: position).map { lyrics.lines[Int($0)].id }
        if overlay != activeOverlayId { activeOverlayId = overlay }
        let call = lyricActiveCall(starts: callStarts, positionMs: position).map(Int.init)
        if call != activeCallIndex {
            activeCallIndex = call
            if call != nil, callHaptics, !clock.isPaused { callPulse += 1 }
        }
        let singers = singersByLine
        let next = mine.isEmpty ? nil : karaokeNextTurn(starts: mainStarts, singers: singers, mine: mine, positionMs: position)
        if let next, let old = turn, next.index == old.index, next.lit < old.lit, !clock.isPaused { tickPulse += 1 }
        if next != turn { turn = next }
        if hasParts {
            let spans = karaokeLane(starts: mainStarts, singers: singers, mine: mine,
                                    positionMs: position, windowMs: Self.laneWindowMs)
                .map { ImasKaraokeLane.Span(id: Int($0.index), from: $0.from, to: $0.to,
                                            colors: cast.colors(cast.ordered($0.singers)), isMine: $0.isMine) }
            if spans != lane { lane = spans }
        }
    }
}

// MARK: - ③ パートを選ぶ

/// 自分が歌うパートを選ぶシート。原唱者から何人でも (2 人分を歌う・全員曲で 1 人だけ抜く)。
/// 選んだ人の行に「あなた」が付き、その前に残り秒数を数える。曲ごとに端末に覚える (id だけ)。
struct KaraokePartSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lyrics: Lyrics
    let cast: LyricPartCast
    @Binding var mine: [String]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ImasNote("選んだ人の行に「あなた」が付き、歌い出しの前に秒数を数えます。")
                }
                Section {
                    ForEach(cast.artists) { idol in
                        let isOn = mine.contains(idol.id)
                        Button {
                            AppAnalytics.tap("karaoke.toggle_part")
                            mine = isOn ? mine.filter { $0 != idol.id } : cast.ordered(mine + [idol.id])
                        } label: {
                            ImasRow(title: idol.name, subtitle: "\(lineCount(idol.id))行",
                                    leading: .avatar(label: idol.shortName, seed: idol.color,
                                                     imageURL: CustomImageService.shared.imageURL(for: idol.id)),
                                    trailing: .custom(AnyView(ImasSelectionMark(isSelected: isOn, seed: idol.color))),
                                    density: .compact)
                        }
                        .buttonStyle(.imasRow)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
            .listStyle(.plain)
            .imasForm()
            .navigationTitle("誰のパートを歌う?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ImasIconButton(systemImage: "xmark", label: "閉じる", size: .small, style: .plain) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func lineCount(_ id: String) -> Int {
        lyrics.lines.filter { !$0.isOverlay && $0.allSingers.contains(id) }.count
    }
}
