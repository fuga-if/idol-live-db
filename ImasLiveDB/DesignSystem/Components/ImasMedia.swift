import Nuke
import NukeUI
import SwiftUI

// =============================================================================
// 画像と印 (docs/DESIGN_SYSTEM.md §10.3)
//
// ImasAvatar       アイドルのアイコン (ユーザーが設定した写真)。担当は輪を二重にする。
//                  写真の無いアイドルには置かない (行は `ImasRow` が帯に、チップはペンライトに替える)。
//                  写真が読めない間・旧い画面の呼び出しだけ、判子 (紙の白 + 実体色の輪と名前) を出す。
// ImasArtwork      曲のジャケ。角のある四角。画像が無ければ灰の面 + 音符。
// ImasIconTile     記号 1 つ。地を敷かない (記号を淡い色の四角に入れない)。
// ImasSwatch       色の丸 (タグの色・ペンライトの色)。読み上げは色名。
// ImasLeadBar      ライブ・公演・アイドルの行頭の細い帯。
// ImasPerformerChip 歌唱者 1 人 (ペンライト + 名前)。欠席は薄字 + 取り消し線。
//
// 色は seed / brand を渡せばその色、渡さなければ環境の実体色 (`.imasTheme`)。
// =============================================================================

// MARK: - アバター

/// アイドルのアイコン。ユーザーが設定した写真を丸く切って、実体色の輪で囲む。担当 (`isPick`) は輪を二重にする。
///
/// 写真の無いアイドルには置かない (行は `ImasRow(.avatar)` が帯に、チップはペンライトに替える)。
/// 写真が読めない間と、まだ部品に移していない画面の呼び出しでは「判子」(紙の白の丸に実体色の輪と名前) を出す。
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

// MARK: - ジャケ

/// 曲のジャケ。実画像があれば表示、無ければ灰の面 + 音符。
struct ImasArtwork: View {
    let title: String
    var seed: String?
    var brand: String? = nil
    var size: CGFloat = 48
    var imageURL: URL? = nil

    @Environment(\.imasTheme) private var envTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let t = (seed != nil || brand != nil)
            ? ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
            : envTheme
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
        .accessibilityLabel(title)
    }

    /// ジャケが無い曲。色の面に曲名を書くと「作った絵」に見えるので、OS の音楽アプリと同じく
    /// 灰の面に音符だけを置く。
    private func fallback(_ t: ImasTheme) -> some View {
        ZStack {
            DS.fill
            Image(systemName: "music.note")
                .font(.imasScaled(max(10, size * 0.32), weight: .regular))
                .foregroundStyle(DS.ink3)
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
    var size: Size = .small
    /// 名前が隣に書いてあり、色名を読み上げなくてよいとき。
    var isDecorative: Bool = false

    var body: some View {
        Circle()
            .fill(Color(hexString: hex))
            .overlay(Circle().strokeBorder(DS.sep, lineWidth: size == .dot ? 0 : 0.5))
            .frame(width: size.rawValue, height: size.rawValue)
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
                  ? AnyShapeStyle(LinearGradient(colors: QS.penlights, startPoint: .top, endPoint: .bottom))
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
