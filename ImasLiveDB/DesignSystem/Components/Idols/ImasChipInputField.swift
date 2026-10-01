import SwiftUI

// =============================================================================
// チップ型の 1 行追加入力
//
// ImasChipInputField   マイタグ等、押すと増える手元のチップを 1 行で追加する欄。
//                      カプセルの入力欄 + 丸い送信ボタン。アイドル・ユニット詳細の
//                      「マイタグ」で共通して使う (同じ形を 2 画面が別々に持っていた)。
// =============================================================================

struct ImasChipInputField: View {
    @Binding var text: String
    var prompt: String
    /// 文字数の上限。超えた分は切り詰める。
    var limit: Int? = nil
    var isEnabled: Bool = true
    /// 追加ボタンの読み上げ (「マイタグを追加」等)。記号だけのボタンなので必須。
    var submitAccessibilityLabel: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.gap) {
            TextField(prompt, text: $text)
                .font(.imasSubhead)
                .foregroundStyle(DS.ink)
                .autocorrectionDisabled()
                .padding(.horizontal, DS.Space.gapLoose)
                .padding(.vertical, DS.Space.gap)
                .background(DS.fill, in: Capsule())
                .onChange(of: text) { _, new in
                    if let limit, new.count > limit { text = String(new.prefix(limit)) }
                }
                .onSubmit(onSubmit)
            Button(action: onSubmit) {
                Image(systemName: "plus.circle.fill")
                    .font(.imasScaled(26, weight: .semibold))
                    .foregroundStyle(isEnabled ? DS.ink : DS.ink3)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(submitAccessibilityLabel)
        }
    }
}
