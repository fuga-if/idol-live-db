import SwiftUI

/// アイドルアイコンをオーバーラップして横並びに表示するスタック。
/// Slack / FaceTime の参加者ピル風の見た目。
struct StackedAvatars: View {
    let idols: [Idol]
    var maxVisible: Int = 5
    var size: CGFloat = 24
    var onTap: (() -> Void)? = nil

    var body: some View {
        stack
            .accessibilityElement(children: .combine)
            .accessibilityLabel("出演者 \(idols.count)名")
    }

    /// onTap が指定されている時だけタップを受ける。nil の場合は親 View の
    /// gesture (onTapGesture / Button) にイベントを通すため tap modifier を付けない。
    @ViewBuilder
    private var stack: some View {
        if let onTap {
            stackBody
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
        } else {
            stackBody
        }
    }

    private var stackBody: some View {
        HStack(spacing: -(size * 0.4)) {
            ForEach(Array(idols.prefix(maxVisible).enumerated()), id: \.offset) { idx, idol in
                // isPick は使わずここで独自の背景色リングを重ねるため、担当リング分の外形余白は
                // 予約しない (予約すると可視アバターより一回り大きい場所にリングが浮いて見える)。
                IdolAvatarView(idol: idol, size: size, reservesPickRing: false)
                    .overlay(
                        Circle().strokeBorder(DS.surface, lineWidth: 2)
                    )
                    .zIndex(Double(maxVisible - idx))
            }
            overflowChip
        }
    }

    /// 入り切らなかった人数。**アバターと同じ丸**にして列の最後に置く。
    ///
    /// 以前は素のテキスト (`+9`) だった。`HStack` の負のスペーシングは
    /// **このテキストにも掛かる**ので左に 4 割ぶん引き寄せられ、しかも `zIndex` が
    /// 最前のアバターより下だったため、**「+」が隣の円の下に潜って数字だけが見えていた**
    /// (「9」とだけ出ていて、何の 9 なのか分からない)。
    ///
    /// 丸にして列の最後に置く。**重なりは打ち消す** — アバターどうしの重なりは
    /// 「同じ集団」の合図だが、これは人ではなく「あと何人いるか」の注記なので、
    /// 同じように重ねると隠れているように見える (実際そう見えるという指摘を受けた)。
    /// 負のスペーシングぶんを左余白で戻し、わずかに離して置く。
    @ViewBuilder
    private var overflowChip: some View {
        if idols.count > maxVisible {
            Text("+\(idols.count - maxVisible)")
                .font(.imasCaption2.weight(.semibold))
                .foregroundStyle(DS.ink2)
                .frame(width: size, height: size)
                .background(DS.fill, in: Circle())
                .padding(.leading, size * 0.4 + DS.sp2)
                .zIndex(Double(maxVisible + 1))
        }
    }
}
