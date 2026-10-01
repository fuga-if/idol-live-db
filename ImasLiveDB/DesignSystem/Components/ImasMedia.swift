import Nuke
import NukeUI
import SwiftUI

// =============================================================================
// 画像と印 (docs/DESIGN_SYSTEM.md §10.3)
//
// ImasAvatar       アイドル。画像が無ければモノグラム、担当は二重輪。
// ImasArtwork      曲のジャケ。画像が無ければブランド色の面 + 曲名。
// ImasIconTile     記号を淡い実体色の角丸四角に入れる (行の先頭・統計・空状態・入口)。
// ImasSwatch       色の丸 (タグの色・ペンライトの色)。読み上げは色名。
// ImasLeadBar      ライブ・公演の行頭の細い帯。
// ImasPerformerChip 歌唱者 1 人 (色の点 + 名前)。欠席は薄字 + 取り消し線。
//
// 色は seed / brand を渡せばその色、渡さなければ環境の実体色 (`.imasTheme`)。
// =============================================================================

// MARK: - アバター

/// モノグラム・アバター。淡い実体色の面 + 細い輪 + 実体色の頭文字。
/// 担当 (`isPick`) のときは外側に二重輪をまとう。
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

    /// 可視のアバターと外形の間の片側の余白 (担当の輪の分)。
    static let ringPadding: CGFloat = 5.5

    private var outerSize: CGFloat { reservesPickRing ? size + Self.ringPadding * 2 : size }

    var body: some View {
        let t = (seed != nil || brand != nil)
            ? ImasTheme.derive(seed: seed, brand: brand, scheme: scheme)
            : envTheme
        ZStack {
            if isPick {
                Circle().fill(t.gradTo).frame(width: size + 11, height: size + 11)
                Circle().fill(t.accent).frame(width: size + 7, height: size + 7)
                Circle().fill(DS.surface).frame(width: size + 4, height: size + 4)
            }
            core(t)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(t.ring, lineWidth: size >= 56 ? 2 : 1.5))
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
                    monogram(t)
                }
            }
            .processors([ImageProcessors.Resize(size: CGSize(width: px, height: px), unit: .pixels)])
        } else {
            monogram(t)
        }
    }

    private func monogram(_ t: ImasTheme) -> some View {
        ZStack {
            t.tint
            Text(label)
                .font(.imasDisplay(size * 0.40, weight: .semibold))
                .foregroundStyle(t.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
        }
    }
}

// MARK: - ジャケ

/// 曲のジャケ。実画像があれば表示、無ければ実体色の面 + 中央に曲名。
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

    private func fallback(_ t: ImasTheme) -> some View {
        ZStack {
            t.accent
            Text(title)
                .font(.imasScaled(max(9, size * 0.13), weight: .bold))
                .foregroundStyle(t.onAccent)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .padding(size * 0.12)
        }
    }
}

// MARK: - 記号の札

/// 記号を淡い実体色の角丸四角に入れる。行の先頭・統計タイル・空状態・入口カードで同じ形にする。
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
            case .s28: return .imasScaled(14, weight: .semibold)
            case .s32: return .imasScaled(15, weight: .semibold)
            case .s36: return .imasScaled(16, weight: .semibold)
            case .s44: return .imasScaled(20, weight: .regular)
            case .s56: return .imasScaled(26, weight: .regular)
            }
        }
    }

    enum Tone {
        /// 実体色の淡い地 (既定)。
        case themed
        /// 灰。
        case neutral
        /// 実体色の塗り (アプリの機能を示すアイコン)。
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
        let c = colors(t)
        Image(systemName: systemImage)
            .font(size.iconFont)
            .foregroundStyle(c.fg)
            .frame(width: size.rawValue, height: size.rawValue)
            .background(c.bg, in: RoundedRectangle(cornerRadius: DS.rIconTile(size.rawValue), style: .continuous))
            .accessibilityHidden(true)
    }

    private func colors(_ t: ImasTheme) -> (bg: Color, fg: Color) {
        switch tone {
        case .themed: return t.isNeutral ? (DS.fill, DS.ink2) : (t.chipBg, t.chipText)
        case .neutral: return (DS.fill, DS.ink2)
        case .solid: return (t.actionFill, t.onActionFill)
        case .positive: return (DS.success.opacity(0.16), DS.successInk)
        case .attention: return (DS.warning.opacity(0.16), DS.warning)
        case .negative: return (DS.danger.opacity(0.14), DS.danger)
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

/// 歌唱者 1 人。色の点 + 名前。欠席は薄字 + 取り消し線。
/// セトリの行・予想の根拠・出演者の一覧で使う。名前は 1 人単位で折り返す。
struct ImasPerformerChip: View {
    let name: String
    var seed: String? = nil
    var isAbsent: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hexString: seed, default: DS.ink3))
                .frame(width: 7, height: 7)
                .opacity(isAbsent ? 0.4 : 1)
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
