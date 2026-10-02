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

// MARK: - 歌詞プレイヤーの 1 行

/// 歌詞プレイヤーの 1 行。今の行は大きく墨で、それ以外は小さく薄く (Apple Music の歌詞と同じ読ませ方)。
/// 大きさは文字の大きさではなく縮尺で変える — 行の折り返しが変わると、今の行が替わるたびに
/// 全体が跳ねるため。光らせない・ぼかさない。
struct ImasPlayerLyricLine: View {
    let text: String
    let isCurrent: Bool
    /// 構成マーカー (「間奏」等)。本文より控えめに出す。
    var isMarker = false
    var isLiked = false
    let seed: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.sp2) {
            // ⚠️ ここに `.textSelection(.enabled)` / `.imasCopyable` を足さないこと (歌詞の取り出し口になる)。
            Text(text)
                .font(isMarker ? .imasHeading(17, weight: .bold) : .imasHeading(28, weight: .heavy))
                .foregroundStyle(isCurrent ? DS.ink : DS.ink3)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isLiked { ImasLyricLikeMark(seed: seed) }
        }
        .scaleEffect(isCurrent ? 1 : 0.86, anchor: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isCurrent)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: - タイミング編集のタイムライン

/// 横長のタイムライン (動画編集アプリの並び)。再生位置は真ん中に固定し、帯の方が流れる。
/// 段は 2 本: 上が歌詞の行、下がコール (コールが無い曲では 1 本)。
///
/// - 地を横になぞる … 再生位置を動かす (`onScrub` が動いている間、`onScrubEnd` が離したとき)
/// - 帯をタップ … その行を選ぶ
/// - 選んだ帯の頭をなぞる … その行の歌い出しを動かす (`onMoveStart`)
struct ImasTimingTimeline: View {
    struct Block: Identifiable, Equatable {
        let id: String
        let startMs: Int
        let endMs: Int
        let label: String
    }

    @Environment(\.colorScheme) private var scheme
    let blocks: [Block]
    /// コールの段。空なら段ごと出さない。
    var callBlocks: [Block] = []
    let playheadMs: Int
    let selectedId: String?
    let seed: String?
    var pointsPerSecond: CGFloat = 70
    let onScrub: (Int) -> Void
    let onScrubEnd: (Int) -> Void
    let onSelect: (String) -> Void
    let onMoveStart: (String, Int) -> Void

    @State private var scrubFrom: Int?
    @State private var moveFrom: Int?

    private let rulerHeight: CGFloat = 20
    private let blockHeight: CGFloat = 48
    private let callHeight: CGFloat = 34
    private var totalHeight: CGFloat {
        rulerHeight + blockHeight + 8 + (callBlocks.isEmpty ? 0 : callHeight + 4)
    }

    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        GeometryReader { geo in
            let w = geo.size.width
            let x: (Int) -> CGFloat = { ms in w / 2 + CGFloat(ms - playheadMs) / 1000 * pointsPerSecond }
            ZStack(alignment: .topLeading) {
                ruler(width: w, x: x)
                ForEach(blocks) { b in
                    let left = x(b.startMs)
                    let width = max(6, x(b.endMs) - left - 2)
                    if left + width > -40 && left < w + 40 {
                        block(b, width: width, height: blockHeight, theme: t)
                            .offset(x: left, y: rulerHeight + 4)
                    }
                }
                ForEach(callBlocks) { b in
                    let left = x(b.startMs)
                    let width = max(6, x(b.endMs) - left - 2)
                    if left + width > -40 && left < w + 40 {
                        block(b, width: width, height: callHeight, theme: t)
                            .offset(x: left, y: rulerHeight + blockHeight + 8)
                    }
                }
                // 再生位置 (真ん中に固定)。
                Rectangle().fill(DS.ink)
                    .frame(width: 2, height: totalHeight)
                    .offset(x: w / 2 - 1)
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: totalHeight, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        let from = scrubFrom ?? playheadMs
                        if scrubFrom == nil { scrubFrom = from }
                        onScrub(max(0, from - Int(v.translation.width / pointsPerSecond * 1000)))
                    }
                    .onEnded { v in
                        let from = scrubFrom ?? playheadMs
                        scrubFrom = nil
                        onScrubEnd(max(0, from - Int(v.translation.width / pointsPerSecond * 1000)))
                    }
            )
        }
        .frame(height: totalHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("タイミングのタイムライン")
    }

    /// 1 秒ごとの目盛り、5 秒ごとに時刻。
    private func ruler(width w: CGFloat, x: @escaping (Int) -> CGFloat) -> some View {
        let visible = Int(w / pointsPerSecond) + 2
        let firstSecond = max(0, playheadMs / 1000 - visible / 2)
        return ZStack(alignment: .topLeading) {
            ForEach(firstSecond...(firstSecond + visible), id: \.self) { s in
                let major = s % 5 == 0
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(major ? DS.ink2 : DS.sep).frame(width: 1, height: major ? 10 : 6)
                    if major {
                        Text(String(format: "%d:%02d", s / 60, s % 60))
                            .imasText(.imprint, color: DS.ink3)
                            .fixedSize()
                    }
                }
                .offset(x: x(s * 1000))
            }
        }
        .frame(height: rulerHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func block(_ b: Block, width: CGFloat, height blockHeight: CGFloat, theme t: ImasTheme) -> some View {
        let selected = b.id == selectedId
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DS.rSM, style: .continuous)
                .fill(selected ? t.accent.opacity(scheme == .dark ? 0.32 : 0.2) : DS.fill)
            RoundedRectangle(cornerRadius: DS.rSM, style: .continuous)
                .strokeBorder(selected ? t.accent : DS.sep, lineWidth: selected ? 2 : 1)
            Text(b.label)
                .imasText(.meta, color: selected ? DS.ink : DS.ink2)
                .lineLimit(1)
                .padding(.leading, DS.sp3)
                .padding(.trailing, DS.sp1)
            if selected {
                // 歌い出しのつまみ。なぞって前後に動かす。
                Capsule().fill(t.accent)
                    .frame(width: 6, height: blockHeight - 12)
                    .padding(.leading, 2)
                    .frame(width: 28, height: blockHeight, alignment: .leading)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                let from = moveFrom ?? b.startMs
                                if moveFrom == nil { moveFrom = from }
                                onMoveStart(b.id, max(0, from + Int(v.translation.width / pointsPerSecond * 1000)))
                            }
                            .onEnded { _ in moveFrom = nil }
                    )
                    .accessibilityLabel("歌い出しのつまみ")
            }
        }
        .frame(width: width, height: blockHeight)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(b.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
