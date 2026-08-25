import SwiftUI

// =============================================================================
// コールガイドの行まわりの部品
//
// ── 位置合わせの方式について ────────────────────────────────────────────────
// 実物のコール表 (くわね氏のコール表 等) は等幅前提で、半角スペースを詰めて
// コールをアンカーした語の**真下**に置いている。iOS ではこれを再現できない:
//   * 本文は可変幅 (SF Pro + ヒラギノ)。文字ごとに幅が違うのでスペース数で揃わない。
//   * Dynamic Type + アプリ内文字倍率で幅が実行時に変わる。
//   * 画面幅が狭いので歌詞行が折り返す。折り返すと「真下」が別の行になる。
// 等幅フォントに切り替えれば桁は揃うが、日本語の等幅は可読性が落ちるうえ
// 折り返しの問題は残る。
//
// そこで採ったのが:
//   1. アンカーした範囲を**行内で色付きに敷く** (どこに掛かるコールかを行の中で示す)
//   2. コールはその行の**直下にインデントして並べる** (上下の近さで対応を示す)
//   3. 同じ行に複数のアンカーがあるときだけ ①②③ を振って一意に対応付ける
// 「真下に置く」を「同じ色で示し、直下に並べる」に置き換えた形。折り返しても
// Dynamic Type を上げても崩れない。
// =============================================================================

// MARK: - 手拍子記号

/// 行頭の手拍子記号 (★裏拍 / ■4つ打ち / ♠PPPH / ♥コールなし)。
/// 指定の無い行でも幅を確保して、記号のある行だけ本文が右にズレるのを防ぐ。
struct CallGuideClapGlyph: View {
    let clap: LyricClap?
    /// 編集モードでは指定なしの行にも押せる場所が要る。
    var isPlaceholderVisible: Bool = false

    static let columnWidth: CGFloat = 18

    var body: some View {
        Group {
            if let clap {
                Text(clap.symbol)
                    .font(.imasCaption)
                    .foregroundStyle(DS.ink2)
                    .accessibilityLabel(clap.label)
            } else if isPlaceholderVisible {
                Image(systemName: "plus.circle")
                    .font(.imasCaption2)
                    .foregroundStyle(DS.ink3)
                    .accessibilityLabel("手拍子を指定")
            } else {
                Color.clear
            }
        }
        .frame(width: Self.columnWidth, alignment: .leading)
    }
}

// MARK: - コール行

/// 歌詞行の直下に並ぶコール群。
///
/// 同一アンカーに複数のコールが並ぶことがあるので、配列順をそのまま保つ (並べ替えない)。
/// 行の中にアンカーが 2 つ以上あるときだけ ①②③ を振って、どの範囲に掛かるコールかを示す。
///
/// ── 「どこに掛かるか」と「いつ出すか」は別の軸 ─────────────────────────────
/// アンカー範囲が答えるのは**どのフレーズに対するコールか**だけで、被せるのか後に返すのかは
/// `timing` が別に持つ。2 つを 1 つの記号に混ぜると読めなくなるので、表示も分けてある:
///
///   1. 記号の列 = どこに掛かるか
///      * 範囲付き … `↳` (行内の 1 箇所に掛かる) / `①②③` (行内に複数のアンカーがある)
///      * 幅ゼロ  … `»` (掛かる範囲が無い。行内に敷いた色も無い)
///   2. 札 = 例外だけを出す
///      * `同時` … 歌に被せるコール。追っかけが既定なので、被せる方だけ札を出す。
///      * `行末` … 幅ゼロ。**同じ行に範囲付きが混ざっているときだけ**出す
///        (混ざっていなければ札は情報を増やさない。①②③ を 1 つしか無い行に振らないのと同じ)。
struct CallGuideCallRows: View {
    @Environment(\.colorScheme) private var scheme
    let calls: [LyricCall]
    /// アンカーの通し番号 (call.id → 0 始まり)。1 つしか無い行では nil を渡す。
    let anchorIndexes: [String: Int]?
    /// 編集モードのみ非 nil。既存コールのタップ編集に使う。
    var onTap: ((LyricCall) -> Void)?

    /// 範囲付きと幅ゼロが同じ行に同居しているか。
    private var isMixed: Bool {
        calls.contains(where: \.hasAnchor) && calls.contains { !$0.hasAnchor }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(calls) { call in
                if let onTap {
                    Button { onTap(call) } label: { row(call) }
                        .buttonStyle(.plain)
                } else {
                    row(call)
                }
            }
        }
        .padding(.leading, DS.sp5)
        .padding(.top, 2)
    }

    private func row(_ call: LyricCall) -> some View {
        let theme = ImasTheme.derive(seed: nil, scheme: scheme)
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(marker(for: call))
                .font(.imasCaption2)
                .foregroundStyle(DS.ink3)
                .frame(width: 16, alignment: .trailing)
            Text(call.text)
                .font(.imasFootnote.weight(.semibold))
                .foregroundStyle(call.emphasis.color(accent: theme.accent))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if call.isOverlapping {
                tag(CallTiming.over.label, color: DS.sys2)
            } else if isMixed, !call.hasAnchor {
                tag("行末", color: DS.ink3)
            }
            if call.isStale {
                tag("ズレ", color: DS.warning)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(call))
    }

    private func accessibilityLabel(_ call: LyricCall) -> String {
        let place = call.hasAnchor ? call.timing.label : "行末"
        return "\(place)のコール: \(call.text)。\(call.emphasis.label)"
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.imasCaption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule())
    }

    private func marker(for call: LyricCall) -> String {
        // 幅ゼロは行内に掛かる範囲が無い = ①②③ / ↳ の対応付けが成り立たないので別記号。
        guard call.hasAnchor else { return "»" }
        guard let index = anchorIndexes?[call.id] else { return "↳" }
        return CallGuideText.anchorMarker(index)
    }
}

// MARK: - 行末にコールを足すボタン

/// 行末 (追っかけ) にコールを 1 タップで足すボタン。
///
/// アイマスのコールは**フレーズの後で客が返す**追っかけが多数派で、歌詞に被せるものは
/// 少数派。多数派を「文字を 2 回タップして範囲を選ぶ → シート」の 3 手に置くのは重いので、
/// 行末にボタンを常設して 1 タップでシートまで飛ばす (範囲選択は被せる用に残す)。
///
/// 置き場所は**最後の文字のすぐ後ろ**。「行末に付く」ことを位置そのもので示すためで、
/// 行が折り返しても最後の文字に付いて回る。
struct CallGuideAppendCallButton: View {
    let action: () -> Void
    /// 親要素が VoiceOver 用のアクションを別に出す場合は true (二重に読み上げさせない)。
    var isAccessibilityHidden = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ImasTheme.derive(seed: nil, scheme: scheme)
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.imasFootnote)
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("行末にコールを追加")
        .accessibilityHidden(isAccessibilityHidden)
    }
}

// MARK: - 凡例

/// コール表のヘッダに出す凡例。
///
/// **その曲で実際に使われているものだけ**を出す (実物と同じ振る舞い。曲ごとに凡例が違う)。
/// 使っていない強調度や手拍子を並べても、読み手には雑音にしかならない。
struct CallGuideLegend: View {
    @Environment(\.colorScheme) private var scheme
    let emphases: [CallEmphasis]
    let claps: [LyricClap]
    /// 「同時」のコールがこの曲にあるか。追っかけ (既定) は凡例に出さない。
    var showsOverTiming: Bool = false

    private var isEmpty: Bool { emphases.isEmpty && claps.isEmpty && !showsOverTiming }

    var body: some View {
        let theme = ImasTheme.derive(seed: nil, scheme: scheme)
        if !isEmpty {
            CallGuideFlowLayout(itemSpacing: DS.sp2, lineSpacing: DS.sp2) {
                ForEach(emphases, id: \.self) { emphasis in
                    legendItem(dot: emphasis.color(accent: theme.accent), text: emphasis.label)
                }
                ForEach(claps, id: \.self) { clap in
                    legendItem(symbol: clap.symbol, text: clap.label)
                }
                if showsOverTiming {
                    legendItem(symbol: CallTiming.over.label, text: "歌に被せる")
                }
            }
        }
    }

    private func legendItem(dot: Color? = nil, symbol: String? = nil, text: String) -> some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            if let symbol { Text(symbol).font(.imasCaption2).foregroundStyle(DS.ink2) }
            Text(text).font(.imasCaption2.weight(.semibold)).foregroundStyle(DS.ink2)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(DS.fill, in: Capsule())
    }
}

// MARK: - 編集モードの範囲選択

/// 編集モードの歌詞行。1 書記素クラスタずつ独立したタップ対象に割って並べる。
///
/// システムのテキスト選択 (`textSelection(.enabled)`) は使わない。理由は 2 つ:
///   1. SwiftUI は選択範囲を**アプリ側に渡してくれない**。「どこを選んだか」が取れない以上、
///      アンカー (start/end) を作れない。
///   2. システム選択は同時にコピーメニューを連れてくる。歌詞タブに一度でもコピー導線が
///      生えると、閲覧モードへ漏れたときに JASRAC 許諾の条件 (一括ダウンロード不可) を破る。
/// 独自の範囲選択なら、編集モードの View にしか選択の口が存在しない = 閲覧モードには
/// 構造的に漏れない。
///
/// 選び方は 2 通りあり、**どちらでも同じ結果**になる:
///   1. なぞる — 長押し (約 0.2 秒) してから指を滑らせる。なぞった範囲がその場で色付く。
///   2. 2 タップ — 開始文字をタップ → 終了文字をタップ。
/// 主導線は 1。2 は 1 文字だけ直したいときや、なぞりが効かない場面のために残してある。
///
/// なぞりに**長押しを前置している**のは、この行が `ScrollView` の中にいるから。
/// 前置しないと歌詞行の上から始まる縦スクロールが全部選択に食われて、編集モードで
/// ページを送れなくなる。長押しを挟めば、スクロールのフリック (すぐ動く) では成立せず、
/// 選ぶつもりの「置いてから滑らせる」でだけ成立する。iOS 標準のテキスト選択と同じ作法でもある。
///
/// タップもなぞりも受けるのは `CallGuideLineTouchLayer` の 1 枚だけ (SwiftUI のジェスチャは
/// 使わない)。理由はそちらのコメント参照。
///
/// 指の位置から文字を引くのは、各書記素セルの矩形を `PreferenceKey` で集めた対応表
/// (`cellFrames`) と `CallGuideText.cellIndex(at:in:)`。折り返した行では**まず縦の帯 (行) を
/// 合わせてから**その行の中で最も近いセルに寄せるので、行間や行末の余白に指があってもズレない。
///
/// 範囲選択は**歌詞に被せるコール**のための導線。多数派の追っかけ (フレーズの後で返す
/// コール) は行末の ＋ (`CallGuideAppendCallButton`) から 1 タップで入る。
struct CallGuideSelectableLine: View {
    let text: String
    /// 既存アンカーの下敷き (編集中も、どこに何が掛かっているか見えるように)。
    let highlights: [CallGuideText.Highlight]
    /// 範囲が確定したときに (スカラー開始, スカラー終了, 選択文字列) を返す。
    let onSelect: (Int, Int, String) -> Void
    /// 行末に追っかけコールを足す。非 nil のときだけ行末に ＋ を出す
    /// (アンカーの選び直し中など、範囲を選ばせたい局面では nil を渡して隠す)。
    var onAppendCall: (() -> Void)?
    /// 選択待ちであることを外から解除する合図 (シートを閉じたとき等)。
    var resetToken: Int = 0

    @Environment(\.colorScheme) private var scheme
    /// 2 タップ方式で開始文字だけ押された状態。
    @State private var pendingStart: Int?
    /// なぞり中の範囲 (セル添字)。指を離すと nil に戻る。
    @State private var dragRange: ClosedRange<Int>?
    /// なぞりを始めたセル。指が戻ったときに範囲を縮められるよう覚えておく。
    @State private var dragOrigin: Int?
    /// 書記素セルの矩形 (セル添字 → 行内座標)。指の位置から文字を引くのに使う。
    @State private var cellFrames: [Int: CGRect] = [:]
    /// 行末の ＋ の矩形。タッチレイヤがここだけ触らないようにする。
    @State private var appendButtonFrame: CGRect?

    /// 行内の座標系。セルの矩形も指の位置もここで揃える。
    private static let space = "CallGuideSelectableLine"

    var body: some View {
        let cells = CallGuideText.cells(of: text)
        CallGuideFlowLayout(itemSpacing: 0, lineSpacing: 4) {
            ForEach(cells) { cell in
                Text(cell.text)
                    .font(.imasBody)
                    .foregroundStyle(DS.ink)
                    .padding(.horizontal, 0.5)
                    .padding(.vertical, 5)
                    .background(background(for: cell))
                    .background { frameReporter(cell) }
            }
            if let onAppendCall {
                // 1 文字ずつのセルと同じ流れに乗せる (行が折り返しても最後の文字の直後に来る)。
                // VoiceOver では行全体が 1 要素に畳まれてボタンが埋もれるので、
                // 下の `accessibilityActions` で改めてアクションとして出す。
                CallGuideAppendCallButton(action: onAppendCall, isAccessibilityHidden: true)
                    .background { appendButtonFrameReporter }
            }
        }
        .coordinateSpace(.named(Self.space))
        .onPreferenceChange(CellFramesKey.self) { cellFrames = $0 }
        .onPreferenceChange(AppendButtonFrameKey.self) { appendButtonFrame = $0 }
        .overlay {
            CallGuideLineTouchLayer(
                excludedRect: appendButtonFrame,
                onTap: { tap(at: $0, in: cells) },
                onPressChanged: { extendSelection(to: $0) },
                onPressEnded: { point, moved in endSelection(at: point, moved: moved, in: cells) }
            )
        }
        // なぞって範囲が伸び縮みしたことを指に返す (どこまで選べているかを見ずに掴めるように)。
        .sensoryFeedback(.selection, trigger: dragRange)
        .onChange(of: resetToken) { _, _ in reset() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityHint("長押しからなぞる、または開始と終了の文字を順にタップすると、歌詞に被せるコールの範囲を選べます")
        .accessibilityActions {
            if let onAppendCall {
                Button("行末にコールを追加", action: onAppendCall)
            }
        }
    }

    // MARK: - 見た目

    @ViewBuilder
    private func background(for cell: CallGuideText.Cell) -> some View {
        let theme = ImasTheme.derive(seed: nil, scheme: scheme)
        if dragRange?.contains(cell.id) == true || pendingStart == cell.id {
            Rectangle().fill(theme.accent.opacity(0.45))
        } else if let color = highlightColor(for: cell) {
            // 0.18 では暗所でほぼ見えなかった (実機確認)。
            Rectangle().fill(color.opacity(0.30))
        } else {
            Rectangle().fill(Color.clear)
        }
    }

    private func highlightColor(for cell: CallGuideText.Cell) -> Color? {
        highlights.first { $0.start <= cell.scalarStart && cell.scalarEnd <= $0.end }?.color
    }

    private func frameReporter(_ cell: CallGuideText.Cell) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: CellFramesKey.self,
                                   value: [cell.id: geo.frame(in: .named(Self.space))])
        }
    }

    /// ＋ ボタンの矩形。タッチレイヤにここだけ穴を開けるために測る。
    private var appendButtonFrameReporter: some View {
        GeometryReader { geo in
            Color.clear.preference(key: AppendButtonFrameKey.self,
                                   value: geo.frame(in: .named(Self.space)))
        }
    }

    // MARK: - なぞって選ぶ

    /// 長押しが成立した後、指が動くたびに範囲を伸び縮みさせる。
    private func extendSelection(to point: CGPoint) {
        guard let index = CallGuideText.cellIndex(at: point, in: cellFrames) else { return }
        let origin = dragOrigin ?? index
        dragOrigin = origin
        // 2 タップ方式の選択待ちが残っていたら、なぞりが上書きする。
        pendingStart = nil
        dragRange = min(origin, index)...max(origin, index)
    }

    /// 指が離れたとき。動いていなければ「なぞった」ではなく「タップ」として扱う
    /// (そうしないと、少し長めに押しただけで 1 文字ぶんのシートが勝手に開く)。
    private func endSelection(at point: CGPoint, moved: Bool, in cells: [CallGuideText.Cell]) {
        defer { dragOrigin = nil; dragRange = nil }
        if let range = dragRange, range.count > 1 || moved {
            commit(range, in: cells)
        } else {
            tap(at: point, in: cells)
        }
    }

    // MARK: - タップで選ぶ

    /// 1 回目のタップで開始位置を覚え、2 回目で範囲を確定する。
    private func tap(at point: CGPoint, in cells: [CallGuideText.Cell]) {
        guard let index = CallGuideText.cellIndex(at: point, in: cellFrames) else { return }
        guard let start = pendingStart else {
            pendingStart = index
            return
        }
        pendingStart = nil
        commit(min(start, index)...max(start, index), in: cells)
    }

    // MARK: - 確定

    /// セル添字の範囲をスカラー範囲に直して返す。なぞり・2 タップの両方がここに合流するので、
    /// **どちらで選んでも結果は同じ**。
    private func commit(_ range: ClosedRange<Int>, in cells: [CallGuideText.Cell]) {
        guard cells.indices.contains(range.lowerBound),
              cells.indices.contains(range.upperBound) else { return }
        onSelect(cells[range.lowerBound].scalarStart,
                 cells[range.upperBound].scalarEnd,
                 cells[range].map(\.text).joined())
    }

    private func reset() {
        pendingStart = nil
        dragOrigin = nil
        dragRange = nil
    }
}

/// 書記素セルの矩形を親まで持ち上げる。指の位置から文字を引くための対応表。
private struct CellFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 行末の ＋ の矩形を親まで持ち上げる。タッチレイヤの穴あけに使う。
private struct AppendButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

// MARK: - 歌詞行のタッチを受けるレイヤ

/// 歌詞行のタップ / 長押し→なぞりを 1 枚で受ける UIKit 製のレイヤ。
///
/// **なぜ SwiftUI のジェスチャではないのか。**
/// `DragGesture` や `LongPressGesture.sequenced(before:)` を `ScrollView` の中の行に載せると、
/// **その行から始まる縦スクロールが丸ごと死ぬ**。`gesture` でも `simultaneousGesture` でも同じで、
/// 長押しが不成立に終わった (= フリックだった) 場合でもスクロールに戻ってこない。
/// 歌詞タブは画面のほぼ全部が歌詞行なので、編集モードでページを送れなくなってしまう。
/// シミュレータで再現・確認済み。
///
/// `UILongPressGestureRecognizer` ならこの問題が無い:
///   * `allowableMovement` を超えて動けば**認識前に失敗**する → フリックはスクロールに素通し
///   * 認識後は `.changed` で指の位置が流れてくる → 長押し→なぞりがこれ 1 本で書ける
///   * 認識した瞬間、同時認識を許していない `UIScrollView` の pan は弾かれる
///     → なぞっている最中にページが動かない
/// UIKit の標準的な作法 (テーブルの長押し並べ替えと同じ) にそのまま乗る形。
///
/// タップもこのレイヤで受ける。文字セル側にジェスチャを残すと、親子でジェスチャの優先度を
/// 取り合って「長押しが始まらない」「タップが二重に飛ぶ」が起きうるため、
/// 行の当たり判定はこの 1 枚に集約してある。
struct CallGuideLineTouchLayer: UIViewRepresentable {
    /// ここだけタッチを通さない (行末の ＋ ボタンを下の SwiftUI に届けるための穴)。
    var excludedRect: CGRect?
    let onTap: (CGPoint) -> Void
    /// 長押し成立後、指が動くたび。
    let onPressChanged: (CGPoint) -> Void
    /// 指が離れたとき。Bool は「押した位置から動いたか」。
    let onPressEnded: (CGPoint, Bool) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        // 行全体は親側で 1 要素に畳んで読ませているので、このレイヤは読ませない。
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handlePress(_:)))
        press.minimumPressDuration = 0.2
        // 認識前にこれ以上動いたら失敗 = スクロールのフリックを邪魔しない。
        press.allowableMovement = 8
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.excludedRect = excludedRect
        context.coordinator.onTap = onTap
        context.coordinator.onPressChanged = onPressChanged
        context.coordinator.onPressEnded = onPressEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onPressChanged: onPressChanged, onPressEnded: onPressEnded)
    }

    /// ＋ ボタンの上だけ `hitTest` を諦めて、下の SwiftUI にタッチを渡す。
    final class TouchView: UIView {
        var excludedRect: CGRect?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if let excludedRect, excludedRect.contains(point) { return nil }
            return super.hitTest(point, with: event)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void
        var onPressChanged: (CGPoint) -> Void
        var onPressEnded: (CGPoint, Bool) -> Void
        /// 長押しが始まった位置。「なぞったのか、ただ長く押しただけか」の判定に使う。
        private var pressOrigin: CGPoint?

        init(onTap: @escaping (CGPoint) -> Void,
             onPressChanged: @escaping (CGPoint) -> Void,
             onPressEnded: @escaping (CGPoint, Bool) -> Void) {
            self.onTap = onTap
            self.onPressChanged = onPressChanged
            self.onPressEnded = onPressEnded
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            onTap(recognizer.location(in: recognizer.view))
        }

        @objc func handlePress(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began:
                pressOrigin = point
                onPressChanged(point)
            case .changed:
                onPressChanged(point)
            case .ended, .cancelled, .failed:
                let origin = pressOrigin ?? point
                pressOrigin = nil
                onPressEnded(point, hypot(point.x - origin.x, point.y - origin.y) > 8)
            default:
                break
            }
        }

        /// 同時認識は許さない。長押しが成立したらスクロールの pan を弾かせるため
        /// (許すと、なぞっている最中にページが一緒に動く)。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
