import SwiftUI

// =============================================================================
// タグ詳細の頭 (docs/DESIGN_SYSTEM.md §5・§10.1)
//
// ImasTagHeaderCard  曲 / アイドル / ユニットのタグ詳細で共通の頭。色の丸・名前・カテゴリの札・
//                    説明文 (無ければ「説明なし」)。カテゴリは「色で意味を分けない」のですべて
//                    同じ札にする (以前はカテゴリごとに手書きの色で塗り分けていて、3 画面
//                    一字一句同一のコードが並走していた)。
// =============================================================================

struct ImasTagHeaderCard: View {
    let name: String
    var colorHex: String? = nil
    var categoryLabel: String? = nil
    var description: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.note) {
            HStack(spacing: DS.Space.gap) {
                if let colorHex {
                    // ImasSwatch 既定の読み上げ (「カラー: ...」) ではこの画面の文脈が
                    // 伝わらないため、「タグカラー:」に差し替える。
                    ImasSwatch(hex: colorHex, size: .small)
                        .accessibilityLabel("タグカラー: \(ColorAccessibilityName.of(colorHex))")
                }
                Text(name).imasText(.heroTitle)
                Spacer(minLength: DS.Space.gap)
                if let categoryLabel {
                    ImasBadge(text: categoryLabel, kind: .neutral)
                        .accessibilityLabel("カテゴリ: \(categoryLabel)")
                }
            }
            if let description, !description.isEmpty {
                Text(description).imasText(.body).imasSelectableText()
            } else {
                Text("説明なし").imasText(.note)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
