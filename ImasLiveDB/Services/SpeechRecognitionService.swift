import Foundation
import Speech
import AVFoundation
import Observation

@Observable @MainActor
final class SpeechRecognitionService {

    private(set) var isListening: Bool = false
    private(set) var recognizedText: String = ""
    private(set) var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // コールバック: 一致した choice を渡す
    var onMatch: ((String) -> Void)?

    // MARK: - Authorization

    func requestAuthorization() async {
        // SFSpeechRecognizer.requestAuthorization の completion は non-MainActor
        // で発火する。 Swift 6 strict concurrency 下で @MainActor 隔離プロパティを
        // 直接触ると _dispatch_assert_queue_fail で SIGTRAP になるため、
        // Task { @MainActor } で明示的にメインアクターに hop してから代入する。
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authStatus = status
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Start / Stop

    func startListening(choices: [String]) {
        guard !isListening else { return }
        guard authStatus == .authorized else { return }
        guard recognizer?.isAvailable == true else { return }

        // MusicKit プレビュー再生中は停止（AudioSession カテゴリ競合を防ぐ）
        MusicKitService.shared.stop()

        do {
            try startSession(choices: choices)
        } catch {
            isListening = false
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        // AudioSession を解放してカテゴリを戻す
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func startSession(choices: [String]) throws {
        recognizedText = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        self.request = req

        let inputNode = audioEngine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        // sampleRate が 0 の場合はハードウェアが未準備 → 起動失敗として扱う
        guard fmt.sampleRate > 0 else {
            try? audioSession.setActive(false)
            throw SpeechError.audioFormatUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            try? audioSession.setActive(false)
            throw error
        }
        isListening = true

        let validChoices = choices.filter { !$0.isEmpty }
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                let spoken = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.recognizedText = spoken
                    if let match = self.findMatch(spoken: spoken, choices: validChoices) {
                        self.stopListening()
                        self.onMatch?(match)
                    }
                }
            }
            if error != nil || (result?.isFinal == true) {
                Task { @MainActor [weak self] in
                    self?.stopListening()
                }
            }
        }
    }

    private enum SpeechError: LocalizedError {
        case audioFormatUnavailable
        var errorDescription: String? {
            switch self {
            case .audioFormatUnavailable: return "音声入力フォーマットを取得できませんでした"
            }
        }
    }

    // MARK: - Matching

    func findMatch(spoken: String, choices: [String]) -> String? {
        let nSpoken = Self.normalize(spoken)
        guard !nSpoken.isEmpty else { return nil }
        if let exact = choices.first(where: { Self.normalize($0) == nSpoken }) { return exact }
        return choices.first { Self.normalize($0).contains(nSpoken) || nSpoken.contains(Self.normalize($0)) }
    }

    private static func normalize(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
        t = t.applyingTransform(.hiraganaToKatakana, reverse: false) ?? t
        return t
    }
}
