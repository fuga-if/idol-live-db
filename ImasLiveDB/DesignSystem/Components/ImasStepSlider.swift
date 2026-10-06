import SwiftUI

// =============================================================================
// ImasStepSlider 段のついた横のスライダー。少数 (2〜5) の段から 1 つを、指で引いて選ぶ。
//
// 用途   段に順序のある値 (担当ブランドの「なし / 担当 / メイン」など)。並びが「弱い → 強い」の向きを持つもの。
// 使わない 順序の無い選択肢 → `ImasSegmented` / 大きな札で選ぶ → `ImasChoiceCards` / オンオフ → `ImasToggleRow`。
// 構成   墨の細い溝に段の目盛り (小さな丸)、選んだ段までを実体の色 (無ければ墨) で埋め、つまみ (紙の丸に色の縁) を置く。
//        段の名前は目盛りの下に並べ、選んだ段だけ墨の太字。
// 操作   引くとつまみが指に付いてきて、段をまたぐたびに触覚を返し、離すと近い段に吸い付く。目盛りや名前を押しても選べる。
//        VoiceOver では調整できる値 (上下のスワイプで 1 段ずつ) として読む。
// 種類   `ImasStepSlider` (スライダーだけ) / `ImasStepSliderRow` (行頭の色の帯 + 題 + スライダーの 1 行。設定の一覧用)。
// 状態   段 0 は溝だけ (埋めない)。
// =============================================================================

struct ImasStepSlider: View {
    /// 段の名前 (左から)。
    let steps: [String]
    @Binding var index: Int
    /// 読み上げの題 (「765AS の担当」)。
    let accessibilityLabel: String
    var seed: String? = nil
    var brand: String? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme
    /// 引いている間のつまみの位置 (溝の左端からの距離)。離したら nil に戻して段に吸い付かせる。
    @State private var dragX: CGFloat?
    @ScaledMetric(relativeTo: .body) private var thumb: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var tick: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var groove: CGFloat = 4

    private var last: Int { max(steps.count - 1, 1) }

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        let accent: Color = t.isNeutral ? DS.sys : t.accent
        VStack(spacing: DS.Space.gapTight) {
            GeometryReader { geo in
                let inset = thumb / 2
                let width = max(geo.size.width - thumb, 1)
                let stepX = { (i: Int) in inset + width * CGFloat(i) / CGFloat(last) }
                let x = dragX.map { min(max($0, inset), inset + width) } ?? stepX(index)
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.line)
                        .frame(height: groove)
                        .padding(.horizontal, inset)
                    Capsule().fill(accent)
                        .frame(width: max(x - inset, 0), height: groove)
                        .offset(x: inset)
                    ForEach(steps.indices, id: \.self) { i in
                        Circle()
                            .fill(stepX(i) <= x + 0.5 ? accent : DS.line)
                            .frame(width: tick, height: tick)
                            .position(x: stepX(i), y: geo.size.height / 2)
                    }
                    Circle()
                        .fill(DS.surface)
                        .overlay(Circle().strokeBorder(index == 0 && dragX == nil ? DS.ink3 : accent,
                                                       lineWidth: groove))
                        .frame(width: thumb, height: thumb)
                        .position(x: x, y: geo.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragX = value.location.x
                            let nearest = Int(((value.location.x - inset) / width * CGFloat(last)).rounded())
                            let clamped = min(max(nearest, 0), steps.count - 1)
                            if clamped != index { index = clamped }
                        }
                        .onEnded { _ in
                            withAnimation(.imasStandard) { dragX = nil }
                        }
                )
            }
            .frame(height: thumb)
            HStack(spacing: 0) {
                ForEach(steps.indices, id: \.self) { i in
                    Button {
                        withAnimation(.imasStandard) { index = i }
                    } label: {
                        Text(steps[i])
                            .imasText(.meta, color: i == index ? DS.ink : DS.ink3)
                            .fontWeight(i == index ? .bold : .regular)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: alignment(i))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(steps.indices.contains(index) ? steps[index] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(index + 1, steps.count - 1)
            case .decrement: index = max(index - 1, 0)
            @unknown default: break
            }
        }
    }

    /// 端の段の名前は端に寄せ、間の段は真ん中 (目盛りの真下に来るように)。
    private func alignment(_ i: Int) -> Alignment {
        if i == 0 { return .leading }
        if i == steps.count - 1 { return .trailing }
        return .center
    }
}

/// 行頭の色の帯 + 題 + 段のついたスライダーの 1 行 (設定の一覧で、ものごとに段を決める)。
struct ImasStepSliderRow: View {
    let title: String
    let steps: [String]
    @Binding var index: Int
    var seed: String? = nil
    var brand: String? = nil

    @ScaledMetric(relativeTo: .body) private var sliderWidth: CGFloat = 188

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.rowGap) {
            ImasLeadBar(seed: seed, brand: brand)
                .frame(height: DS.Size.touch)
            Text(title)
                .imasText(.rowTitle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            ImasStepSlider(steps: steps, index: $index, accessibilityLabel: "\(title)の担当",
                           seed: seed, brand: brand)
                .frame(width: sliderWidth)
        }
        .padding(.horizontal, DS.Space.rowH)
        .padding(.vertical, DS.Space.rowVCompact)
        .frame(minHeight: DS.Size.touch)
    }
}
