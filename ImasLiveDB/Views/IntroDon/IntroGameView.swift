import SwiftUI
import NukeUI

/// イントロドンのプレイ画面。本家 IntroQuiz の IntroRoundBody レイアウトに準拠:
/// ステータス(EQ) → 中央の大きな「!」ボタン → ヒント → 操作列 → 回答エリア。
struct IntroGameView: View {
    @Bindable var session: IntroGameSession
    @State private var showExitAlert = false
    @State private var autoNextTask: Task<Void, Never>? = nil
    @State private var speechService = SpeechRecognitionService()
    @State private var showSpeechDenied = false
    @State private var didHoldPlay = false   // 再生ボタン: 長押し(=もう少し流す)とタップ(=頭出し)の判別
    @State private var rushFlash = false      // Rush: ○/✕ エフェクトの表示中フラグ
    @State private var rushFlashCorrect = true
    @State private var rushFlashTask: Task<Void, Never>? = nil
    @Environment(\.dismiss) private var dismiss

    private var isRush: Bool { session.settings.mode == .rush }

    /// 音声判定 UI を出すか。音声モードでは常に音声 UI (選択肢は出さない)。
    /// 未許可は voiceStatusCard で許可導線を出す。Rush は音声を使わず常に 4択。
    private var useVoice: Bool {
        session.settings.answerMode == .voice && !isRush
    }

    var body: some View {
        ZStack {
            ID.bgDark.ignoresSafeArea()

            switch session.phase {
            case .loading:
                loadingOverlay
            case .playing, .answering, .revealed:
                gameContent
            default:
                EmptyView()
            }

            if rushFlash {
                Image(systemName: rushFlashCorrect ? "circle" : "xmark")
                    .font(.system(size: 96, weight: .heavy))
                    .foregroundColor(rushFlashCorrect ? ID.correct : ID.incorrect)
                    .shadow(color: (rushFlashCorrect ? ID.correct : ID.incorrect).opacity(0.5), radius: 16)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    AppAnalytics.tap("intro_game.exit")
                    showExitAlert = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.imasScaled( 16, weight: .semibold))
                        .foregroundColor(ID.t2)
                        .frame(width: 36, height: 36)
                        .background(ID.surfaceDarkCard)
                        .clipShape(Circle())
                }
                .idPress()
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .alert("ゲームを終了しますか？", isPresented: $showExitAlert) {
            Button("終了", role: .destructive) {
                stopSpeech()
                session.stopPlayback()
                session.reset()
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("音声認識を許可してください", isPresented: $showSpeechDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("設定アプリから「マイク」と「音声認識」の権限を許可してください。")
        }
        .navigationDestination(isPresented: Binding(
            get: { session.phase == .finished },
            set: { _ in }
        )) {
            IntroGameResultView(session: session)
        }
        // 音声判定: 回答フェーズに入ったら自動で聴取開始 (本家の堅牢ロジックを移植した
        // SpeechRecognitionService が format 事前検証/リトライ/世代管理でクラッシュを防ぐ)。
        // 認可は遷移の瞬間ではなくゲーム開始時 (.task) に先行要求しておく。
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .answering {
                autoStartVoiceIfNeeded()
            } else if speechService.isListening {
                speechService.stopListening()
            }
        }
        .task {
            // 音声モードは開始時にマイク+音声認識をまとめて要求しておく
            // (音声のみ許可済み・マイク未要求の取りこぼしを防ぐ)。
            if session.settings.answerMode == .voice, speechService.authStatus != .authorized {
                await speechService.requestAuthorization()
            }
        }
        .onChange(of: session.rushFlashTick) { _, _ in
            rushFlashCorrect = session.rushFlashCorrect
            // アニメは flash 自身に限定 (ZStack 全体に乗せると出題切替までヌルッと
            // 動いて "重い" 原因になる)。
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { rushFlash = true }
            rushFlashTask?.cancel()
            rushFlashTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.easeOut(duration: 0.2)) { rushFlash = false }
            }
        }
        .onDisappear {
            stopSpeech()
            session.stopPlayback()
        }
        .trackScreen("intro_game")
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(ID.t2)
                .scaleEffect(1.2)
            Text("問題を生成中...")
                .font(ID.font(14, weight: .semibold))
                .foregroundColor(ID.t2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Game Content

    private var gameContent: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)

            progressBar
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            if session.phase == .revealed {
                revealedBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
            } else {
                roundBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Round Body (本家 IntroRoundBody 準拠)

    private var roundBody: some View {
        GeometryReader { geo in
            let buzzSize = min(geo.size.height * 0.24, 168)
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                statusArea
                    .frame(height: 60)

                // 通常モードは中央の大きな「!」ボタンで早押し → 回答。
                // Rush は押すまで流し続け、選択肢を常時出すのでボタンは出さない。
                if !isRush {
                    buzzButton(size: buzzSize)
                        .frame(height: buzzSize)
                    buzzHint
                        .frame(height: 16)
                        .padding(.top, 8)
                }

                controlsRow
                    .frame(height: 46)
                    .padding(.top, 16)

                answerArea
                    .padding(.top, 14)
                    .opacity(showAnswer ? 1 : 0)
                    .allowsHitTesting(showAnswer)

                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// 回答エリアを出すか。Rush は常時、通常は回答フェーズのみ。
    private var showAnswer: Bool { isRush || session.phase == .answering }

    // MARK: - Header / Progress

    private var headerBar: some View {
        HStack(spacing: 12) {
            if isRush {
                rushTimePill
            } else {
                Text("\(session.currentIndex + 1) / \(session.totalCount)")
                    .font(ID.font(13, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(ID.t2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ID.surfaceDarkCard)
                    .clipShape(IDCorner(radius: 8))
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(ID.correct)
                    .font(.imasScaled( 12))
                Text("\(session.score)")
                    .font(ID.font(15, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(ID.t0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(ID.correct.opacity(0.12))
            .clipShape(IDCorner(radius: 8))
        }
    }

    private var rushTimePill: some View {
        let urgent = session.rushRemaining <= 10
        let secs = Int(session.rushRemaining.rounded(.up))
        return HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.imasScaled( 12, weight: .bold))
            Text(String(format: "%d:%02d", secs / 60, secs % 60))
                .font(ID.font(15, weight: .black))
                .monospacedDigit()
        }
        .foregroundColor(urgent ? ID.incorrect : ID.t0)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((urgent ? ID.incorrect : ID.accentPurple).opacity(0.14))
        .clipShape(IDCorner(radius: 8))
        .animation(.easeInOut(duration: 0.2), value: urgent)
    }

    private var progressBar: some View {
        let progress: Double
        let color: Color
        if isRush {
            let limit = session.settings.rushTimeLimit
            progress = limit > 0 ? session.rushRemaining / limit : 0
            color = session.rushRemaining <= 10 ? ID.incorrect : ID.accentPurple
        } else {
            progress = session.totalCount > 0
                ? Double(session.currentIndex) / Double(session.totalCount)
                : 0
            color = ID.accentPink
        }
        return IDProgressBar(progress: progress, color: color, bgColor: ID.surfaceDarkSubtle, height: 3)
    }

    // MARK: - Status Area

    @ViewBuilder
    private var statusArea: some View {
        switch session.phase {
        case .playing where isRush:
            VStack(spacing: 8) {
                Image(systemName: session.isPlayingIntro ? "speaker.wave.2.fill" : "music.note")
                    .font(.imasScaled( 24, weight: .bold))
                    .foregroundColor(ID.t0)
                Text("曲名は？")
                    .font(ID.font(13, weight: .black))
                    .tracking(2)
                    .foregroundColor(ID.t2)
            }
        case .playing:
            IDEQAnimation(columns: 16, rows: 5, dotSize: 7, spacing: 2,
                          color: ID.t0, isAnimating: session.isPlayingIntro)
                .frame(height: 50)
        case .answering:
            Text(useVoice ? "曲名を声で答えてください" : "曲名を選んでください")
                .font(ID.font(14, weight: .bold))
                .foregroundColor(ID.t2)
        default:
            EmptyView()
        }
    }

    // MARK: - Buzz Button

    private func buzzButton(size: CGFloat) -> some View {
        let canBuzz = session.phase == .playing
        return Button {
            AppAnalytics.tap("intro_game.buzz")
            session.buzzToAnswer()
        } label: {
            Text("!")
                .font(.system(size: max(48, size * 0.45), weight: .black, design: .rounded))
                .foregroundColor(canBuzz ? ID.bgDark : ID.t3)
                .frame(width: size, height: size)
                .background(canBuzz ? ID.t0 : ID.surfaceDarkCard)
                .clipShape(Circle())
                .shadow(color: canBuzz ? ID.t0.opacity(0.25) : .clear, radius: 16, y: 6)
        }
        .idPress()
        .disabled(!canBuzz)
    }

    @ViewBuilder
    private var buzzHint: some View {
        if session.phase == .playing {
            Text("わかったらタップ")
                .font(ID.font(12, weight: .semibold))
                .foregroundColor(ID.t2)
        } else {
            Color.clear
        }
    }

    // MARK: - Controls Row (頭出し / もう少し流す / スキップ)

    private var controlsRow: some View {
        HStack(spacing: 28) {
            controlButton(icon: "arrow.counterclockwise", label: "頭出し") {
                AppAnalytics.tap("intro_game.replay")
                stopSpeech()
                Task { await session.replayIntro() }
            }

            // 長押しで「もう少し流す」、タップでも頭出し。
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(session.isPlayingIntro ? ID.accentPurple : ID.surfaceDarkCard)
                        .frame(width: 46, height: 46)
                    Image(systemName: session.isPlayingIntro ? "waveform" : "play.fill")
                        .font(.imasScaled( 17, weight: .bold))
                        .foregroundColor(session.isPlayingIntro ? ID.t0 : ID.accentPurple)
                }
                .scaleEffect(didHoldPlay ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: didHoldPlay)
                .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 100) {
                    didHoldPlay = true
                    AppAnalytics.tap("intro_game.play_more")
                    stopSpeech()
                    session.continueIntro()
                } onPressingChanged: { pressing in
                    if pressing {
                        didHoldPlay = false
                    } else if didHoldPlay {
                        didHoldPlay = false
                        session.pauseHeldIntro()
                    } else {
                        stopSpeech()
                        Task { await session.replayIntro() }
                    }
                }
                Text("もう少し流す")
                    .font(ID.font(10, weight: .semibold))
                    .foregroundColor(ID.t3)
            }

            controlButton(icon: "forward.end.fill", label: "スキップ") {
                AppAnalytics.tap("intro_game.skip")
                stopSpeech()
                session.skipQuestion()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(ID.surfaceDarkCard).frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.imasScaled( 16, weight: .bold))
                        .foregroundColor(ID.t1)
                }
                Text(label)
                    .font(ID.font(10, weight: .semibold))
                    .foregroundColor(ID.t3)
            }
        }
        .idPress()
    }

    // MARK: - Answer Area

    @ViewBuilder
    private var answerArea: some View {
        if useVoice {
            voiceAnswerArea
        } else if let q = session.currentQuestion {
            VStack(spacing: 8) {
                ForEach(q.choices, id: \.self) { title in
                    IDChoiceButton(title: title) {
                        AppAnalytics.tap("intro_game.choose_answer")
                        stopSpeech()
                        session.submitAnswer(title)
                    }
                }
            }
        }
    }

    // MARK: - Voice (音声判定)

    private var voiceAnswerArea: some View {
        VStack(spacing: 12) {
            voiceStatusCard
            micButton
        }
    }

    private var voiceStatusCard: some View {
        VStack(spacing: 8) {
            if speechService.authStatus == .denied || speechService.authStatus == .restricted {
                Text("設定アプリでマイクと音声認識を許可してください")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.incorrect)
                    .multilineTextAlignment(.center)
            } else if speechService.authStatus == .notDetermined {
                Text("マイクをタップして声で回答")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.t2)
            } else if speechService.isListening {
                HStack(spacing: 8) {
                    PulseDot(color: ID.accentPink)
                    Text(speechService.recognizedText.isEmpty
                        ? "聴取中… 曲名を声で答えてください"
                        : "「\(speechService.recognizedText)」")
                        .font(ID.font(14, weight: .bold))
                        .foregroundColor(speechService.recognizedText.isEmpty ? ID.t2 : ID.t0)
                        .lineLimit(1)
                }
            } else {
                Text(speechService.recognizedText.isEmpty
                    ? "マイクをタップして回答"
                    : "「\(speechService.recognizedText)」")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.t2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(ID.accentPink.opacity(speechService.isListening ? 0.12 : 0.06))
        .clipShape(IDCorner(radius: 14))
    }

    private var micButton: some View {
        Button {
            AppAnalytics.tap("intro_game.mic_toggle")
            handleMicTap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: speechService.isListening ? "mic.slash.fill" : "mic.fill")
                    .font(.imasScaled( 15, weight: .bold))
                Text(speechService.isListening ? "聴取を停止" : "マイクで回答")
                    .font(ID.font(14, weight: .bold))
            }
            .foregroundColor(speechService.isListening ? ID.incorrect : ID.t0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(speechService.isListening ? ID.incorrect.opacity(0.12) : ID.accentPink.opacity(0.18))
            .clipShape(IDCorner(radius: 12))
        }
        .idPress()
    }

    // MARK: - Revealed

    private var revealedBody: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            if let isCorrect = session.isCorrect {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(isCorrect ? ID.correct : ID.incorrect)
            }

            if let q = session.currentQuestion {
                artwork(for: q)

                Text(q.title)
                    .font(ID.font(20, weight: .black))
                    .foregroundColor(ID.t0)
                    .multilineTextAlignment(.center)

                IDAnswerReveal(
                    title: q.title,
                    choices: q.choices,
                    correctTitle: q.title,
                    selectedTitle: session.selectedTitle
                )
            }

            Button {
                AppAnalytics.tap("intro_game.next")
                autoNextTask?.cancel()
                Task { await session.nextQuestion() }
            } label: {
                let isLast = !isRush && session.currentIndex + 1 >= session.totalCount
                HStack(spacing: 8) {
                    Text(isLast ? "結果を見る" : "次の問題へ")
                        .font(ID.font(16, weight: .bold))
                    Image(systemName: isLast ? "flag.checkered" : "arrow.right")
                        .font(.imasScaled( 14, weight: .semibold))
                }
                .foregroundColor(ID.menuCardDarkText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(ID.menuCardDark)
                .clipShape(IDCorner())
            }
            .idPress()

            Spacer(minLength: 0)
        }
        .onAppear {
            let delay: UInt64 = isRush ? 1_400_000_000 : 5_000_000_000
            autoNextTask?.cancel()
            autoNextTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await session.nextQuestion()
            }
        }
        .onDisappear { autoNextTask?.cancel() }
    }

    @ViewBuilder
    private func artwork(for q: IntroGameQuestion) -> some View {
        if let artworkUrl = q.artworkUrl, let url = URL(string: artworkUrl) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 110, height: 110)
                        .clipShape(IDCorner(radius: 16))
                        .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
                } else {
                    musicNoteIcon(size: 110)
                }
            }
            .frame(width: 110, height: 110)
        } else {
            musicNoteIcon(size: 110)
        }
    }

    private func musicNoteIcon(size: CGFloat) -> some View {
        ZStack {
            IDCorner(radius: 16).fill(ID.surfaceDarkSubtle).frame(width: size, height: size)
            Image(systemName: "music.note")
                .font(.imasScaled( size * 0.32))
                .foregroundColor(ID.t3)
        }
    }

    // MARK: - Speech Helpers

    /// 回答フェーズで音声モードなら自動聴取を開始 (許可済みのみ自動。未判定は遅延要求)。
    private func autoStartVoiceIfNeeded() {
        guard useVoice, !isRush, !speechService.isListening else { return }
        switch speechService.authStatus {
        case .authorized:
            beginVoiceListening()
        case .notDetermined:
            Task {
                await speechService.requestAuthorization()
                if session.phase == .answering, speechService.authStatus == .authorized {
                    beginVoiceListening()
                }
            }
        default:
            break  // 拒否時は useVoice が false になり 4択にフォールバック
        }
    }

    private func handleMicTap() {
        if speechService.isListening {
            stopSpeech()
            return
        }
        if speechService.authStatus == .notDetermined {
            Task {
                await speechService.requestAuthorization()
                if speechService.authStatus == .authorized {
                    beginVoiceListening()
                } else {
                    showSpeechDenied = true
                }
            }
            return
        }
        guard speechService.authStatus == .authorized else {
            showSpeechDenied = true
            return
        }
        beginVoiceListening()
    }

    private func beginVoiceListening() {
        guard let q = session.currentQuestion, !speechService.isListening else { return }
        // 録音セッション開始前に再生を完全停止して .playback セッションを解放する
        // (.playback ↔ .record の競合でクラッシュするのを防ぐ)。
        session.stopPlayback()
        // 音声モードは「正解タイトル」を唯一の対象に照合 (findMatch は双方向 contains で
        // オープン判定になる)。
        speechService.onMatch = { [weak session] match in
            session?.submitAnswer(match)
        }
        speechService.startListening(choices: [q.title])
    }

    private func stopSpeech() {
        if speechService.isListening {
            speechService.stopListening()
        }
    }
}

// MARK: - IDChoiceButton

private struct IDChoiceButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.imasScaled( 13, weight: .semibold))
                    .foregroundColor(ID.accentPurple.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(ID.accentPurple.opacity(0.10))
                    .clipShape(IDCorner(radius: 6))

                Text(title)
                    .font(ID.font(14, weight: .semibold))
                    .foregroundColor(ID.t1)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.imasScaled(11).weight(.semibold))
                    .foregroundColor(ID.t3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(ID.surfaceDarkCard)
            .clipShape(IDCorner(radius: 14))
            .overlay(
                IDCorner(radius: 14)
                    .stroke(ID.accentPurple.opacity(0.12), lineWidth: 1)
            )
        }
        .idPress()
    }
}

// MARK: - PulseDot

private struct PulseDot: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 14, height: 14)
                .scaleEffect(animate ? 1.6 : 1.0)
                .opacity(animate ? 0 : 1)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}
