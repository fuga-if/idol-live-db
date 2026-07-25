import SwiftUI

struct IntroGameResultView: View {
    let session: IntroGameSession
    /// Setup/Game と共有する「ホームに戻る」「もう一度あそぶ」シグナル。
    /// このView自身はdismiss()を呼ばず、シグナルを立てるだけにする。実際のpopはSetup/Gameが
    /// それぞれ自分の(実体のある)dismiss()で行うことで、複数階層をまとめて確実に閉じられる。
    let exitSignal: IntroDonExitSignal

    /// 実際に回答した問題数 (スキップ含む)。正答率の母数。
    /// Rush は候補曲(最大300)を全部出せるわけがないので totalCount ではなく回答数で割る。
    private var answered: Int { session.records.count }

    private var percentage: Int {
        guard answered > 0 else { return 0 }
        return session.score * 100 / answered
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var modeLabel: String {
        if session.isAllSongsChallenge { return "全曲チャレンジ" }
        switch session.settings.mode {
        case .rush: return "ラッシュ \(Int(session.settings.rushTimeLimit))秒"
        case .party: return "パーティ対戦"
        case .allSongs, .normal: return "ノーマル"
        }
    }

    /// 結果カードを画像化してシェア (本家宣伝フッター付き)。
    private func shareResultImage() {
        // 全曲チャレンジは曲数が多すぎて内訳が無意味なのでサマリ+タイムのみ。
        let lines = session.isAllSongsChallenge
            ? []
            : session.records.map { IntroShareLine(title: $0.title, correct: $0.correct) }
        let card = IntroResultShareCard(
            modeLabel: modeLabel,
            score: session.score,
            total: answered,
            percentage: percentage,
            timeText: session.isAllSongsChallenge ? timeString(session.elapsedTime) : nil,
            bestCombo: session.bestCombo,
            lines: lines
        )
        let image = IntroShareImageRenderer.render(size: CGSize(width: 1080, height: 1350)) { card }
        IntroShareImageRenderer.share(image: image, text: shareText)
    }

    /// シェア用テキスト (本家アプリの宣伝も兼ねる)。
    private var shareText: String {
        let pct = percentage
        let base: String
        if session.isAllSongsChallenge {
            base = "🎵イントロドン 全曲チャレンジ \(timeString(session.elapsedTime))・正答率\(pct)% (\(session.score)/\(answered))"
        } else {
            switch session.settings.mode {
            case .rush:
                let secs = Int(session.settings.rushTimeLimit)
                base = "🎵イントロドン・ラッシュ \(secs)秒で \(session.score)問正解！(正答率\(pct)%)"
            case .party:
                base = "🎵イントロドン パーティ対戦であそんだよ！"
            case .allSongs, .normal:
                base = "🎵イントロドンで \(session.score)/\(answered) 正解！(正答率\(pct)%)"
            }
        }
        let combo = session.bestCombo >= 2 ? " 最大\(session.bestCombo)連続🔥" : ""
        return base + combo + "\n#イントロドン #アイマス"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                scoreHero
                    .padding(.horizontal, DS.sp6)
                    .padding(.top, DS.sp7)

                if session.isAllSongsChallenge && session.newBestTimeAchieved {
                    banner(icon: "stopwatch.fill", text: "ベストタイム更新！", tag: "NEW TIME")
                        .padding(.horizontal, DS.sp6)
                        .padding(.top, DS.sp4)
                } else if session.isNewBest {
                    bestBanner
                        .padding(.horizontal, DS.sp6)
                        .padding(.top, DS.sp4)
                }

                Spacer().frame(height: 28)

                IDSectionLabel(text: "全問の結果")
                    .padding(.horizontal, DS.sp6)
                Spacer().frame(height: 12)
                questionsLog
                    .padding(.horizontal, DS.sp6)

                Spacer().frame(height: 28)

                actionButtons
                    .padding(.horizontal, DS.sp6)

                Spacer().frame(height: 40)
            }
        }
        .background(ID.menuBg.ignoresSafeArea())
        .navigationTitle("結果")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .trackScreen("intro_game_result")
    }

    private var scoreHero: some View {
        VStack(spacing: DS.sp6) {
            // Score number
            VStack(spacing: DS.sp2) {
                HStack(alignment: .lastTextBaseline, spacing: DS.sp2) {
                    Text("\(session.score)")
                        .font(ID.font(64, weight: .black))
                        .foregroundColor(ID.menuText)
                    Text("/ \(answered)")
                        .font(ID.font(22, weight: .bold))
                        .foregroundColor(ID.menuTextSecondary)
                        .padding(.bottom, 6)
                }

                Text("正答率 \(percentage)%")
                    .font(ID.font(16, weight: .bold))
                    .foregroundColor(ID.menuTextSecondary)

                // 全曲チャレンジはタイムを競う。
                if session.isAllSongsChallenge {
                    Label(timeString(session.elapsedTime), systemImage: "stopwatch")
                        .font(ID.font(15, weight: .bold))
                        .foregroundColor(ID.menuText)
                        .monospacedDigit()
                        .padding(.top, DS.sp1)
                }
            }

            // Grade badge
            gradeBadge
        }
        .frame(maxWidth: .infinity)
        .padding(DS.sp8)
        .background(ID.menuCardSubtle)
        .clipShape(IDCorner())
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }

    private var gradeBadge: some View {
        let (label, color) = gradeInfo
        return Text(label)
            .font(ID.font(14, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, DS.sp6)
            .padding(.vertical, DS.sp3)
            .background(color.opacity(0.12))
            .clipShape(IDCorner(radius: 10))
    }

    private var gradeInfo: (String, Color) {
        switch percentage {
        case 100:   return ("パーフェクト! 🎵", ID.accentGold)
        case 80...: return ("すごい！",         ID.correct)
        case 60...: return ("なかなか！",        ID.accentBlue)
        case 40...: return ("もう少し！",        ID.warning)
        default:    return ("練習あるのみ！",    ID.incorrect)
        }
    }

    private var bestBanner: some View {
        banner(icon: "star.fill", text: "ベストスコア更新！", tag: "NEW BEST")
    }

    private func banner(icon: String, text: String, tag: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(ID.accentGold)
                .font(.imasScaled( 16))
            Text(text)
                .font(ID.font(14, weight: .bold))
                .foregroundColor(ID.menuText)
            Spacer()
            Text(tag)
                .font(ID.font(10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(ID.accentGold)
        }
        .padding(.horizontal, DS.sp6)
        .padding(.vertical, 14)
        .background(ID.accentGold.opacity(0.10))
        .clipShape(IDCorner(radius: 14))
        .overlay(
            IDCorner(radius: 14)
                .stroke(ID.accentGold.opacity(0.30), lineWidth: 1)
        )
    }

    private var questionsLog: some View {
        VStack(spacing: 0) {
            ForEach(Array(session.records.enumerated()), id: \.element.id) { index, record in
                recordRow(index: index, record: record)

                if index < session.records.count - 1 {
                    Rectangle()
                        .fill(ID.menuDivider)
                        .frame(height: 1)
                        .padding(.horizontal, DS.sp5)
                }
            }
        }
        .background(ID.menuCardSubtle)
        .clipShape(IDCorner(radius: 16))
    }

    private func recordRow(index: Int, record: IntroAnswerRecord) -> some View {
        HStack(spacing: DS.sp4) {
            Text("\(index + 1)")
                .font(ID.font(11, weight: .bold))
                .monospacedDigit()
                .foregroundColor(ID.menuTextSecondary)
                .frame(width: 22, alignment: .trailing)

            Image(systemName: record.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(record.correct ? ID.correct : ID.incorrect)
                .font(.imasScaled( 16))

            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(record.title)
                    .font(ID.font(13, weight: .semibold))
                    .foregroundColor(ID.menuText)
                    .lineLimit(1)

                if !record.correct {
                    Text(record.selectedTitle.map { "回答: \($0)" } ?? "スキップ")
                        .font(.imasScaled(11))
                        .minimumScaleFactor(0.8)
                        .foregroundColor(ID.menuTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, DS.sp5)
        .padding(.vertical, DS.sp4)
    }

    private var actionButtons: some View {
        VStack(spacing: DS.sp4) {
            Button {
                AppAnalytics.tap("intro_game_result.share")
                shareResultImage()
            } label: {
                HStack(spacing: DS.sp3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.imasScaled( 15, weight: .semibold))
                    Text("結果を画像でシェア")
                        .font(ID.font(16, weight: .bold))
                }
                .foregroundColor(ID.menuText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(ID.menuCardSubtle)
                .clipShape(IDCorner())
                .overlay(IDCorner().stroke(ID.menuDivider, lineWidth: 1))
            }
            .idPress()

            Button {
                AppAnalytics.tap("intro_game_result.replay")
                session.reset()
                // Setup画面(積み上げ済み)まで戻すだけ。IntroGameSetupView() を新規pushしていた
                // 従来実装は Home→Setup→Game→Result→Setup→Game→Result… とスタックが際限なく
                // 伸びるバグの原因だったため、既存のSetupを再利用する形に変更。
                exitSignal.requestReplay()
            } label: {
                HStack(spacing: DS.sp3) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.imasScaled( 15, weight: .semibold))
                    Text("もう一度あそぶ")
                        .font(ID.font(17, weight: .bold))
                }
                .foregroundColor(ID.menuCardDarkText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.sp5)
                .background(ID.menuCardDark)
                .clipShape(IDCorner())
                .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
            }
            .idPress()

            Button {
                AppAnalytics.tap("intro_game_result.go_home")
                session.reset()
                exitSignal.requestExitToHome()
            } label: {
                Text("ホームに戻る")
                    .font(ID.font(14, weight: .semibold))
                    .foregroundColor(ID.menuTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.sp4)
                    .background(ID.menuCardSubtle)
                    .clipShape(IDCorner(radius: 14))
            }
            .idPress()
        }
    }
}
