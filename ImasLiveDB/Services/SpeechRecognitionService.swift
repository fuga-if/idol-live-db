import Foundation
import Speech
import AVFoundation
import Observation

/// イントロドンの音声判定。/dev/intro (本家 IntroQuiz) の SpeechService の安定パターンを移植:
/// - installTap 前に input format を事前検証 (sampleRate/channelCount==0 の過渡状態で
///   installTap すると Swift で捕捉不可の ObjC 例外が飛びクラッシュする → 0.3s 後にリトライ)。
/// - 認識セッション世代トークン: stop/再開のたびに +1。古いタスクの遅延コールバックを破棄。
/// - 認識コールバックは任意スレッドで来るので DispatchQueue.main + MainActor.assumeIsolated に集約。
/// - 録音は .playAndRecord(.measurement)、終了時に .playback へ戻す (カテゴリリークで
///   直後の効果音が小音量になるのを防ぐ)。
/// - isFinal / エラーで自動再開し、8 秒で打ち切り。
@Observable @MainActor
final class SpeechRecognitionService {

    private(set) var isListening: Bool = false
    private(set) var recognizedText: String = ""
    /// 音声認識 + マイクの総合許可状態 (UI のゲーティング用)。
    private(set) var authStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    /// 一致した choice を渡すコールバック。
    var onMatch: ((String) -> Void)?

    @ObservationIgnored private let jaRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var matchTimer: Timer?
    @ObservationIgnored private var restartTask: DispatchWorkItem?
    @ObservationIgnored private var generationId: Int = 0
    @ObservationIgnored private var choices: [String] = []
    @ObservationIgnored private var normChoices: [(orig: String, norm: String)] = []
    @ObservationIgnored private var accumulated: String = ""

    private static let listenWindow: TimeInterval = 8.0

    // MARK: - Authorization

    /// 音声認識 + マイクの両方を要求し、総合結果を authStatus に反映する。
    /// continuation 経由で受け、代入は await 後の MainActor 上で行う (コールバック
    /// スレッドから @MainActor プロパティを触る actor 隔離違反を避ける)。
    func requestAuthorization() async {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else {
            authStatus = speech   // notDetermined / denied / restricted をそのまま反映
            return
        }
        let mic = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        authStatus = mic ? .authorized : .denied
    }

    private func hasPermission() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    // MARK: - Start / Stop

    func startListening(choices: [String]) {
        stopEngine()
        invalidateTimer()
        self.choices = choices.filter { !$0.isEmpty }
        normChoices = self.choices.map { ($0, Self.normalize($0)) }
        recognizedText = ""
        accumulated = ""
        recognizer = jaRecognizer
        beginRecognition(startTimer: true)
    }

    func stopListening() {
        isListening = false
        invalidateTimer()
        accumulated = ""
        restartTask?.cancel()
        restartTask = nil
        stopEngine()
        // .playAndRecord のまま放置すると iOS が出力音量を絞り、直後の効果音/次のイントロが
        // 小音量になる。.playback に戻して category リークを防ぐ。
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
    }

    // MARK: - Recognition

    private func beginRecognition(startTimer: Bool) {
        guard hasPermission() else {
            isListening = false
            authStatus = .denied
            stopEngine()
            return
        }

        let engine = AVAudioEngine()
        audioEngine = engine
        guard let recognizer, recognizer.isAvailable else {
            isListening = false
            stopEngine()
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        request = req
        req.shouldReportPartialResults = true
        req.taskHint = .search
        req.addsPunctuation = false
        if let first = choices.first { req.contextualStrings = [first] }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isListening = false
            stopEngine()
            return
        }

        let input = engine.inputNode
        // installTap 前に format を事前検証。setActive 直後/ルート変更直後は sampleRate・
        // channelCount が 0 になることがあり、その format で installTap すると ObjC 例外
        // (Swift 捕捉不可) でクラッシュする。不正なら engine を解体し 0.3s 後に再試行。
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stopEngine()
            scheduleRetry()
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        generationId &+= 1
        let generation = generationId

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // 認識コールバックは任意スレッド。Sendable な値だけ取り出して main に集約する。
            let spoken = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hadError = error != nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.generationId else { return }
                    self.handleResult(spoken: spoken, isFinal: isFinal, hadError: hadError)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isListening = true
            if startTimer {
                matchTimer = Timer.scheduledTimer(withTimeInterval: Self.listenWindow, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopListening() }
                }
            }
        } catch {
            stopEngine()
        }
    }

    private func handleResult(spoken: String?, isFinal: Bool, hadError: Bool) {
        if let spoken {
            recognizedText = accumulated.isEmpty ? spoken : accumulated + spoken
            if let matched = matchedChoice(in: recognizedText) {
                stopListening()
                onMatch?(matched)
                return
            }
            if isFinal {
                restart(carrying: spoken)
                return
            }
        }
        if hadError {
            restart(carrying: nil)
        }
    }

    /// isFinal / エラーで認識が切れたら、聴取窓の間は自動で再開する。
    private func restart(carrying text: String?) {
        guard isListening else { return }
        stopEngine()
        if let text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            accumulated += text
        }
        scheduleRetry()
    }

    /// 0.3s 後に beginRecognition を再実行 (format 未確定/再開で共用)。
    private func scheduleRetry() {
        guard isListening else { return }
        let saved = accumulated
        restartTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isListening else { return }
                self.accumulated = saved
                self.beginRecognition(startTimer: false)
            }
        }
        restartTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    private func stopEngine() {
        generationId &+= 1
        matchTimer?.invalidate()   // 念のため (invalidateTimer 経由でも呼ばれる)
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    private func invalidateTimer() {
        matchTimer?.invalidate()
        matchTimer = nil
    }

    // MARK: - Matching

    /// 認識テキストに一致する choice を返す。正規化して双方向 contains で判定。
    private func matchedChoice(in spoken: String) -> String? {
        let n = Self.normalize(spoken)
        guard n.count >= 2 else { return nil }
        if let exact = normChoices.first(where: { $0.norm == n }) { return exact.orig }
        return normChoices.first {
            !$0.norm.isEmpty && ($0.norm.contains(n) || n.contains($0.norm))
        }?.orig
    }

    private static func normalize(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
        t = t.applyingTransform(.hiraganaToKatakana, reverse: false) ?? t
        return t
    }
}
