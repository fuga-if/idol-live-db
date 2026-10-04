import CoreText
import SwiftUI
import UIKit

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
    /// なぞって位置を選べるか。縦にスクロールする面の中ではタップだけにする
    /// (なぞりを受けると、スクロールの途中で指が乗ったときに飛んでしまう)。
    var allowsScrub = false
    let onSeek: (Double) -> Void

    private let height: CGFloat = 36
    /// なぞっている間の位置 (0〜1)。離したらそこへ動かす。
    @State private var scrubFraction: Double?

    private var shownProgress: Double? { scrubFraction ?? progress }

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
                            let played = shownProgress.map { Double(i) / Double(levels.count) < $0 } ?? false
                            Rectangle()
                                .fill(played ? t.accent : DS.ink3.opacity(0.35))
                                .frame(height: max(2, CGFloat(levels[i]) * (height - 10)))
                        }
                    }
                }
                if let progress = shownProgress {
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
            .gesture(scrubGesture(width: width), including: allowsScrub ? .all : .none)
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

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in scrubFraction = max(0, min(1, v.location.x / max(width, 1))) }
            .onEnded { v in
                let fraction = max(0, min(1, v.location.x / max(width, 1)))
                scrubFraction = nil
                onSeek(fraction)
            }
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
    /// いまこの行の文字を一緒に叫ぶところ (歌詞と同じ文字の同時コール)。曲の色で点ける。
    var isCalled = false
    let seed: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.sp2) {
            // ⚠️ ここに `.textSelection(.enabled)` / `.imasCopyable` を足さないこと (歌詞の取り出し口になる)。
            let color = isCalled ? ImasTheme.derive(seed: seed, scheme: scheme).accent : isCurrent ? DS.ink : DS.ink3
            if ImasRubyText.hasRuby(text) {
                // 振り仮名は親字の上に乗せる (Text では組めないので UILabel)。
                ImasRubyLabel(attributed: ImasRubyText.attributed(
                    text,
                    font: isMarker ? Font.imasScaledUIFont(17, weight: .bold, proportional: true)
                                   : Font.imasScaledUIFont(28, weight: .heavy, proportional: true),
                    color: UIColor(color), lineSpacing: 4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(isMarker ? .imasHeading(17, weight: .bold) : .imasHeading(28, weight: .heavy))
                    .foregroundStyle(color)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isLiked { ImasLyricLikeMark(seed: seed) }
        }
        .scaleEffect(isCurrent ? 1 : 0.86, anchor: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isCurrent)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: - タイミング編集のタイムライン

/// 横長のタイムライン (動画編集アプリの並び)。再生位置は真ん中に固定し、帯の方が流れる。
/// 段は上が歌詞の行。その下に細い段 (被せ・コール) を並べられる (空の段は出さない)。
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
    /// 下に並べる細い段 (被せ・コール)。空の段は出さない。
    var subLanes: [[Block]] = []
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
    private var visibleSubLanes: [[Block]] { subLanes.filter { !$0.isEmpty } }
    private var totalHeight: CGFloat {
        rulerHeight + blockHeight + 8 + CGFloat(visibleSubLanes.count) * (callHeight + 4)
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
                ForEach(Array(visibleSubLanes.enumerated()), id: \.offset) { lane, lanesBlocks in
                    ForEach(lanesBlocks) { b in
                        let left = x(b.startMs)
                        let width = max(6, x(b.endMs) - left - 2)
                        if left + width > -40 && left < w + 40 {
                            block(b, width: width, height: callHeight, theme: t)
                                .offset(x: left, y: rulerHeight + blockHeight + 8 + CGFloat(lane) * (callHeight + 4))
                        }
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

// MARK: - 歌詞プレイヤーの被せ (2 段目)

/// 被せ・追いかけ・コーラス (歌詞の括弧の中) を、メインの行の下に重ねる 2 段目。
/// メインより小さく、左に細い罫を引いて「重なっている層」だと分かるようにする。
/// 光っている間 (`isCurrent`) は墨、それ以外は薄く。光らせない・ぼかさない。
/// 歌詞プレイヤーで行の直下に出すコール 1 つ。いま出すコールは大きく色で点け、他は控えめに。
/// (下の操作面にコールの段を別に置かず、歌詞の流れの中でコールを読ませる。)
struct ImasPlayerCallLine: View {
    let marker: String
    let text: String
    /// コールの色 (強調度ごと。`CallEmphasis.color(accent:)`)。
    let color: Color
    let isActive: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.sp2) {
            Text(marker)
                .font(.imasCaption)
                .foregroundStyle(DS.ink3)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(isActive ? .imasHeading(24, weight: .heavy) : .imasHeading(15, weight: .bold))
                .foregroundStyle(isActive ? color : color.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, DS.sp3)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isActive)
        .accessibilityLabel("コール \(text)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct ImasPlayerOverlayLine: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    let isCurrent: Bool
    let seed: String?

    var body: some View {
        let t = ImasTheme.derive(seed: seed, scheme: scheme)
        HStack(alignment: .top, spacing: DS.sp2) {
            Rectangle()
                .fill(isCurrent ? t.accent : DS.sep)
                .frame(width: 2)
            // ⚠️ ここに `.textSelection(.enabled)` / `.imasCopyable` を足さないこと。
            Text(text)
                .font(.imasHeading(19, weight: .bold))
                .foregroundStyle(isCurrent ? DS.ink2 : DS.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, DS.sp4)
        .animation(.easeOut(duration: 0.2), value: isCurrent)
        .accessibilityLabel("被せ \(text)")
    }
}

// MARK: - パート分け (誰が歌うか)

/// 行の頭に立てる歌唱者の帯。担当色を縦に縞で並べる (複数人なら人数ぶんの縞。虹は縞で出す決まり)。
/// 歌唱者が付いていない行では幅だけ取って何も描かない (行の頭が揃うように)。
struct ImasPartStripe: View {
    /// 歌唱者の担当色 (hex)。並び順に上から縞にする。
    let colors: [String]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                Rectangle().fill(ImasTheme.derive(seed: hex, scheme: scheme).accent)
            }
        }
        .frame(width: 4)
        .accessibilityHidden(true)
    }
}

/// 行の下に添える歌唱者の名前 (「春香・千早」)。帯の色だけに頼らず、言葉でも出す。
struct ImasPartNames: View {
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            Text(names.joined(separator: "・"))
                .imasText(.meta, color: DS.ink2)
                .lineLimit(2)
                .accessibilityLabel("歌唱 \(names.joined(separator: "、"))")
        }
    }
}

// MARK: - 振り仮名 (ルビ)

/// 歌詞の振り仮名 (本文の記法は `五輪咲《ごりん》` / `｜ダミー《だみ》`) を、記号を外して**親字の上**に
/// 小さく乗せる。読み方はコア (`lyricRubySpans`) が持つ。被せの括弧はここでは触らない。
///
/// SwiftUI の Text は振り仮名を組めないので、振り仮名のある行だけ UILabel (CoreText の
/// `kCTRubyAnnotationAttributeName`) で描く (`ImasRubyLabel`)。振り仮名の無い行は今まで通り Text。
///
/// ⚠️ 歌詞の本文を扱う。組み立てた文字列を保存・共有しないこと (`Models/Lyrics.swift` 冒頭)。
/// UILabel は選択もコピーもできない (できる部品に差し替えないこと)。
enum ImasRubyText {
    /// 本文の 1 スカラーの役割。
    enum Role: Equatable {
        /// そのまま出す文字 (`rubyIndex` があれば、その振り仮名の親字)。
        case text(rubyIndex: Int?)
        /// 振り仮名の読み (親字の上に乗る。本文としては出さない)。
        case reading
        /// 《》｜ の記号 (出さない)。
        case hidden
    }

    static func hasRuby(_ text: String) -> Bool { !lyricRubySpans(text: text).isEmpty }

    /// 各スカラーの役割と、振り仮名ごとの読み。
    static func roles(_ text: String) -> (roles: [Role], readings: [String]) {
        let scalars = Array(text.unicodeScalars)
        var roles = [Role](repeating: .text(rubyIndex: nil), count: scalars.count)
        var readings: [String] = []
        for span in lyricRubySpans(text: text) {
            let open = Int(span.open), close = Int(span.close)
            guard open < close, close <= scalars.count, Int(span.baseEnd) <= open else { continue }
            let index = readings.count
            readings.append(String(String.UnicodeScalarView(scalars[(open + 1)..<(close - 1)])))
            for k in Int(span.baseStart)..<Int(span.baseEnd) { roles[k] = .text(rubyIndex: index) }
            roles[open] = .hidden
            roles[close - 1] = .hidden
            for k in (open + 1)..<(close - 1) { roles[k] = .reading }
            if let marker = span.marker, Int(marker) < scalars.count { roles[Int(marker)] = .hidden }
        }
        return (roles, readings)
    }

    /// 振り仮名を親字の上に乗せた UILabel 用の文字列。`decorate` で範囲ごとの書式 (アンカーの地の色など) を足す
    /// (位置は元の本文のスカラー位置)。
    static func attributed(_ text: String, font: UIFont, color: UIColor, lineSpacing: CGFloat = 0,
                           decorate: (Int) -> [NSAttributedString.Key: Any] = { _ in [:] }) -> NSAttributedString {
        let scalars = Array(text.unicodeScalars)
        let (roles, readings) = roles(text)
        var spacing = lineSpacing
        let paragraph = withUnsafeBytes(of: &spacing) { raw in
            var setting = CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size,
                                                  value: raw.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let result = NSMutableAttributedString()
        var k = 0
        while k < scalars.count {
            guard case .text(let rubyIndex) = roles[k] else { k += 1; continue }
            let start = k
            let extra = decorate(k)
            while k < scalars.count, roles[k] == .text(rubyIndex: rubyIndex), decorate(k).count == extra.count { k += 1 }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            ]
            attrs.merge(extra) { _, new in new }
            if let rubyIndex {
                let annotation = CTRubyAnnotationCreateWithAttributes(
                    .auto, .auto, .before, readings[rubyIndex] as CFString,
                    [kCTRubyAnnotationSizeFactorAttributeName: 0.5,
                     kCTForegroundColorAttributeName: color.withAlphaComponent(0.8).cgColor] as CFDictionary)
                attrs[NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)] = annotation
            }
            result.append(NSAttributedString(string: String(String.UnicodeScalarView(scalars[start..<k])), attributes: attrs))
        }
        return result
    }
}

/// 振り仮名のある歌詞の 1 行。UILabel は振り仮名を描かないので、CoreText で直接組む。
/// 幅に合わせて折り返し、高さは中身に合わせる。アンカーの地の色 (`.backgroundColor`) も自前で敷く。
struct ImasRubyLabel: UIViewRepresentable {
    let attributed: NSAttributedString

    func makeUIView(context: Context) -> RubyTextView { RubyTextView() }

    func updateUIView(_ view: RubyTextView, context: Context) {
        view.attributed = attributed
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RubyTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        return CGSize(width: width, height: uiView.fittingHeight(width: width))
    }

    final class RubyTextView: UIView {
        var attributed = NSAttributedString() {
            didSet { setNeedsDisplay(); invalidateIntrinsicContentSize() }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
            contentMode = .redraw
            // ⚠️ 選択・コピーの口を付けないこと (歌詞の取り出し口になる)。
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func fittingHeight(width: CGFloat) -> CGFloat {
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let size = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(location: 0, length: 0), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            return ceil(size.height) + 2
        }

        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.textMatrix = .identity
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                                 CGPath(rect: bounds, transform: nil), nil)
            let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            // アンカーの地の色を、文字の下に敷く (CoreText は背景色を描かない)。
            for (line, origin) in zip(lines, origins) {
                for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                    let attrs = CTRunGetAttributes(run) as NSDictionary
                    guard let color = attrs[NSAttributedString.Key.backgroundColor] as? UIColor else { continue }
                    var ascent: CGFloat = 0, descent: CGFloat = 0
                    let width = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil)
                    let x = CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil)
                    context.setFillColor(color.cgColor)
                    context.fill(CGRect(x: origin.x + x, y: origin.y - descent, width: width, height: ascent + descent))
                }
            }
            CTFrameDraw(frame, context)
        }
    }
}
