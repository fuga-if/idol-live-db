import SwiftUI

// =============================================================================
// チャット (docs/DESIGN_SYSTEM.md §9)
//
// 用途      会話の画面。利用者の発言の紙片と、画面の下に据える入力欄。
// 使わない  相手の返事 → 地の文 (`imasText(.body)`) のまま。吹き出しにしない。
//           検索 → ImasSearchField
// 構成      紙片: 右に寄せた角丸の四角 (地は surface2)。色を付けない。
//           入力欄: [複数行の欄] [送る (墨の四角に ↑)]。上に区切り線。
// 状態      送る: 通常 / 無効 (薄く)
// =============================================================================

/// 利用者の発言。右に寄せた紙片。
struct ImasChatBubble: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .imasText(.body)
            .padding(.horizontal, DS.Space.card)
            .padding(.vertical, DS.Space.gap)
            .background(DS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, DS.Space.section)
    }
}

/// 画面の下に据える入力欄と送るボタン。`safeAreaInset(edge: .bottom)` に置く。
struct ImasChatComposer: View {
    let prompt: String
    @Binding var text: String
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.gap) {
            TextField(prompt, text: $text, axis: .vertical)
                .font(.imasBody)
                .lineLimit(1...5)
                .padding(.horizontal, DS.Space.card)
                .padding(.vertical, DS.Space.gap)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.line))
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.imasScaled(16, weight: .bold))
                    .foregroundStyle(DS.onSys)
                    .frame(width: 40, height: 40)
                    .background(DS.sys, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.35)
            .accessibilityLabel("送る")
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.vertical, DS.Space.gap)
        .background(DS.paper)
        .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 1) }
    }
}
