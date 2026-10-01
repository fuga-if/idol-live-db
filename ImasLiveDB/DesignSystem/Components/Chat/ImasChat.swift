import SwiftUI

// =============================================================================
// AI チャットの吹き出しと入力欄
//
// 用途      ChatGPT 連携の質問チャット・キャラとのトークで共通して使う会話画面の部品。
//           将来のキャラクターチャット機能でも再利用する前提の設計。
// ImasChatBubble    発言 1 つ。相手 (AI・キャラ) は左、自分は右。相手は通常文・生成中・
//                   失敗の 3 状態を持つ。相手に実体色 (`seed`) を渡すと吹き出しの地がその色に薄く染まる。
// ImasChatComposer  入力欄。複数行のテキストフィールドと、送信⇄停止を切り替える丸い記号ボタン。
// ImasChatToolChip  ツール実行中であることを示す小さな札 (「曲を検索中…」)。
// =============================================================================

/// 発言のどちら側か。
enum ImasChatRole { case user, assistant }

/// 発言 1 つ。相手側 (AI・キャラ) は左、自分は右。
/// `avatar` を渡すと相手側の吹き出しの左にアイコン (と `partnerName`) を出す (キャラとのトーク用)。
struct ImasChatBubble<Avatar: View>: View {
    enum Content {
        /// 通常の発言。
        case text(String)
        /// 生成中。空文字なら点滅ドット、文字があればそれまでの生成分を出す。
        case streaming(String)
        /// 応答を受け取れなかった。
        case failed(message: String?, onRetry: () -> Void)
    }

    let role: ImasChatRole
    let content: Content
    /// 相手の名前 (キャラとのトーク)。吹き出しの上に小さく出す。
    var partnerName: String? = nil
    /// 相手の実体色 (キャラとのトーク)。無ければ地の面のまま。
    var seed: String? = nil
    @ViewBuilder var avatar: () -> Avatar

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.rowGap) {
            if role == .user {
                Spacer(minLength: DS.Size.touch)
                VStack(alignment: .trailing, spacing: DS.Space.gapTight) {
                    if let partnerName {
                        Text(partnerName).imasText(.meta)
                    }
                    bubble
                }
            } else {
                avatar()
                VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                    if let partnerName {
                        Text(partnerName).imasText(.meta)
                    }
                    bubble
                }
                Spacer(minLength: DS.Size.touch)
            }
        }
    }

    private var fill: Color {
        guard role == .assistant else { return DS.sys }
        guard let seed else { return DS.surface }
        return ImasTheme.derive(seed: seed, scheme: scheme).tint
    }

    private var ink: Color { role == .user ? DS.onSys : DS.ink }

    @ViewBuilder private var bubble: some View {
        switch content {
        case let .text(text):
            Text(text)
                .imasText(.body, color: ink)
                .textSelection(.enabled)
                .padding(.horizontal, DS.Space.card)
                .padding(.vertical, DS.Space.gap + 2)
                .background(fill, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        case let .streaming(text):
            Group {
                if text.isEmpty {
                    Image(systemName: "ellipsis")
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .foregroundStyle(DS.ink2)
                } else {
                    Text(text).imasText(.body, color: ink)
                }
            }
            .padding(.horizontal, DS.Space.card)
            .padding(.vertical, DS.Space.gap + 2)
            .background(fill, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        case let .failed(message, onRetry):
            ImasNotice(kind: .warning, message: message ?? "応答を受け取れませんでした",
                       actionTitle: "もう一度", action: onRetry)
        }
    }
}

extension ImasChatBubble where Avatar == EmptyView {
    init(role: ImasChatRole, content: Content, partnerName: String? = nil, seed: String? = nil) {
        self.init(role: role, content: content, partnerName: partnerName, seed: seed, avatar: { EmptyView() })
    }
}

// MARK: - 入力欄

/// チャットの入力欄。複数行のテキストフィールドと、送信⇄停止を切り替える丸いボタン。
/// `footer` に利用プランの注記などを添えられる。
struct ImasChatComposer<Footer: View>: View {
    @Binding var text: String
    let placeholder: String
    /// 応答が生成中か (丸ボタンが停止の記号に変わる)。
    let isRunning: Bool
    /// 送信できる状態か (空文字・未選択のモデル等でブロックする)。
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: DS.Space.gap) {
            HStack(alignment: .bottom, spacing: DS.Space.rowGap) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .imasText(.body)
                    .lineLimit(1...5)
                    .padding(.horizontal, DS.Space.card)
                    .padding(.vertical, DS.Space.gap)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rControl(44), style: .continuous))
                ImasIconButton(
                    systemImage: isRunning ? "stop.fill" : "arrow.up",
                    label: isRunning ? "止める" : "送信",
                    style: (isRunning || canSend) ? .filled : .tinted
                ) {
                    isRunning ? onStop() : onSend()
                }
                .disabled(!isRunning && !canSend)
            }
            footer()
        }
        .padding(.horizontal, DS.Space.screen)
        .padding(.top, DS.Space.gap)
        .padding(.bottom, DS.Space.gap)
        .background(DS.bg)
    }
}

extension ImasChatComposer where Footer == EmptyView {
    init(text: Binding<String>, placeholder: String, isRunning: Bool, canSend: Bool,
         onSend: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.init(text: text, placeholder: placeholder, isRunning: isRunning, canSend: canSend,
                  onSend: onSend, onStop: onStop, footer: { EmptyView() })
    }
}

// MARK: - ツール実行中の札

/// ツールの実行中であることを示す小さな札 (「曲を検索中…」)。生成中の吹き出しの上に置く。
struct ImasChatToolChip: View {
    let label: String

    var body: some View {
        HStack(spacing: DS.Space.gapTight) {
            ProgressView().controlSize(.mini)
            Text(label).imasText(.chip)
        }
        .foregroundStyle(DS.ink2)
        .padding(.horizontal, DS.Space.card)
        .padding(.vertical, DS.Space.gapTight + 2)
        .background(DS.fill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
