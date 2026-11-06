import SwiftUI

// =============================================================================
// 今年の P 活動報告 (1 年の記録をめくって見せる物語) の部品。
//
// 地は客席の闇 (電光掲示板と同じ暗い板)。最後のまとめだけ明るい紙 (SNS に貼る 1 枚)。
// 動きは `animate` が真になったときに 1 回だけ。動きを減らす設定では最後の形をそのまま出す
// (呼ぶ側が `animate` を真のまま、部品が `accessibilityReduceMotion` を見て動かさない)。
//
// ImasStoryProgress        上の細い進み具合 (ページ数ぶんの棒)
// ImasYearCountUp          数え上がる大きな数
// ImasYearStubRow          ① 参加した公演の半券の行
// ImasYearStubRoll         ① 半券の行が下から流れてくる束
// ImasYearCalendar         ② 現場カレンダー (現場のあった月に判子)
// ImasJapanTileMap         ③ 都道府県の升の地図 (行った県が順に灯る)
// ImasJacketFlip           ④ ジャケットが裏返って出てくる
// ImasYearSummarySheet     ⑤ まとめの明るい紙 (書き出す画像にもそのまま使う)
// =============================================================================

enum ImasYearReportStyle {
    static let title = Font.imasHeading(24, weight: .heavy)
    static let big = Font.imasDisplay(96, weight: .semibold)
    static let mid = Font.imasDisplay(60, weight: .semibold)
}

/// 上の進み具合。今のページは `progress` (0〜1) まで埋まる。
struct ImasStoryProgress: View {
    let count: Int
    let index: Int
    let progress: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.boardLine)
                        Capsule().fill(DS.boardInk)
                            .frame(width: geo.size.width * fill(i))
                    }
                }
                .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(count) ページ中 \(index + 1) ページ目")
    }

    private func fill(_ i: Int) -> CGFloat {
        i < index ? 1 : (i == index ? CGFloat(min(max(progress, 0), 1)) : 0)
    }
}

/// 数え上がる大きな数 (動きを減らす設定では最初から最後の数)。
struct ImasYearCountUp: View {
    let value: Int
    var font: Font = ImasYearReportStyle.mid
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        Text("\(Int(shown.rounded()))")
            .font(font)
            .monospacedDigit()
            .foregroundStyle(DS.boardInk)
            .contentTransition(.numericText(value: shown))
            .onAppear { run() }
            .onChange(of: animate) { _, _ in run() }
            .accessibilityLabel("\(value)")
    }

    private func run() {
        guard animate, !reduceMotion else {
            shown = Double(value)
            return
        }
        shown = 0
        withAnimation(.easeOut(duration: 0.9)) { shown = Double(value) }
    }
}

/// ① 半券の 1 行 (月の刻印と日・公演・会場・配信の札)。
struct ImasYearStubRow: View {
    let monthImprint: String
    let day: Int
    let title: String
    let venue: String?
    let isLocal: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.gap) {
            VStack(spacing: 0) {
                Text(monthImprint).font(.imasMono(9)).foregroundStyle(DS.boardDim)
                Text("\(day)").font(.imasDisplay(16)).monospacedDigit().foregroundStyle(DS.boardInk)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Space.gapTight) {
                    Text(title).font(.imasCaption.weight(.bold)).foregroundStyle(DS.boardInk).lineLimit(2)
                    if !isLocal {
                        Text("配信")
                            .font(.imasMono(9))
                            .foregroundStyle(DS.lamp)
                            .padding(.horizontal, 3)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(DS.lamp, lineWidth: 1))
                    }
                }
                if let venue {
                    Text(venue).font(.imasCaption2).foregroundStyle(DS.boardDim).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.boardLine).frame(height: 1)
                .mask(HStack(spacing: 3) { ForEach(0..<80, id: \.self) { _ in Rectangle().frame(width: 3) } })
        }
        .accessibilityElement(children: .combine)
    }
}

/// ① 半券の束。下から流れて上がってくる (動きを減らす設定では止まったまま)。
struct ImasYearStubRoll<Row: View>: View {
    let count: Int
    let animate: Bool
    @ViewBuilder let row: (Int) -> Row

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { row($0) }
                Spacer(minLength: 0)
            }
            .offset(y: offset)
            .onAppear { run(height: geo.size.height) }
            .onChange(of: animate) { _, _ in run(height: geo.size.height) }
        }
        .clipped()
        .overlay(alignment: .top) { Rectangle().fill(DS.boardLine).frame(height: 1) }
    }

    private func run(height: CGFloat) {
        guard animate, !reduceMotion else {
            offset = 0
            return
        }
        offset = height
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: min(6, 1.2 + Double(count) * 0.25))) { offset = 0 }
    }
}

/// ② 現場カレンダー。月の升に、その月の現場の数の判子を順に押す。
struct ImasYearCalendar: View {
    /// 1〜12 月の現場の数。
    let counts: [Int]
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.gap), count: 4),
                  spacing: DS.Space.gap) {
            ForEach(Array(counts.enumerated()), id: \.offset) { i, n in
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DS.boardLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        Text("\(i + 1)月").font(.imasMono(11)).foregroundStyle(DS.boardDim).padding(5)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if n > 0 {
                            Circle()
                                .strokeBorder(DS.stamp, lineWidth: 2)
                                .frame(width: 30, height: 30)
                                .overlay(Text("\(n)").font(.imasDisplay(13)).foregroundStyle(DS.lamp))
                                .rotationEffect(.degrees(-12))
                                .scaleEffect(stamped ? 1 : 0.01)
                                .opacity(stamped ? 1 : 0)
                                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.5)
                                    .delay(Double(i) * 0.12), value: stamped)
                                .padding(6)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(n > 0 ? "\(i + 1)月 \(n) 公演" : "\(i + 1)月 現場なし")
            }
        }
        .onAppear { stamped = animate || reduceMotion }
        .onChange(of: animate) { _, on in
            stamped = false
            if on { DispatchQueue.main.async { stamped = true } }
        }
    }
}

/// ③ 都道府県の升の地図 (JIS コードの位置に升を置く。行った県を初めて行った順に灯す)。
struct ImasJapanTileMap: View {
    /// 初めて行った順の JIS コード。
    let lit: [Int]
    let accent: Color
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    /// JIS コード → (列, 行)。13 列 × 13 行の升に日本の形を寄せて置く。
    static let tiles: [Int: (Int, Int)] = [
        1: (12, 0),
        2: (12, 2), 5: (11, 3), 3: (12, 3), 6: (11, 4), 4: (12, 4),
        17: (9, 5), 16: (10, 5), 15: (11, 5), 7: (12, 5),
        32: (4, 6), 31: (5, 6), 28: (6, 6), 26: (7, 6), 18: (8, 6), 21: (9, 6), 20: (10, 6), 10: (11, 6), 9: (12, 6),
        40: (2, 7), 35: (3, 7), 34: (4, 7), 33: (5, 7), 27: (6, 7), 29: (7, 7), 25: (8, 7), 23: (9, 7), 19: (10, 7), 11: (11, 7), 8: (12, 7),
        42: (0, 8), 41: (1, 8), 44: (2, 8), 30: (6, 8), 24: (7, 8), 22: (9, 8), 14: (10, 8), 13: (11, 8), 12: (12, 8),
        43: (1, 9), 45: (2, 9), 38: (4, 9), 37: (5, 9), 36: (6, 9),
        46: (1, 10), 39: (5, 10),
        47: (0, 12),
    ]

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 13
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.tiles.keys).sorted(), id: \.self) { code in
                    let (c, r) = Self.tiles[code]!
                    let order = lit.firstIndex(of: code)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(order != nil && on ? accent : DS.boardLine)
                        .animation(reduceMotion || order == nil ? nil : .easeOut(duration: 0.4)
                            .delay(Double(order ?? 0) * 0.15), value: on)
                        .frame(width: cell - 3, height: cell - 3)
                        .offset(x: CGFloat(c) * cell, y: CGFloat(r) * cell)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { on = animate || reduceMotion }
        .onChange(of: animate) { _, now in
            on = false
            if now { DispatchQueue.main.async { on = true } }
        }
        .accessibilityElement()
        .accessibilityLabel("行った都道府県の地図 \(lit.count) 都道府県")
    }
}

/// ④ ジャケットが裏返って出てくる。
struct ImasJacketFlip: View {
    let title: String
    let imageURL: URL?
    var seed: String? = nil
    var side: CGFloat = 180
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(DS.boardLine)
                .overlay(Text("?").font(.imasMono(14)).foregroundStyle(DS.boardDim))
                .opacity(turned ? 0 : 1)
            ImasArtwork(title: title, seed: seed, size: side, imageURL: imageURL)
                .opacity(turned ? 1 : 0)
        }
        .frame(width: side, height: side)
        .rotation3DEffect(.degrees(turned ? 0 : 180), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.7), value: turned)
        .onAppear { turned = animate || reduceMotion }
        .onChange(of: animate) { _, now in
            turned = false
            if now { DispatchQueue.main.async { turned = true } }
        }
        .accessibilityLabel(title)
    }
}

/// ⑤ まとめの明るい紙。画面でも書き出しでも同じものを描く (`width` で大きさを決める)。
struct ImasYearSummarySheet: View {
    struct Row: Hashable {
        let label: String
        let value: String
        let isNumber: Bool
    }

    let imprint: String
    let title: String
    let rows: [Row]
    let accent: Color
    var width: CGFloat = 340

    private var s: CGFloat { width / 340 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accent.frame(height: 8 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(imprint)
                    .font(.imasMono(10 * s))
                    .tracking(1.4 * s)
                    .foregroundStyle(DS.ticketSub)
                Text(title)
                    .font(.imasHeading(22 * s, weight: .heavy))
                    .foregroundStyle(DS.ticketInk)
                    .padding(.top, 4 * s)
                    .padding(.bottom, 12 * s)
                Rectangle().fill(DS.ticketInk).frame(height: 2 * s)
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).font(.imasScaled(13 * s)).foregroundStyle(DS.ticketInk)
                        Spacer(minLength: 8 * s)
                        Text(row.value)
                            .font(row.isNumber ? .imasDisplay(22 * s) : .imasScaled(13 * s, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(DS.ticketInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.vertical, 8 * s)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.ticketDash).frame(height: 1) }
                }
                Spacer(minLength: 12 * s)
                Text("IDOL LIVE DB")
                    .font(.imasMono(9 * s))
                    .tracking(2 * s)
                    .foregroundStyle(DS.ticketSub)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(18 * s)
        }
        .frame(width: width, height: width * 1.25)
        .background(DS.ticket)
    }
}

/// 物語のページの地 (暗い板)。上に進み具合、下に中身。
struct ImasYearReportBoard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, DS.Space.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.board)
        .environment(\.colorScheme, .dark)
    }
}

extension Text {
    /// 物語のページの刻印 (「2026 · 参加公演」)。
    func imasYearImprint() -> some View {
        font(.imasMono(11)).tracking(1.5).foregroundStyle(DS.boardDim)
    }

    /// 物語のページの題。
    func imasYearTitle() -> some View {
        font(ImasYearReportStyle.title).foregroundStyle(DS.boardInk).fixedSize(horizontal: false, vertical: true)
    }

    /// 暗い板の上の添え書き。
    func imasYearNote() -> some View {
        font(.imasFootnote).foregroundStyle(DS.boardDim)
    }
}
