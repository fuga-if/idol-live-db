import SwiftUI

// =============================================================================
// 対戦の表示部品 (docs/DESIGN_SYSTEM.md §12)
//
// ImasStageScoreChip     多人数対戦中の軽量スコア表示 (色ドット + 名前 + 点数)。
// ImasStageVersusResult  1 対 1 対戦の最終結果画面。`QuizStageResultView` の対戦版。
// =============================================================================

/// 多人数対戦中の軽量スコア表示。
struct ImasStageScoreChip: View {
    let colorHex: String
    let name: String
    let score: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hexString: colorHex)).frame(width: 10, height: 10)
            Text(name).font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
            Text("\(score)").font(QS.text(18, weight: .black)).monospacedDigit().foregroundStyle(QS.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 1 対 1 対戦の最終結果 (勝者バナー + 2 人分のスコア + 操作)。
struct ImasStageVersusResult<Actions: View>: View {
    struct Player {
        let name: String
        let colorHex: String
        let score: Int
    }

    /// 勝者の色 (引き分けは nil)。
    let winnerColorHex: String?
    let headline: String
    let players: (Player, Player)
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 20) {
            Text(headline)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(winnerColorHex.map { Color(hexString: $0) } ?? QS.ink)

            HStack(spacing: 24) {
                score(players.0)
                Text("vs").font(QS.text(14, weight: .bold)).foregroundStyle(QS.faint)
                score(players.1)
            }

            VStack(spacing: 10) { actions }
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func score(_ p: Player) -> some View {
        VStack(spacing: 6) {
            Text(p.name).font(QS.text(14, weight: .bold)).foregroundStyle(Color(hexString: p.colorHex))
            Text("\(p.score)").font(.system(size: 44, weight: .black)).monospacedDigit().foregroundStyle(QS.ink)
        }
    }
}
