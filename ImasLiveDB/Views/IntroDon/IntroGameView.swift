import SwiftUI
import NukeUI

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

    /// 音声モードで実際に音声 UI を出すか。許可拒否/不可なら 4択にフォールバック。
    private var useVoice: Bool {
        session.settings.answerMode == .voice
            && speechService.authStatus != .denied
            && speechService.authStatus != .restricted
    }

    var body: some View {
        ZStack {
            // ダーク背景
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
                    .font(.system(size: 180, weight: .heavy))
                    .foregroundColor(rushFlashCorrect ? ID.correct : ID.incorrect)
                    .shadow(color: (rushFlashCorrect ? ID.correct : ID.incorrect).opacity(0.6), radius: 24)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: rushFlash)
        .onChange(of: session.rushFlashTick) { _, _ in
            rushFlashCorrect = session.rushFlashCorrect
            rushFlash = true
            rushFlashTask?.cancel()
            rushFlashTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                rushFlash = false
            }
        }
        .toolbar(.hidden, for: .tabBar)
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
        // 音声の起動 (認可リクエスト/録音セッション開始) を画面遷移の瞬間に撃つと
        // システム callback の遅延で actor 隔離違反 (SIGTRAP) や録音セッション競合で
        // クラッシュする。そのため音声判定は「マイクをタップして回答」の明示操作で開始し、
        // フェーズが回答以外へ移ったら聴取を確実に止めるだけにする。
        .onChange(of: session.phase) { _, newPhase in
            if newPhase != .answering, speechService.isListening {
                speechService.stopListening()
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
                .padding(.bottom, 16)

            // カードは可変高(残り領域を埋め・小型端末では縮む)。これで下の選択肢が
            // 画面外に押し出されない (旧: minHeight 230 + Spacer で溢れていた)。
            questionCard
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 「もう少し流す」再生コントロール (回答前のみ)
            if session.phase == .playing || session.phase == .answering {
                playControlBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            answerSection
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var answerSection: some View {
        switch session.phase {
        case .answering:
            if useVoice { voiceAnswerArea } else { choicesArea }
        case .revealed:
            revealedArea
        default:
            earlyAnswerArea
        }
    }

    // MARK: - Header / Progress (Rush 対応)

    private var headerBar: some View {
        HStack(spacing: 12) {
            if session.settings.mode == .rush {
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
        if session.settings.mode == .rush {
            let limit = session.settings.rushTimeLimit
            progress = limit > 0 ? session.rushRemaining / limit : 0
            color = session.rushRemaining <= 10 ? ID.incorrect : ID.accentPurple
        } else {
            progress = session.totalCount > 0
                ? Double(session.currentIndex) / Double(session.totalCount)
                : 0
            color = ID.accentPink
        }
        return IDProgressBar(
            progress: progress,
            color: color,
            bgColor: ID.surfaceDarkSubtle,
            height: 3
        )
    }

    // MARK: - Question Card

    private var questionCard: some View {
        ZStack {
            IDCorner()
                .fill(ID.surfaceDarkCard)
                .shadow(color: Color.black.opacity(0.35), radius: 16, y: 8)

            // Glow border when playing
            if session.phase == .playing && session.isPlayingIntro {
                IDCorner()
                    .stroke(
                        LinearGradient(
                            colors: [ID.accentPurple.opacity(0.8), ID.accentBlue.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }

            VStack(spacing: 20) {
                cardVisual
                cardLabel
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .animation(.easeInOut(duration: 0.3), value: session.phase)
    }

    @ViewBuilder
    private var cardVisual: some View {
        switch session.phase {
        case .playing, .answering:
            VStack(spacing: 10) {
                IDEQAnimation(
                    columns: 16,
                    rows: 5,
                    dotSize: 9,
                    spacing: 3,
                    color: ID.t0,
                    isAnimating: session.isPlayingIntro
                )
                .frame(height: 65)

                if session.isPlayingIntro {
                    HStack(spacing: 6) {
                        PulseDot(color: ID.accentPurple)
                        Text("再生中")
                            .font(ID.font(12, weight: .bold))
                            .foregroundColor(ID.t2)
                        PulseDot(color: ID.accentBlue)
                    }
                }
            }

        case .revealed:
            if let q = session.currentQuestion,
               let artworkUrl = q.artworkUrl,
               let url = URL(string: artworkUrl) {
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

        default:
            ZStack {
                IDCorner(radius: 40)
                    .fill(
                        LinearGradient(
                            colors: [ID.accentPurple.opacity(0.25), ID.accentBlue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Text("?")
                    .font(.imasScaled( 50, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ID.accentPurple, ID.accentBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }

    private func musicNoteIcon(size: CGFloat) -> some View {
        ZStack {
            IDCorner(radius: 16)
                .fill(ID.surfaceDarkSubtle)
                .frame(width: size, height: size)
            Image(systemName: "music.note")
                .font(.imasScaled( size * 0.32))
                .foregroundColor(ID.t3)
        }
    }

    @ViewBuilder
    private var cardLabel: some View {
        switch session.phase {
        case .revealed:
            if let q = session.currentQuestion {
                VStack(spacing: 8) {
                    Text(q.title)
                        .font(ID.font(18, weight: .bold))
                        .foregroundColor(ID.t0)
                        .multilineTextAlignment(.center)

                    if let isCorrect = session.isCorrect {
                        resultBadge(isCorrect: isCorrect, skipped: session.selectedTitle == nil)
                    }
                }
            }

        case .answering:
            Text(useVoice ? "曲名を声で答えてください" : "曲名を選んでください")
                .font(ID.font(13, weight: .semibold))
                .foregroundColor(ID.t2)

        default:
            Text("イントロを聴いてください")
                .font(ID.font(13, weight: .semibold))
                .foregroundColor(ID.t2.opacity(0.8))
        }
    }

    private func resultBadge(isCorrect: Bool, skipped: Bool) -> some View {
        let label: String
        let tint: Color
        let icon: String
        if isCorrect {
            label = "正解！"
            tint  = ID.correct
            icon  = "checkmark.circle.fill"
        } else if skipped {
            label = "スキップ"
            tint  = ID.incorrect
            icon  = "xmark.circle.fill"
        } else {
            label = "不正解"
            tint  = ID.incorrect
            icon  = "xmark.circle.fill"
        }
        return Label(label, systemImage: icon)
            .font(ID.font(13, weight: .bold))
            .foregroundColor(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(tint.opacity(0.15))
            .clipShape(IDCorner(radius: 8))
    }

    // MARK: - もう少し流す (再生コントロール)

    /// タップで頭出し再生、長押しで「もう少し流す」(本家 playUntilStopped 相当)。
    private var playControlBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(session.isPlayingIntro ? ID.accentPurple : ID.surfaceDarkCard)
                    .frame(width: 52, height: 52)
                Image(systemName: session.isPlayingIntro ? "waveform" : "play.fill")
                    .font(.imasScaled( 20, weight: .bold))
                    .foregroundColor(session.isPlayingIntro ? ID.t0 : ID.accentPurple)
            }
            .contentShape(Circle())
            .scaleEffect(didHoldPlay ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: didHoldPlay)
            // 長押し(0.2s)で「もう少し流す」、短いタップで頭出し再生し直し。
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
                    AppAnalytics.tap("intro_game.replay")
                    stopSpeech()
                    Task { await session.replayIntro() }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.isPlayingIntro ? "再生中…" : "タップでもう一度")
                    .font(ID.font(13, weight: .bold))
                    .foregroundColor(ID.t1)
                Text("長押しでもう少し流す")
                    .font(ID.font(11, weight: .semibold))
                    .foregroundColor(ID.t3)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Early Answer (再生中の早押し)

    @ViewBuilder
    private var earlyAnswerArea: some View {
        if useVoice {
            // 音声モードでは再生中はマイクを使えない(録音と再生のカテゴリ競合)。
            // 再生が終わると .answering に移って自動で聴取開始する。
            VStack(spacing: 8) {
                Text("イントロ終了後に声で回答できます")
                    .font(ID.font(12, weight: .semibold))
                    .foregroundColor(ID.t3)
                skipButton
            }
        } else {
            VStack(spacing: 8) {
                // Rush は押すまで流し続けるため .playing のまま。選択肢を常時出す。
                if (session.isPlayingIntro || session.settings.mode == .rush),
                   let q = session.currentQuestion {
                    Text(session.settings.mode == .rush ? "わかったらタップ！" : "早押し可能！")
                        .font(ID.font(11, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(ID.accentPurple.opacity(0.7))
                        .padding(.bottom, 2)

                    VStack(spacing: 6) {
                        ForEach(q.choices, id: \.self) { title in
                            IDChoiceButton(title: title) {
                                AppAnalytics.tap("intro_game.choose_answer")
                                session.submitAnswer(title)
                            }
                        }
                    }
                }

                Button {
                    AppAnalytics.tap("intro_game.skip")
                    stopSpeech()
                    session.skipQuestion()
                } label: {
                    Text("スキップ")
                        .font(ID.font(13, weight: .semibold))
                        .foregroundColor(ID.t3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Choices (4択 / answering phase)

    private var choicesArea: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let q = session.currentQuestion {
                    ForEach(q.choices, id: \.self) { title in
                        IDChoiceButton(title: title) {
                            AppAnalytics.tap("intro_game.choose_answer")
                            stopSpeech()
                            session.submitAnswer(title)
                        }
                    }
                }
            }

            Spacer().frame(height: 10)

            skipButton
        }
    }

    // MARK: - Voice (音声判定 / answering phase)

    private var voiceAnswerArea: some View {
        VStack(spacing: 12) {
            voiceStatusCard

            HStack(spacing: 12) {
                micButton
                skipButton
            }
        }
    }

    private var voiceStatusCard: some View {
        VStack(spacing: 8) {
            if speechService.authStatus == .notDetermined {
                Text("マイクの使用を許可してください")
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
                    ? "マイクボタンで聴取を開始"
                    : "「\(speechService.recognizedText)」")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.t2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(ID.accentPink.opacity(speechService.isListening ? 0.12 : 0.06))
        .clipShape(IDCorner(radius: 14))
    }

    private var micButton: some View {
        Button {
            AppAnalytics.tap("intro_game.mic_toggle")
            handleMicTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: speechService.isListening ? "mic.slash.fill" : "mic.fill")
                    .font(.imasScaled( 13, weight: .semibold))
                Text(speechService.isListening ? "停止" : "音声入力")
                    .font(ID.font(13, weight: .semibold))
            }
            .foregroundColor(speechService.isListening ? ID.incorrect : ID.t2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(speechService.isListening ? ID.incorrect.opacity(0.12) : ID.surfaceDarkCard)
            .clipShape(IDCorner(radius: 10))
        }
        .idPress()
    }

    private var skipButton: some View {
        Button {
            AppAnalytics.tap("intro_game.skip")
            stopSpeech()
            session.skipQuestion()
        } label: {
            Text("スキップ")
                .font(ID.font(13, weight: .semibold))
                .foregroundColor(ID.t3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(ID.surfaceDarkSubtle)
                .clipShape(IDCorner(radius: 10))
        }
        .idPress()
    }

    // MARK: - Revealed

    private var revealedArea: some View {
        VStack(spacing: 10) {
            if let q = session.currentQuestion {
                IDAnswerReveal(
                    title: q.title,
                    choices: q.choices,
                    correctTitle: q.title,
                    selectedTitle: session.selectedTitle
                )
            }

            Spacer().frame(height: 4)

            Button {
                AppAnalytics.tap("intro_game.next")
                autoNextTask?.cancel()
                Task { await session.nextQuestion() }
            } label: {
                let isLast = session.settings.mode != .rush
                    && session.currentIndex + 1 >= session.totalCount
                HStack(spacing: 8) {
                    Text(isLast ? "結果を見る" : "次の問題へ")
                        .font(ID.font(16, weight: .bold))
                    Image(systemName: isLast ? "flag.checkered" : "arrow.right")
                        .font(.imasScaled( 14, weight: .semibold))
                }
                .foregroundColor(ID.menuCardDarkText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(ID.menuCardDark)
                .clipShape(IDCorner())
                .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
            }
            .idPress()
        }
        .onAppear {
            // Rush は次々回す。それ以外は読ませる余裕を持たせる。
            let delay: UInt64 = session.settings.mode == .rush ? 1_400_000_000 : 5_000_000_000
            autoNextTask?.cancel()
            autoNextTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await session.nextQuestion()
            }
        }
        .onDisappear {
            autoNextTask?.cancel()
        }
    }

    // MARK: - Speech Helpers

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
        // オープン判定になる)。4択モードでは選択肢全部を渡す。
        let targets = useVoice ? [q.title] : q.choices
        speechService.onMatch = { [weak session] match in
            session?.submitAnswer(match)
        }
        speechService.startListening(choices: targets)
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
            .padding(.vertical, 14)
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
