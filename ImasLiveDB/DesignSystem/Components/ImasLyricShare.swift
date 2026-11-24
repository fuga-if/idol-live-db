import SwiftUI
import UIKit
import UniformTypeIdentifiers

// =============================================================================
// 歌詞の一部の共有 (公開サイトの曲ページの `#lyric-…` へのリンク)
//
// 用途      歌詞タブで行を長押しして選んだ範囲の塗りと、画面の下に浮かぶ帯。
//           帯から渡すのは **URL だけ**。歌詞の本文は共有にもコピーにも乗せない
//           (JASRAC 許諾の条件。SongLyricsTab の ⚠️ と同じ)。
// 構成      選んだ行 … 字の下に曲の色 (ソロは担当色、ほかはブランド色) の平らな面 + 下端の線。
//                      公開サイトの塗り (`.lyrics__mark`) と同じ見え方。
//           帯 … 左に曲の色の縦帯、「12〜14行目 / この部分へのリンク」、共有・コピー・× の記号。
//                浮いている枠なので iOS 26 は Liquid Glass、それより前は平らな面。
//
// 光らせない・ぼかさない (グラデーション・光は禁止)。色は曲の配色だけ。
// =============================================================================

extension View {
    /// 共有のために選んだ歌詞の行の塗り。行の折り返しは変えない (余白へはみ出す)。
    func imasLyricSharePicked(_ isPicked: Bool, seed: String?) -> some View {
        modifier(ImasLyricSharePickedModifier(isPicked: isPicked, seed: seed))
    }
}

private struct ImasLyricSharePickedModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let isPicked: Bool
    let seed: String?

    func body(content: Content) -> some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        content
            .padding(.horizontal, DS.sp2)
            .background {
                if isPicked {
                    // 面は Web と同じ濃さ (24%)。下端の線で「ここを選んだ」をくっきり示す。
                    t.accent.opacity(0.24)
                        .overlay(alignment: .bottom) { t.accent.frame(height: 2) }
                        .clipShape(RoundedRectangle(cornerRadius: DS.rTag, style: .continuous))
                }
            }
            .padding(.horizontal, -DS.sp2)
            .animation(.easeOut(duration: 0.15), value: isPicked)
            .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

/// 選んだ歌詞へのリンクを渡す帯。画面の下に浮かべる。
///
/// 渡すのは `url` だけ。共有 (`ShareLink`) もコピーも URL しか持たない。
struct ImasLyricShareBar: View {
    @Environment(\.colorScheme) private var scheme
    /// 「12行目」「12〜14行目」(コアの `shareLyricLinesLabel`)。
    let linesLabel: String
    /// 下段の一言 (「この部分へのリンク」/ 広げ方の案内)。コピーした直後だけ「コピーしました」に替わる。
    var note: String = "この部分へのリンク"
    let url: URL
    let seed: String?
    let onClose: () -> Void

    @State private var copiedToken = 0
    @State private var showsCopied = false

    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        HStack(spacing: DS.sp3) {
            RoundedRectangle(cornerRadius: DS.rTag, style: .continuous)
                .fill(t.accent)
                .frame(width: 4)
                .padding(.vertical, DS.sp1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.sp1) {
                Text(linesLabel).imasText(.rowTitle)
                Text(showsCopied ? "リンクをコピーしました" : note)
                    .imasText(.meta)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.imasScaled(16, weight: .semibold))
                    .foregroundStyle(DS.onSys)
                    .frame(width: 44, height: 44)
                    .background(DS.sys, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.imasPress)
            .accessibilityLabel("この部分へのリンクを共有")
            ImasIconButton(systemImage: showsCopied ? "checkmark" : "doc.on.doc",
                           label: "この部分へのリンクをコピー", style: .tinted) { copy() }
            ImasIconButton(systemImage: "xmark", label: "選択を解除", size: .small, style: .plain, action: onClose)
        }
        // 縦帯は高さを持たないので、中身の高さに揃える (無いと帯が画面いっぱいに伸びる)。
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, DS.sp4)
        .padding(.trailing, DS.sp2)
        .padding(.vertical, DS.sp3)
        .imasFloatingChrome(cornerRadius: DS.rCard)
        .overlay {
            // ガラスでない (iOS 25 以前) ときは紙の上に置く枠線で縁を出す。
            RoundedRectangle(cornerRadius: DS.rCard, style: .continuous)
                .strokeBorder(DS.sep, lineWidth: Self.usesGlass ? 0 : 1)
        }
        .sensoryFeedback(.success, trigger: copiedToken)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("選んだ歌詞の共有")
    }

    private static var usesGlass: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26, *) { return true }
        #endif
        return false
    }

    private func copy() {
        // URL だけを載せる (本文は載せない)。
        // 貼る先が URL を受けない (メモ・チャットの入力欄) ときのために文字の形も添える。
        UIPasteboard.general.setItems([[UTType.url.identifier: url,
                                        UTType.utf8PlainText.identifier: url.absoluteString]])
        copiedToken += 1
        withAnimation(.easeOut(duration: 0.15)) { showsCopied = true }
        UIAccessibility.post(notification: .announcement, argument: "リンクをコピーしました")
        let token = copiedToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard token == copiedToken else { return }
            withAnimation(.easeOut(duration: 0.15)) { showsCopied = false }
        }
    }
}
