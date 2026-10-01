import SwiftUI

// =============================================================================
// カード・タイル・メーター (docs/DESIGN_SYSTEM.md §6.3〜§6.5・§10.4)
//
// ImasFeatureCard  ハブの最上段で「いま一番大事なもの」を 1 枚で。地は実体色。
// ImasEntryCard    奥の画面への入口を大きく見せる。
// ImasStatTile     数のタイル。`ImasStatGrid` で 2 列 (3 個なら 3 列) に並べる。
// ImasStatBar      項目ごとの割合の横棒。
// ImasProgressRing 1 つの割合を大きく。
// =============================================================================

// MARK: - 主役のカード

/// ハブの最上段で「いま一番大事なもの」を 1 枚で見せる (担当・次のライブ・開催中のお題・つづきから)。
/// 地は実体のごく薄い色。固定のグラデーションは使わない。横幅はいつも画面いっぱい。
struct ImasFeatureCard<Media: View>: View {
    struct Action {
        let title: String
        var systemImage: String? = nil
        let action: () -> Void
    }

    /// 上の目印 (「担当」「参加予定・あと 37 日」)。実体色の太字。
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    var primary: Action? = nil
    var secondary: Action? = nil
    @ViewBuilder var media: Media

    var body: some View {
        FeatureCardBody(eyebrow: eyebrow, title: title, subtitle: subtitle,
                        primary: primary, secondary: secondary, media: media)
            .imasTheme(seed: seed, brand: brand)
    }
}

extension ImasFeatureCard where Media == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil, seed: String? = nil,
         brand: String? = nil, primary: Action? = nil, secondary: Action? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, seed: seed, brand: brand,
                  primary: primary, secondary: secondary) { EmptyView() }
    }
}

private struct FeatureCardBody<Media: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    let primary: ImasFeatureCard<Media>.Action?
    let secondary: ImasFeatureCard<Media>.Action?
    let media: Media

    @Environment(\.imasTheme) private var theme

    var body: some View {
        ImasCard(style: .tinted) {
            VStack(alignment: .leading, spacing: DS.Space.card) {
                HStack(alignment: .center, spacing: DS.Space.gapLoose + 2) {
                    media
                    VStack(alignment: .leading, spacing: DS.Space.gapTight) {
                        if let eyebrow {
                            Text(eyebrow)
                                .font(ImasTextRole.eyebrow.font)
                                .foregroundStyle(theme.isNeutral ? DS.ink2 : theme.accent)
                        }
                        Text(title)
                            .font(.imasTitle3.weight(.bold))
                            .foregroundStyle(DS.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle {
                            Text(subtitle).imasText(.rowSubtitle).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if primary != nil || secondary != nil {
                    HStack(spacing: DS.Space.gap) {
                        if let primary {
                            button(primary).buttonStyle(.imas(.primary, size: .medium, fillsWidth: true))
                        }
                        if let secondary {
                            button(secondary).buttonStyle(.imas(.secondary, size: .medium, fillsWidth: true))
                        }
                    }
                }
            }
        }
    }

    private func button(_ a: ImasFeatureCard<Media>.Action) -> Button<some View> {
        Button(action: a.action) {
            if let s = a.systemImage { Label(a.title, systemImage: s) } else { Label { Text(a.title) } icon: { EmptyView() } }
        }
    }
}

// MARK: - 入口のカード

/// 奥の画面への入口を大きく見せる。一覧で十分なら `ImasNavRow`。
struct ImasEntryCard: View {
    let systemImage: String
    let title: String
    var preview: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    /// 押してから外へ飛ぶまでの待ち。矢印をくるくるに替える。
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: DS.Space.gapLoose + 2) {
            ImasIconTile(systemImage: systemImage, size: .s44, tone: .themed, seed: seed, brand: brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).imasText(.cardTitle)
                if let preview {
                    Text(preview).imasText(.note).lineLimit(2)
                }
            }
            Spacer(minLength: DS.Space.gap)
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                ImasRowChevron()
            }
        }
        .padding(DS.Space.card)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
    }
}

// MARK: - 数のタイル

/// 数のタイル。記号 + 数 + 単位 + 名前。奥へ行けるときは右上に矢印。
struct ImasStatTile: View {
    let systemImage: String
    let value: String
    var unit: String? = nil
    let label: String
    var seed: String? = nil
    var brand: String? = nil
    var tappable: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ImasIconTile(systemImage: systemImage, size: .s28, tone: .themed, seed: seed, brand: brand)
                Spacer(minLength: 0)
                if tappable { ImasRowChevron() }
            }
            // 金額のように桁が伸びる値でも折り返さない (タイルの高さが揃わなくなる)。
            ImasMetric(value: value, unit: unit, size: .large)
            Text(label).imasText(.rowSubtitle).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.card)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 数のタイルを 2 列 (3 個なら 3 列) に並べる。
struct ImasStatGrid<Content: View>: View {
    var columns: Int = 2
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.gap), count: columns),
                  spacing: DS.Space.gap) {
            content
        }
    }
}

// MARK: - 割合の横棒

/// 項目ごとの割合 (ブランド別の回収率など)。
struct ImasStatBar: View {
    let label: String
    let value: String
    /// 0〜100。
    let percent: Double
    var seed: String? = nil
    var brand: String? = nil
    /// 右端の値の幅。金額のように桁が伸びる値は広げる。
    var valueWidth: CGFloat = 52

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        HStack(spacing: DS.Space.gapLoose) {
            HStack(spacing: 7) {
                Circle().fill(t.dot).frame(width: 8, height: 8)
                Text(label).font(.imasFootnote).foregroundStyle(DS.ink).lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(t.accent).frame(width: geo.size.width * min(1, max(0, percent / 100)))
                }
            }
            .frame(height: 8)
            Text(value)
                .font(ImasNumeralSize.small.font)
                .foregroundStyle(DS.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .padding(.vertical, DS.Space.gap)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 割合の輪

/// 1 つの割合を大きく見せる輪 (回収率・習熟度)。中央に % を出す。
struct ImasProgressRing: View {
    /// 0〜1。
    let fraction: Double
    var size: CGFloat = 92
    var lineWidth: CGFloat = 10
    var seed: String? = nil
    var brand: String? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        let clamped = min(1, max(0, fraction))
        ZStack {
            Circle().stroke(DS.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(t.isNeutral ? DS.sys : t.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))%")
                .font(Font.imasScaled(size * 0.24, weight: .heavy).width(.condensed).monospacedDigit())
                .foregroundStyle(DS.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(Int((clamped * 100).rounded()))パーセント")
    }
}
