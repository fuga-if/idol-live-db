import SwiftUI

struct IntroGameResultView: View {
    let session: IntroGameSession
    @Environment(\.dismiss) private var dismiss

    private var percentage: Int {
        guard session.totalCount > 0 else { return 0 }
        return session.score * 100 / session.totalCount
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                scoreHero
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                if session.isNewBest {
                    bestBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                Spacer().frame(height: 28)

                IDSectionLabel(text: "全問の結果")
                    .padding(.horizontal, 20)
                Spacer().frame(height: 12)
                questionsLog
                    .padding(.horizontal, 20)

                Spacer().frame(height: 28)

                actionButtons
                    .padding(.horizontal, 20)

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
        VStack(spacing: 20) {
            // Score number
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(session.score)")
                        .font(ID.font(64, weight: .black))
                        .foregroundColor(ID.menuText)
                    Text("/ \(session.totalCount)")
                        .font(ID.font(22, weight: .bold))
                        .foregroundColor(ID.menuTextSecondary)
                        .padding(.bottom, 6)
                }

                Text("正答率 \(percentage)%")
                    .font(ID.font(16, weight: .bold))
                    .foregroundColor(ID.menuTextSecondary)
            }

            // Grade badge
            gradeBadge
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(ID.menuCardSubtle)
        .clipShape(IDCorner())
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }

    private var gradeBadge: some View {
        let (label, color) = gradeInfo
        return Text(label)
            .font(ID.font(14, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(color.opacity(0.12))
            .clipShape(IDCorner(radius: 10))
    }

    private var gradeInfo: (String, Color) {
        switch percentage {
        case 100:   return ("パーフェクト! 🎵", ID.accentGold)
        case 80...: return ("すごい！",         ID.correct)
        case 60...: return ("なかなか！",        ID.accentBlue)
        case 40...: return ("もう少し！",        Color.orange)
        default:    return ("練習あるのみ！",    ID.incorrect)
        }
    }

    private var bestBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .foregroundColor(ID.accentGold)
                .font(.imasScaled( 16))
            Text("ベストスコア更新！")
                .font(ID.font(14, weight: .bold))
                .foregroundColor(ID.menuText)
            Spacer()
            Text("NEW BEST")
                .font(ID.font(10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(ID.accentGold)
        }
        .padding(.horizontal, 20)
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
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(ID.menuCardSubtle)
        .clipShape(IDCorner(radius: 16))
    }

    private func recordRow(index: Int, record: IntroAnswerRecord) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(ID.font(11, weight: .bold))
                .monospacedDigit()
                .foregroundColor(ID.menuTextSecondary)
                .frame(width: 22, alignment: .trailing)

            Image(systemName: record.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(record.correct ? ID.correct : ID.incorrect)
                .font(.imasScaled( 16))

            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            NavigationLink {
                IntroGameSetupView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.imasScaled( 15, weight: .semibold))
                    Text("もう一度あそぶ")
                        .font(ID.font(17, weight: .bold))
                }
                .foregroundColor(ID.menuCardDarkText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(ID.menuCardDark)
                .clipShape(IDCorner())
                .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
            }
            .idPress()

            Button {
                AppAnalytics.tap("intro_game_result.go_home")
                session.reset()
                dismiss()
                dismiss()
            } label: {
                Text("ホームに戻る")
                    .font(ID.font(14, weight: .semibold))
                    .foregroundColor(ID.menuTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ID.menuCardSubtle)
                    .clipShape(IDCorner(radius: 14))
            }
            .idPress()
        }
    }
}
