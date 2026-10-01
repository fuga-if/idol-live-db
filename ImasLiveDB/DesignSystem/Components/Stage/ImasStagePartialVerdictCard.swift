import SwiftUI

// =============================================================================
// 部分点のある判定カード (docs/DESIGN_SYSTEM.md §12)
//
// ImasStagePartialVerdictCard  `QuizVerdictCard` は正解/不正解の二値専用。
//                               「全員中 N 人正解」のような部分点はこちらを使う
//                               (全問正解 = 生成りのカード、一部正解 = ステージ地色)。
// =============================================================================

struct ImasStagePartialVerdictCard: View {
    let number: Int
    /// 満点 (生成りのカードになる) か、部分点 (ステージ地色) か。
    let isPerfect: Bool
    /// 大見出し文 (「全員正解！」「2 / 3 正解」)。
    let headline: String
    let score: Int

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Q.%02d — ", number) + (isPerfect ? "PERFECT" : "RESULT"))
                    .font(QS.mono(12)).tracking(1.4)
                Text(headline)
                    .font(QS.text(isPerfect ? 40 : 34, weight: .black))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            Text("+\(score)").font(QS.num(64, weight: .black))
        }
        .foregroundStyle(isPerfect ? QS.paperInk : QS.ink)
        .padding(.horizontal, 22).padding(.vertical, 18)
        .background(isPerfect ? QS.paper : QS.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(isPerfect ? Color.clear : QS.line, lineWidth: 1))
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
