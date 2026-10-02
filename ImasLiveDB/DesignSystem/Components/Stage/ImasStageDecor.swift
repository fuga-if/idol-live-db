import SwiftUI

// =============================================================================
// ステージの小さな飾り (docs/DESIGN_SYSTEM.md §12)
//
// ImasStageWordmark    ink 塗りの角丸四角に文字 1〜2 字 (ハブの QUIZ STAGE チケットの「@」)。
// ImasStagePanel       QS.panel の面に中身を乗せる汎用カード (音声判定の状態表示など)。
// ImasStagePreviewCard QS.bg の色でカードの形に切り抜く (明るい一覧の中に埋め込む
//                      ステージのプレビュー。ハブの QUIZ STAGE チケットの外枠)。
// ImasStageRushFlash   正誤を知らせる大きな ○ / × の一瞬のフラッシュ。
// ImasStagePulse       「聴取中」のような継続状態を示す点滅ドット。
// ImasStagePenlightBars 歌唱メンバーの色を細い棒で並べる (セトリ当てクイズ)。
// =============================================================================

/// ink 塗りの角丸四角に短い文字 (ワードマーク)。
struct ImasStageWordmark: View {
    let text: String
    var size: CGFloat = 22

    var body: some View {
        Text(text)
            .font(QS.text(14, weight: .black))
            .foregroundStyle(QS.bg)
            .frame(width: size, height: size)
            .background(QS.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// QS.panel の面に中身を乗せる汎用カード。既定は角丸 14・縦の余白のみ
/// (再生状況などの小さな状態表示)。角丸・余白を変えれば大きな面 (INTRO パネルなど) にも使える。
struct ImasStagePanel<Content: View>: View {
    /// 面の角丸。
    var corner: CGFloat = 14
    var horizontalPadding: CGFloat = 0
    var topPadding: CGFloat = 18
    var bottomPadding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .background(QS.panel, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// QS.bg の色でカードの形に切り抜く。明るい一覧の中に「ここから先は会場」と
/// 分かるステージのプレビューを埋め込むときに使う (ハブの QUIZ STAGE チケットなど)。
struct ImasStagePreviewCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        content
            .background(QS.bg, in: shape)
            .clipShape(shape)
    }
}

/// 正誤を知らせる大きな ○ / × の一瞬のフラッシュ (ラッシュ系クイズ)。
struct ImasStageRushFlash: View {
    let isCorrect: Bool

    var body: some View {
        Image(systemName: isCorrect ? "circle" : "xmark")
            .font(.system(size: 96, weight: .heavy))
            .foregroundStyle(isCorrect ? DS.success : DS.danger)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .allowsHitTesting(false)
    }
}

/// 歌唱メンバーの色を細い棒で並べる (セトリ当てクイズの歌唱メンバー欄)。
struct ImasStagePenlightBars: View {
    let colors: [Color]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Capsule().fill(color).frame(width: 8, height: 20)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 「聴取中」のような継続状態を示す点滅ドット。
struct ImasStagePulse: View {
    var color: Color = DS.pick
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 14, height: 14)
                .scaleEffect(animate ? 1.6 : 1.0)
                .opacity(animate ? 0 : 1)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
        .accessibilityHidden(true)
    }
}
