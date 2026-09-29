import Foundation
import Speech
import AVFoundation
import Observation

/// イントロドンの音声判定。/dev/intro (本家 IntroQuiz) の SpeechService を忠実移植:
/// - installTap 前の format 事前検証 + 0.3s リトライ (過渡状態の ObjC 例外クラッシュ回避)
/// - 認識世代トークンで stale コールバック破棄
/// - 割り込み / ルート変更 / mediaServicesReset を購読して engine を自動復帰
/// - 変種マッチング (正規化 / カタカナ / ローマ字 / 読み / Latin) + 逐次一致
/// - 録音は .playAndRecord(.measurement)、終了時 .playback へ復帰
/// - isFinal / エラーで自動再開、8 秒で打ち切り
///
/// 認識コールバックの MainActor hop だけは assumeIsolated が SIGTRAP する実績があったため
/// `Task { @MainActor }` にしている (Sendable な値だけ持ち込むので挙動は同じ)。
/// 非 Sendable な SFSpeechAudioBufferRecognitionRequest を @Sendable な tap クロージャへ
/// 持ち込むための箱。append はオーディオスレッドからのみ呼ばれ、request 自体はスレッドセーフ。
private final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ r: SFSpeechAudioBufferRecognitionRequest) { request = r }
}

@Observable @MainActor
final class SpeechRecognitionService {

    private(set) var isListening: Bool = false
    private(set) var recognizedText: String = ""
    private(set) var authStatus: SFSpeechRecognizerAuthorizationStatus = SpeechRecognitionService.combinedStatus()
    /// 一致したら正解タイトルを渡す。
    var onMatch: ((String) -> Void)?

    @ObservationIgnored private var accumulatedText: String = ""
    @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var matchTimer: Timer?
    @ObservationIgnored private var restartTask: DispatchWorkItem?
    @ObservationIgnored private var rebuildTask: DispatchWorkItem?
    @ObservationIgnored private var rebuildRetryCount = 0
    @ObservationIgnored private let rebuildRetryLimit = 5
    @ObservationIgnored private var generationId = 0
    // deinit (nonisolated) から removeObserver するため nonisolated(unsafe)。
    @ObservationIgnored nonisolated(unsafe) private var sessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var wasListeningBeforeInterruption = false
    @ObservationIgnored private var resolved = false

    @ObservationIgnored private var targetTitle = ""
    /// 照合に使う正解の綴り。選び方も照合もコア (`voice_answer_targets` / `voice_answer_matches`)。
    @ObservationIgnored private var targets: VoiceAnswerTargets?
    @ObservationIgnored private var timerStartDate: Date?

    @ObservationIgnored private let jaRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    @ObservationIgnored private let enRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    @ObservationIgnored private var normalizeCache: [String: String] = [:]
    @ObservationIgnored private var readingCache: [String: String] = [:]
    @ObservationIgnored private var latinCache: [String: String] = [:]

    private static let listenWindow: TimeInterval = 8.0

    init() {
        registerSessionObservers()
    }

    deinit {
        // engine/timer 等は stopListening / onDisappear で停止済み。observer は weak self なので
        // 残っても無害だが、念のため解除する (nonisolated deinit から触れるのは observer のみ)。
        let center = NotificationCenter.default
        for o in sessionObservers { center.removeObserver(o) }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        // 既に確定済みの権限は再要求しない。
        // コールバックは @Sendable (=非隔離) にする: @MainActor 隔離のまま渡すと
        // システムがバックグラウンドスレッドで呼んだ瞬間 executor アサーションで SIGTRAP する。
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { @Sendable _ in
                    Task { @MainActor in c.resume() }
                }
            }
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                AVAudioApplication.requestRecordPermission { @Sendable _ in
                    Task { @MainActor in c.resume() }
                }
            }
        }
        authStatus = Self.combinedStatus()
    }

    private func hasPermission() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    /// 音声認識 + マイクの現在状態を合成 (両方 granted→authorized / 片方 denied→denied / 他→notDetermined)。
    private static func combinedStatus() -> SFSpeechRecognizerAuthorizationStatus {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission
        if speech == .authorized && mic == .granted { return .authorized }
        if speech == .denied || speech == .restricted || mic == .denied { return .denied }
        return .notDetermined
    }

    // MARK: - Session observers (割り込み/ルート変更/mediaReset 復帰)

    private func registerSessionObservers() {
        let center = NotificationCenter.default
        let main = OperationQueue.main
        let interruption = center.addObserver(forName: AVAudioSession.interruptionNotification,
                                              object: AVAudioSession.sharedInstance(), queue: main) { [weak self] note in
            // note は非 Sendable なので primitive(UInt?) だけ取り出して main へ渡す。
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in self?.handleInterruption(typeRaw: typeRaw, optRaw: optRaw) }
        }
        let routeChange = center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                             object: AVAudioSession.sharedInstance(), queue: main) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.handleRouteChange(reasonRaw: reasonRaw) }
        }
        let mediaReset = center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: AVAudioSession.sharedInstance(), queue: main) { [weak self] _ in
            Task { @MainActor in self?.handleMediaServicesReset() }
        }
        sessionObservers = [interruption, routeChange, mediaReset]
    }

    private func handleInterruption(typeRaw: UInt?, optRaw: UInt?) {
        guard let raw = typeRaw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            wasListeningBeforeInterruption = isListening
            stopEngine()
        case .ended:
            guard wasListeningBeforeInterruption, !resolved else {
                wasListeningBeforeInterruption = false
                return
            }
            wasListeningBeforeInterruption = false
            let shouldResume: Bool
            if let optsRaw = optRaw {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optsRaw).contains(.shouldResume)
            } else {
                shouldResume = true
            }
            if shouldResume {
                reinstateTimerIfNeeded()
                beginRecognition(startTimer: false)
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard isListening,
              let raw = reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            guard !resolved else { return }
            scheduleRebuildDebounced()
        default:
            break
        }
    }

    private func handleMediaServicesReset() {
        let shouldRecover = isListening && !resolved
        stopEngine()
        if speechRecognizer === enRecognizer {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        } else {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        }
        if shouldRecover { scheduleRebuildDebounced() }
    }

    // MARK: - Start / Stop

    func startListening(choices: [String]) {
        stopEngine()
        invalidateTimer()
        resolved = false
        targetTitle = choices.first ?? ""
        recognizedText = ""
        accumulatedText = ""
        wasListeningBeforeInterruption = false
        timerStartDate = nil
        rebuildRetryCount = 0
        rebuildTask?.cancel(); rebuildTask = nil
        normalizeCache.removeAll(); readingCache.removeAll(); latinCache.removeAll()

        // 曲名の飾りを落とすのはコア、綴りの変換 (かな・ローマ字・読み・ラテン文字) は OS。
        let clean = voiceStripTitleDecorations(title: targetTitle)
        let n = normalize(clean)
        targets = voiceAnswerTargets(
            normalized: n, katakana: toKatakana(n), romaji: toRomaji(n),
            reading: normalize(japaneseReading(clean)), latin: toLatin(clean))

        let useEnglish = !containsJapanese(clean) && isLikelyEnglish(clean)
        speechRecognizer = useEnglish ? enRecognizer : jaRecognizer
        beginRecognition(startTimer: true)
    }

    func stopListening() {
        isListening = false
        wasListeningBeforeInterruption = false
        invalidateTimer()
        timerStartDate = nil
        accumulatedText = ""
        restartTask?.cancel(); restartTask = nil
        rebuildTask?.cancel(); rebuildTask = nil
        stopEngine()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
    }

    // MARK: - Recognition

    private func beginRecognition(startTimer: Bool) {
        guard hasPermission() else {
            isListening = false
            authStatus = Self.combinedStatus()
            stopEngine()
            return
        }
        let engine = AVAudioEngine()
        audioEngine = engine
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            isListening = false
            stopEngine()
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = req
        req.shouldReportPartialResults = true
        req.taskHint = .search
        req.addsPunctuation = false
        req.contextualStrings = [voiceStripTitleDecorations(title: targetTitle)]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isListening = false
            stopEngine()
            return
        }

        let inputNode = engine.inputNode
        // installTap 前に format 検証 (sr/ch==0 の過渡状態で installTap すると ObjC 例外で落ちる)。
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stopEngine()
            scheduleRetry(carrying: nil)
            return
        }
        // tap はオーディオスレッドで呼ばれる。@Sendable (非隔離) にしないと @MainActor 隔離と
        // 推論され、オーディオスレッド呼び出しで executor アサーション SIGTRAP する。
        // req は非 Sendable なので @unchecked Sendable の箱に入れて持ち込む。
        let reqBox = RequestBox(req)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            reqBox.request.append(buffer)
        }

        generationId &+= 1
        let generation = generationId
        // recognitionTask の resultHandler もバックグラウンドスレッド呼び出し → @Sendable に。
        recognitionTask = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, error in
            let spoken = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hadError = error != nil
            Task { @MainActor [weak self] in
                guard let self, generation == self.generationId else { return }
                self.handleRecognitionResult(spoken: spoken, isFinal: isFinal, hadError: hadError)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isListening = true
            if startTimer {
                timerStartDate = Date()
                matchTimer = Timer.scheduledTimer(withTimeInterval: Self.listenWindow, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if !self.resolved { self.stopListening() }
                    }
                }
            }
        } catch {
            stopEngine()
        }
    }

    private func handleRecognitionResult(spoken: String?, isFinal: Bool, hadError: Bool) {
        if let spoken {
            recognizedText = accumulatedText.isEmpty ? spoken : accumulatedText + spoken
            checkMatch(text: spoken)
            if isFinal {
                if !resolved { restartListening(carrying: spoken) }
                return
            }
        }
        if hadError, !resolved {
            restartListening(carrying: nil)
        }
    }

    private func restartListening(carrying text: String?) {
        guard isListening else { return }
        if let text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            accumulatedText += text
        }
        stopEngine()
        scheduleRetry(carrying: nil)
    }

    private func scheduleRetry(carrying text: String?) {
        guard isListening else { return }
        if let text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            accumulatedText += text
        }
        let saved = accumulatedText
        restartTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.resolved, self.isListening else { return }
                self.accumulatedText = saved
                self.beginRecognition(startTimer: false)
            }
        }
        restartTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    private func reinstateTimerIfNeeded() {
        guard !resolved, let start = timerStartDate else { return }
        let remaining = Self.listenWindow - Date().timeIntervalSince(start)
        if remaining <= 0 {
            stopListening()
        } else {
            invalidateTimer()
            matchTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if !self.resolved { self.stopListening() }
                }
            }
        }
    }

    private func scheduleRebuildDebounced() {
        guard rebuildRetryCount < rebuildRetryLimit else { return }
        rebuildTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.resolved, self.isListening else { return }
                self.rebuildRetryCount += 1
                self.stopEngine()
                self.scheduleRetry(carrying: nil)
            }
        }
        rebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func stopEngine() {
        generationId &+= 1
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioEngine = nil
    }

    private func invalidateTimer() {
        matchTimer?.invalidate()
        matchTimer = nil
    }

    // MARK: - Match checking

    /// 聞き取りが更新されるたびに 1 回。変換した聞き取りを詰めて、当たりかはコアに訊く。
    private func checkMatch(text: String) {
        guard !resolved, let targets else { return }
        let combinedRaw = accumulatedText.isEmpty ? nil : accumulatedText + text
        let heard = VoiceHeard(
            normalized: normalize(text),
            reading: voiceNeedsReading(text: text) ? readingNormalized(text) : nil,
            combined: combinedRaw.map(normalize),
            combinedReading: combinedRaw.flatMap { voiceNeedsReading(text: $0) ? readingNormalized($0) : nil },
            latin: latinCached(text),
            combinedLatin: combinedRaw.map(latinCached))
        if voiceAnswerMatches(targets: targets, heard: heard) { resolveCorrect(text) }
    }

    private func resolveCorrect(_ spoken: String) {
        guard isListening, !resolved else { return }
        resolved = true
        recognizedText = spoken
        let cb = onMatch
        let title = targetTitle
        stopListening()
        cb?(title)
    }

    // MARK: - String helpers

    private func latinCached(_ text: String) -> String {
        if let c = latinCache[text] { return c }
        let r = toLatin(text); latinCache[text] = r; return r
    }

    private func readingNormalized(_ text: String) -> String? {
        if let c = readingCache[text] { return c.isEmpty ? nil : c }
        let r = normalize(japaneseReading(text)); readingCache[text] = r; return r.isEmpty ? nil : r
    }

    private func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            let v = $0.value
            return (v >= 0x3040 && v <= 0x309F) || (v >= 0x30A0 && v <= 0x30FF) || (v >= 0x4E00 && v <= 0x9FFF)
        }
    }

    private func normalize(_ text: String) -> String {
        if let c = normalizeCache[text] { return c }
        let r = computeNormalize(text); normalizeCache[text] = r; return r
    }

    private func computeNormalize(_ text: String) -> String {
        let cleaned = text.lowercased().unicodeScalars.filter { scalar in
            let v = scalar.value
            return CharacterSet.alphanumerics.contains(scalar) ||
                   (v >= 0x3040 && v <= 0x309F) || (v >= 0x30A0 && v <= 0x30FF) ||
                   (v >= 0x4E00 && v <= 0x9FFF) || scalar == "\u{30FC}"
        }.map(String.init).joined()
        let m = NSMutableString(string: cleaned)
        CFStringTransform(m, nil, "Hiragana-Katakana" as CFString, false)
        return m as String
    }

    private func toKatakana(_ text: String) -> String {
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, "Latin-Katakana" as CFString, false)
        return m as String
    }

    private func toRomaji(_ text: String) -> String {
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, "Katakana-Latin" as CFString, false)
        CFStringTransform(m, nil, "Hiragana-Latin" as CFString, false)
        return (m as String).lowercased()
    }

    private func japaneseReading(_ text: String) -> String {
        let src = text as CFString
        let tokenizer = CFStringTokenizerCreate(nil, src, CFRangeMake(0, CFStringGetLength(src)),
                                                kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
        var result = ""
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                let m = NSMutableString(string: latin)
                CFStringTransform(m, nil, "Latin-Katakana" as CFString, false)
                result += m as String
            } else {
                let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                let start = text.index(text.startIndex, offsetBy: range.location)
                let end = text.index(start, offsetBy: range.length)
                result += String(text[start..<end])
            }
        }
        return result
    }

    private func toLatin(_ text: String) -> String {
        let m = NSMutableString(string: text)
        CFStringTransform(m, nil, "Any-Latin" as CFString, false)
        CFStringTransform(m, nil, "Latin-ASCII" as CFString, false)
        return (m as String).lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private func isLikelyEnglish(_ text: String) -> Bool {
        let ascii = text.unicodeScalars.filter { $0.isASCII && $0.value > 32 }.count
        let total = text.unicodeScalars.filter { $0.value > 32 }.count
        return total > 0 && Double(ascii) / Double(total) > 0.6
    }
}
