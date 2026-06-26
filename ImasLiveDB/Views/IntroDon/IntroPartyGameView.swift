import SwiftUI

/// パーティ対戦 (1台2人・分割画面)。上半分=2P(180°回転)、下半分=1P。
/// 早押し → 押した人が回答 (4択) → 正解で加点して次のラウンド。
struct IntroPartyGameView: View {
    @Bindable var session: IntroPartySession
    @Environment(AppDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    @State private var showExitAlert = false
    @State private var autoNextTask: Task<Void, Never>? = nil
    @State private var didHoldPlay = false

    var body: some View {
        ZStack {
            ID.bgDark.ignoresSafeArea()

            switch session.phase {
            case .loading:
                loadingOverlay
            case .finished:
                finishedOverlay
            default:
                splitLayout
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
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
                Color(white: 0.06)
                Text("相手が回答中…")
                    .font(ID.font(15, weight: .bold))
                    .foregroundColor(ID.t3)
                    .rotationEffect(.degrees(rotation))

            case .revealed:
                revealedColor(for: index)
                revealHalfContent(for: index).rotationEffect(.degrees(rotation))

            default:
                (buzzable ? color : Color(white: 0.08))
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
        .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))
    }

    private func buzzContent(player: IntroPartySession.Player, eliminated: Bool) -> some View {
        VStack(spacing: 8) {
            if eliminated {
                Image(systemName: "xmark.circle.fill")
                    .font(.imasScaled( 30, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Text("OUT")
                    .font(ID.font(16, weight: .black))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Text(player.name)
                    .font(.imasScaled( 40, weight: .black))
                    .foregroundColor(.white)
                Text("タップで早押し！")
                    .font(ID.font(14, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }

    private func answerChoices(for index: Int) -> some View {
        VStack(spacing: 10) {
            Text("\(session.players[index].name) 回答中")
                .font(ID.font(12, weight: .bold))
                .foregroundColor(ID.t2)
            if let q = session.currentQuestion {
                let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(q.choices, id: \.self) { title in
                        Button {
                            AppAnalytics.tap("intro_party.answer")
                            session.submitAnswer(player: index, title: title)
                        } label: {
                            Text(title)
                                .font(ID.font(13, weight: .bold))
                                .foregroundColor(ID.t0)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .padding(.horizontal, 6)
                                .background(ID.surfaceDarkCard)
                                .clipShape(IDCorner(radius: 12))
                        }
                        .idPress()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func revealedColor(for index: Int) -> Color {
        if session.lastCorrect, session.lastAnswerer == index {
            return ID.correct.opacity(0.22)
        }
        return Color(white: 0.07)
    }

    @ViewBuilder
    private func revealHalfContent(for index: Int) -> some View {
        if session.lastCorrect, session.lastAnswerer == index {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.imasScaled( 28, weight: .bold))
                    .foregroundColor(ID.correct)
                Text("正解！ +1")
                    .font(ID.font(16, weight: .black))
                    .foregroundColor(ID.correct)
            }
        } else if let q = session.currentQuestion {
            VStack(spacing: 4) {
                Text("正解")
                    .font(ID.font(11, weight: .bold))
                    .foregroundColor(ID.t3)
                Text(q.title)
                    .font(ID.font(15, weight: .bold))
                    .foregroundColor(ID.t1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Center Strip

    private var centerStrip: some View {
        ZStack {
            ID.surfaceDarkCard

            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    scoreChip(0)
                    Text(session.roundText)
                        .font(ID.font(12, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(ID.t3)
                    scoreChip(1)
                }

                switch session.phase {
                case .revealed:
                    Button {
                        autoNextTask?.cancel()
                        Task { await session.nextRound() }
                    } label: {
                        let isLast = session.currentIndex + 1 >= session.totalRounds
                        Text(isLast ? "結果を見る" : "次のラウンドへ")
                            .font(ID.font(14, weight: .bold))
                            .foregroundColor(ID.menuCardDarkText)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(ID.menuCardDark)
                            .clipShape(IDCorner(radius: 10))
                    }
                    .idPress()

                case .buzzed:
                    Text("早押し成立！回答してください")
                        .font(ID.font(12, weight: .semibold))
                        .foregroundColor(ID.accentPurple)

                default:
                    HStack(spacing: 14) {
                        playButton
                        giveUpButton
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))
    }

    private func scoreChip(_ index: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hexString: session.players[index].colorHex))
                .frame(width: 10, height: 10)
            Text(session.players[index].name)
                .font(ID.font(12, weight: .bold))
                .foregroundColor(ID.t2)
            Text("\(session.scores[index])")
                .font(ID.font(18, weight: .black))
                .monospacedDigit()
                .foregroundColor(ID.t0)
        }
    }

    private var playButton: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(session.isPlayingIntro ? ID.accentPurple : ID.surfaceDarkSubtle)
                    .frame(width: 40, height: 40)
                Image(systemName: session.isPlayingIntro ? "waveform" : "play.fill")
                    .font(.imasScaled( 15, weight: .bold))
                    .foregroundColor(session.isPlayingIntro ? ID.t0 : ID.accentPurple)
            }
            .contentShape(Circle())
            .scaleEffect(didHoldPlay ? 0.9 : 1.0)
            .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 100) {
                didHoldPlay = true
                session.continueIntro()
            } onPressingChanged: { pressing in
                if pressing {
                    didHoldPlay = false
                } else if didHoldPlay {
                    didHoldPlay = false
                    session.pauseHeldIntro()
                } else {
                    Task { await session.replayIntro() }
                }
            }
            Text("長押しでもう少し")
                .font(ID.font(10, weight: .semibold))
                .foregroundColor(ID.t3)
        }
    }

    private var giveUpButton: some View {
        Button {
            AppAnalytics.tap("intro_party.giveup")
            session.giveUp()
        } label: {
            Text("わからない")
                .font(ID.font(12, weight: .semibold))
                .foregroundColor(ID.t3)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(ID.surfaceDarkSubtle)
                .clipShape(IDCorner(radius: 10))
        }
        .idPress()
    }

    // MARK: - Loading / Finished

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView().tint(ID.t2).scaleEffect(1.2)
            Text("問題を生成中...")
                .font(ID.font(14, weight: .semibold))
                .foregroundColor(ID.t2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finishedOverlay: some View {
        VStack(spacing: 20) {
            if let w = session.winner {
                Text("\(session.players[w].name) の勝ち！")
                    .font(.imasScaled( 28, weight: .black))
                    .foregroundColor(Color(hexString: session.players[w].colorHex))
            } else {
                Text("引き分け")
                    .font(.imasScaled( 28, weight: .black))
                    .foregroundColor(ID.t0)
            }

            HStack(spacing: 24) {
                finalScore(0)
                Text("vs").font(ID.font(14, weight: .bold)).foregroundColor(ID.t3)
                finalScore(1)
            }

            VStack(spacing: 10) {
                Button {
                    Task { try? await session.generateQuestions(database: database) }
                } label: {
                    Text("もう一度")
                        .font(ID.font(16, weight: .bold))
                        .foregroundColor(ID.menuCardDarkText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(ID.menuCardDark)
                        .clipShape(IDCorner(radius: 14))
                }
                .idPress()

                Button {
                    session.reset()
                    dismiss()
                } label: {
                    Text("退出")
                        .font(ID.font(15, weight: .semibold))
                        .foregroundColor(ID.t2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(ID.surfaceDarkCard)
                        .clipShape(IDCorner(radius: 14))
                }
                .idPress()
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finalScore(_ index: Int) -> some View {
        VStack(spacing: 6) {
            Text(session.players[index].name)
                .font(ID.font(14, weight: .bold))
                .foregroundColor(Color(hexString: session.players[index].colorHex))
            Text("\(session.scores[index])")
                .font(.imasScaled( 44, weight: .black))
                .monospacedDigit()
                .foregroundColor(ID.t0)
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
