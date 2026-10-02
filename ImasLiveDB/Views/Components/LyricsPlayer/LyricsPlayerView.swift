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

    @State private var positionMs: Int?
    @State private var activeLineId: String?
    @State private var followPausedUntil: Date = .distantPast
    @State private var likeToken = 0
    @State private var startFailed = false

    private var starts: [Int64?] { lyrics.lines.map { $0.startMs.map(Int64.init) } }
    private var hasTiming: Bool { lyricHasTiming(starts: starts) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, DS.sp5)
                .padding(.top, DS.sp4)
                .padding(.bottom, DS.sp3)
            lyricsScroll
            controls
                .padding(.horizontal, DS.sp5)
                .padding(.bottom, DS.sp4)
        }
        .background(DS.bg)
        .task { await startIfNeeded() }
        .task(id: playback.isFullLoaded) { await poll() }
        .sensoryFeedback(.impact(weight: .light), trigger: likeToken)
        .imasTheme(seed: seed)
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
            ImasIconButton(systemImage: "metronome", label: "タイミングを編集", size: .small, style: .plain) {
                onEditTimings()
            }
            ImasIconButton(systemImage: "chevron.down", label: "閉じる", size: .small) { dismiss() }
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
            VStack(alignment: .leading, spacing: DS.sp1) {
                ImasPlayerLyricLine(text: line.text, isCurrent: !hasTiming || line.id == activeLineId,
                                    isMarker: line.kind == .marker, isLiked: isLiked, seed: seed)
                if !line.calls.isEmpty {
                    CallGuideCallRows(calls: line.calls, anchorIndexes: nil)
                }
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
                seed: seed
            ) { fraction in
                AppAnalytics.tap("lyrics_player.heat_seek")
                followPausedUntil = .distantPast
                Task { await playback.playFrom(Int(fraction * Double(duration))) }
            }
            HStack {
                Text(Self.clock(position)).imasText(.imprint, color: DS.ink3)
                Spacer()
                Text("-" + Self.clock(max(0, duration - position))).imasText(.imprint, color: DS.ink3)
            }
            HStack(spacing: DS.sp8) {
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
                let index = lyricActiveLine(starts: starts, positionMs: Int64(ms)).map(Int.init)
                let id = index.map { lyrics.lines[$0].id }
                if id != activeLineId { activeLineId = id }
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
