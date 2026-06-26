import SwiftUI
import NukeUI

struct IntroGameView: View {
    @Bindable var session: IntroGameSession
    @State private var showExitAlert = false
    @State private var autoNextTask: Task<Void, Never>? = nil
    @State private var speechService = SpeechRecognitionService()
    @State private var showSpeechDenied = false
    @Environment(\.dismiss) private var dismiss

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
        // 画面遷移の瞬間に Speech 認可リクエストを発射するとシステムの
        // callback が遅れて actor 隔離違反でクラッシュする再現があったため、
        // 認可は「音声入力」ボタンを押した時点で初めて要求する遅延発火に変更。
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

            IDProgressBar(
                progress: session.totalCount > 0
                    ? Double(session.currentIndex) / Double(session.totalCount)
                    : 0,
                color: ID.accentPink,
                bgColor: ID.surfaceDarkSubtle,
                height: 3
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            questionCard
                .padding(.horizontal, 16)

            Spacer(minLength: 12)

            switch session.phase {
            case .answering:
                choicesArea
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            case .revealed:
                revealedArea
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            default:
                earlyAnswerArea
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("\(session.currentIndex + 1) / \(session.totalCount)")
                .font(ID.font(13, weight: .bold))
                .monospacedDigit()
                .foregroundColor(ID.t2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ID.surfaceDarkCard)
                .clipShape(IDCorner(radius: 8))

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
        .frame(maxWidth: .infinity)
        .frame(minHeight: 230)
        .animation(.easeInOut(duration: 0.3), value: session.phase)
    }

    @ViewBuilder
    private var cardVisual: some View {
        switch session.phase {
        case .playing:
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
            Text("曲名を選んでください")
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

    // MARK: - Early Answer (再生中の早押し)

    private var earlyAnswerArea: some View {
        VStack(spacing: 8) {
            if session.isPlayingIntro, let q = session.currentQuestion {
                Text("早押し可能！")
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

            // スキップボタン
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

    // MARK: - Choices (answering phase)

    private var choicesArea: some View {
        VStack(spacing: 0) {
            // 音声入力ステータス
            if speechService.isListening || !speechService.recognizedText.isEmpty {
                speechStatusRow
                    .padding(.bottom, 8)
            }

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

            HStack(spacing: 12) {
                micButton
                skipButton
            }
        }
    }

    private var speechStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.imasScaled( 12))
                .foregroundColor(ID.accentPink)
            if speechService.recognizedText.isEmpty {
                Text("聴取中...")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.t2)
            } else {
                Text("「\(speechService.recognizedText)」")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.t1)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ID.accentPink.opacity(0.08))
        .clipShape(IDCorner(radius: 8))
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
                .padding(.vertical, 10)
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
                let isLast = session.currentIndex + 1 >= session.totalCount
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
            autoNextTask?.cancel()
            autoNextTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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
        // 未判定のときはここで認可をリクエスト (画面遷移時の eager request を避けるため)
        if speechService.authStatus == .notDetermined {
            Task {
                await speechService.requestAuthorization()
                if speechService.authStatus == .authorized {
                    beginSpeechListening()
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
        beginSpeechListening()
    }

    private func beginSpeechListening() {
        guard let q = session.currentQuestion else { return }
        speechService.onMatch = { [weak session] match in
            session?.submitAnswer(match)
        }
        speechService.startListening(choices: q.choices)
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
