import SwiftUI

// =============================================================================
// チップ (docs/DESIGN_SYSTEM.md §8.2)
//
// 用途      ImasChip         情報の小さな札 (押せない)。ブランド・種類・タグ
//           ImasFilterChip   押すと選択が切り替わる。絞り込み・カテゴリ・歌唱メンバーの予想
//           ImasRemovableChip 押すと外れる。効いている絞り込み・選んだもの
// 使わない  状態を示す小さい札 (参加済・ユニット・NEW) → ImasBadge /
//           操作のボタン → ImasButton
// 構成      [先頭 (ペンライト・記号・アイコン、任意)] [文言] [× (Removable のみ)]
// 寸法      高さ 32、角丸 8 の四角 (カプセルにしない)、文字 14pt 中太、左右 12。
// 状態      未選択 (線) / 選択 (墨の塗り。ペンライトはそのまま光る) / 押下 / 無効 (薄く)
// 色        地は墨と灰だけ。アイドル・ブランドの色は先頭のペンライトに出す。
//           淡い色の地 (v1) は使わない。
// =============================================================================

/// チップの先頭に置けるもの。
enum ImasChipLeading {
    /// SF Symbols の記号。
    case symbol(String)
    /// ペンライト (アイドル・ブランドの色)。
    case dot
    /// アイドルのアイコン (22)。写真があれば写真、無ければ判子。
    case avatar(label: String, imageURL: URL? = nil)
    /// 読み込んだブランドのロゴ (端末の中のファイル、20 の丸)。
    case logo(URL)
}

enum ImasChipStyle {
    /// 線 + ペンライト。実体に属する情報 (ブランド・ユニット)。
    case themed
    /// 墨の塗り。選んだもの。
    case selected
    /// 灰の地。目立たせない情報。
    case neutral
    /// 線だけ。押すとその画面へ行くチップ (最近見た・関連) と、選んでいない切り替え。
    case outlined
}

/// 情報の小さな札 (押せない)。押せるようにするなら `ImasFilterChip`。
struct ImasChip: View {
    let text: String
    var systemImage: String? = nil
    var style: ImasChipStyle = .neutral
    var seed: String? = nil
    var brand: String? = nil
    /// 実体色そのもの (ユーザーが選んだタグ色等)。指定すると seed/brand より優先し、
    /// 素の色を塗らずに WCAG の計算を通す (どんな明るさでも文字が読める側に倒れる)。
    var color: Color? = nil
    /// グリッド内で幅を揃えたいとき true。
    var fillsWidth: Bool = false
    var leading: ImasChipLeading? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: color, env: envTheme, scheme: scheme)
        let c = ImasChipColors.colors(style: style)
        let shape = RoundedRectangle(cornerRadius: DS.rControl(DS.Size.chip), style: .continuous)
        let lead = leading ?? systemImage.map(ImasChipLeading.symbol) ?? (style == .themed ? .dot : nil)
        HStack(spacing: 6) {
            ImasChipLeadingView(
                leading: lead,
                theme: t,
                penlight: style == .selected
                    ? ImasChipColors.penlightOnInk(seed: seed, brand: brand, color: color, fallback: t, scheme: scheme)
                    : t.penlight
            )
            Text(text)
                .font(ImasTextRole.chip.font)
                .lineLimit(1)
        }
        .padding(.leading, lead == nil ? 12 : 10)
        .padding(.trailing, 12)
        .frame(minHeight: DS.Size.chip)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .foregroundStyle(c.fg)
        .background(c.bg, in: shape)
        .overlay { if let stroke = c.stroke { shape.strokeBorder(stroke, lineWidth: 1) } }
        .contentShape(shape)
    }
}

/// 押して選択を切り替えるチップ。フィルタ・カテゴリ・種別・タグ・歌唱メンバーの予想の「唯一の正」。
///
/// 以前は画面ごとに 19 種の自前実装があり、角丸・フォント・余白がバラバラだった。
/// 見た目は `ImasChip` と同一で、押下と選択状態だけを足す。
struct ImasFilterChip: View {
    let text: String
    var systemImage: String? = nil
    let isSelected: Bool
    var seed: String? = nil
    var brand: String? = nil
    var color: Color? = nil
    var fillsWidth: Bool = false
    var isDisabled: Bool = false
    var leading: ImasChipLeading? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ImasChip(
                text: text,
                systemImage: systemImage,
                style: isSelected ? .selected : .outlined,
                seed: seed,
                brand: brand,
                color: color,
                fillsWidth: fillsWidth,
                leading: leading
            )
        }
        .buttonStyle(.imasPress)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 押すと外れるチップ。効いている絞り込み・選んだものを見せて、その場で外させる。
struct ImasRemovableChip: View {
    let text: String
    var seed: String? = nil
    var brand: String? = nil
    var leading: ImasChipLeading? = nil
    let onRemove: () -> Void

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: DS.rControl(DS.Size.chip), style: .continuous)
        // 色のある絞り込み (ブランド・アイドル) は何も渡さなくてもペンライトを出す。
        let lead = leading ?? ((seed != nil || brand != nil) ? .dot : nil)
        Button(action: onRemove) {
            HStack(spacing: 6) {
                ImasChipLeadingView(leading: lead, theme: t, penlight: t.penlight)
                Text(text).font(ImasTextRole.chip.font).lineLimit(1)
                Image(systemName: "xmark")
                    .font(.imasScaled(10, weight: .bold))
                    .foregroundStyle(DS.ink2)
            }
            .padding(.leading, lead == nil ? 12 : 10)
            .padding(.trailing, 10)
            .frame(minHeight: DS.Size.chip)
            .foregroundStyle(DS.ink)
            .background(DS.fill, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.imasPress)
        .accessibilityLabel("\(text) を外す")
    }
}

// MARK: - 並べ方

/// `ImasChipRow` の端の透かしの寸法 (総称型の中には static な値を置けないので外に出す)。
private enum ImasChipRowFade {
    static let coordinateSpace = "imasChipRowFade"
    static let width: CGFloat = 18
    static let tolerance: CGFloat = 2
}

/// チップを 1 段で横に並べ、はみ出したら横にスクロールする。2 段以上にはしない。
/// `fades: true` で、隠れている側の端をグラデーションで透かして「続きがある」ことを示す
/// (先に続きがある側だけ小さい chevron も重ねる。カテゴリの絞り込み列などで使う)。
struct ImasChipRow<Content: View>: View {
    var fades: Bool = false
    @ViewBuilder var content: Content

    @State private var contentFrame: CGRect = .zero
    @State private var viewportWidth: CGFloat = 0

    private var showsLeading: Bool { contentFrame.minX < -ImasChipRowFade.tolerance }
    private var showsTrailing: Bool { contentFrame.maxX > viewportWidth + ImasChipRowFade.tolerance }

    var body: some View {
        let scroller = ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.gap) { content }
                .padding(.horizontal, DS.Space.screen)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(ImasChipRowFade.coordinateSpace))
                } action: { contentFrame = $0 }
        }
        .scrollClipDisabled()
        .coordinateSpace(name: ImasChipRowFade.coordinateSpace)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }

        if fades {
            scroller
                .mask(fadeMask)
                .overlay(alignment: .trailing) {
                    if showsTrailing {
                        Image(systemName: "chevron.compact.right")
                            .imasText(.meta)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.imasStandard, value: showsLeading)
                .animation(.imasStandard, value: showsTrailing)
        } else {
            scroller
        }
    }

    /// 続きがある側だけ透明に落とすアルファマスク (色は不可視なので固定黒で問題ない)。
    private var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(showsLeading ? 0 : 1), .black],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: ImasChipRowFade.width)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(showsTrailing ? 0 : 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: ImasChipRowFade.width)
        }
    }
}

/// チップを幅で折り返して並べる。
struct ImasChipFlow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: DS.Space.gap) { content }
    }
}

// MARK: - 選択の印

/// ピッカー・複数選択の印。複数選択 = ○ と塗りの ✓、1 つ選択 = ✓ だけ。
/// 色は実体の accent (無ければ白黒)。
struct ImasSelectionMark: View {
    let isSelected: Bool
    var seed: String? = nil
    var brand: String? = nil
    var color: Color? = nil
    var size: CGFloat = 20
    /// 1 つだけ選ぶ一覧では ○ を出さず、選んだ行にだけ ✓ を出す。
    var isSingle: Bool = false

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: color, env: envTheme, scheme: scheme)
        let accent: Color = t.isNeutral ? DS.sys : t.accent
        Group {
            if isSingle {
                Image(systemName: "checkmark")
                    .font(.imasScaled(size * 0.8, weight: .bold))
                    .foregroundStyle(accent)
                    .opacity(isSelected ? 1 : 0)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.imasScaled(size, weight: .regular))
                    .foregroundStyle(isSelected ? accent : DS.ink3)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }
}

// MARK: - 受賞の札

/// 「みんなの投票」終了お題での順位。優勝 = 墨の塗り + 金の冠、入賞 (2〜3 位) = 線 + 金の記章。
/// チップと同じ寸法で、曲詳細・アイドル詳細のヒーローに並べる。
struct ImasAwardChip: View {
    let title: String
    let rank: Int

    private var isWinner: Bool { rank == 1 }
    private var rankLabel: String { isWinner ? "優勝" : "第\(rank)位" }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.rControl(DS.Size.chip), style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: isWinner ? "crown.fill" : "rosette")
                .font(.imasScaled(12, weight: .semibold))
                .foregroundStyle(DS.favorite)
            Text("\(title) \(rankLabel)")
                .font(ImasTextRole.chip.font)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: DS.Size.chip)
        .foregroundStyle(isWinner ? DS.onSys : DS.ink)
        .background(isWinner ? DS.sys : Color.clear, in: shape)
        .overlay { if !isWinner { shape.strokeBorder(DS.line, lineWidth: 1) } }
        .accessibilityLabel("\(title) で\(rankLabel)")
    }
}

// MARK: - 内部

/// チップの先頭。
private struct ImasChipLeadingView: View {
    let leading: ImasChipLeading?
    /// アイコンの色 (チップの実体の色)。
    let theme: ImasTheme
    /// ペンライトの色 (墨の塗りの上では明るい側の色)。
    let penlight: Color

    var body: some View {
        switch leading {
        case .none:
            EmptyView()
        case .symbol(let name):
            Image(systemName: name).font(.imasScaled(12, weight: .semibold))
        case .dot:
            // 色の点は出さない (幅を取るだけで、名前が何かを言っている)。
            EmptyView()
        case .avatar(let label, let url):
            // 写真があれば写真、無ければ判子 (アイコンは消さない)。
            ImasAvatar(label: label, seed: nil, size: 22, imageURL: url, reservesPickRing: false)
                .environment(\.imasTheme, theme)
                .padding(.leading, -4)
        case .logo(let url):
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    .padding(.leading, -3)
                    .accessibilityHidden(true)
            } else {
                EmptyView()
            }
        }
    }
}

/// チップ家族の色の決め方 (明示の色 → seed/brand → 環境の実体色)。
enum ImasChipColors {
    static func theme(seed: String?, brand: String?, color: Color?, env: ImasTheme, scheme: ColorScheme) -> ImasTheme {
        if let color { return ImasTheme.derive(colorSeed: color, scheme: scheme) }
        if seed != nil || brand != nil { return ImasTheme.derive(seed: seed, brand: brand, scheme: scheme) }
        return env
    }

    /// 墨の塗り (選択) の上のペンライト。塗りは画面と逆の明るさなので、逆の明るさ用の色を引く
    /// (ライトの紺は黒い塗りの上で沈む)。
    static func penlightOnInk(seed: String?, brand: String?, color: Color?, fallback: ImasTheme,
                              scheme: ColorScheme) -> Color {
        let inverse: ColorScheme = scheme == .dark ? .light : .dark
        if let color { return ImasTheme.derive(colorSeed: color, scheme: inverse).penlight }
        if seed != nil || brand != nil { return ImasTheme.derive(seed: seed, brand: brand, scheme: inverse).penlight }
        return fallback.isNeutral ? DS.onSys : fallback.penlight
    }

    static func colors(style: ImasChipStyle) -> (bg: Color, fg: Color, stroke: Color?) {
        switch style {
        case .themed: return (.clear, DS.ink, DS.line)
        case .selected: return (DS.sys, DS.onSys, nil)
        case .neutral: return (DS.fill, DS.ink2, nil)
        case .outlined: return (.clear, DS.ink, DS.line)
        }
    }
}
