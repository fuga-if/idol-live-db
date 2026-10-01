import SwiftUI

/// パーティ対戦 (1台2人・分割画面)。上半分=2P(180°回転)、下半分=1P。
/// 早押し → 押した人が回答 (4択) → 正解で加点して次のラウンド。
///
/// 見た目は他のクイズと同じ「ステージ」(QuizStage.swift): 暗い会場・生成りの判定・墨の操作。
struct IntroPartyGameView: View {
    @Bindable var session: IntroPartySession
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    @State private var showExitAlert = false
    @State private var autoNextTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            QS.bg.ignoresSafeArea()

            switch session.phase {
            case .loading:
                loadingOverlay
            case .finished:
                finishedOverlay
            default:
                splitLayout
            }
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                QuizStageRoundButton(systemImage: "xmark", label: "対戦を終了") {
                    showExitAlert = true
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("対戦を終了しますか？", isPresented: $showExitAlert) {
            Button("終了", role: .destructive) {
                session.stopPlayback()
                session.reset()
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .onChange(of: session.phase) { _, newValue in
            if newValue == .revealed { scheduleNext() }
        }
        .onDisappear {
            autoNextTask?.cancel()
            session.stopPlayback()
        }
        .trackScreen("intro_party_game")
    }

    // MARK: - Split Layout

    private var splitLayout: some View {
        VStack(spacing: 0) {
            playerHalf(1, rotation: 180)
                .frame(maxHeight: .infinity)
            centerStrip
                .frame(height: 132)
            playerHalf(0, rotation: 0)
                .frame(maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Player Half

    @ViewBuilder
    private func playerHalf(_ index: Int, rotation: Double) -> some View {
        let player = session.players[index]
        let color = Color(hexString: player.colorHex)
        let eliminated = session.eliminatedThisRound.contains(index)
        let buzzable = session.phase == .playing && !eliminated

        ZStack {
            switch session.phase {
            case .buzzed where session.buzzedPlayer == index:
                color.opacity(0.18)
                answerChoices(for: index).rotationEffect(.degrees(rotation))

            case .buzzed:
                QS.bg
                Text("相手が回答中…")
                    .font(QS.text(15, weight: .bold))
                    .foregroundStyle(QS.faint)
                    .rotationEffect(.degrees(rotation))

            case .revealed:
                revealedColor(for: index)
                revealHalfContent(for: index).rotationEffect(.degrees(rotation))

            default:
                (buzzable ? color : QS.raised)
                buzzContent(player: player, eliminated: eliminated).rotationEffect(.degrees(rotation))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if buzzable {
                        AppAnalytics.tap("intro_party.buzz")
                        session.buzz(player: index)
                    }
                }
        )
        .overlay(Rectangle().stroke(QS.bg.opacity(0.6), lineWidth: 1))
    }

    private func buzzContent(player: IntroPartySession.Player, eliminated: Bool) -> some View {
        VStack(spacing: DS.sp3) {
            if eliminated {
                Image(systemName: "xmark.circle.fill")
                    .font(.imasScaled(30, weight: .bold))
                    .foregroundStyle(QS.ink.opacity(0.35))
                Text("OUT").font(QS.text(16, weight: .black)).foregroundStyle(QS.ink.opacity(0.4))
            } else {
                Text(player.name).font(.imasScaled(40, weight: .black)).foregroundStyle(QS.ink)
                Text("タップで早押し！").font(QS.text(14, weight: .bold)).foregroundStyle(QS.ink.opacity(0.85))
            }
        }
    }

    private func answerChoices(for index: Int) -> some View {
        VStack(spacing: DS.sp3) {
            Text("\(session.players[index].name) 回答中").font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
            if let q = session.currentQuestion {
                QuizStageChoiceGrid(choices: q.choices.map { QuizStageChoice(id: $0, title: $0) }, columns: 2) { choice in
                    AppAnalytics.tap("intro_party.answer")
                    session.submitAnswer(player: index, title: choice.title)
                }
            }
        }
        .padding(.horizontal, DS.sp6)
    }

    private func revealedColor(for index: Int) -> Color {
        if session.lastCorrect, session.lastAnswerer == index {
            return DS.success.opacity(0.22)
        }
        return QS.raised
    }

    @ViewBuilder
    private func revealHalfContent(for index: Int) -> some View {
        if session.lastCorrect, session.lastAnswerer == index {
            VStack(spacing: DS.sp2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.imasScaled(28, weight: .bold)).foregroundStyle(DS.success)
                Text("正解！ +1").font(QS.text(16, weight: .black)).foregroundStyle(DS.success)
            }
        } else if let q = session.currentQuestion {
            VStack(spacing: DS.sp2) {
                Text("正解").font(QS.text(11, weight: .bold)).foregroundStyle(QS.faint)
                Text(q.title).font(QS.text(15, weight: .bold)).foregroundStyle(QS.ink)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .padding(.horizontal, DS.sp5)
        }
    }

    // MARK: - Center Strip

    private var centerStrip: some View {
        ZStack {
            QS.panel

            VStack(spacing: DS.sp3) {
                HStack(spacing: DS.sp5) {
                    ImasStageScoreChip(colorHex: session.players[0].colorHex, name: session.players[0].name,
                                      score: session.scores[0])
                    Text(session.roundText).font(QS.text(12, weight: .bold)).monospacedDigit().foregroundStyle(QS.faint)
                    ImasStageScoreChip(colorHex: session.players[1].colorHex, name: session.players[1].name,
                                      score: session.scores[1])
                }

                switch session.phase {
                case .revealed:
                    let isLast = session.currentIndex + 1 >= session.totalRounds
                    QuizStagePrimaryButton(title: isLast ? "結果を見る" : "次のラウンドへ", compact: true) {
                        autoNextTask?.cancel()
                        Task { await session.nextRound() }
                    }

                case .buzzed:
                    Text("早押し成立！回答してください").font(QS.text(12, weight: .semibold)).foregroundStyle(QS.ink)

                default:
                    HStack(spacing: DS.sp4) {
                        playButton
                        giveUpButton
                    }
                }
            }
            .padding(.horizontal, DS.sp4)
        }
        .overlay(Rectangle().stroke(QS.bg.opacity(0.6), lineWidth: 1))
    }

    private var playButton: some View {
        ImasStagePlaybackControl(
            isPlaying: session.isPlayingIntro,
            style: .circle,
            onTap: { Task { await session.replayIntro() } },
            onHoldBegin: { session.continueIntroHeld() },
            onHoldEnd: { session.pauseHeldIntro() }
        )
    }

    private var giveUpButton: some View {
        ImasButton(title: "わからない", role: .secondary, size: .small) {
            AppAnalytics.tap("intro_party.giveup")
            session.giveUp()
        }
    }

    // MARK: - Loading / Finished

    private var loadingOverlay: some View {
        VStack(spacing: DS.sp5) {
            ImasInlineLoading(tint: QS.dim)
            Text("問題を生成中...").font(QS.text(14, weight: .semibold)).foregroundStyle(QS.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finishedOverlay: some View {
        ImasStageVersusResult(
            winnerColorHex: session.winner.map { session.players[$0].colorHex },
            headline: session.winner.map { "\(session.players[$0].name) の勝ち！" } ?? "引き分け",
            players: (.init(name: session.players[0].name, colorHex: session.players[0].colorHex, score: session.scores[0]),
                     .init(name: session.players[1].name, colorHex: session.players[1].colorHex, score: session.scores[1]))
        ) {
            ImasButton(title: "もう一度", role: .primary, size: .large) {
                Task { try? await session.generateQuestions(database: database) }
            }
            ImasButton(title: "退出", role: .secondary, size: .large) {
                session.reset()
                dismiss()
            }
        }
    }

    // MARK: - Helpers

    private func scheduleNext() {
        autoNextTask?.cancel()
        autoNextTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await session.nextRound()
        }
    }
}
