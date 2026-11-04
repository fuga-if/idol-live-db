import AVFoundation
import AVKit
import CoreMedia
import Observation
import OSLog
import SwiftUI
import UIKit
import VideoToolbox
import os

/// 歌詞をピクチャ・イン・ピクチャ (PiP) で出す。他のアプリを開いている間も、いま歌っている行が画面の隅に残る。
///
/// PiP は映像しか浮かべられないので、いま歌っている行・次の行・コールを 1 枚の絵に描き、
/// `AVSampleBufferDisplayLayer` に映像の 1 コマとして流す。
///
/// 曲ぶんの絵 (行・コールが替わるところごとに 1 枚) を先に描いて H.264 の映像にし、曲の時刻を付けて
/// まとめて層に流しておく (`Timeline`)。層は自分の時計 (`controlTimebase`) で絵を替えていくので、
/// アプリが裏で止められても (Spotify で鳴らしている間など) 歌詞は曲の時間どおりに進む。
/// アプリが動いている間は再生位置と時計を突き合わせ、ずれたら (シーク・一時停止) 流し直す。
/// 曲ぶんの絵ができるまでは、行が替わるたびに 1 枚描いてすぐ出す。
/// 歌詞は `LyricsSession` が預かったものから引く (ロック画面のライブアクティビティと同じ)。
///
/// - 歌詞プレイヤーの頭の記号で始める / 終える。
/// - 歌詞プレイヤーを開いたまま鳴らしていてホームへ出たら、自分で浮かぶ (PiP の自動開始)。
/// - PiP の再生ボタン・15 秒送りは、そのままフル再生を操作する。
/// - 曲を止めたら PiP も閉じる。
///
/// ⚠️ 歌詞の本文を描くのは、いま歌っている行と次の行の 2 行だけ。描いた絵は層に流すだけで、
/// 保存・共有しない (`Models/Lyrics.swift` 冒頭の許諾条件)。
@MainActor @Observable
final class LyricsPictureInPicture: NSObject {
    static let shared = LyricsPictureInPicture()

    /// 端末が PiP を使えるか (iPhone は iOS 14 から全機種。設定でオフにしていれば自動では浮かばない)。
    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// いま浮かべているか。
    private(set) var isActive = false

    /// 絵の大きさ (16:9。PiP の窓の形がこれで決まる)。
    nonisolated static let canvas = CGSize(width: 960, height: 540)

    @ObservationIgnored private let layer = AVSampleBufferDisplayLayer()
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var timebase: CMTimebase?
    /// 層を抱える場所。最後に画面に載ったものが層を持つ (歌詞プレイヤーを開けばその中、閉じたら根の画面へ戻す)。
    @ObservationIgnored private var hosts: [WeakHost] = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastFrame: Frame?
    @ObservationIgnored private var lastPlaying: Bool?
    @ObservationIgnored private var playerVisible = false
    /// 始めると押したが、まだ PiP を始められる状態になっていない (最初の 1 コマを流した直後など)。
    @ObservationIgnored private var pendingStart = false
    @ObservationIgnored private var style: UIUserInterfaceStyle = .unspecified
    /// 曲ぶんの絵。いま鳴っている曲・見た目と合っていれば、これを層に流す。
    @ObservationIgnored private var timeline: Timeline?
    /// 層に流しているのが曲ぶんの絵か (false なら 1 枚ずつ)。
    @ObservationIgnored private var showsTimeline = false
    @ObservationIgnored private var building: (key: TimelineKey, task: Task<Void, Never>)?
    /// 作れなかった曲ぶんの絵 (裏にいて映像にできなかった等)。しばらくは作り直さない。
    @ObservationIgnored private var failedBuild: (key: TimelineKey, at: Date)?
    /// 層がまだ受け取っていない絵 (層の受け口が空いたら続きを渡す)。
    @ObservationIgnored private var pendingSamples: [CMSampleBuffer] = []
    @ObservationIgnored private var pendingIndex = 0
    /// PiP の再生ボタン・時間の帯が主スレッドの外から引く値。
    private nonisolated let snapshot = OSAllocatedUnfairLock(initialState: Snapshot())

    private struct Snapshot: Sendable {
        var isPlaying = false
        var durationMs = 0
    }

    private struct WeakHost {
        weak var view: LyricsPiPHostView?
    }

    /// 曲ぶんの絵がどの曲・どの見た目・どの時刻の付け方のものか。
    struct TimelineKey: Equatable {
        var songId: String
        var dark: Bool
        /// 行・コールの時刻と本文 (記録し直したら作り直す)。
        var signature: Int
        var durationSec: Int
    }

    /// 曲ぶんの絵。`ms` はその絵を出し始める曲の時刻。
    struct Timeline {
        var key: TimelineKey
        var frames: [(ms: Int, sample: CMSampleBuffer)]
    }

    /// 描いた絵の中身。同じなら描き直さない。
    struct Frame: Equatable {
        var songId: String?
        var lineIndex: Int?
        var nextIndex: Int?
        var call: String?
        var dark: Bool
    }

    override private init() {
        super.init()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &timebase)
        if let timebase {
            CMTimebaseSetRate(timebase, rate: 0)
            layer.controlTimebase = timebase
            self.timebase = timebase
        }
    }

    // MARK: - 歌詞プレイヤーから

    /// 歌詞プレイヤーを開いている間は true。鳴らしたままホームへ出たら自分で浮かぶ。
    func setPlayerVisible(_ visible: Bool) {
        playerVisible = visible
        sync()
        updateAutoStart()
    }

    /// 記号を押した: 浮かべる / 閉じる。
    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }
        AppAnalytics.tap("lyrics_player.pip_start")
        sync()
        tick()
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            pendingStart = true
        }
    }

    // MARK: - 歌詞・再生が変わったとき

    /// 預かった歌詞か再生が変わったときに呼ぶ (`LyricsSession`)。描く必要があれば周期で描き始める。
    /// 描くのは歌詞プレイヤーを開いている間 (自分で浮かぶための 1 コマを用意しておく) と、浮かべている間だけ。
    func sync() {
        let player = MusicKitService.shared
        guard player.isFullPlayback, isActive || (playerVisible && usableEntry() != nil) else {
            stopLoop()
            if isActive { controller?.stopPictureInPicture() }
            updateAutoStart()
            return
        }
        setUpControllerIfNeeded()
        guard loop == nil else { return }
        tick()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.tick()
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
        // 裏に回ると層の中身が消えることがあるので、次に描き始めたら必ず 1 コマ流し直す。
        lastFrame = nil
        showsTimeline = false
    }

    /// 行の時刻があり、フル再生で鳴っている曲の歌詞。
    private func usableEntry() -> LyricsSession.Entry? {
        let player = MusicKitService.shared
        guard player.isFullPlayback,
              let entry = LyricsSession.shared.entry(forSongId: player.nowPlayingSongId),
              lyricHasTiming(starts: entry.lyrics.lines.map { $0.startMs.map(Int64.init) })
        else { return nil }
        return entry
    }

    private func updateAutoStart() {
        let player = MusicKitService.shared
        controller?.canStartPictureInPictureAutomaticallyFromInline =
            playerVisible && player.isPlaying && usableEntry() != nil && (lastFrame != nil || showsTimeline)
    }

    private func tick() {
        let player = MusicKitService.shared
        guard player.isFullPlayback else {
            sync()
            return
        }
        let entry = usableEntry()
        if entry == nil || !playerVisible, !isActive {
            sync()
            return
        }
        let positionMs = player.fullPlaybackPositionMs ?? 0
        let isPlaying = player.isPlaying
        let durationMs = player.fullPlaybackDurationMs ?? 0
        snapshot.withLock {
            $0.isPlaying = isPlaying
            $0.durationMs = durationMs
        }
        let jumped = syncTimebase(positionMs: positionMs, isPlaying: isPlaying)
        if isPlaying != lastPlaying {
            lastPlaying = isPlaying
            controller?.invalidatePlaybackState()
            updateAutoStart()
        }

        let dark = style == .dark
        // 曲ぶんの絵があればそれを流す。無ければ作り始め、できるまでは 1 枚ずつ。
        if let entry {
            let key = Self.timelineKey(entry, dark: dark, durationMs: durationMs)
            if let timeline, timeline.key == key {
                let renderer = layer.sampleBufferRenderer
                if !showsTimeline || jumped || renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
                    schedule(timeline, from: positionMs)
                }
                return
            }
            buildTimelineIfNeeded(entry, key: key)
        }
        if showsTimeline {
            showsTimeline = false
            clearLayer()
            lastFrame = nil
        }

        let frame = Self.frame(entry, positionMs: positionMs, dark: dark)
        guard frame != lastFrame else { return }
        let firstFrame = lastFrame == nil
        guard let buffer = Self.render(entry, frame: frame) else { return }
        enqueue(buffer)
        lastFrame = frame
        if firstFrame { updateAutoStart() }
    }

    /// 層の時計を再生位置に合わせる。時計を動かした (ずれていた・シークした) ら true。
    @discardableResult
    private func syncTimebase(positionMs: Int, isPlaying: Bool) -> Bool {
        guard let timebase else { return false }
        let position = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
        var jumped = false
        if abs(CMTimebaseGetTime(timebase).seconds - position.seconds) > 0.3 {
            CMTimebaseSetTime(timebase, time: position)
            jumped = true
        }
        let rate: Float64 = isPlaying ? 1 : 0
        if CMTimebaseGetRate(timebase) != rate { CMTimebaseSetRate(timebase, rate: rate) }
        return jumped
    }

    // MARK: - 曲ぶんの絵

    private func buildTimelineIfNeeded(_ entry: LyricsSession.Entry, key: TimelineKey) {
        guard building?.key != key else { return }
        if let failedBuild, failedBuild.key == key, Date().timeIntervalSince(failedBuild.at) < 15 { return }
        building?.task.cancel()
        let task = Task { [weak self] in
            let frames = await Self.makeTimeline(entry, dark: key.dark, durationMs: key.durationSec * 1000)
            guard let self, !Task.isCancelled, self.building?.key == key else { return }
            self.building = nil
            if let frames {
                self.timeline = Timeline(key: key, frames: frames)
                self.failedBuild = nil
            } else {
                self.failedBuild = (key, Date())
            }
            self.tick()
        }
        building = (key, task)
    }

    /// 層を空にして、曲ぶんの絵を今の位置から流し直す。今の位置の絵は今の時刻に付け直してすぐ出す。
    private func schedule(_ timeline: Timeline, from positionMs: Int) {
        clearLayer()
        let frames = timeline.frames
        let start = frames.lastIndex { $0.ms <= positionMs } ?? 0
        pendingSamples = frames[start...].enumerated().compactMap { offset, frame in
            Self.retimed(frame.sample, ms: offset == 0 ? positionMs : frame.ms)
        }
        pendingIndex = 0
        showsTimeline = true
        lastFrame = nil
        feedLayer()
        if pendingIndex < pendingSamples.count {
            layer.sampleBufferRenderer.requestMediaDataWhenReady(on: .main) { [weak self] in
                MainActor.assumeIsolated { self?.feedLayer() }
            }
        }
    }

    private func feedLayer() {
        let renderer = layer.sampleBufferRenderer
        while pendingIndex < pendingSamples.count, renderer.isReadyForMoreMediaData {
            renderer.enqueue(pendingSamples[pendingIndex])
            pendingIndex += 1
        }
        if pendingIndex >= pendingSamples.count {
            renderer.stopRequestingMediaData()
            pendingSamples = []
            pendingIndex = 0
        }
    }

    private func clearLayer() {
        let renderer = layer.sampleBufferRenderer
        renderer.stopRequestingMediaData()
        renderer.flush()
        pendingSamples = []
        pendingIndex = 0
    }

    private static func retimed(_ sample: CMSampleBuffer, ms: Int) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMTime(value: CMTimeValue(ms), timescale: 1000),
                                        decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
                                              sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                              sampleBufferOut: &out)
        return out
    }

    static func timelineKey(_ entry: LyricsSession.Entry, dark: Bool, durationMs: Int) -> TimelineKey {
        var hasher = Hasher()
        for line in entry.lyrics.lines {
            hasher.combine(line.id)
            hasher.combine(line.startMs)
            hasher.combine(line.text)
            for call in line.calls {
                hasher.combine(call.id)
                hasher.combine(call.startMs)
                hasher.combine(call.text)
            }
        }
        return TimelineKey(songId: entry.song.id, dark: dark, signature: hasher.finalize(),
                           durationSec: durationMs / 1000)
    }

    /// 曲の中で絵が替わるところと、そこから出す絵。行・コールの始まりちょうどと、その間を 0.1 秒刻みで見る
    /// (コールが消えるところも拾うため)。同じ絵が続くところは 1 枚にまとめる。曲の終わりには曲名だけの絵を置く。
    static func timelinePoints(_ entry: LyricsSession.Entry, dark: Bool, durationMs: Int) -> [(ms: Int, frame: Frame)] {
        let lines = entry.lyrics.lines
        let starts = lines.compactMap(\.startMs) + lines.flatMap { $0.calls.compactMap(\.startMs) }
        let endMs = durationMs > 0 ? durationMs : (starts.max() ?? 0) + 10_000
        var times = Set(starts.filter { $0 >= 0 && $0 < endMs })
        times.insert(0)
        for ms in stride(from: 0, to: endMs, by: 100) { times.insert(ms) }
        var points: [(ms: Int, frame: Frame)] = []
        for ms in times.sorted() {
            let frame = Self.frame(entry, positionMs: ms, dark: dark)
            if points.last?.frame != frame { points.append((ms, frame)) }
        }
        if durationMs > 0 { points.append((durationMs, Frame(songId: nil, dark: dark))) }
        return points
    }

    /// 曲ぶんの絵を描いて H.264 (全部キーフレーム。どこからでも出せるように) にする。作れなければ nil。
    static func makeTimeline(_ entry: LyricsSession.Entry, dark: Bool,
                             durationMs: Int) async -> [(ms: Int, sample: CMSampleBuffer)]? {
        let points = timelinePoints(entry, dark: dark, durationMs: durationMs)
        guard !points.isEmpty, let encoder = FrameEncoder(size: canvas) else { return nil }
        for (index, point) in points.enumerated() {
            if Task.isCancelled { encoder.cancel(); return nil }
            guard let pixelBuffer = renderPixelBuffer(point.frame.songId == nil ? nil : entry, frame: point.frame)
            else { encoder.cancel(); return nil }
            encoder.encode(pixelBuffer, ms: point.ms)
            // 主スレッドを長く塞がない (歌詞プレイヤーの追従を止めない)。
            if index % 3 == 2 { await Task.yield() }
        }
        let box = await Task.detached(priority: .userInitiated) { encoder.finish() }.value
        guard let samples = box?.samples, samples.count == points.count else { return nil }
        return samples.map { (ms: Int(CMSampleBufferGetPresentationTimeStamp($0).value * 1000
                                      / Int64(max(1, CMSampleBufferGetPresentationTimeStamp($0).timescale))),
                              sample: $0) }
    }

    private func enqueue(_ buffer: CMSampleBuffer) {
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
        }
        renderer.enqueue(buffer)
    }

    // MARK: - 層を抱える場所

    fileprivate func hostChanged(_ host: LyricsPiPHostView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        if host.window != nil { hosts.append(WeakHost(view: host)) }
        adoptLayer()
    }

    fileprivate func hostLaidOut(_ host: LyricsPiPHostView) {
        if layer.superlayer === host.layer { adoptLayer() }
    }

    private func adoptLayer() {
        guard let host = hosts.last(where: { $0.view?.window != nil })?.view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if layer.superlayer !== host.layer { host.layer.addSublayer(layer) }
        layer.frame = host.bounds
        CATransaction.commit()
        let newStyle = host.traitCollection.userInterfaceStyle
        if newStyle != style {
            style = newStyle
            lastFrame = nil
        }
    }

    private func setUpControllerIfNeeded() {
        guard controller == nil, Self.isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] pip, _ in
            let possible = pip.isPictureInPicturePossible
            Task { @MainActor in self?.possibleChanged(possible) }
        }
        controller = pip
        // PiP は音声セッションが「再生」の分類でないと始められない (有効化はしない。鳴らす側に任せる)。
        Task.detached(priority: .utility) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
            } catch {
                Logger.musickit.error("pip_audio_category_failed: \(error.localizedDescription)")
            }
        }
    }

    private func possibleChanged(_ possible: Bool) {
        guard possible, pendingStart else { return }
        pendingStart = false
        controller?.startPictureInPicture()
    }

    fileprivate func setActive(_ active: Bool) {
        isActive = active
        pendingStart = false
        if active {
            lastFrame = nil
            showsTimeline = false
        }
        sync()
    }

    // MARK: - 描く

    static func frame(_ entry: LyricsSession.Entry?, positionMs: Int, dark: Bool) -> Frame {
        guard let entry else { return Frame(songId: nil, dark: dark) }
        let lines = entry.lyrics.lines
        let mainStarts = lines.map { $0.isOverlay ? nil : $0.startMs.map(Int64.init) }
        let index = lyricActiveLine(starts: mainStarts, positionMs: Int64(positionMs)).map(Int.init)
        let current = index.flatMap { lines[$0].kind == .lyric ? $0 : nil }
        let next = lines.indices.dropFirst((index ?? -1) + 1).first { lines[$0].kind == .lyric && !lines[$0].isOverlay }
        let calls = lines.flatMap { line in line.calls.map { (line: line, call: $0) } }
        let call = lyricActiveCall(starts: calls.map { $0.call.startMs.map(Int64.init) }, positionMs: Int64(positionMs))
            .map { calls[Int($0)] }
            .map { $0.line.echoes($0.call) ? "一緒に" : $0.call.text }
        return Frame(songId: entry.song.id, lineIndex: current, nextIndex: next, call: call, dark: dark)
    }

    /// 1 コマ描いて、すぐ出す印を付けた映像の 1 コマにする。
    static func render(_ entry: LyricsSession.Entry?, frame: Frame) -> CMSampleBuffer? {
        guard let pixelBuffer = renderPixelBuffer(entry, frame: frame) else { return nil }
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: format, sampleTiming: &timing,
                                                 sampleBufferOut: &sample)
        guard let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    /// 1 コマを絵 (BGRA) に描く。
    static func renderPixelBuffer(_ entry: LyricsSession.Entry?, frame: Frame) -> CVPixelBuffer? {
        let size = canvas
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer
        else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
        if let context {
            // UIKit の向き (左上が原点) にしてから描く。
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            let traits = UITraitCollection(userInterfaceStyle: frame.dark ? .dark : .light)
            traits.performAsCurrent { draw(entry, frame: frame, in: context, size: size) }
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return context == nil ? nil : pixelBuffer
    }

    /// 地は平らな紙の色。上に曲名、真ん中にいま歌っている行 (歌う人の色で字を塗る)、その下に歌う人とコール、
    /// 一番下に次の行を薄く。
    private static func draw(_ entry: LyricsSession.Entry?, frame: Frame, in context: CGContext, size: CGSize) {
        let scheme: ColorScheme = frame.dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: frame.dark ? .dark : .light)
        func resolve(_ color: Color) -> UIColor { UIColor(color).resolvedColor(with: traits) }
        let ink = resolve(DS.ink), ink2 = resolve(DS.ink2), ink3 = resolve(DS.ink3)
        let accent = resolve(ImasTheme.derive(seed: entry?.seed, scheme: scheme).accent)

        context.setFillColor(resolve(DS.bg).cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let margin: CGFloat = 48
        let width = size.width - margin * 2
        var y: CGFloat = 40

        guard let entry else {
            drawPlain("♪", font: font(64, .heavy), color: ink3, at: CGPoint(x: margin, y: size.height / 2 - 40),
                      width: width)
            return
        }

        // 曲名 (差し色の短い印を頭に)。
        context.setFillColor(accent.cgColor)
        context.fill(CGRect(x: margin, y: y + 6, width: 6, height: 28))
        y += drawPlain(entry.song.title, font: font(30, .bold), color: ink2,
                       at: CGPoint(x: margin + 20, y: y), width: width - 20)
        y += 28

        let lines = entry.lyrics.lines
        if let index = frame.lineIndex {
            let line = lines[index]
            let split = lyricOverlaySplit(text: line.text)
            let mainText = split.main.isEmpty ? line.text : split.main
            let parts = entry.cast.marks(line, scheme: scheme, mapRange: mainText == line.text ? nil : { start, end in
                lyricMainRange(text: line.text, start: UInt32(start), end: UInt32(end)).map { (Int($0.start), Int($0.end)) }
            })
            let attributed = ImasRubyText.attributed(mainText, font: font(72, .heavy), color: ink, lineSpacing: 4,
                                                     parts: parts)
            y += drawRuby(attributed, at: CGPoint(x: margin, y: y), width: width, maxHeight: 250, in: context)
            y += 10
            // 歌う人: 写真を設定している人はアイコンを並べ、その右に名前 (写真の無い人は名前だけ)。
            let photos = line.allSingers.compactMap { id -> (Idol, UIImage)? in
                guard let idol = entry.cast.artists.first(where: { $0.id == id }),
                      let photo = avatarPhoto(idolId: id) else { return nil }
                return (idol, photo)
            }
            let groups = entry.cast.groups(line).filter { !$0.isEmpty }
            if !photos.isEmpty || !groups.isEmpty {
                let iconSize: CGFloat = photos.isEmpty ? 38 : 60
                var x = margin
                let shown = photos.prefix(photos.count > avatarMax ? avatarMax - 1 : avatarMax)
                for (idol, photo) in shown {
                    drawAvatar(idol, photo: photo, at: CGPoint(x: x, y: y), size: iconSize, scheme: scheme,
                               traits: traits, in: context)
                    x += iconSize + 8
                }
                if photos.count > shown.count {
                    drawPlain("+\(photos.count - shown.count)", font: font(26, .bold), color: ink2,
                              at: CGPoint(x: x, y: y + (iconSize - 32) / 2), width: 60)
                    x += 60
                }
                if !groups.isEmpty {
                    if x > margin { x += 6 }
                    drawPlain(groups.map { $0.joined(separator: "・") }.joined(separator: " → "),
                              font: font(30, .bold), color: ink2,
                              at: CGPoint(x: x, y: y + (iconSize - 38) / 2), width: margin + width - x)
                }
                y += iconSize + 8
            }
        } else {
            // イントロ・間奏。
            y += drawPlain("♪", font: font(62, .heavy), color: ink3, at: CGPoint(x: margin, y: y), width: width)
            y += 10
        }
        if let call = frame.call {
            drawPlain("» " + call, font: font(34, .heavy), color: accent, at: CGPoint(x: margin, y: y), width: width)
        }

        if let next = frame.nextIndex {
            let text = lyricOverlaySplit(text: lines[next].text).main
            let attributed = ImasRubyText.attributed(text.isEmpty ? lines[next].text : text,
                                                     font: font(40, .bold), color: ink3)
            // 1 行だけ (振り仮名の分の高さも取る。足りないと CoreText は行ごと描かない)。
            let height = min(rubyHeight(attributed, width: width), 92)
            drawRuby(attributed, at: CGPoint(x: margin, y: size.height - 32 - height), width: width,
                     maxHeight: height, in: context)
        }
    }

    private static func rubyHeight(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        let view = ImasRubyLabel.RubyTextView(frame: .zero)
        view.attributed = attributed
        return view.fittingHeight(width: width)
    }

    /// 歌う人のアイコンを並べる上限 (超えたら最後の 1 つを「+N」にする)。
    private static let avatarMax = 6

    /// 設定した写真のアイコン (丸に切り抜き、担当色の輪)。写真の無い人は描かない (名前の文字だけにする)。
    private static func drawAvatar(_ idol: Idol, photo: UIImage, at point: CGPoint, size: CGFloat,
                                   scheme: ColorScheme, traits: UITraitCollection, in context: CGContext) {
        let accent = UIColor(ImasTheme.derive(seed: idol.color, scheme: scheme).accent).resolvedColor(with: traits)
        let rect = CGRect(origin: point, size: CGSize(width: size, height: size))
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        // 丸に合わせて切り抜く (はみ出す方を切る)。
        let scale = max(size / photo.size.width, size / photo.size.height)
        let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        photo.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height))
        context.restoreGState()
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
    }

    /// 設定した写真の小さな版 (描くたびに元の写真を読み直さない)。
    private static var avatarPhotos: [String: UIImage] = [:]

    private static func avatarPhoto(idolId: String) -> UIImage? {
        guard let url = CustomImageService.shared.imageURL(for: idolId) else { return nil }
        if let hit = avatarPhotos[url.path] { return hit }
        guard let original = UIImage(contentsOfFile: url.path), original.size.width > 0, original.size.height > 0
        else { return nil }
        let scale = 160 / min(original.size.width, original.size.height)
        guard let image = original.preparingThumbnail(of: CGSize(width: original.size.width * scale,
                                                                 height: original.size.height * scale))
        else { return nil }
        avatarPhotos[url.path] = image
        return image
    }

    /// 1 行で切って描く。描いた高さを返す。
    @discardableResult
    private static func drawPlain(_ text: String, font: UIFont, color: UIColor, at point: CGPoint,
                                  width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        let height = ceil(font.lineHeight)
        attributed.draw(with: CGRect(x: point.x, y: point.y, width: width, height: height),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return height
    }

    /// 歌詞の行を、歌詞プレイヤーと同じ組み方 (振り仮名・歌う人の色の塗り分け) で描く。描いた高さを返す。
    @discardableResult
    private static func drawRuby(_ attributed: NSAttributedString, at point: CGPoint, width: CGFloat,
                                 maxHeight: CGFloat, in context: CGContext) -> CGFloat {
        let height = min(rubyHeight(attributed, width: width), maxHeight)
        let view = ImasRubyLabel.RubyTextView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        view.attributed = attributed
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.clip(to: view.bounds)
        view.draw(view.bounds)
        context.restoreGState()
        return height
    }

    /// 絵の中の字は固定の大きさ (端末の文字の大きさの設定では変えない。絵ごと PiP の窓に縮むので)。
    private static func font(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kTextSpacingType,
                UIFontDescriptor.FeatureKey.selector: kAltProportionalTextSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - PiP の窓から

extension LyricsPictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.setActive(true) }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.setActive(false) }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: any Error) {
        Logger.musickit.error("pip_start_failed: \(error.localizedDescription)")
        Task { @MainActor in self.setActive(false) }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

extension LyricsPictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in
            let player = MusicKitService.shared
            if playing { player.resume() } else { player.pause() }
            self.tick()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        let durationMs = snapshot.withLock { $0.durationMs }
        guard durationMs > 0 else { return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity) }
        return CMTimeRange(start: .zero, duration: CMTime(value: CMTimeValue(durationMs), timescale: 1000))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        !snapshot.withLock { $0.isPlaying }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        let deltaMs = Int(skipInterval.seconds * 1000)
        Task { @MainActor in
            let player = MusicKitService.shared
            let position = player.fullPlaybackPositionMs ?? 0
            let duration = player.fullPlaybackDurationMs ?? .max
            player.seekFull(toMs: min(max(0, position + deltaMs), duration))
            self.tick()
        }
        completionHandler()
    }
}

// MARK: - 絵を映像にする

/// 描いた絵を H.264 の映像の 1 コマずつにする (VideoToolbox)。全部キーフレームにして、
/// どの絵からでも層に流し始められるようにする。
private final class FrameEncoder: @unchecked Sendable {
    /// 映像にしたコマ (`CMSampleBuffer` は Sendable でないので箱に入れて主スレッドへ返す)。
    struct Output: @unchecked Sendable {
        let samples: [CMSampleBuffer]
    }

    private var session: VTCompressionSession?
    private let lock = NSLock()
    private var outputs: [CMSampleBuffer] = []
    private var failed = false

    init?(size: CGSize) {
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(size.width),
                                                height: Int32(size.height), codecType: kCMVideoCodecType_H264,
                                                encoderSpecification: nil, imageBufferAttributes: nil,
                                                compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                                compressionSessionOut: &created)
        guard status == noErr, let created else {
            Logger.musickit.error("pip_encoder_create_failed: \(status)")
            return nil
        }
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 1 as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_Quality, value: 0.85 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(created)
        session = created
    }

    func encode(_ pixelBuffer: CVPixelBuffer, ms: Int) {
        guard let session else { return }
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: CMTime(value: CMTimeValue(ms), timescale: 1000), duration: .invalid,
            frameProperties: [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary,
            infoFlagsOut: nil
        ) { [self] status, _, sample in
            lock.lock()
            defer { lock.unlock() }
            if status == noErr, let sample { outputs.append(sample) } else { failed = true }
        }
        if status != noErr {
            Logger.musickit.error("pip_encode_failed: \(status)")
            lock.lock()
            failed = true
            lock.unlock()
        }
    }

    /// 残りを映像にし終えて返す。1 コマでも失敗していれば nil。
    func finish() -> Output? {
        guard let session else { return nil }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
        lock.lock()
        defer { lock.unlock() }
        guard !failed else { return nil }
        return Output(samples: outputs.sorted {
            CMSampleBufferGetPresentationTimeStamp($0) < CMSampleBufferGetPresentationTimeStamp($1)
        })
    }

    func cancel() {
        guard let session else { return }
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }
}

// MARK: - 層を抱える画面の部品

/// PiP の元になる層を抱える。PiP は画面に載っている層からしか始められないので、
/// 根の画面の裏 (常に在る) と、歌詞プレイヤーのジャケの裏 (浮かぶときにそこから縮む) に置く。
struct LyricsPiPSource: UIViewRepresentable {
    func makeUIView(context: Context) -> LyricsPiPHostView { LyricsPiPHostView() }
    func updateUIView(_ view: LyricsPiPHostView, context: Context) {}
}

final class LyricsPiPHostView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: LyricsPiPHostView, _) in
            LyricsPictureInPicture.shared.hostLaidOut(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        LyricsPictureInPicture.shared.hostChanged(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        LyricsPictureInPicture.shared.hostLaidOut(self)
    }
}
