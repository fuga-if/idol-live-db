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
struct CallGuideCallRows: View {
    let calls: [LyricCall]
    /// アンカーの通し番号 (call.id → 0 始まり)。1 つしか無い行では nil を渡す。
    let anchorIndexes: [String: Int]?
    /// 編集モードのみ非 nil。既存コールのタップ編集に使う。
    var onTap: ((LyricCall) -> Void)?

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
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(marker(for: call))
                .font(.imasCaption2)
                .foregroundStyle(DS.ink3)
                .frame(width: 16, alignment: .trailing)
            Text(call.text)
                .font(.imasFootnote.weight(.semibold))
                .foregroundStyle(call.emphasis.color)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if call.isStale {
                Text("ズレ")
                    .font(.imasCaption2.weight(.bold))
                    .foregroundStyle(DS.warning)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(DS.warning.opacity(0.16), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("コール: \(call.text)。\(call.emphasis.label)")
    }

    private func marker(for call: LyricCall) -> String {
        guard let index = anchorIndexes?[call.id] else { return "↳" }
        return CallGuideText.anchorMarker(index)
    }
}

// MARK: - 凡例

/// コール表のヘッダに出す凡例。
///
/// **その曲で実際に使われているものだけ**を出す (実物と同じ振る舞い。曲ごとに凡例が違う)。
/// 使っていない強調度や手拍子を並べても、読み手には雑音にしかならない。
struct CallGuideLegend: View {
    let emphases: [CallEmphasis]
    let claps: [LyricClap]

    var body: some View {
        if !emphases.isEmpty || !claps.isEmpty {
            CallGuideFlowLayout(itemSpacing: DS.sp2, lineSpacing: DS.sp2) {
                ForEach(emphases, id: \.self) { emphasis in
                    legendItem(dot: emphasis.color, text: emphasis.label)
                }
                ForEach(claps, id: \.self) { clap in
                    legendItem(symbol: clap.symbol, text: clap.label)
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
/// 選択は「開始文字をタップ → 終了文字をタップ」の 2 タップ。ドラッグにしないのは、
/// 折り返した行をまたぐドラッグの当たり判定が不安定で、1 文字ズレが起きやすいから。
struct CallGuideSelectableLine: View {
    let text: String
    /// 既存アンカーの下敷き (編集中も、どこに何が掛かっているか見えるように)。
    let highlights: [CallGuideText.Highlight]
    /// 範囲が確定したときに (スカラー開始, スカラー終了, 選択文字列) を返す。
    let onSelect: (Int, Int, String) -> Void
    /// 選択待ちであることを外から解除する合図 (シートを閉じたとき等)。
    var resetToken: Int = 0

    @Environment(\.colorScheme) private var scheme
    @State private var pendingStart: Int?

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
                    .contentShape(Rectangle())
                    .onTapGesture { tap(cell, in: cells) }
            }
        }
        .onChange(of: resetToken) { _, _ in pendingStart = nil }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityHint("開始と終了の文字を順にタップしてコールの範囲を選びます")
    }

    @ViewBuilder
    private func background(for cell: CallGuideText.Cell) -> some View {
        let theme = ImasTheme.derive(seed: nil, scheme: scheme)
        if pendingStart == cell.id {
            Rectangle().fill(theme.accent.opacity(0.35))
        } else if let color = highlightColor(for: cell) {
            Rectangle().fill(color.opacity(0.18))
        } else {
            Rectangle().fill(Color.clear)
        }
    }

    private func highlightColor(for cell: CallGuideText.Cell) -> Color? {
        highlights.first { $0.start <= cell.scalarStart && cell.scalarEnd <= $0.end }?.color
    }

    private func tap(_ cell: CallGuideText.Cell, in cells: [CallGuideText.Cell]) {
        guard let start = pendingStart else {
            pendingStart = cell.id
            return
        }
        let lower = min(start, cell.id)
        let upper = max(start, cell.id)
        guard cells.indices.contains(lower), cells.indices.contains(upper) else {
            pendingStart = nil
            return
        }
        let scalarStart = cells[lower].scalarStart
        let scalarEnd = cells[upper].scalarEnd
        let selected = cells[lower...upper].map(\.text).joined()
        pendingStart = nil
        onSelect(scalarStart, scalarEnd, selected)
    }
}
