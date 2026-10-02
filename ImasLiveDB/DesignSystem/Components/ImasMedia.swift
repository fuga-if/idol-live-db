import Nuke
import NukeUI
import SwiftUI

// =============================================================================
// 画像と印 (docs/DESIGN_SYSTEM.md §10.3)
//
// ImasAvatar       アイドルのアイコン。設定した写真があれば写真、無ければ判子 (紙の白 + 実体色の輪と名前)。
//                  担当は輪を二重にする。アイドルを出す所ではいつも出す (目印として読まれている)。
// ImasIconBadge    アイコンの角に重ねる小さな丸い口 (写真を選ぶ「カメラ」)。
// ImasAvatarStack  歌唱者・出演者のアイコンを重ねて並べる。入り切らない人数は「+N」の丸。
// ImasArtwork      曲のジャケ。角のある四角。画像が無ければ灰の面 + 音符。
// ImasIconTile     記号 1 つ。地を敷かない (記号を淡い色の四角に入れない)。
// ImasSwatch       色の丸 (タグの色・ペンライトの色)。読み上げは色名。
// ImasLeadBar      ライブ・公演・アイドルの行頭の細い帯。
// ImasPerformerChip 歌唱者 1 人 (ペンライト + 名前)。欠席は薄字 + 取り消し線。
// ImasVideoThumbnail 参考動画のサムネ (16:9・角丸・真ん中に再生の記号)。読めなければ灰の面。
// ImasPenlightColorBar ペンライトの色の組を横並びの帯で (等分・角丸)。読み上げは色名の文 (コアが組む)。
//
// 色は seed / brand を渡せばその色、渡さなければ環境の実体色 (`.imasTheme`)。
// =============================================================================

// MARK: - アバター

/// アイドルのアイコン。設定した写真があれば写真、無ければ「判子」にする。
///
/// 判子は紙の白の丸に、実体色の輪と実体色の名前 (詰め組みの太字)。色は輪と文字だけに出す
/// (淡い色の地は敷かない)。担当 (`isPick`) は輪を二重にする (二重丸の判子)。
/// アイドルを出す所 (詳細の頭・名札・行・チップ・セトリの歌唱者) ではいつも出す。写真の有無で消さない。
struct ImasAvatar: View {
    let label: String
    var seed: String?
    var brand: String? = nil
    var size: CGFloat = 40
    var isPick: Bool = false
    var imageURL: URL? = nil
    /// true (既定) のとき、担当の輪の分の外形を isPick に関わらず常に確保する
    /// (担当/非担当が混ざる一覧・格子で占める場所を揃えるため)。
    var reservesPickRing: Bool = true

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    /// 可視のアイコンと外形の間の片側の余白 (担当の外の輪の分)。どの大きさでもこれに収まる。
    static let ringPadding: CGFloat = 5.5

    private var outerSize: CGFloat { reservesPickRing ? size + Self.ringPadding * 2 : size }
    /// 輪の太さ。大きいアイコンほど太く。
    private var ringWidth: CGFloat { size >= 64 ? 2.5 : (size >= 36 ? 1.75 : 1.25) }
    /// 二重の輪の間。
    private var ringGap: CGFloat { size >= 64 ? 3 : 2 }

    var body: some View {
        let t = (seed != nil || brand != nil)
            ? ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
            : envTheme
        ZStack {
            if isPick {
                let d = size + (ringWidth + ringGap) * 2
                Circle()
                    .strokeBorder(t.accent, lineWidth: ringWidth)
                    .frame(width: d, height: d)
            }
            core(t)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(t.accent, lineWidth: ringWidth))
        }
        .frame(width: outerSize, height: outerSize)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func core(_ t: ImasTheme) -> some View {
        if let imageURL {
            let px = Int(size * displayScale)
            LazyImage(url: imageURL) { state in
                if let img = state.image {
                    img.resizable().scaledToFill()
                } else {
                    seal(t)
                }
            }
            .processors([ImageProcessors.Resize(size: CGSize(width: px, height: px), unit: .pixels)])
        } else {
            seal(t)
        }
    }

    /// 判子。名前はアイコンの大きさに対して決める (Dynamic Type で丸からはみ出さないよう固定)。
    private func seal(_ t: ImasTheme) -> some View {
        ZStack {
            DS.paper
            Text(label)
                .font(Font(Font.imasProportionalUIFont(size * 0.34, weight: .bold)))
                .foregroundStyle(t.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, size * 0.1)
        }
    }
}

// MARK: - アイコンの角の口

/// アイコンの角に重ねる小さな丸い口 (写真を選ぶ「カメラ」など)。実体の色で塗り、紙の色で縁取る。
/// 押す動作は画面が包む (`PhotosPicker { ImasIconBadge(...) }`)。
struct ImasIconBadge: View {
    let systemImage: String
    /// 読み上げ (「写真を選ぶ」)。
    var label: String? = nil
    var seed: String? = nil
    var brand: String? = nil
    var size: CGFloat = 26

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        Image(systemName: systemImage)
            .font(.imasScaled(11, weight: .semibold))
            .foregroundStyle(t.isNeutral ? DS.onSys : t.onAccent)
            .frame(width: size, height: size)
            .background(t.isNeutral ? DS.sys : t.accent, in: Circle())
            .overlay(Circle().strokeBorder(DS.surface, lineWidth: 2))
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
    }
}

// MARK: - アイコンの重ね

/// 歌唱者・出演者のアイコンを少しずつ重ねて並べる (同じ集団の合図)。
/// 入り切らない人数は列の最後に「+N」の丸。この丸は人ではなく注記なので、重ねずに少し離して置く。
struct ImasAvatarStack: View {
    /// 読み上げの形。
    enum AccessibilityMode {
        /// 全員の名前を「、」で繋いで読む (既定。セトリの歌唱者など少人数向け)。
        case names
        /// 「<label> N名」で読む (全体曲など大人数の行で、毎行全員を読ませないため)。
        case count(label: String)
    }

    let people: [ImasPerformer]
    var maxVisible: Int = 5
    var size: CGFloat = 26
    /// 押したとき (歌唱者の一覧を開く)。nil なら押せない (親の行のタップに通す)。
    var onTap: (() -> Void)? = nil
    var accessibilityMode: AccessibilityMode = .names

    var body: some View {
        if let onTap {
            stack.contentShape(Rectangle()).onTapGesture(perform: onTap)
                .accessibilityAddTraits(.isButton)
        } else {
            stack
        }
    }

    private var stack: some View {
        HStack(spacing: -(size * 0.4)) {
            ForEach(Array(people.prefix(maxVisible).enumerated()), id: \.element.id) { idx, p in
                ImasAvatar(label: p.iconLabel ?? p.name, seed: p.color, size: size, imageURL: p.imageURL,
                           reservesPickRing: false)
                    .overlay(Circle().strokeBorder(DS.surface, lineWidth: 2))
                    .opacity(p.isAbsent ? 0.4 : 1)
                    .zIndex(Double(maxVisible - idx))
            }
            if people.count > maxVisible {
                Text("+\(people.count - maxVisible)")
                    .font(.imasCaption2.weight(.semibold))
                    .foregroundStyle(DS.ink2)
                    .frame(width: size, height: size)
                    .background(DS.fill, in: Circle())
                    .padding(.leading, size * 0.4 + DS.Space.gapTight)
                    .zIndex(Double(maxVisible + 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch accessibilityMode {
        case .names: return people.map(\.name).joined(separator: "、")
        case .count(let label): return "\(label) \(people.count)名"
        }
    }
}

// MARK: - ジャケ

/// 曲のジャケ。実画像があれば表示、無ければブランド色の面 + 曲名 (色の手がかりが無ければ灰の面 + 記号)。
/// 回収は印にしない (ジャケに判子を押さない。2026-10-02 ユーザーの決まり)。
/// `previewURL` を渡すと試聴の再生/停止オーバーレイが点き、タップで `onPreview` を呼ぶ
/// (再生状態そのものはアプリ側が持つので `isPreviewing` で渡す)。
struct ImasArtwork: View {
    let title: String
    var seed: String?
    var brand: String? = nil
    var size: CGFloat = 48
    var imageURL: URL? = nil
    /// 詳細の頭の大きいジャケ。レコードのスリーブのように紙から浮かせる (影)。
    var isElevated: Bool = false
    /// 画像が無いときの記号。曲は音符のまま、円盤など曲以外の実体はそれぞれの記号に替える。
    var fallbackSystemImage: String = "music.note"
    /// 試聴できる音源の URL。nil なら試聴の記号を出さない (タップしても何も起きない)。
    var previewURL: URL? = nil
    /// いま試聴中か (再生中は停止の記号にする)。
    var isPreviewing: Bool = false
    /// タップされたとき (再生/停止の切り替えは呼び出し側が行う)。`previewURL` が無いときは呼ばれない。
    var onPreview: (() -> Void)? = nil

    @Environment(\.colorScheme) private var artworkScheme

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // 試聴 URL が無いときは (アプリ内のほぼ全ての呼び出し) タップの記号を一切付けない。
        // `.onTapGesture` は無条件に付けると、行全体を Button/NavigationLink にしている
        // 呼び出し元でジャケの上だけタップが奪われて遷移しなくなる (他画面への影響が大きい
        // ため、試聴に対応する呼び出し側だけに絞る)。
        if previewURL != nil {
            core(theme).contentShape(Rectangle())
                .onTapGesture { onPreview?() }
                .accessibilityAddTraits(.isButton)
        } else {
            core(theme)
        }
    }

    private var theme: ImasTheme {
        (seed != nil || brand != nil) ? ImasTheme.derive(seed: seed, brand: brand, scheme: scheme) : envTheme
    }

    /// 曲名の読み上げ。試聴の記号はここに積まず `accessibilityLabel`/`Value` に分ける
    /// (「どの曲か」と「いま鳴っているか」は別の情報なので、値の方だけ状態が変わる)。
    private var baseAccessibilityLabel: String { title }

    private var previewAccessibilityLabel: String {
        previewURL != nil ? "\(baseAccessibilityLabel)を試聴" : baseAccessibilityLabel
    }

    private var previewAccessibilityValue: String {
        previewURL != nil ? (isPreviewing ? "再生中" : "停止中") : ""
    }

    private func core(_ t: ImasTheme) -> some View {
        Group {
            if let imageURL {
                let px = Int(size * displayScale)
                LazyImage(url: imageURL) { state in
                    if let img = state.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        fallback(t)
                    }
                }
                .processors([ImageProcessors.Resize(size: CGSize(width: px, height: px), unit: .pixels)])
            } else {
                fallback(t)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DS.rArtwork(size), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rArtwork(size), style: .continuous)
                .strokeBorder(DS.sep, lineWidth: 0.5)
        )
        .shadow(color: isElevated ? .black.opacity(artworkScheme == .dark ? 0.6 : 0.22) : .clear,
                radius: isElevated ? 15 : 0, y: isElevated ? 12 : 0)
        .overlay {
            if previewURL != nil {
                ZStack {
                    if isPreviewing {
                        Color.black.opacity(0.4)
                    }
                    Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                        .font(.imasScaled(max(11, size * 0.25)))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.rArtwork(size), style: .continuous))
                .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(previewAccessibilityLabel)
        .accessibilityValue(previewAccessibilityValue)
    }

    /// ジャケが無い曲。ブランド色 (`seed`/`brand`) が分かるときは実体色の面 + 曲名にする
    /// (合同ライブで曲ごとのブランドが色で分かるのはこれだけが頼りなので、灰に潰さない)。
    /// 色が分からない実体 (アルバム・シリーズの格子など `seed`/`brand` を渡さない呼び出し) は
    /// OS の音楽アプリと同じ灰の面 + 記号のまま。
    private func fallback(_ t: ImasTheme) -> some View {
        ZStack {
            if seed != nil || brand != nil {
                t.accent
                if !title.isEmpty {
                    Text(title)
                        .font(.imasScaled(max(9, size * 0.13), weight: .bold))
                        .foregroundStyle(t.onAccent)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .padding(size * 0.12)
                } else {
                    Image(systemName: fallbackSystemImage)
                        .font(.imasScaled(size * 0.4))
                        .foregroundStyle(t.onAccent.opacity(0.85))
                }
            } else {
                DS.fill
                Image(systemName: fallbackSystemImage)
                    .font(.imasScaled(max(10, size * 0.32), weight: .regular))
                    .foregroundStyle(DS.ink3)
            }
        }
    }
}

// MARK: - 記号の札

/// 記号 1 つ。行の先頭・空状態・入口で同じ大きさにする。地は敷かない
/// (記号を淡い色の角丸四角に入れると、どのアプリにもある見た目になる)。
struct ImasIconTile: View {
    enum Size: CGFloat {
        /// 統計タイル。
        case s28 = 28
        /// 行の先頭 (設定・記録)。
        case s32 = 32
        /// 予定の行。
        case s36 = 36
        /// 入口カード。
        case s44 = 44
        /// 空状態。
        case s56 = 56

        var iconFont: Font {
            switch self {
            case .s28: return .imasScaled(18, weight: .medium)
            case .s32: return .imasScaled(20, weight: .medium)
            case .s36: return .imasScaled(21, weight: .regular)
            case .s44: return .imasScaled(24, weight: .light)
            case .s56: return .imasScaled(34, weight: .ultraLight)
            }
        }
    }

    enum Tone {
        /// 実体の色 (無ければ墨)。
        case themed
        /// 灰。
        case neutral
        /// 墨。
        case solid
        case positive, attention, negative
    }

    let systemImage: String
    var size: Size = .s32
    var tone: Tone = .themed
    var seed: String? = nil
    var brand: String? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasChipColors.theme(seed: seed, brand: brand, color: nil, env: envTheme, scheme: scheme)
        Image(systemName: systemImage)
            .font(size.iconFont)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color(t))
            .frame(width: size.rawValue, height: size.rawValue)
            .accessibilityHidden(true)
    }

    private func color(_ t: ImasTheme) -> Color {
        switch tone {
        case .themed: return t.isNeutral ? DS.ink : t.accent
        case .neutral: return DS.ink2
        case .solid: return DS.ink
        case .positive: return DS.successInk
        case .attention: return DS.warning
        case .negative: return DS.danger
        }
    }
}

// MARK: - 色の丸

/// 色そのものを見せる丸 (タグの色・ペンライトの色・イメージカラー)。
/// 色はデータの値なので hex をそのまま塗る (導出を通さない唯一の部品)。読み上げは色名。
struct ImasSwatch: View {
    enum Size: CGFloat {
        /// 名前の前の点。
        case dot = 8
        /// 行・チップの中。
        case small = 16
        /// 選ぶ・比べる。
        case large = 28
    }

    let hex: String?
    private let diameter: CGFloat
    private let showsRing: Bool
    /// 名前が隣に書いてあり、色名を読み上げなくてよいとき。
    var isDecorative: Bool = false
    /// 選んだ色の丸に墨の輪を付ける (色のグリッドから選ぶ画面)。
    var isSelected: Bool = false

    init(hex: String?, size: Size = .small, isDecorative: Bool = false, isSelected: Bool = false) {
        self.hex = hex
        self.diameter = size.rawValue
        self.showsRing = size != .dot
        self.isDecorative = isDecorative
        self.isSelected = isSelected
    }

    /// 既定の 3 段階に無い寸法が要るとき (他画面の既存の大きさに揃える移行期など)。
    init(hex: String?, diameter: CGFloat, isDecorative: Bool = false, isSelected: Bool = false) {
        self.hex = hex
        self.diameter = diameter
        self.showsRing = diameter > Size.dot.rawValue
        self.isDecorative = isDecorative
        self.isSelected = isSelected
    }

    var body: some View {
        Circle()
            .fill(Color(hexString: hex))
            .overlay(Circle().strokeBorder(isSelected ? DS.ink : DS.sep, lineWidth: isSelected ? 2.5 : (showsRing ? 0.5 : 0)))
            .frame(width: diameter, height: diameter)
            .accessibilityElement()
            .accessibilityLabel(isDecorative ? "" : "カラー: \(ColorAccessibilityName.of(hex))")
            .accessibilityHidden(isDecorative)
    }
}

// MARK: - リードバー

/// 一覧の行頭の控えめな実体色の帯 (ライブ・公演・曲のブランド)。
struct ImasLeadBar: View {
    var seed: String?
    var brand: String? = nil
    /// 合同ライブ等で虹色にする。
    var rainbow: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
        RoundedRectangle(cornerRadius: DS.Size.leadBar / 2, style: .continuous)
            .fill(rainbow
                  ? AnyShapeStyle(ImasStripes.vertical(QS.penlights))
                  : AnyShapeStyle(t.bar))
            .frame(width: DS.Size.leadBar)
            .accessibilityHidden(true)
    }
}

// MARK: - 歌唱者

/// 歌唱者 1 人。ペンライト + 名前。欠席は薄字 + 取り消し線。
/// セトリの行・予想の根拠・出演者の一覧で使う。名前は 1 人単位で折り返す。
struct ImasPerformerChip: View {
    let name: String
    var seed: String? = nil
    var isAbsent: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            ImasPenlight(
                color: seed == nil ? DS.ink3 : ImasTheme.derive(seed: seed, brand: nil, scheme: scheme).penlight,
                size: .small
            )
            .opacity(isAbsent ? 0.35 : 1)
            Text(name)
                .font(.imasFootnote)
                .strikethrough(isAbsent, color: DS.ink3)
                .foregroundStyle(isAbsent ? DS.ink3 : DS.ink2)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAbsent ? "\(name) 欠席" : name)
    }
}

// MARK: - 動画のサムネ

/// 参考動画のサムネ。16:9 に切って角を丸め、真ん中に再生の記号を重ねる。
/// 大きいサムネが無い動画は `fallbackURL` (小さいサムネ) に落とす。どちらも読めなければ灰の面。
struct ImasVideoThumbnail: View {
    let url: URL?
    var fallbackURL: URL? = nil

    var body: some View {
        ZStack {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if state.error != nil {
                    LazyImage(url: fallbackURL) { fallback in
                        if let image = fallback.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(DS.surface2)
                        }
                    }
                } else {
                    Rectangle().fill(DS.surface2)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
            Image(systemName: "play.circle.fill")
                .font(.imasScaled(46))
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.35), radius: 5)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - ペンライトの色の組

/// ペンライトの色の組を横並びの帯で見せる (色ごとに等分・角丸)。
/// 読み上げの文 (「ペンライト: 2色 ピンク、白」) はコアが組む。
struct ImasPenlightColorBar: View {
    /// 色の hex。並び順のまま左から塗る。
    let colors: [String]
    var height: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                Rectangle().fill(Color(hexString: hex, default: DS.ink3))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.rXS, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(penlightAccessibilityLabel(hexes: colors))
    }
}
