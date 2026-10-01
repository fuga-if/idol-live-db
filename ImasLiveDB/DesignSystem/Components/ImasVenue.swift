import SwiftUI

// =============================================================================
// 会場とチケットの部品 (docs/DESIGN_SYSTEM.md §1・§10.5)
//
// ImasTicketShape   切り取り線の両端に半円の切り欠きがある紙の形。
// ImasPerforation   切り取り線 (点線)。
// ImasPunchHole     パンチ穴。回収・参加の小さな印。
// ImasStampMark     ジャケの角に押す小さな判子。回収の印。
// ImasTicket        紙のチケット。次のライブ・次の出演。右の半券に「あと 37 DAYS」。
// ImasBoard         電光掲示板。記録や出演の数を暗い板に細長い数字で。
// ImasMasthead      画面の頭の印字の行 (「PRODUCE · 2026.10.01 THU」)。
//
// チケットの紙 (`DS.ticket`) はダークでも明るいまま。暗い客席で手元のチケットだけが白く見える。
// =============================================================================

// MARK: - 紙の形

/// チケットの形。角丸の四角に、切り取り線の両端の半円の切り欠き。
struct ImasTicketShape: Shape {
    enum Cut: Equatable {
        /// 縦の切り取り線。右端からの距離 (半券の幅)。
        case vertical(fromTrailing: CGFloat)
        /// 横の切り取り線。上端からの距離。
        case horizontal(fromTop: CGFloat)
        /// 縦の切り取り線。左端からの距離 (半券の行の日付の幅)。
        case verticalFromLeading(CGFloat)
        case none
    }

    var cornerRadius: CGFloat
    var cut: Cut
    var notchRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let base = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        let r = notchRadius
        var notches = Path()
        switch cut {
        case .vertical(let d):
            let x = rect.maxX - d
            notches.addEllipse(in: CGRect(x: x - r, y: rect.minY - r, width: r * 2, height: r * 2))
            notches.addEllipse(in: CGRect(x: x - r, y: rect.maxY - r, width: r * 2, height: r * 2))
        case .verticalFromLeading(let d):
            let x = rect.minX + d
            notches.addEllipse(in: CGRect(x: x - r, y: rect.minY - r, width: r * 2, height: r * 2))
            notches.addEllipse(in: CGRect(x: x - r, y: rect.maxY - r, width: r * 2, height: r * 2))
        case .horizontal(let d):
            let y = rect.minY + d
            notches.addEllipse(in: CGRect(x: rect.minX - r, y: y - r, width: r * 2, height: r * 2))
            notches.addEllipse(in: CGRect(x: rect.maxX - r, y: y - r, width: r * 2, height: r * 2))
        case .none:
            return base
        }
        return base.subtracting(notches)
    }
}

// MARK: - 切り取り線

/// 切り取り線 (点線)。チケットの半券の境目・セトリや申込書の欄の区切り。
struct ImasPerforation: View {
    enum Axis { case horizontal, vertical }

    var axis: Axis = .horizontal
    /// 線の色。チケットの紙の上は `DS.ticketDash`、面の上は `DS.perforation`。
    var color: Color = DS.perforation
    var lineWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            Path { p in
                switch axis {
                case .horizontal:
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                case .vertical:
                    p.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [lineWidth * 3, lineWidth * 3]))
        }
        .frame(width: axis == .vertical ? max(lineWidth, 1) : nil,
               height: axis == .horizontal ? max(lineWidth, 1) : nil)
        .accessibilityHidden(true)
    }
}

// MARK: - 穴と判子

/// パンチ穴。回収した曲・参加した公演の小さな印。
///
/// 紙に開いた穴なので、ライトは下の暗い客席が、ダークは照明が透けて明るく見える。
/// 意味は読み上げで伝える (`label`)。
struct ImasPunchHole: View {
    enum Size {
        case small, regular

        var diameter: CGFloat { self == .small ? 10 : 13 }
    }

    var size: Size = .regular
    var label: String? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .fill(DS.hole.shadow(.inner(color: .black.opacity(scheme == .dark ? 0.45 : 0.55), radius: 1.2, y: 1.5)))
            .frame(width: size.diameter, height: size.diameter)
            .shadow(color: scheme == .dark ? DS.hole.opacity(0.3) : .clear, radius: 4)
            .accessibilityElement()
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
    }
}

/// ジャケの角に押す小さな判子 (回収)。ジャケが出る所ならどこでも同じ印で通す。
///
/// 下の面の色で縁を抜くので、置く面の色を `under` に渡す (既定は面)。
struct ImasStampMark: View {
    var diameter: CGFloat = 20
    var under: Color = DS.surface

    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    var body: some View {
        let d = diameter * scale
        Image(systemName: "checkmark")
            .font(.system(size: d * 0.46, weight: .black))
            .foregroundStyle(DS.stamp)
            .frame(width: d, height: d)
            .background(Circle().fill(under))
            .overlay(Circle().strokeBorder(DS.stamp, lineWidth: max(1.4, d * 0.08)))
            .rotationEffect(.degrees(-12))
            .accessibilityLabel("回収済み")
    }
}

// MARK: - チケット

/// 紙のチケット。次のライブ・次の出演・参加を記録するときの公演。
///
/// 構成は [ペンライト + 印字の目印] / [題 (18pt 極太・詰め組み)] / [日付・会場の行] と、
/// 右の半券の「あと 37 DAYS」。紙はダークでも明るい。押すとその公演へ。
struct ImasTicket: View {
    struct Countdown: Equatable {
        var prefix: String = "あと"
        let value: String
        var unit: String = "DAYS"
    }

    /// 目印 (「参加予定」「次の出演」)。前に「ADMIT ONE ·」のような印字を付けたいときは `imprint`。
    let label: String
    var imprint: String? = "ADMIT ONE"
    let title: String
    /// 日付・会場などの行。先頭の印字 (「11.07 SAT」) は `metaImprint` に。
    var metaImprint: String? = nil
    var meta: String? = nil
    /// ペンライトの色の手がかり (公演のブランド・担当)。無ければペンライトを出さない。
    var seed: String? = nil
    var brand: String? = nil
    var countdown: Countdown? = nil
    var onOpen: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var stubWidth: CGFloat = 96

    /// チケットの紙は明るいので、ダークでもライト用の色でペンライトを点ける。
    private var penlight: Color? {
        guard seed != nil || brand != nil else { return nil }
        return ImasTheme.derive(seed: seed, brand: brand, scheme: .light).penlight
    }

    var body: some View {
        let content = HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let penlight { ImasPenlight(color: penlight, size: .regular).environment(\.colorScheme, .light) }
                    Text([imprint, label].compactMap { $0 }.joined(separator: " · "))
                        .imasText(.imprint)
                        .foregroundStyle(DS.ticketSub)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.imasHeading(18, weight: .heavy))
                    .foregroundStyle(DS.ticketInk)
                    .fixedSize(horizontal: false, vertical: true)
                if metaImprint != nil || meta != nil {
                    (Text(metaImprint.map { $0 + (meta == nil ? "" : " · ") } ?? "")
                        .font(.imasMono(11, weight: .medium))
                     + Text(meta ?? "").font(.imasFootnote))
                        .foregroundStyle(DS.ticketSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let countdown {
                ImasPerforation(axis: .vertical, color: DS.ticketDash, lineWidth: 2)
                    .padding(.vertical, 12)
                VStack(spacing: 4) {
                    Text(countdown.prefix).imasText(.imprint).foregroundStyle(DS.ticketSub)
                    Text(countdown.value)
                        .font(ImasNumeralSize.countdown.font)
                        .foregroundStyle(DS.ticketInk)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(countdown.unit).imasText(.imprint).foregroundStyle(DS.ticketSub)
                }
                .frame(width: stubWidth)
                .padding(.vertical, 10)
            }
        }
        .background(DS.ticket, in: ImasTicketShape(cornerRadius: 14,
                                                    cut: countdown == nil ? .none : .vertical(fromTrailing: stubWidth + 1)))
        .compositingGroup()
        .shadow(color: .black.opacity(0.06), radius: 9, y: 4)
        .accessibilityElement(children: .combine)

        if let onOpen {
            Button(action: onOpen) { content }
                .buttonStyle(.imasPress)
        } else {
            content
        }
    }
}

// MARK: - 電光掲示板

/// 電光掲示板。記録や出演の数を、暗い板に細長い太字の数字で並べる。
///
/// 上の行は印字 (「STATS」「2005 — 2026」)。数は 2〜4 個。ライトでもダークでも板は暗い。
struct ImasBoard: View {
    struct Cell: Identifiable, Hashable {
        var id: String { label }
        let value: String
        var unit: String? = nil
        let label: String
    }

    var title: String? = nil
    var trailing: String? = nil
    let cells: [Cell]
    var onSelect: ((Cell) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || trailing != nil {
                HStack {
                    if let title { Text(title).imasText(.imprint).foregroundStyle(DS.boardDim) }
                    Spacer(minLength: 8)
                    if let trailing { Text(trailing).imasText(.imprint).foregroundStyle(DS.boardDim) }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                Rectangle().fill(DS.boardLine).frame(height: 1)
            }
            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    if index > 0 {
                        Rectangle().fill(DS.boardLine).frame(width: 1).padding(.vertical, 10)
                    }
                    cellView(cell)
                }
            }
        }
        .background(DS.board, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func cellView(_ cell: Cell) -> some View {
        let body = VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(cell.value)
                    .font(ImasNumeralSize.large.font)
                    .foregroundStyle(DS.boardInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit = cell.unit {
                    Text(unit).font(.imasCaption2.weight(.semibold)).foregroundStyle(DS.boardDim)
                }
            }
            Text(cell.label)
                .font(.imasCaption2)
                .foregroundStyle(DS.boardDim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)

        if let onSelect {
            Button { onSelect(cell) } label: { body.contentShape(Rectangle()) }
                .buttonStyle(.imasPress)
        } else {
            body
        }
    }
}

// MARK: - 頭の印字

/// 画面の頭の印字の行 (「PRODUCE · 2026.10.01 THU」「SETLIST · DAY2」)。大きな題の上に置く。
struct ImasMasthead: View {
    let items: [String]

    init(_ items: String...) { self.items = items }
    init(items: [String]) { self.items = items }

    var body: some View {
        Text(items.joined(separator: " · "))
            .imasText(.imprint)
            .lineLimit(1)
            .accessibilityHidden(true)
    }
}
