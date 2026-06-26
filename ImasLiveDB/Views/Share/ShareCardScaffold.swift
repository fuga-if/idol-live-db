import SwiftUI
import UIKit

// =============================================================================
// シェアカード共通基盤  ※ 公式トンマナ準拠 (編集的・プレミアム・洗練)
// -----------------------------------------------------------------------------
// アートディレクション (グラデを使わない):
// - 背景は「単色」。写真カードは near-black、写真なしカードは near-black / off-white。
//   多色グラデ・虹色グラデ・多段 scrim は使わない (AI 感のある安っぽさを避ける)。
// - 写真カードは「上にジャケ写フルブリード / 下にソリッド黒パネル」のハードエッジな
//   カラーブロック分割。継ぎ目に細いメンバーカラー罫線 1 本 (差し色)。
// - メンバーカラーは差し色 1 点 (細ライン・小四角・ドット) のみ。背景全体は染めない。
// - タイトルは明朝 (design: .serif) で上品・編集的に。英字キャプスは字間広め。
// - 大きな幾何学透かし (円/ストローク) を淡く 1 つ。
//
// 版権上、キャラ絵・歌詞・公式ロゴは一切含めない。
// ジャケット写真は Apple Music 由来 artwork (songs.artwork_url) のみ、
// プロダクトオーナー判断で焼き込み可。
//
// ImageRenderer は SwiftUI Environment (ライト/ダーク) を引き継がないため、
// カード内では DS.* の動的色を使わず、固定色だけを使う。
// =============================================================================

/// カードの論理サイズ (pt)。レンダラは 2x で px に焼く。
/// width/height を別に持ち、カードごとに比率を変えられる。
enum ShareCard {
    struct Size: Equatable {
        var width: CGFloat
        var height: CGFloat
    }

    /// 既定: 4:5 縦長 (540×675pt → 1080×1350px)。X タイムラインで存在感が出る。
    static let portrait = Size(width: 540, height: 675)

    // MARK: - シェア比率プリセット

    /// シェアシートで選べるアスペクト比。論理サイズはすべて長辺 ~675pt 基準で
    /// 揃え (2x で px 化)、X / Instagram フィード / ストーリーズに最適化する。
    enum Ratio: String, CaseIterable, Identifiable {
        /// 1:1 正方形 (540×540pt → 1080×1080px)。Instagram フィードの基本形。
        case square
        /// 4:5 縦長 (540×675pt → 1080×1350px)。既定。X タイムラインで存在感が出る。
        case portrait
        /// 9:16 縦長 (540×960pt → 1080×1920px)。ストーリーズ / リール向け。
        case story

        var id: String { rawValue }

        /// 比率トグルに出す短いラベル。
        var label: String {
            switch self {
            case .square:   return "1:1"
            case .portrait: return "4:5"
            case .story:    return "9:16"
            }
        }

        /// 用途が伝わる補助ラベル (VoiceOver / 補足表示用)。
        var caption: String {
            switch self {
            case .square:   return "正方形"
            case .portrait: return "縦長"
            case .story:    return "ストーリーズ"
            }
        }

        var size: Size {
            switch self {
            case .square:   return Size(width: 540, height: 540)
            case .portrait: return Size(width: 540, height: 675)
            case .story:    return Size(width: 540, height: 960)
            }
        }
    }

    /// 既定の比率。デザインの主役は 4:5。
    static let defaultRatio: Ratio = .portrait
}

// MARK: - 固定色 (グラデを使わない単色パレット)

/// シェアカード共通の固定色。near-black / off-white をベースに、
/// メンバーカラー (accent) は差し色としてのみ使う。
enum ShareInk {
    /// 写真カード下部パネル / ダーク背景カードのソリッド地色。
    static let nearBlack = Color(.sRGB, red: 0x0E / 255, green: 0x0E / 255, blue: 0x12 / 255)
    /// 明色背景カードのソリッド地色。
    static let offWhite = Color(.sRGB, red: 0xFA / 255, green: 0xFA / 255, blue: 0xF8 / 255)
}

/// シェアカード専用パレット。seed → メンバーカラー (accent) を導出し、
/// 残りは near-black/off-white の固定編集色で構成する (多色グラデは持たない)。
struct ShareCardPalette {
    /// メンバーカラー (差し色)。罫線・小四角・ドット・プログレスにのみ使う。
    let accent: Color
    /// フォールバック背景に使う「深く落としたメンバーカラー単色」。
    let accentDeep: Color

    init(seed: String?) {
        let hex = ColorMath.firstValidHex(seed) ?? ColorMath.neutralSeed
        let (h, s, l) = ColorMath.rgbToHsl(ColorMath.hexToRgb(hex))
        let neutral = s < 0.10
        // 差し色: 暗背景でも視認できる明度に寄せた鮮やかめのメンバーカラー。
        let aS = neutral ? ColorMath.clamp(s, 0, 0.12) : ColorMath.clamp(s, 0.45, 0.95)
        let aL = ColorMath.clamp(l, 0.52, 0.66)
        accent = ColorMath.color(h: h, s: aS, l: aL)
        // フォールバック地色: メンバーカラーを深く落とした単色 (near-black 寄り)。
        accentDeep = ColorMath.color(h: h, s: neutral ? 0.06 : ColorMath.clamp(s * 0.5, 0.12, 0.30), l: 0.10)
    }
}

// MARK: - 流入導線フッター

/// 全カード共通の控えめなフッター (#アイドルライブDB)。主張しすぎないよう小さく上品に。
struct ShareCardFooter: View {
    /// フッターの主インク色 (暗背景なら白寄り、明背景なら黒寄り)。
    var ink: Color
    /// 区切り線の色。
    var rule: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "music.mic")
                .font(.imasScaled( 12, weight: .semibold))
            Text("#アイドルライブDB")
                .font(.imasScaled( 14, weight: .bold))
            Spacer()
            Text("IDOL LIVE DATABASE")
                .font(.imasScaled( 9, weight: .semibold))
                .tracking(2.4)
                .opacity(0.7)
        }
        .foregroundStyle(ink)
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(rule).frame(height: 0.75)
        }
    }
}

// MARK: - 英字キャプスのセクションラベル (メンバーカラー小四角 + 字間広め)

/// `▬ タグを追加しました！` のような編集的ラベル。小バーは差し色のメンバーカラー。
/// ラベルは和文なので字間は控えめに (英字キャプスのような広い tracking は和文だと読みにくい)。
struct ShareEyebrow: View {
    let text: String
    var accent: Color
    var ink: Color

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(accent)
                .frame(width: 18, height: 3)
            Text(text)
                .font(.imasScaled( 14, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(ink)
        }
    }
}

// MARK: - 写真カードの共通骨格 (ハードエッジのカラーブロック分割)

/// ジャケ写を主役にするカード (タグ / セトリ感想) の共通レイアウト。
/// 上 ~58% にジャケ写をフルブリード、下をソリッド near-black パネルにする
/// ハードエッジ分割。継ぎ目に細いメンバーカラー罫線 1 本。グラデは使わない。
struct PhotoShareScaffold<Content: View>: View {
    let artwork: UIImage?
    let palette: ShareCardPalette
    var size: ShareCard.Size = ShareCard.portrait
    @ViewBuilder var content: Content

    /// 写真の占有率 (上から)。残りがソリッドのテキストパネル。
    /// アスペクト比で最適値が変わる: 正方形は写真を大きめに、9:16 は縦に長い分
    /// テキストパネルを稼ぎたいので写真を抑える。縦横比 (h/w) から線形に決める。
    private var photoRatio: CGFloat {
        let aspect = size.height / size.width // 1.0(1:1) … 1.78(9:16)
        // 1:1 → 0.64、4:5 → 0.58、9:16 → 0.46 あたりに収まるよう補間しクランプ。
        let raw = 0.78 - aspect * 0.18
        return min(max(raw, 0.44), 0.66)
    }

    var body: some View {
        let photoHeight = size.height * photoRatio
        // テキストパネルの余白も比率追従 (縦長ほどゆったり、正方形は詰める)。
        let panelHPad = size.width * 0.074
        let panelTopPad = size.height * 0.044
        let panelBottomPad = size.height * 0.047
        VStack(spacing: 0) {
            // 上: ジャケ写フルブリード (または単色フォールバック)。
            photoBlock(height: photoHeight)
                // 写真下端の可読性が要る場合に備え、均一なフラット薄黒を 1 枚だけ
                // (グラデではなくベタ)。継ぎ目付近の白ラベルの抜けを防ぐ。
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.black.opacity(0.12))
                        .frame(height: photoHeight * 0.28)
                        .allowsHitTesting(false)
                }

            // 継ぎ目: 細いメンバーカラー罫線 1 本 (差し色)。
            Rectangle()
                .fill(palette.accent)
                .frame(height: 3)

            // 下: ソリッド near-black のテキストパネル。
            ZStack(alignment: .topLeading) {
                ShareInk.nearBlack
                VStack(alignment: .leading, spacing: 0) {
                    content
                    Spacer(minLength: 0)
                    ShareCardFooter(ink: .white.opacity(0.62), rule: .white.opacity(0.16))
                }
                .padding(.horizontal, panelHPad)
                .padding(.top, panelTopPad)
                .padding(.bottom, panelBottomPad)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(ShareInk.nearBlack)
        .clipped()
    }

    @ViewBuilder
    private func photoBlock(height: CGFloat) -> some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: height)
                .clipped()
        } else {
            // フォールバック: 深く落としたメンバーカラー単色 + 幾何透かし 1 つ。
            ZStack {
                palette.accentDeep
                Circle()
                    .stroke(.white.opacity(0.07), lineWidth: 2)
                    .frame(width: height * 0.95, height: height * 0.95)
                Circle()
                    .stroke(palette.accent.opacity(0.18), lineWidth: 2)
                    .frame(width: height * 0.62, height: height * 0.62)
                Image(systemName: "music.note")
                    .font(.imasScaled( height * 0.28, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.10))
            }
            .frame(width: size.width, height: height)
            .clipped()
        }
    }
}

// MARK: - 単色編集カードの共通骨格 (写真なし: 回収率)

/// 写真を持たないカード (回収率) の骨格。単色 near-black 地 + 大きな幾何透かし 1 つ。
/// 多色グラデは使わない。メンバーカラーは差し色のみ。
struct SoloShareScaffold<Content: View>: View {
    let palette: ShareCardPalette
    var size: ShareCard.Size = ShareCard.portrait
    /// 上部の種別ラベル (英字キャプス)。
    var badge: String
    @ViewBuilder var content: Content

    /// near-black 地に白基調。
    private let ink = Color.white

    var body: some View {
        ZStack {
            ShareInk.nearBlack
            watermark

            VStack(alignment: .leading, spacing: 0) {
                ShareEyebrow(text: badge, accent: palette.accent, ink: ink.opacity(0.82))
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                ShareCardFooter(ink: ink.opacity(0.62), rule: ink.opacity(0.16))
            }
            .padding(.horizontal, size.width * 0.081)
            .padding(.vertical, size.height * 0.068)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// 大きな幾何学透かし 1 つ (淡い同心円)。右上にアンカーし比率に依らず安定させる。
    private var watermark: some View {
        let outer = size.width
        let inner = size.width * 0.667
        return ZStack {
            Circle()
                .stroke(ink.opacity(0.06), lineWidth: 1.5)
                .frame(width: outer, height: outer)
            Circle()
                .stroke(palette.accent.opacity(0.14), lineWidth: 1.5)
                .frame(width: inner, height: inner)
        }
        // カード右上隅の外側に中心を置き、上部に弧が覗く構図を全比率で再現。
        .frame(width: size.width, height: size.height, alignment: .center)
        .offset(x: size.width * 0.39, y: -size.height * 0.30)
    }
}
