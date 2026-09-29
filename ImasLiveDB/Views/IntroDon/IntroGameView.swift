import SwiftUI

/// イントロドンのプレイ画面。本家 IntroQuiz の IntroRoundBody レイアウトに準拠:
/// ステータス(EQ) → 中央の大きな「!」ボタン → ヒント → 操作列 → 回答エリア。
/// 見た目は他のクイズと同じ「ステージ」(QuizStage.swift): 暗い会場・セトリのペンライト・生成りの判定カード。
struct IntroGameView: View {
    @Bindable var session: IntroGameSession
    /// 結果画面の「ホームに戻る」を Setup へ伝えるシグナル (この画面は中継するだけ)。
    let exitSignal: IntroDonExitSignal
    @State private var showExitAlert = false
    /// 結果画面 (fullScreenCover) を出しているか。
    ///
    /// **実体のある `@State` にすること。** `session.phase` から導出した computed binding は
    /// setter が no-op になり、閉じたつもりで閉じず結果のあとが空白画面になる。
    @State private var showResult = false
    @State private var autoNextTask: Task<Void, Never>? = nil
    @State private var speechService = SpeechRecognitionService()
    @State private var showSpeechDenied = false
    @State private var didHoldPlay = false   // 再生ボタン: 長押し(=もう少し流す)とタップ(=頭出し)の判別
    @State private var rushFlash = false      // Rush: ○/✕ エフェクトの表示中フラグ
    @State private var rushFlashCorrect = true
    @State private var rushFlashTask: Task<Void, Never>? = nil
    /// 経過秒ラベルの 0 リセット用 token (次の問題 / もう一度で bump)。
    @State private var playbackResetToken = 0
    @Environment(\.dismiss) private var dismiss

    private var isRush: Bool { session.settings.mode == .rush }
    /// 高速形式 (押すまで流す・選択肢常時・即次へ)。Rush と 全曲チャレンジ。
    private var isFast: Bool { session.settings.mode == .rush || session.settings.mode == .allSongs }

    /// 音声判定 UI を出すか。音声モードでは常に音声 UI (選択肢は出さない)。
    /// 未許可は voiceStatusCard で許可導線を出す。Rush は音声を使わず常に 4択。
    private var useVoice: Bool {
        session.settings.answerMode == .voice && !isFast
    }

    var body: some View {
        ZStack {
            QS.bg.ignoresSafeArea()

            switch session.phase {
            case .loading:
                loadingOverlay
            case .playing, .answering, .revealed:
                gameContent
            case .idle:
                // 通常はここに来る前に showResult / exitSignal 経由でこの画面ごとpopされる想定だが、
                // 何らかの理由で reset() 後もこの画面が残ってしまった場合の保険。
                // 空白のまま留まらせず、自動でこの階層を閉じる。
                Color.clear.onAppear { dismiss() }
            case .finished:
                // showResult 側の navigationDestination が処理するため、ここでは何も描かない
                // (finished 中に一瞬 gameContent が消えて空白になるのを避けるため Color.clear)。
                Color.clear
            }

            if rushFlash {
                Image(systemName: rushFlashCorrect ? "circle" : "xmark")
                    .font(.imasScaled(96, weight: .heavy))
                    .foregroundColor(rushFlashCorrect ? ID.correct : ID.incorrect)
                    .shadow(color: (rushFlashCorrect ? ID.correct : ID.incorrect).opacity(0.5), radius: 16)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                QuizStageRoundButton(systemImage: "xmark", label: "ゲームを終了") {
                    AppAnalytics.tap("intro_game.exit")
                    showExitAlert = true
                }
            }
            ToolbarItem(placement: .principal) { headerTitle }
            ToolbarItem(placement: .topBarTrailing) { QuizStageScore(points: session.score) }
        }
        .toolbarBackground(QS.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
        // **結果は push しない。** push すると Game が隠れ、SwiftUI が Game の
        // `onChange` を走らせなくなる (body は再評価されるのに onChange だけ来ない)。
        // 結果画面のボタンがどれも無反応になり「アプリを落とすしかない」と
        // App Store のレビューで複数報告された。cover なら Game が presenter の
        // まま生きているので、自分の dismiss() がそのまま効く。
        .fullScreenCover(isPresented: $showResult) {
            IntroGameResultView(
                session: session,
                // 積み上げ済みの設定画面まで戻す (設定を変えて遊び直せる)。
                onReplay: {
                    showResult = false
                    dismiss()
                },
                onHome: {
                    showResult = false
                    // Setup は自分が見えるようになってから onChange を受け取れる。
                    exitSignal.requestExitToHome()
                    dismiss()
                }
            )
        }
        // 音声判定は「自動起動しない」(本家準拠)。再生中に録音セッションへ切替えると
        // AVAudioSession 競合でクラッシュするため、voice 起動は buzz/マイクタップ時のみ。
        // ここでは回答フェーズを抜けたら聴取を止めるだけ。
        .onChange(of: session.phase) { _, newPhase in
            if newPhase != .answering, speechService.isListening {
                speechService.stopListening()
            }
            // finished 以外へ移ったら必ず倒す。true のまま残すと、次に この画面へ戻った
            // ときに結果画面がもう一度出てしまう (「結果画面が二重に出る」の原因)。
            showResult = (newPhase == .finished)
        }
        // 次の問題に進む (currentIndex 変化) や「もう一度」 (replay) のたびに
        // PlaybackElapsedLabel を 0 に戻すための token bump。
        .onChange(of: session.currentIndex) { _, _ in playbackResetToken &+= 1 }
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
        VStack(spacing: DS.sp5) {
            ProgressView()
                .tint(QS.ink)
                .scaleEffect(1.2)
            Text("問題を生成中...")
                .font(QS.text(14, weight: .bold))
                .foregroundColor(QS.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Game Content

    private var gameContent: some View {
        VStack(spacing: 0) {
            progressArea
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            if session.phase == .revealed {
                revealedBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
            } else {
                roundBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Round Body (本家 IntroRoundBody 準拠)

    private var roundBody: some View {
        GeometryReader { geo in
            let buzzSize = min(geo.size.height * 0.2, 148)
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // 再生まわりは 1 枚のパネル (INTRO) にまとめる。
                VStack(spacing: 0) {
                    HStack {
                        Text("INTRO").font(QS.mono(11)).tracking(1.4).foregroundStyle(QS.dim)
                        Spacer()
                        elapsedLabel
                    }
                    .padding(.bottom, 6)

                    statusArea
                        .frame(height: 56)

                    // 通常モードは中央の大きな「!」ボタンで早押し → 回答。
                    // 高速形式(Rush/全曲)は押すまで流し選択肢を常時出すのでボタンは出さない。
                    if !isFast {
                        buzzButton(size: buzzSize)
                            .frame(height: buzzSize)
                        buzzHint
                            .frame(height: 16)
                            .padding(.top, 10)
                    }

                    controlsRow
                        .padding(.top, 16)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 14)
                .background(QS.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

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
    private var showAnswer: Bool { isFast || session.phase == .answering }

    // MARK: - Header / Progress

    /// ナビゲーションバー中央。通常は「イントロドン / Q.04 / 10」、ラッシュは残り時間、
    /// 全曲チャレンジは経過タイム (タイムを競う)。
    @ViewBuilder
    private var headerTitle: some View {
        if isRush {
            let urgent = session.rushRemaining <= 10
            let secs = Int(session.rushRemaining.rounded(.up))
            VStack(spacing: 1) {
                Text("ラッシュ").font(QS.text(11, weight: .bold)).tracking(0.8).foregroundStyle(QS.dim)
                Text(String(format: "%d:%02d", secs / 60, secs % 60))
                    .font(QS.num(24))
                    .foregroundStyle(urgent ? QS.stamp : QS.ink)
                    .animation(.easeInOut(duration: 0.2), value: urgent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("ラッシュ 残り\(secs)秒")
        } else if session.isAllSongsChallenge {
            VStack(spacing: 1) {
                Text("全曲チャレンジ · \(session.currentIndex + 1) / \(session.totalCount)")
                    .font(QS.text(11, weight: .bold)).foregroundStyle(QS.dim)
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let secs = Int(session.elapsedSoFar)
                    Text(String(format: "%d:%02d", secs / 60, secs % 60))
                        .font(QS.num(24)).foregroundStyle(QS.ink)
                }
            }
        } else {
            QuizStageTitle(title: "イントロドン", current: min(session.currentIndex + 1, session.totalCount),
                           total: session.totalCount)
        }
    }

    /// 通常モードはセトリのペンライト (正解した曲が灯る)。ラッシュは残り時間、
    /// 全曲チャレンジは進み具合を細い帯で出す (本数が多すぎてペンライトに並ばない)。
    @ViewBuilder
    private var progressArea: some View {
        if !isFast && session.totalCount <= 20 {
            let results: [Color?] = session.records.enumerated().map { i, r in r.correct ? QS.penlight(i) : nil }
            QuizStageProgress(
                slots: QuizPenlight.slots(results: results, total: session.totalCount,
                                          answering: session.phase != .revealed),
                caption: "セトリ \(session.records.count) / \(session.totalCount) 曲目まで点灯",
                streak: session.combo)
        } else {
            VStack(spacing: 10) {
                IDProgressBar(progress: barProgress, color: barColor, bgColor: QS.raised, height: 6)
                HStack {
                    Text("\(session.records.count) 曲目まで · \(session.score) 曲正解")
                    Spacer()
                    if session.combo >= 2 {
                        Label("\(session.combo) 連続正解中", systemImage: "arrowtriangle.up.fill")
                            .labelStyle(QuizTightLabelStyle())
                            .fontWeight(.bold)
                            .foregroundStyle(QS.ink)
                    }
                }
                .font(QS.text(12))
                .foregroundStyle(QS.dim)
            }
        }
    }

    /// 帯の進み具合 (ラッシュは残り時間、全曲チャレンジは出題済みの割合)。
    private var barProgress: Double {
        if isRush {
            let limit = session.settings.rushTimeLimit
            return limit > 0 ? session.rushRemaining / limit : 0
        }
        return session.totalCount > 0 ? Double(session.currentIndex) / Double(session.totalCount) : 0
    }

    private var barColor: Color {
        isRush && session.rushRemaining <= 10 ? QS.stamp : QS.ink
    }

    // MARK: - Status Area

    /// 経過秒ラベルを見せる phase (再生・回答・正解前の停止中)。
    private var showsElapsed: Bool {
        switch session.phase {
        case .playing, .answering: return true
        default: return false
        }
    }

    /// 経過秒ラベル。statusArea や Buzz ボタンと縦に分離して被らない位置に常設。
    /// phase 分岐の外に常設し opacity で見せ隠し (取り外すと @State がリセットされる)。
    @ViewBuilder
    private var elapsedLabel: some View {
        PlaybackElapsedLabel(
            isRunning: session.isPlayingIntro,
            resetToken: playbackResetToken
        )
        .opacity(showsElapsed ? 1 : 0)
        .frame(height: 18)
    }

    @ViewBuilder
    private var statusArea: some View {
        switch session.phase {
        case .playing where isFast:
            VStack(spacing: 8) {
                Image(systemName: session.isPlayingIntro ? "speaker.wave.2.fill" : "music.note")
                    .font(.imasScaled( 24, weight: .bold))
                    .foregroundColor(QS.ink)
                Text("曲名は？")
                    .font(QS.text(13, weight: .black))
                    .tracking(2)
                    .foregroundColor(QS.dim)
            }
        case .playing:
            IDEQAnimation(columns: 16, rows: 5, dotSize: 7, spacing: DS.sp1,
                          color: QS.ink, isAnimating: session.isPlayingIntro)
                .frame(height: 50)
        case .answering:
            Text(useVoice ? "曲名を声で答えてください" : "曲名を選んでください")
                .font(QS.text(15, weight: .bold))
                .foregroundColor(QS.ink)
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
            // 本家準拠: buzz したら (音声モードなら) ここで音声判定を起動する。
            if useVoice { beginVoiceListening() }
        } label: {
            Text("!")
                // 円の直径 (size) に対する比率で決まるグリフ。単独でスケールさせると
                // 固定直径の円からはみ出すため、ここは意図的に固定 pt のままにする。
                .font(.system(size: max(48, size * 0.45), weight: .black, design: .rounded))
                .foregroundColor(canBuzz ? QS.bg : QS.faint)
                .frame(width: size, height: size)
                .background(canBuzz ? QS.ink : QS.raised)
                .clipShape(Circle())
                .shadow(color: canBuzz ? QS.ink.opacity(0.25) : .clear, radius: 16, y: 6)
        }
        .idPress()
        .disabled(!canBuzz)
    }

    @ViewBuilder
    private var buzzHint: some View {
        if session.phase == .playing {
            Text("わかったらタップ")
                .font(QS.text(12, weight: .bold))
                .foregroundColor(QS.dim)
        } else {
            Color.clear
        }
    }

    // MARK: - Controls Row (頭出し / もう少し流す / スキップ)

    private var controlsRow: some View {
        HStack(spacing: 6) {
            controlTile(icon: "arrow.counterclockwise", label: "もう一度") {
                AppAnalytics.tap("intro_game.replay")
                stopSpeech()
                playbackResetToken &+= 1   // 経過秒を 0 に戻す
                Task { await session.replayIntro() }
            }

            // 長押しで「もう少し流す」、タップでも頭出し。
            VStack(spacing: 2) {
                Image(systemName: session.isPlayingIntro ? "waveform" : "play.fill")
                    .font(.imasScaled(15, weight: .bold))
                Text(session.isPlayingIntro ? "再生中" : "続きから")
                    .font(QS.text(12, weight: .bold))
            }
            .foregroundStyle(session.isPlayingIntro ? QS.bg : QS.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(session.isPlayingIntro ? QS.ink : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(QS.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
            .scaleEffect(didHoldPlay ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: didHoldPlay)
            .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 100) {
                // 長押し中 = もう少し流す (押してる間ずっと流す)。
                didHoldPlay = true
                AppAnalytics.tap("intro_game.play_more")
                stopSpeech()
                session.continueIntroHeld()
            } onPressingChanged: { pressing in
                if pressing {
                    didHoldPlay = false
                } else if didHoldPlay {
                    didHoldPlay = false
                    session.pauseHeldIntro()
                } else {
                    // タップ(短押し) = 「続きから」: 停止位置から introDuration 秒だけ再生。
                    // continueIntroHeld を呼ぶと停止タイマー無しでずっと流れ続けるため、
                    // 短押しは時間指定付きの continueIntroForDuration を使う。
                    stopSpeech()
                    session.continueIntroForDuration()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("タップで続きを流す。長押しの間は流し続けます")

            controlTile(icon: "forward.end.fill", label: "次の曲") {
                AppAnalytics.tap("intro_game.skip")
                stopSpeech()
                session.skipQuestion()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func controlTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.imasScaled(15, weight: .bold))
                Text(label)
                    .font(QS.text(12, weight: .bold))
            }
            .foregroundStyle(QS.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(QS.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(QuizPressStyle())
    }

    // MARK: - Answer Area

    @ViewBuilder
    private var answerArea: some View {
        if useVoice {
            voiceAnswerArea
        } else if let q = session.currentQuestion {
            VStack(spacing: 8) {
                ForEach(Array(q.choices.enumerated()), id: \.element) { i, title in
                    IntroChoiceRow(letter: ["A", "B", "C", "D", "E", "F"][i % 6], title: title) {
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
        VStack(spacing: DS.sp4) {
            voiceStatusCard
            micButton
        }
    }

    private var voiceStatusCard: some View {
        VStack(spacing: DS.sp3) {
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
                HStack(spacing: DS.sp3) {
                    PulseDot(color: ID.accentPink)
                    Text(speechService.recognizedText.isEmpty
                        ? "聴取中… 曲名を声で答えてください"
                        : "「\(speechService.recognizedText)」")
                        .font(ID.font(14, weight: .bold))
                        .foregroundColor(speechService.recognizedText.isEmpty ? ID.t2 : ID.t0)
                        .lineLimit(1)
                }
            } else {
                // 聴取していない時は前回の認識テキストを出さない (次の曲に残らないように)。
                Text("マイクをタップして回答")
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.t2)
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
            HStack(spacing: DS.sp3) {
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
        let isLast = !isRush && session.currentIndex + 1 >= session.totalCount
        return VStack(spacing: 12) {
            Spacer(minLength: 0)

            if let q = session.currentQuestion {
                // 正解 / 不正解 (スキップも不正解扱い) の大きなカード。1 曲 1 点なので点の内訳は出さない。
                QuizVerdictCard(verdict: QuizVerdict(
                    isCorrect: session.isCorrect == true,
                    number: session.currentIndex + 1,
                    answerName: q.title,
                    answerHex: nil,
                    earned: session.isCorrect == true ? 1 : 0, base: 1, hints: 0,
                    pickedName: session.isCorrect == true ? nil : (session.selectedTitle ?? "スキップ"),
                    detail: nil,
                    artworkURL: q.artworkUrl.flatMap { URL(string: $0) },
                    showsPoints: false))
                .id(session.currentIndex)
            }

            QuizStageNextButton(isLastQuestion: isLast, onNext: goNext, onFinish: goNext)

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

    private func goNext() {
        AppAnalytics.tap("intro_game.next")
        autoNextTask?.cancel()
        Task { await session.nextQuestion() }
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

    /// 本家 SoloCoordinator.buzz と同じ順序: SwiftUI に1フレーム描かせてから
    /// 再生を完全停止 (stop+deactivate) → voice 起動。すべて1つの Task で順次実行する。
    private func beginVoiceListening() {
        guard let q = session.currentQuestion, !speechService.isListening else { return }
        let title = q.title
        speechService.onMatch = { [weak session] match in
            session?.submitAnswer(match)
        }
        Task { @MainActor in
            await Task.yield()                       // 1フレーム描画させる (本家)
            session.releasePlaybackForRecording()    // 再生を完全停止+セッション解放 (本家 musicPlayback.stop)
            guard session.phase == .answering, !speechService.isListening else { return }
            speechService.startListening(choices: [title])   // 本家 voice.start
        }
    }

    private func stopSpeech() {
        if speechService.isListening {
            speechService.stopListening()
        }
    }
}

// MARK: - IntroChoiceRow

/// 曲名の 4 択 1 行 (ステージの選択肢と同じ見た目。曲名は長いので 1 列)。
private struct IntroChoiceRow: View {
    let letter: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(letter).font(QS.mono(12)).foregroundStyle(QS.faint)
                Text(title)
                    .font(QS.text(16, weight: .bold))
                    .foregroundStyle(QS.ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(QS.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(QuizPressStyle())
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
