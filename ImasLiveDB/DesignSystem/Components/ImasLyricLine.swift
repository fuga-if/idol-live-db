import SwiftUI

// =============================================================================
// 歌詞の行の印 (docs/DESIGN_SYSTEM.md §9 の延長)
//
// 用途      歌詞タブの 1 行に重ねる印。再生に追従している今の行・タイミング記録で次に
//           タップする行・ここ好き・記録した時刻。
// 使わない  クイズの出題箇所 (SongLyricsTab の FocusedLineStyle。言葉の見出しが付く別物)。
// 構成      今の行 / 次の行 … 左の縦帯 (曲の色) + 淡い地。行の折り返しは変えない (余白へはみ出す)。
//           ここ好き … 行末のハート (曲の色)。時刻 … 等幅の小さい数字。
//
// 光らせない・ぼかさない (グラデーション・光は禁止)。色は曲の配色 (担当色 / ブランド色) だけ。
// =============================================================================

/// 行に重ねる状態。
enum ImasLyricLineState: Equatable {
    case normal
    /// 再生に追従している今の行。
    case current
    /// タイミング記録で次にタップしてほしい行。
    case cursor
}

extension View {
    /// 歌詞の行に「今の行」「次に記録する行」の印を重ねる。
    func imasLyricLine(_ state: ImasLyricLineState, seed: String?) -> some View {
        modifier(ImasLyricLineModifier(state: state, seed: seed))
    }
}

private struct ImasLyricLineModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let state: ImasLyricLineState
    let seed: String?

    func body(content: Content) -> some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        let isOn = state != .normal
        // 地の濃さ: 今の行は読ませたいので少し濃く、次の行は「ここを押す」の目印なので薄く。
        let fill: Double = switch state {
        case .normal: 0
        case .current: scheme == .dark ? 0.24 : 0.14
        case .cursor: scheme == .dark ? 0.14 : 0.08
        }
        content
            .padding(.horizontal, DS.sp2)
            .background(t.accent.opacity(fill),
                        in: RoundedRectangle(cornerRadius: DS.rSM, style: .continuous))
            .overlay(alignment: .leading) {
                if isOn {
                    Capsule().fill(t.accent).frame(width: 3).padding(.vertical, 4)
                }
            }
            .padding(.horizontal, -DS.sp2)
            .animation(.easeOut(duration: 0.2), value: state)
    }
}

/// 行末の「ここ好き」。付いている行にだけ置く。
struct ImasLyricLikeMark: View {
    @Environment(\.colorScheme) private var scheme
    let seed: String?

    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        Image(systemName: UserMarkKind.lyricLikes.activeIcon)
            .font(.imasScaled(12, weight: .semibold))
            .foregroundStyle(t.accent)
            .accessibilityLabel(UserMarkKind.lyricLikes.label)
    }
}

/// 記録した時刻 (「1:02.3」)。記録が無い行は「—」。
struct ImasLyricTimeLabel: View {
    let ms: Int?
    var isEmphasized = false

    var body: some View {
        Text(ms.map(Self.format) ?? "—")
            .imasText(.imprint, color: isEmphasized ? DS.ink : DS.ink3)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel(ms.map { "\(Self.format($0)) から" } ?? "時刻なし")
    }

    static func format(_ ms: Int) -> String {
        let tenths = max(0, ms) / 100
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}

// MARK: - ここ好きの山つきシークバー

/// 曲の時間軸に「ここ好き」の山を立てたシークバー (YouTube の「最も再生された部分」の歌詞版)。
///
/// 山は細い縦棒の並び。再生済みの側は曲の色、まだの側は墨の薄い色。いちばん好かれている
/// 地点 (おすすめ) の上に小さなハートを置く。光らせない・ぼかさない。
/// タップした位置へ動かす (`onSeek` は 0〜1 の割合)。
struct ImasLikeHeatSeekBar: View {
    @Environment(\.colorScheme) private var scheme
    /// 区間ごとの高さ (0〜1)。空なら山を出さず線だけ。
    let levels: [Float]
    /// 今の位置 (0〜1)。再生していなければ nil (進みの色を付けない)。
    let progress: Double?
    /// おすすめ地点 (0〜1)。
    let peak: Double?
    let seed: String?
    let onSeek: (Double) -> Void

    private let height: CGFloat = 36

    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .bottomLeading) {
                if levels.isEmpty {
                    Rectangle().fill(DS.sep).frame(height: 2)
                } else {
                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach(levels.indices, id: \.self) { i in
                            let played = progress.map { Double(i) / Double(levels.count) < $0 } ?? false
                            Rectangle()
                                .fill(played ? t.accent : DS.ink3.opacity(0.35))
                                .frame(height: max(2, CGFloat(levels[i]) * (height - 10)))
                        }
                    }
                }
                if let progress {
                    Rectangle().fill(DS.ink)
                        .frame(width: 2, height: height - 4)
                        .offset(x: max(0, min(width - 2, width * progress - 1)))
                }
                if let peak {
                    Image(systemName: UserMarkKind.lyricLikes.activeIcon)
                        .font(.imasScaled(9, weight: .bold))
                        .foregroundStyle(t.accent)
                        .position(x: max(5, min(width - 5, width * peak)), y: 4)
                }
            }
            .frame(width: width, height: height, alignment: .bottomLeading)
            .contentShape(Rectangle())
            // なぞりではなくタップ。歌詞の縦スクロールの途中で指が乗っても飛ばないように。
            .onTapGesture(coordinateSpace: .local) { location in
                onSeek(max(0, min(1, location.x / max(width, 1))))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("ここ好きの多い場所")
        .accessibilityValue(peak.map { "おすすめは \(Int($0 * 100))% の位置" } ?? "")
        .accessibilityAction(named: "おすすめ地点から再生") { if let peak { onSeek(peak) } }
    }
}
