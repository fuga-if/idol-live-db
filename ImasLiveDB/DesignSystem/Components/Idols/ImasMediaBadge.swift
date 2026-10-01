import SwiftUI

// =============================================================================
// 画像サムネイルの角バッジ
//
// ImasMediaBadge   写真サムネイルの角に乗せる小さな印 (アイコン設定・スライドショー対象外など)。
//                  下の写真は何色か分からないので、実体色ではなく半透明の黒 + 白で乗せる
//                  (字幕の下の黒い帯と同じ考え方。アイコンタイルの「地を敷かない」原則の例外)。
// =============================================================================

/// 写真サムネイルの角に乗せる小さな印。`label` があれば記号+文字の札、無ければ記号だけの丸。
struct ImasMediaBadge: View {
    let systemImage: String
    /// 文字を伴う札 (「アイコン」)。nil なら記号だけの丸。
    var label: String? = nil
    /// 記号だけのときの読み上げ。
    var accessibilityLabel: String? = nil

    var body: some View {
        Group {
            if let label {
                Label(label, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.imasCaption2.weight(.bold))
                    .padding(.horizontal, DS.Space.gapTight + 2)
                    .padding(.vertical, DS.Space.gapTight)
                    .background(.black.opacity(0.55), in: Capsule())
            } else {
                Image(systemName: systemImage)
                    .font(.imasCaption2.weight(.bold))
                    .padding(DS.Space.gapTight)
                    .background(.black.opacity(0.55), in: Circle())
            }
        }
        .foregroundStyle(.white)
        .padding(DS.Space.gapTight)
        .accessibilityLabel(accessibilityLabel ?? label ?? "")
        .accessibilityHidden(accessibilityLabel == nil && label == nil)
    }
}
