import SwiftUI

// =============================================================================
// チャット (docs/DESIGN_SYSTEM.md §9)
//
// 用途      会話の画面。利用者の発言の紙片、考えている途中の一行、画面の下に据える入力欄。
// 使わない  相手の返事 → 地の文 (`imasText(.body)`) のまま。吹き出しにしない。
//           検索 → ImasSearchField
// 構成      紙片: 右に寄せた角丸の四角 (地は surface2)。色を付けない。画像は字の上に小さく並べる。
//           途中: [くるくる] [何をしているかの一言] を 1 行で。止めるのは入力欄のボタン。
//           入力欄: [添える (+)] [複数行の欄] [送る ↑ / 止める ■]。上に区切り線。
//                   添えた画像は欄の上に小さく並び、× で外せる。
// 状態      送る: 通常 / 無効 (薄く) / 考えている途中 (■ に替わり、押すと止まる)
// =============================================================================

/// 利用者の発言。右に寄せた紙片。
struct ImasChatBubble: View {
    let text: String
    var images: [UIImage] = []

    init(_ text: String, images: [UIImage] = []) {
        self.text = text
        self.images = images
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.gap) {
            if !images.isEmpty {
                HStack(spacing: DS.Space.gap) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        ImasChatThumbnail(image: image, side: 72)
                    }
                }
            }
            if !text.isEmpty {
                Text(text)
                    .imasText(.body)
                    .padding(.horizontal, DS.Space.card)
                    .padding(.vertical, DS.Space.gap)
                    .background(DS.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, DS.Space.section)
    }
}

/// 考えている途中の一行。
struct ImasChatThinking: View {
    let label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        HStack(spacing: DS.Space.gap) {
            ProgressView().controlSize(.small).tint(DS.ink3)
            Text(label)
                .imasText(.note)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 添えた画像の小さな写し。
struct ImasChatThumbnail: View {
    let image: UIImage
    var side: CGFloat = 56
    /// 外すボタン。nil なら出さない (送ったあとの紙片)。
    var onRemove: (() -> Void)? = nil

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.line))
            .overlay(alignment: .topTrailing) {
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.imasScaled(9, weight: .bold))
                            .foregroundStyle(DS.onSys)
                            .frame(width: 20, height: 20)
                            .background(DS.sys, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("画像を外す")
                }
            }
            .accessibilityLabel("添えた画像")
    }
}

/// 画面の下に据える入力欄。`safeAreaInset(edge: .bottom)` に置く。
///
/// `accessory` は欄の左に置く小物 (画像を添えるメニューなど。無ければ `EmptyView`)。
struct ImasChatComposer<Accessory: View>: View {
    let prompt: String
    @Binding var text: String
    /// 添えた画像 (欄の上に並べる)。
    var attachments: [UIImage] = []
    var onRemoveAttachment: (Int) -> Void = { _ in }
    let canSend: Bool
    /// 考えている途中か。途中なら送るボタンが「止める」に替わる。
    var isRunning: Bool = false
    let onSend: () -> Void
    var onStop: () -> Void = {}
    @ViewBuilder var accessory: Accessory

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            if !attachments.isEmpty {
                HStack(spacing: DS.Space.gapLoose) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { index, image in
                        ImasChatThumbnail(image: image) { onRemoveAttachment(index) }
                    }
                }
                .padding(.top, DS.Space.gapTight)
            }
            HStack(alignment: .bottom, spacing: DS.Space.gap) {
                accessory
                TextField(prompt, text: $text, axis: .vertical)
                    .font(.imasBody)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, DS.Space.card)
                    .padding(.vertical, DS.Space.gap)
                    .frame(minHeight: 40)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.line))
                Button {
                    if isRunning {
                        onStop()
                    } else {
                        // 送ったら返事が見えるようにキーボードを下げる。
                        focused = false
                        onSend()
                    }
                } label: {
                    Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                        .font(.imasScaled(isRunning ? 13 : 16, weight: .bold))
                        .foregroundStyle(DS.onSys)
                        .frame(width: 40, height: 40)
                        .background(DS.sys, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isRunning && !canSend)
                .opacity(isRunning || canSend ? 1 : 0.3)
                .accessibilityLabel(isRunning ? "止める" : "送る")
            }
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.vertical, DS.Space.gap)
        .background(DS.paper)
        .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 1) }
    }
}

/// 入力欄の左に置く、記号だけの四角いボタンの見た目 (画像を添えるメニューのラベルに使う)。
struct ImasChatAccessoryLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.imasScaled(16, weight: .semibold))
            .foregroundStyle(DS.ink)
            .frame(width: 40, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.line))
            .contentShape(Rectangle())
    }
}
