import SwiftUI

/// 歌詞プレイヤー。全画面で、いま歌われている行を大きく出して真ん中へ追従する
/// (Apple Music の歌詞表示の読ませ方)。
///
/// - 行をタップ … その行の歌い出しへ飛ぶ (時刻のある行だけ)
/// - 行をダブルタップ … ここ好き
/// - 指でスクロール … 数秒は追従を止める
///
/// 背景はジャケのぼかしにしない (グラデーション・光は使わない決まり)。平らな地のまま。
///
/// ⚠️ 歌詞の本文にテキスト選択・コピー・共有の口を付けないこと (`SongLyricsTab` 冒頭)。
struct LyricsPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let song: Song
    let seed: String?
    let artistLine: String?
    let artworkURL: URL?
    let lyrics: Lyrics
    let playback: LyricsPlayback
    /// みんなの人数 (付け外しの後にサーバが返した値)。歌詞タブと共有する。
    @Binding var likeCounts: [String: Int]
    /// タイミング編集を開く。
    let onEditTimings: () -> Void
    /// パート分けの色・名前を引く表 (原唱者)。
    var cast: LyricPartCast = .empty

    @State private var positionMs: Int?
    @State private var activeLineId: String?
    /// いま光らせる被せの行。
    @State private var activeOverlayId: String?
    @State private var followPausedUntil: Date = .distantPast
    @State private var likeToken = 0
    /// いま出しているコールの添字 (曲の順)。変わった瞬間に震わせる (コール練習)。
    @State private var activeCallIndex: Int?
    @State private var callPulse = 0
    /// コールのタイミングで震わせるか (端末の設定。既定はオン)。
    @AppStorage("lyrics.call_haptics") private var callHaptics = true
    @State private var startFailed = false
    @State private var showsAddToPlaylist = false
    @State private var showsQueue = false
    /// 下へ引いている量 (畳む手前で画面ごと付いてくる)。
    @State private var pullOffset: CGFloat = 0

    private var starts: [Int64?] { lyrics.lines.map { $0.startMs.map(Int64.init) } }
    /// メインの行だけに時刻を入れた並び (被せの行に今の行を取られない)。
    private var mainStarts: [Int64?] { lyrics.lines.map { $0.isOverlay ? nil : $0.startMs.map(Int64.init) } }
    /// 被せの行だけに時刻を入れた並び。
    private var overlayStarts: [Int64?] { lyrics.lines.map { $0.isOverlay ? $0.startMs.map(Int64.init) : nil } }
    /// 曲の順に並べたコール。時刻が 1 つでもあれば、歌詞と並べてコールの段を流す。
    private var allCalls: [LyricCall] { lyrics.lines.flatMap(\.calls) }
    private var callStarts: [Int64?] { allCalls.map { $0.startMs.map(Int64.init) } }
    private var hasTiming: Bool { lyricHasTiming(starts: starts) }
    /// いま出しているコールの id。
    private var activeCallId: String? { activeCallIndex.flatMap { $0 < allCalls.count ? allCalls[$0].id : nil } }

    var body: some View {
        // 歌詞は画面いっぱいに流し、頭と下の操作はその上に浮かべる (iOS 26 は下の操作がガラスで、
        // 後ろを流れる歌詞が透けて見える)。紙面の歌詞そのものは平らなまま。
        lyricsScroll
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, DS.sp5)
                    .padding(.top, DS.sp4)
                    .padding(.bottom, DS.sp3)
                    .background(DS.bg)
                    .modifier(PullsDownToDismiss(offset: $pullOffset) { dismiss() })
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controls
                    .padding(.horizontal, DS.sp4)
                    .padding(.vertical, DS.sp4)
                    .imasFloatingChrome()
                    .padding(.horizontal, DS.sp3)
                    .padding(.bottom, DS.sp2)
                    .modifier(PullsDownToDismiss(offset: $pullOffset) { dismiss() })
            }
            .background(DS.bg)
            // 下へスワイプで畳む (頭と下の操作をつまむ。歌詞は一番上から引き下げる)。
            .offset(y: pullOffset)
        .task { await startIfNeeded() }
        .task(id: playback.isFullLoaded) { await poll() }
        .sensoryFeedback(.impact(weight: .light), trigger: likeToken)
        .sensoryFeedback(.impact(weight: .heavy), trigger: callPulse)
        .imasTheme(seed: seed)
        .sheet(isPresented: $showsAddToPlaylist) { AddToPlaylistSheet(song: song) }
        .sheet(isPresented: $showsQueue) { PlayQueueSheet() }
    }

    // MARK: - 頭

    private var header: some View {
        HStack(spacing: DS.sp3) {
            ImasArtwork(title: song.title, seed: seed, size: 52, imageURL: artworkURL)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(song.title).imasText(.rowTitle).lineLimit(1)
                if let artistLine, !artistLine.isEmpty {
                    Text(artistLine).imasText(.rowSubtitle).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !allCalls.isEmpty {
                ImasIconButton(systemImage: callHaptics ? "iphone.radiowaves.left.and.right" : "iphone.slash",
                               label: callHaptics ? "コールで震わせる: オン" : "コールで震わせる: オフ",
                               size: .small, style: .glass) {
                    AppAnalytics.tap("lyrics_player.toggle_call_haptics")
                    callHaptics.toggle()
                }
            }
            ImasIconButton(systemImage: "text.badge.plus", label: "プレイリストに追加", size: .small, style: .glass) {
                AppAnalytics.tap("lyrics_player.add_to_playlist")
                showsAddToPlaylist = true
            }
            ImasIconButton(systemImage: "metronome", label: "タイミングを編集", size: .small, style: .glass) {
                onEditTimings()
            }
            ImasIconButton(systemImage: "chevron.down", label: "閉じる", size: .small, style: .glass) { dismiss() }
        }
    }

    // MARK: - 歌詞

    private var lyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sp5) {
                    if !hasTiming { noTimingNote }
                    if startFailed {
                        ImasNote("再生には Apple Music でのフル再生が必要です。", systemImage: "music.note")
                    }
                    let likes = UserMarkService.shared.lyricLikes(songId: song.id)
                    ForEach(lyrics.lines) { line in
                        row(line, isLiked: likes.contains(line.id))
                            .id(line.id)
                    }
                }
                .padding(.horizontal, DS.sp5)
                .padding(.vertical, DS.sp8)
            }
            .onChange(of: activeLineId) { _, id in
                guard let id, Date() >= followPausedUntil else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.38))
                }
            }
            .modifier(PausesLyricsFollow(until: $followPausedUntil))
            .modifier(OverscrollDismiss { dismiss() })
        }
    }

    private var noTimingNote: some View {
        VStack(alignment: .leading, spacing: DS.sp3) {
            ImasNote("この曲はまだ行の時刻が記録されていないので、追従できません。", systemImage: "metronome")
            ImasButton(title: "タイミングを記録する", systemImage: "metronome", role: .secondary, size: .small) {
                onEditTimings()
            }
        }
    }

    @ViewBuilder
    private func row(_ line: LyricLine, isLiked: Bool) -> some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: DS.sp2)
        case .lyric, .marker:
            HStack(alignment: .top, spacing: DS.sp3) {
                rowBody(line, isLiked: isLiked)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { like(line) }
            .onTapGesture {
                guard let start = line.startMs else { return }
                AppAnalytics.tap("lyrics_player.seek_line")
                followPausedUntil = .distantPast
                Task { await playback.playFrom(start) }
            }
            .accessibilityAction(named: isLiked ? "ここ好きを外す" : "ここ好き") { like(line) }
        }
    }

    private func rowBody(_ line: LyricLine, isLiked: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.sp1) {
            if line.isOverlay {
                // 行まるごとの被せ。メインとは別に、自分の時刻で光る 2 段目。
                ImasPlayerOverlayLine(text: lyricOverlaySplit(text: line.text).overlay ?? line.text,
                                      isCurrent: !hasTiming || line.id == activeOverlayId, seed: seed)
            } else {
                // 行の中の括弧 (追いかけ) は本文から外して、すぐ下に 2 段目として重ねる。
                let split = lyricOverlaySplit(text: line.text)
                let isCurrent = !hasTiming || line.id == activeLineId
                let mainText = split.main.isEmpty ? line.text : split.main
                ImasPlayerLyricLine(text: mainText, isCurrent: isCurrent,
                                    isMarker: line.kind == .marker, isLiked: isLiked,
                                    echoes: line.calls.filter { line.echoes($0) }.compactMap { call in
                                        // 被せを外したメインの行の中の位置に置き直す (被せに掛かるものは印を付けない)。
                                        lyricMainRange(text: line.text, start: UInt32(call.start), end: UInt32(call.end))
                                            .map { .init(start: Int($0.start), end: Int($0.end), isActive: call.id == activeCallId) }
                                    },
                                    // 歌う人は字の下に担当色の線で (被せを外した本文の位置に置き直す)。
                                    parts: cast.marks(line, scheme: scheme, mapRange: mainText == line.text ? nil : { start, end in
                                        lyricMainRange(text: line.text, start: UInt32(start), end: UInt32(end))
                                            .map { (Int($0.start), Int($0.end)) }
                                    }),
                                    seed: seed)
                if let overlay = split.overlay, !split.main.isEmpty {
                    ImasPlayerOverlayLine(text: overlay, isCurrent: isCurrent, seed: seed)
                }
            }
            ImasPartNames(groups: cast.groups(line))
            // コールは行の直下に流す。いま出すコールだけ大きく点ける (歌詞と同じ文字のものは行に出さず、上の歌詞を点ける)。
            ForEach(line.calls.filter { !line.echoes($0) }) { call in
                ImasPlayerCallLine(marker: call.hasAnchor ? "↳" : "»", text: call.text,
                                   color: call.emphasis.color(accent: ImasTheme.derive(seed: seed, scheme: scheme).accent),
                                   isActive: call.id == activeCallId)
            }
        }
    }

    // MARK: - 下の操作

    private var durationMs: Int {
        let lastStart = starts.compactMap { $0 }.max().map(Int.init) ?? 0
        return playback.durationMs() ?? song.durationSec.map { $0 * 1000 } ?? lastStart + 8000
    }

    private var controls: some View {
        let duration = max(1, durationMs)
        let counts = lyrics.lines.map { UInt32(max(0, likeCounts[$0.id] ?? $0.likeCount)) }
        let heat = hasTiming
            ? lyricLikeHeat(starts: starts, counts: counts, durationMs: Int64(duration), buckets: 60)
            : LyricLikeHeat(levels: [], peakMs: nil)
        let position = positionMs ?? 0
        return VStack(spacing: DS.sp3) {
            ImasLikeHeatSeekBar(
                levels: heat.levels,
                progress: playback.isFullLoaded ? Double(position) / Double(duration) : nil,
                peak: heat.peakMs.map { Double($0) / Double(duration) },
                seed: seed,
                allowsScrub: true
            ) { fraction in
                AppAnalytics.tap("lyrics_player.heat_seek")
                followPausedUntil = .distantPast
                Task { await playback.playFrom(Int(fraction * Double(duration))) }
            }
            HStack {
                Text(Self.clock(position)).imasText(.imprint, color: DS.ink3)
                Spacer()
                if playback.isFullLoaded {
                    // 次に流れる曲と自動再生 (∞) は、Apple Music と同じく下の操作の並びに置く。
                    ImasIconButton(systemImage: "list.bullet", label: "次に流れる曲", size: .small, style: .plain) {
                        AppAnalytics.tap("lyrics_player.open_queue")
                        showsQueue = true
                    }
                    Spacer()
                }
                Text("-" + Self.clock(max(0, duration - position))).imasText(.imprint, color: DS.ink3)
            }
            HStack(spacing: playback.hasQueue ? DS.sp5 : DS.sp8) {
                if playback.hasQueue {
                    ImasIconButton(systemImage: "backward.fill", label: "前の曲", style: .plain) {
                        AppAnalytics.tap("lyrics_player.skip_previous")
                        playback.skipPrevious()
                    }
                }
                ImasIconButton(systemImage: "gobackward.10", label: "10 秒戻す") {
                    playback.seek(max(0, position - 10_000))
                }
                ImasIconButton(systemImage: playback.isPlaying ? "pause.fill" : "play.fill",
                               label: playback.isPlaying ? "一時停止" : "再生", style: .filled) {
                    if playback.isFullLoaded {
                        playback.togglePlay()
                    } else {
                        Task { await startIfNeeded() }
                    }
                }
                ImasIconButton(systemImage: "goforward.10", label: "10 秒進める") {
                    playback.seek(min(duration, position + 10_000))
                }
                if playback.hasQueue {
                    ImasIconButton(systemImage: "forward.fill", label: "次の曲", style: .plain) {
                        AppAnalytics.tap("lyrics_player.skip_next")
                        playback.skipNext()
                    }
                    .disabled(!playback.canSkipNext)
                }
            }
        }
    }

    // MARK: - 再生との連動

    /// 開いたときにこの曲がフル尺で鳴っていなければ鳴らす (プレイヤーを開く = 聴く)。
    private func startIfNeeded() async {
        guard !playback.isFullLoaded else { return }
        startFailed = !(await playback.startFull())
    }

    private func poll() async {
        while !Task.isCancelled {
            if let ms = playback.positionMs() {
                if ms != positionMs { positionMs = ms }
                let index = lyricActiveLine(starts: mainStarts, positionMs: Int64(ms)).map(Int.init)
                let id = index.map { lyrics.lines[$0].id }
                if id != activeLineId { activeLineId = id }
                let overlay = lyricActiveOverlay(starts: overlayStarts, positionMs: Int64(ms))
                    .map { lyrics.lines[Int($0)].id }
                if overlay != activeOverlayId { activeOverlayId = overlay }
                // コール練習: 次のコールに入った瞬間だけ震わせる (コールが切れたときは震わせない)。
                let call = lyricActiveCall(starts: callStarts, positionMs: Int64(ms)).map(Int.init)
                if call != activeCallIndex {
                    activeCallIndex = call
                    if call != nil, callHaptics, playback.isPlaying { callPulse += 1 }
                }
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func like(_ line: LyricLine) {
        likeToken += 1
        Task {
            if let count = await LyricLikeAction.toggle(songId: song.id, lineId: line.id) {
                likeCounts[line.id] = count
            }
        }
    }

    static func clock(_ ms: Int) -> String {
        let s = max(0, ms) / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 指でスクロールしている間と離して数秒は、歌詞の追従で引き戻さない (iOS 18 から)。
struct PausesLyricsFollow: ViewModifier {
    @Binding var until: Date

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating {
                    until = Date().addingTimeInterval(4)
                }
            }
        } else {
            content
        }
    }
}

/// 画面を下へスワイプして畳む (頭と下の操作の上で)。指に付いて下がり、引き切るか勢いよく払うと閉じる。
/// 横の動きが勝つとき (つまみを横になぞる等) は取らない。
struct PullsDownToDismiss: ViewModifier {
    @Binding var offset: CGFloat
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard value.translation.height > 0,
                          value.translation.height > abs(value.translation.width) * 1.5 else { return }
                    offset = value.translation.height
                }
                .onEnded { value in
                    if offset > 140 || (offset > 40 && value.predictedEndTranslation.height > 360) {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { offset = 0 }
                    }
                }
        )
    }
}

/// 歌詞を一番上からさらに引き下げたら畳む (Apple Music と同じ)。iOS 18 未満は何もしない。
struct OverscrollDismiss: ViewModifier {
    let onDismiss: () -> Void
    @State private var isInteracting = false
    @State private var fired = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    isInteracting = phase == .interacting
                    if phase == .idle { fired = false }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { _, pulled in
                    guard isInteracting, !fired, pulled < -120 else { return }
                    fired = true
                    onDismiss()
                }
        } else {
            content
        }
    }
}
