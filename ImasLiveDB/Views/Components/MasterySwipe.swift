import SwiftUI

/// 行をスワイプすると出る段階ピッカー。
///
/// タップで 1 段上げる案 (誤爆すると戻せない) と、指の位置が段になるドラッグ案
/// (スクロールと競合する) を捨てて、**既存の swipe actions と同じ手つき**に寄せた。
/// 押し込んだ状態で迷っても何も起きず、ボタンを押した段に決まって閉じる。
///
/// ## なぜ「未設定」だけ逆向きに置くか
///
/// trailing に 4 段 + 未設定 の 5 つを並べると **画面幅に収まらず端が見切れる**
/// (iPhone 15 Pro / 393pt で実測。4 段だけなら約 330pt で収まる)。
/// 数を減らすために消すのではなく、**破壊的な操作を反対側に分ける**ことで
/// 両方フルラベルで出せるようにした。段数を増やしたときに最初に溢れるのも
/// trailing 側なので、そこを 4 つ前後に保てる形にしておく。
///
/// 曲一覧の行には他の swipe actions を割り当てていないので、左右とも空いている
/// (`swipeActions` を使っているのは `CalendarDayDetailView` だけ)。
struct MasterySwipeActions: ViewModifier {
    let songId: String
    // 既存の作法に合わせて shared を直接見る (environment には注入されていない)。
    // @Observable なので body 内で読めば変更は観測される。
    private var marks: UserMarkService { UserMarkService.shared }

    func body(content: Content) -> some View {
        let scale = marks.scale
        // ⚠️ ここで `marks.mastery(songId:)` を読むと、**一覧の全行**が
        // マークの変更番号に依存する。1 曲付け替えただけで 2,000 行が再評価される
        // (段階は行のチップが持っているので、ここでは要らない)。
        return content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // swipe actions は右から並ぶので、最上段を手前に置いて
                // 指の届く位置に「覚えた」を出す。
                ForEach(levelsTopFirst(scale), id: \.self) { level in
                    stageButton(level, scale: scale)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                // 「未設定に戻す」は常に出す。出し分けのために現在値を読むと、
                // 行ごとにマークへ依存して一覧全体が再評価される。
                Button(role: .destructive) { set(0) } label: {
                    Label("未設定", systemImage: "minus.circle")
                }
            }
    }

    private func levelsTopFirst(_ scale: MasteryScale) -> [UInt8] {
        Array((1...Int(scale.steps)).reversed()).map(UInt8.init)
    }

    /// ラベルは**文字だけ**にする。`Label(_, systemImage:)` にすると幅が足りない
    /// ときにアイコンだけが残って、どの段なのか読めなくなる (実機で「覚えた」が
    /// チェックマーク 1 個になった)。いま何段かは行のチップが示すので、
    /// ここで現在値を示す必要はない。
    private func stageButton(_ level: UInt8, scale: MasteryScale) -> some View {
        Button { set(level) } label: {
            Text(scale.swipeLabel(level))
        }
        .tint(MasteryPalette.fill(level: level, steps: scale.steps))
    }

    private func set(_ level: UInt8) {
        // 失敗しても一覧は前の値のまま (壊れた値を見せない)。書けなかったことは知らせる。
        do { try marks.setMastery(songId: songId, level: level) }
        catch { LocalWriteFailure.report(error, action: "習熟度の記録") }
    }
}

extension View {
    /// 曲の行に習熟度のスワイプピッカーを付ける。
    func masterySwipe(songId: String) -> some View {
        modifier(MasterySwipeActions(songId: songId))
    }
}

// MARK: - 行に出す段階チップ

/// 一覧の行に出す現在の段階。未設定は出さない (既定)
/// — 一覧全体が段階の色でうるさくならないように。
struct MasteryChip: View {
    let level: UInt8
    let scale: MasteryScale
    /// 未設定のときも点線の枠で出すか。習熟度の詳細画面では出す。
    var showsUnset: Bool = false

    var body: some View {
        if level == 0 && !showsUnset {
            EmptyView()
        } else {
            Text(scale.shortLabel(level))
                .font(.imasScaled(10, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, DS.sp3)
                .padding(.vertical, DS.sp1 + 1)
                .foregroundStyle(MasteryPalette.ink(level: level, steps: scale.steps))
                .background {
                    if level == 0 {
                        RoundedRectangle(cornerRadius: DS.rXS, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .foregroundStyle(DS.ink3)
                    } else {
                        RoundedRectangle(cornerRadius: DS.rXS, style: .continuous)
                            .fill(MasteryPalette.fill(level: level, steps: scale.steps))
                    }
                }
                .accessibilityLabel("習熟度 \(scale.label(level))")
        }
    }
}
