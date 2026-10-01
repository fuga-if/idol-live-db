import SwiftUI

// =============================================================================
// ステージの案内行 (docs/DESIGN_SYSTEM.md §12)
//
// ImasStageInfoRow   「記号 + 2 行文 (+ 矢印)」の案内行。`QuizVerdictFootnote` が原型。
//                     押せる (別画面・リンク) か、案内だけ (押せない) かを選べる。
// =============================================================================

/// ステージ上の「記号 + 2 行文」の案内行。
struct ImasStageInfoRow: View {
    let systemImage: String
    let title: String
    var detail: String? = nil
    /// 遷移あり (押せる) なら矢印を出す。
    var showsChevron: Bool = false
    /// 記号の代わりにくるくるを出す (次の問題の先読み待ちなど)。
    var isLoading: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.imasPress)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView().tint(QS.dim)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(QS.dim)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(QS.text(13, weight: .bold)).foregroundStyle(QS.ink)
                if let detail {
                    Text(detail).font(QS.text(11)).foregroundStyle(QS.dim)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(QS.faint)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(QS.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
