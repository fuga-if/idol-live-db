import SwiftUI

// =============================================================================
// カラオケモードの部品
//
// ImasKaraokeLane        この先 20 秒に誰が歌うかの帯。担当色の区間、2 人以上は角のはっきりした縦縞。
//                        自分のパートの区間は墨の枠で囲む。左端が今。
// ImasKaraokeRow         1 行の入れ物。行頭に歌う人の帯 (ImasPartStripe)、選んだ行は面を敷く。
// ImasKaraokeSingerLabel 行の上の「春香・千早」(担当色の字) と手拍子の記号、自分のパートなら「あなた」。
// ImasKaraokeCallTag     コール 1 つ。強調度の色の枠 (演者要望 = 朱、おこのみで = 緑)。今のコールは大きく。
// ImasKaraokeCountdown   自分の番までの残り秒と 4 つの四角。
// ImasKaraokeTapPad      歌い出しで叩く大きな面 (枠だけ)。
// ImasKaraokeOffsetBadge 手のずらしの量 (「+0.3秒」)。
// ImasKaraokeStatus      耳で合わせている・合わせた等の短い状態。
//
// 部屋が暗いので、このモードの画面はいつも暗い地 (`colorScheme = .dark`) で使う。
// 光る・ぼかすは使わない。塗りは歌う人の色と墨・白だけ。
// =============================================================================

// MARK: - 帯

struct ImasKaraokeLane: View {
    struct Span: Identifiable, Equatable {
        let id: Int
        /// 帯の左端 0〜右端 1。
        let from: Double
        let to: Double
        /// 歌う人の担当色 (hex)。2 人以上なら縞。
        let colors: [String]
        let isMine: Bool
    }

    let spans: [Span]
    var seconds: Int = 20
    @Environment(\.colorScheme) private var scheme

    /// 縞 1 本の幅。
    private static let stripe: CGFloat = 6
    private static let height: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sp2) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(DS.fill)
                    ForEach(spans) { span in
                        let x = w * span.from
                        let width = max(1, w * (span.to - span.from) - 2)
                        stripes(span.colors)
                            .frame(width: width, height: Self.height)
                            .overlay {
                                if span.isMine { Rectangle().strokeBorder(DS.ink, lineWidth: 2) }
                            }
                            .offset(x: x)
                    }
                    // 今 (左端)。
                    Rectangle().fill(DS.ink).frame(width: 2, height: Self.height + 6).offset(y: -3)
                }
            }
            .frame(height: Self.height)
            HStack {
                Text("今")
                Spacer()
                Text("+\(seconds / 2)秒")
                Spacer()
                Text("+\(seconds)秒")
            }
            .imasText(.micro, color: DS.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("この先\(seconds)秒に歌う人の帯")
    }

    private func stripes(_ colors: [String]) -> some View {
        let fills = colors.map { ImasTheme.derive(seed: $0, scheme: scheme).accent }
        return Canvas { context, size in
            guard !fills.isEmpty else { return }
            if fills.count == 1 {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(fills[0]))
                return
            }
            var x: CGFloat = 0
            var k = 0
            while x < size.width {
                let rect = CGRect(x: x, y: 0, width: min(Self.stripe, size.width - x), height: size.height)
                context.fill(Path(rect), with: .color(fills[k % fills.count]))
                x += Self.stripe
                k += 1
            }
        }
    }
}

// MARK: - 行

struct ImasKaraokeRow<Content: View>: View {
    /// 行を歌う人の担当色 (hex)。空なら帯を描かない (幅だけ取る)。
    let colors: [String]
    /// 選んでいる行 (合わせる行) に面を敷く。
    var isHighlighted = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: DS.sp3) {
            ImasPartStripe(colors: colors)
            VStack(alignment: .leading, spacing: DS.sp2) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, isHighlighted ? DS.sp3 : 0)
        .padding(.trailing, isHighlighted ? DS.sp3 : 0)
        .background(isHighlighted ? DS.surface : Color.clear)
        .contentShape(Rectangle())
    }
}

struct ImasKaraokeSingerLabel: View {
    /// 歌う人の名前と担当色 (同じ並び)。
    let names: [String]
    let colors: [String]
    var clap: String? = nil
    var isMine = false
    /// 行の上に添える札 (「この行で合わせる」)。
    var pin: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.sp2) {
            if let pin {
                Text(pin).imasText(.eyebrow, color: DS.favorite)
            }
            if let clap {
                Text(clap).imasText(.meta, color: DS.ink2)
            }
            if !names.isEmpty {
                names.indices.reduce(Text("")) { text, k in
                    let color = k < colors.count ? ImasTheme.derive(seed: colors[k], scheme: scheme).accent : DS.ink2
                    return text + (k == 0 ? Text("") : Text("・").foregroundStyle(DS.ink3))
                        + Text(names[k]).foregroundStyle(color)
                }
                .imasText(.eyebrow)
                .lineLimit(1)
            }
            if isMine {
                Text("あなた")
                    .imasText(.badge, color: DS.bg)
                    .padding(.horizontal, DS.sp2)
                    .background(DS.ink)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - コール

struct ImasKaraokeCallTag: View {
    let text: String
    /// 強調度の色 (`CallEmphasis.color(accent:)`)。
    let color: Color
    let isActive: Bool

    var body: some View {
        Text(text)
            .font(isActive ? .imasHeading(22, weight: .heavy) : .imasHeading(15, weight: .bold))
            .foregroundStyle(isActive ? color : color.opacity(0.6))
            .padding(.horizontal, DS.sp3)
            .padding(.vertical, DS.sp1)
            .overlay { Rectangle().strokeBorder(isActive ? color : color.opacity(0.45), lineWidth: 2) }
            .fixedSize(horizontal: false, vertical: true)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isActive)
            .accessibilityLabel("コール \(text)")
            .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - 自分の番の数え

struct ImasKaraokeCountdown: View {
    /// 残り (ms)。
    let remainingMs: Int
    /// 点いている四角の数。
    let lit: Int
    var total = 4
    /// 自分のパートの色 (hex)。
    let seed: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = seed.map { ImasTheme.derive(seed: $0, scheme: scheme).accent } ?? DS.ink
        HStack(alignment: .center, spacing: DS.sp3) {
            Rectangle().fill(color).frame(width: 4)
            Text(String(format: "%.1f", Double(max(0, remainingMs)) / 1000))
                .font(.imasDisplay(30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text("秒であなた").imasText(.meta, color: DS.ink2)
            Spacer(minLength: 0)
            HStack(spacing: DS.sp2) {
                ForEach(0..<total, id: \.self) { k in
                    Rectangle().fill(k < lit ? color : DS.ink3).frame(width: 10, height: 10)
                }
            }
        }
        .padding(.vertical, DS.sp3)
        .padding(.trailing, DS.sp4)
        .background(DS.surface)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("あと\(max(0, remainingMs) / 1000)秒であなたのパート")
    }
}

// MARK: - 合わせる

struct ImasKaraokeTapPad: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.sp2) {
                Text(title).font(.imasHeading(22, weight: .heavy)).foregroundStyle(DS.favorite)
                Text(subtitle).imasText(.meta, color: DS.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .overlay { Rectangle().strokeBorder(DS.favorite, lineWidth: 3) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.imasPress)
        .accessibilityHint(subtitle)
    }
}

struct ImasKaraokeOffsetBadge: View {
    let ms: Int

    var body: some View {
        Text(Self.label(ms))
            .font(.imasMono(15, weight: .bold))
            .foregroundStyle(DS.ink)
            .padding(.horizontal, DS.sp3)
            .padding(.vertical, DS.sp1)
            .overlay { Rectangle().strokeBorder(DS.ink3, lineWidth: 1.5) }
            .accessibilityLabel("ずらし \(Self.label(ms))")
    }

    static func label(_ ms: Int) -> String {
        String(format: "%@%.1f秒", ms >= 0 ? "+" : "−", Double(abs(ms)) / 1000)
    }
}

struct ImasKaraokeStatus: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: DS.sp2) {
            Image(systemName: systemImage)
            Text(text).lineLimit(1)
        }
        .imasText(.meta, color: DS.ink2)
    }
}
