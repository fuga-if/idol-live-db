import SwiftUI

// =============================================================================
// ステージの操作部品 (docs/DESIGN_SYSTEM.md §12)
//
// ImasStageIconTileButton  記号 + 1 行ラベルの操作タイル (もう一度・次の曲)。
// ImasStagePlaybackControl 「タップ = 続きから」「長押し = 流し続ける」の 2 段ジェスチャー再生操作。
//                          イントロドン・パーティ対戦の両方が持っていた独立実装を 1 つに。
// ImasStageCircleButton    ステージ中央に置く大きな単発操作ボタン (直径可変。早押しの「!」)。
// =============================================================================

/// 記号 + 1 行ラベルの操作タイル。実線の枠 (再生操作は `ImasStagePlaybackControl` の点線枠と区別する)。
struct ImasStageIconTileButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .bold))
                Text(label).font(QS.text(12, weight: .bold))
            }
            .foregroundStyle(QS.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(QS.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.imasPress)
    }
}

/// 「タップ = 続きから」「長押し = 流し続ける」の 2 段ジェスチャー再生操作。
/// イントロドン (タイル) とパーティ対戦 (丸) の両方が独立に持っていたジェスチャー実装を 1 つに。
struct ImasStagePlaybackControl: View {
    enum Style {
        /// 点線の枠のタイル (未再生) / ink 塗り (再生中)。操作列の 1 枠として。
        case tile
        /// 小さい丸 + 横に添え書き。中央ストリップのような狭い場所用。
        case circle
    }

    let isPlaying: Bool
    var style: Style = .tile
    /// 読み上げ: 再生中のラベル。
    var playingLabel: String = "再生中"
    /// 読み上げ: 止まっているときのラベル。タップで何が起きるか (続きから／頭から 等) を呼び出し側が渡す。
    var pausedLabel: String = "続きから"
    var accessibilityHintText: String = "タップで続きを流す。長押しの間は流し続けます"
    let onTap: () -> Void
    let onHoldBegin: () -> Void
    let onHoldEnd: () -> Void

    @State private var isHolding = false

    var body: some View {
        Group {
            switch style {
            case .tile: tileBody
            case .circle: circleBody
            }
        }
        .scaleEffect(isHolding ? (style == .tile ? 0.94 : 0.9) : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHolding)
        .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 100) {
            isHolding = true
            onHoldBegin()
        } onPressingChanged: { pressing in
            if pressing {
                isHolding = false
            } else if isHolding {
                isHolding = false
                onHoldEnd()
            } else {
                onTap()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isPlaying ? playingLabel : pausedLabel)
        .accessibilityHint(accessibilityHintText)
    }

    private var tileBody: some View {
        VStack(spacing: 2) {
            Image(systemName: isPlaying ? "waveform" : "play.fill").font(.system(size: 15, weight: .bold))
            Text(isPlaying ? "再生中" : "続きから").font(QS.text(12, weight: .bold))
        }
        .foregroundStyle(isPlaying ? QS.bg : QS.ink)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(isPlaying ? QS.ink : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(QS.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .contentShape(Rectangle())
    }

    private var circleBody: some View {
        HStack(spacing: 10) {
            Image(systemName: isPlaying ? "waveform" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isPlaying ? QS.bg : QS.ink)
                .frame(width: 40, height: 40)
                .background(isPlaying ? QS.ink : QS.raised, in: Circle())
            Text("長押しでもう少し").font(QS.text(10, weight: .semibold)).foregroundStyle(QS.faint)
        }
        .contentShape(Rectangle())
    }
}

/// ステージ中央の大きな単発操作ボタン (早押しの「!」)。直径は呼び出し側が画面から決める。
struct ImasStageCircleButton: View {
    let label: String
    let size: CGFloat
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                // 円の直径に対する比率で決まるグリフ。単独でスケールさせると固定直径の円から
                // はみ出すため、意図的に固定 pt のままにする。
                .font(.system(size: max(48, size * 0.45), weight: .black, design: .rounded))
                .foregroundStyle(isEnabled ? QS.bg : QS.faint)
                .frame(width: size, height: size)
                .background(isEnabled ? QS.ink : QS.raised, in: Circle())
                .shadow(color: isEnabled ? QS.ink.opacity(0.25) : .clear, radius: 16, y: 6)
        }
        .buttonStyle(.imasPress)
        .disabled(!isEnabled)
    }
}
