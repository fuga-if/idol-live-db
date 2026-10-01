import SwiftUI

// =============================================================================
// ステージの数タイル (docs/DESIGN_SYSTEM.md §12)
//
// ImasStageStatTile   ステージの暗い面に「ラベル + 大きな数字」を 1 枚で見せる。
//                      クイズの結果 (スコア推移)・ハブの QUIZ STAGE チケット・
//                      イントロドンのタイムなど、画面ごとに重複していたタイルを 1 つに。
// ImasStageBadgeStamp  「自己ベスト更新」のような達成を知らせる回転ラベル。
//
// 色はどちらもステージ固定の `QS.*` (ライト/ダークで反転させない)。
// =============================================================================

/// ステージ上の「ラベル + 大きな数字」のタイル。単値でも、対比 (前 → 後) でも、
/// 右に付随バッジ (自己ベスト更新など) を添えても使える。
struct ImasStageStatTile<Value: View, Trailing: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(QS.text(12, weight: .bold)).foregroundStyle(QS.dim)
                value().foregroundStyle(QS.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension ImasStageStatTile where Trailing == EmptyView {
    init(label: String, @ViewBuilder value: @escaping () -> Value) {
        self.init(label: label, value: value, trailing: { EmptyView() })
    }
}

/// 達成を知らせる回転ラベル (「自己ベスト更新」「ベストタイム更新」)。
struct ImasStageBadgeStamp: View {
    let title: String
    /// 旧値 → 新値の併記 (「700 → 755」)。無ければ文言だけ。
    var detail: String? = nil
    /// 出現アニメーションの進み具合 (0 = 出現前、1 = 出現後)。呼び出し側の `@State` と合わせる。
    var appeared: Bool = true

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(QS.text(13, weight: .black))
            if let detail {
                Text(detail).font(QS.mono(11))
            }
        }
        .foregroundStyle(QS.stamp)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(QS.stamp, lineWidth: 2))
        .rotationEffect(.degrees(-5))
        .scaleEffect(appeared ? 1 : 1.8)
        .opacity(appeared ? 1 : 0)
    }
}
