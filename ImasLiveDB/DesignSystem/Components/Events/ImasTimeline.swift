import SwiftUI

// =============================================================================
// 帯の時間軸 (ガント) (docs/DESIGN_SYSTEM.md §6.7 会場の部品)
//
// 用途: 1 つのライブのチケット受付 (先行・一般・リセール・当日…) の期間を、同じ時間軸の上に
//       横の帯で並べて「いつ何が受付中か・次は何か」を一目で読ませる。
// 使わない場面: 日付が 1 つしかないもの (札か `ImasDateMark`)。月の予定 (月カレンダー)。
// 構成: `ImasTimelineAxis` (上の目盛と「今日」) + 段ごとの `ImasTimelineLane` (受付名 + `ImasTimelineTrack` (帯・当落の◆・
//       今日の朱の線・公演日の点線・目盛の薄い線)) を 1 枚のカードに詰めて重ねる + `ImasTimelineLegend` (記号の凡例)。
//       軸の位置 (0.0〜1.0) はすべて imas-core が計算して渡す (画面で日付の割り算をしない)。
// 種類: 帯の見え方は 3 つ。`.active` 墨の塗り (受付中) / `.ahead` 墨の線 (受付前) /
//       `.past` 灰の塗り (締切後)。色で段階を分けない (§10.1 と同じく、意味は札の文字が言う)。
// 状態: 開始・締切が登録されていない端は閉じずに、切り取り線のような刻みで描く (分からないことを
//       分かったように見せない)。角は丸めない (チケットの帯の硬い縁)。光・影・グラデーションは無い。
// =============================================================================

/// 時間軸の上の 1 点 (目盛・公演日)。`at` は軸の左端 0.0 〜 右端 1.0。
struct ImasTimelineMark: Hashable {
    let at: Double
    let label: String
}

/// 軸の目盛と、全行に引く縦の線 (今日・公演日)。
struct ImasTimelineScale: Hashable {
    var ticks: [ImasTimelineMark]
    /// 今日の位置。範囲の外なら nil。
    var today: Double?
    var shows: [ImasTimelineMark]
}

/// 帯 1 本。
struct ImasTimelineBar: Hashable {
    enum Style: Hashable {
        /// 受付中 (墨の塗り)。
        case active
        /// 受付前 (墨の線)。
        case ahead
        /// 締切後 (灰の塗り)。
        case past
    }

    let start: Double
    let end: Double
    var startOpen = false
    var endOpen = false
    let style: Style
}

/// 上の目盛 (日付) と「今日」の札。
struct ImasTimelineAxis: View {
    let scale: ImasTimelineScale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ImasTimelineLabels(marks: scale.ticks.map { ($0.at, $0.label) }) { label in
                Text(label).font(Font.imasCaption.monospacedDigit()).foregroundStyle(DS.ink3)
            }
            if let today = scale.today {
                ImasTimelineLabels(marks: [(today, "今日")]) { label in
                    Text(label).imasText(.badge, color: DS.stamp)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 帯 1 本ぶんの線路。目盛の薄い線・公演日の点線・今日の朱の線を下敷きに、帯と当落の◆を描く。
struct ImasTimelineTrack: View {
    let scale: ImasTimelineScale
    let bar: ImasTimelineBar?
    /// 当落発表の位置。
    var result: Double? = nil
    /// 当落がまだ先なら塗りの◆、過ぎていれば灰の◆。
    var resultPending = false

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func x(_ at: Double, _ width: CGFloat) -> CGFloat { CGFloat(at) * width }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        // 下敷き: 基線・目盛・公演日
        var base = Path()
        base.move(to: CGPoint(x: 0, y: h / 2))
        base.addLine(to: CGPoint(x: w, y: h / 2))
        context.stroke(base, with: .color(DS.sep), lineWidth: 1)
        for tick in scale.ticks {
            context.fill(Path(CGRect(x: x(tick.at, w), y: 0, width: 1, height: h)), with: .color(DS.sep))
        }
        for show in scale.shows {
            var p = Path()
            p.move(to: CGPoint(x: x(show.at, w), y: 0))
            p.addLine(to: CGPoint(x: x(show.at, w), y: h))
            context.stroke(p, with: .color(DS.ink2), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }

        if let bar { drawBar(bar, in: &context, width: w, height: h) }

        if let result {
            let cx = min(max(x(result, w), h * 0.3), w - h * 0.3)
            let r = h * 0.36
            var diamond = Path()
            diamond.move(to: CGPoint(x: cx, y: h / 2 - r))
            diamond.addLine(to: CGPoint(x: cx + r, y: h / 2))
            diamond.addLine(to: CGPoint(x: cx, y: h / 2 + r))
            diamond.addLine(to: CGPoint(x: cx - r, y: h / 2))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(DS.surface))
            context.fill(diamond.strokedPath(StrokeStyle(lineWidth: 1.5)), with: .color(resultPending ? DS.ink : DS.ink3))
            if resultPending {
                context.fill(diamond.applying(scaleAbout(CGPoint(x: cx, y: h / 2), 0.45)), with: .color(DS.ink))
            }
        }

        if let today = scale.today {
            context.fill(Path(CGRect(x: x(today, w) - 0.75, y: 0, width: 1.5, height: h)), with: .color(DS.stamp))
        }
    }

    private func drawBar(_ bar: ImasTimelineBar, in context: inout GraphicsContext, width w: CGFloat, height h: CGFloat) {
        let barH = h * 0.7
        let y = (h - barH) / 2
        let x0 = x(bar.start, w)
        // 1 日の受付でも見えるよう、最低限の幅を持たせる。
        let x1 = max(x(bar.end, w), x0 + 3)
        // 開いた端は「刻み」で描く: 実線の帯を刻みの長さぶん手前で止め、残りを細い縦の刻みにする。
        let notch: CGFloat = min(12, (x1 - x0) / 3)
        let solidStart = bar.startOpen ? x0 + notch : x0
        let solidEnd = bar.endOpen ? x1 - notch : x1
        let color: Color = bar.style == .past ? DS.ink3 : DS.ink
        let body = CGRect(x: solidStart, y: y, width: max(solidEnd - solidStart, 1), height: barH)
        switch bar.style {
        case .active, .past:
            context.fill(Path(body), with: .color(bar.style == .past ? DS.line : DS.ink))
        case .ahead:
            context.fill(Path(body), with: .color(DS.surface))
            context.stroke(Path(body.insetBy(dx: 0.75, dy: 0.75)), with: .color(DS.ink), lineWidth: 1.5)
        }
        func notches(from a: CGFloat, to b: CGFloat) {
            var cursor = a
            while cursor < b - 1 {
                context.fill(Path(CGRect(x: cursor, y: y, width: 1.5, height: barH)), with: .color(color))
                cursor += 3.5
            }
        }
        if bar.startOpen { notches(from: x0, to: solidStart) }
        if bar.endOpen { notches(from: solidEnd + 2, to: x1) }
    }

    private func scaleAbout(_ c: CGPoint, _ s: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: s, y: s).translatedBy(x: -c.x, y: -c.y)
    }
}

/// 帯の 1 段: 上に受付名 (と段階)、下に線路。段を縦に詰めて重ねるとガントの表になる。
struct ImasTimelineLane: View {
    let title: String
    /// 題の右に薄く添える文字 (段階「受付中」など)。
    var trailing: String? = nil
    let scale: ImasTimelineScale
    let bar: ImasTimelineBar?
    var result: Double? = nil
    var resultPending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.gapTight) {
                Text(title).imasText(.rowSubtitle, color: DS.ink).lineLimit(1)
                Spacer(minLength: DS.Space.gapTight)
                if let trailing { Text(trailing).imasText(.meta) }
            }
            ImasTimelineTrack(scale: scale, bar: bar, result: result, resultPending: resultPending)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 記号の凡例 (受付中の帯・受付前の帯・当落の◆・公演日・今日)。カードの下に 1 行で添える。
struct ImasTimelineLegend: View {
    var body: some View {
        FlowLayout(spacing: DS.Space.gapLoose, lineSpacing: DS.Space.gapTight) {
            item(bar: .init(start: 0.1, end: 0.9, style: .active), "受付中")
            item(bar: .init(start: 0.1, end: 0.9, style: .ahead), "受付前")
            item(bar: .init(start: 0.1, end: 0.9, style: .past), "締切後")
            item(result: 0.5, "当落発表")
            item(scale: .init(ticks: [], today: nil, shows: [.init(at: 0.5, label: "")]), "公演日")
            item(scale: .init(ticks: [], today: 0.5, shows: []), "今日")
        }
        .accessibilityHidden(true)
    }

    private func item(
        bar: ImasTimelineBar? = nil,
        result: Double? = nil,
        scale: ImasTimelineScale = .init(ticks: [], today: nil, shows: []),
        _ label: String
    ) -> some View {
        HStack(spacing: DS.Space.gapTight) {
            ImasTimelineTrack(scale: scale, bar: bar, result: result, resultPending: true)
                .frame(width: 22)
            Text(label).imasText(.meta)
        }
    }
}

/// 軸の位置 (0〜1) に文字を置く。端の文字は枠からはみ出さないよう内側へ寄せる。
private struct ImasTimelineLabels<Label: View>: View {
    let marks: [(Double, String)]
    @ViewBuilder let label: (String) -> Label

    var body: some View {
        // 文字の高さぶんの枠を作り、その上に位置で置く。
        label("0").hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                        let anchor: UnitPoint = mark.0 < 0.08 ? .topLeading : (mark.0 > 0.92 ? .topTrailing : .top)
                        label(mark.1)
                            .fixedSize()
                            .alignmentGuide(.leading) { d in
                                d[anchor == .topLeading ? .leading : (anchor == .topTrailing ? .trailing : HorizontalAlignment.center)]
                                    - CGFloat(mark.0) * geo.size.width
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
    }
}
