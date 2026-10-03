import SwiftUI
import UIKit

// =============================================================================
// 意味で引く決まり (docs/DESIGN_SYSTEM.md §4・§9・§10)
//
// `DS.sp*` / `DS.r*` / `Font.imas*` は「値の段」。ここはその上に「役割の名前」を付ける。
// 部品はここの名前で寸法と文字を引き、画面のコードは部品だけを使う (数字を書かない)。
// =============================================================================

// MARK: - 面の角丸

extension DS {
    /// カードの角丸。チケットや入場証と同じ、紙を切り抜いた程度の丸み。
    ///
    /// 以前は OS の表 (iOS 26 で 26pt) に揃えていたが、「会場とチケット」では面を紙として
    /// 見せるので、OS の表より角を立てる。OS の表 (設定) と同じ画面に並べることはしない。
    static var rCard: CGFloat { 18 }

    /// カードの中に入れる面の角丸。外の角丸から内側の余白を引いて同心円にする。
    static var rInner: CGFloat { max(6, rCard - Space.card) }

    /// 札の角丸。札は「印刷された小さな見出し」なので、ほぼ角のある四角にする。
    /// カプセルにすると、淡い色の丸い札が並ぶ「よくある見た目」になる (v1 の反省)。
    static let rTag: CGFloat = 4

    /// 押せる部品 (ボタン・切り替え・入口) の角丸。高さに比例させる (50→12, 40→10, 32→8)。
    /// 中身の部品はカプセルにしない。カプセルは OS の枠 (タブバー・ツールバー) だけが使う形。
    static func rControl(_ height: CGFloat) -> CGFloat { (height * 0.24).rounded() }

    /// 記号を入れる角丸四角の角丸。設定の行の頭など、OS の形に合わせる所だけで使う。
    static func rIconTile(_ size: CGFloat) -> CGFloat { (size * 0.28).rounded() }

    /// ジャケの角丸。CD のジャケは角のある四角なので小さく (下限 3・上限 10)。
    static func rArtwork(_ size: CGFloat) -> CGFloat { min(10, max(3, (size * 0.08).rounded())) }
}

// MARK: - 地

/// 部品が置かれている地。
///
/// 「会場とチケット」では地は 1 種類 (ロビーの生成り / 客席の闇) で、面はどこでも `DS.surface`。
/// 一覧・詳細・ハブ (`ImasPage`) とフォーム・設定 (`imasForm()`) の区別は残しておく
/// (面の影や線の出し方を地ごとに変えたくなったときの受け口)。
enum ImasBackdrop {
    /// 一覧・詳細・ハブの地。
    case paper
    /// フォーム・設定の地。
    case grouped
}

private struct ImasBackdropKey: EnvironmentKey {
    static let defaultValue: ImasBackdrop = .grouped
}

extension EnvironmentValues {
    var imasBackdrop: ImasBackdrop {
        get { self[ImasBackdropKey.self] }
        set { self[ImasBackdropKey.self] = newValue }
    }
}

extension DS {
    /// 地の上に置く面の色。どの地でも同じ面 (生成りの紙 / 客席の暗い面)。
    static func surface(on backdrop: ImasBackdrop) -> Color {
        DS.surface
    }
}

// MARK: - 意味のある余白

extension DS {
    /// 役割で引く余白。値は 4pt の段 (`sp*`) から選んでいる。
    enum Space {
        /// 画面の左右。OS の表の内側の余白と同じ。
        static let screen: CGFloat = 16
        /// 区画どうしの間。
        static let section: CGFloat = 28
        /// 見出しと中身の間。
        static let header: CGFloat = 8
        /// 中身と補足文の間。
        static let note: CGFloat = 6
        /// カードの内側。
        static let card: CGFloat = 16
        /// 行の左右。
        static let rowH: CGFloat = 16
        /// 行の上下 (一覧)。
        static let rowV: CGFloat = 12
        /// 行の上下 (カードの中の短い一覧・ピッカー)。
        static let rowVCompact: CGFloat = 8
        /// 行の中の、先頭・本文・末尾の間。
        static let rowGap: CGFloat = 12
        /// 並んだもの同士 (チップ・ボタン・タイル)。
        static let gap: CGFloat = 8
        /// 詰めて並べるもの同士 (題と副題、記号と文字)。
        static let gapTight: CGFloat = 4
        /// ゆったり並べるもの同士。
        static let gapLoose: CGFloat = 12
    }
}

// MARK: - 大きさ

extension DS {
    /// 部品の大きさの段。画面からは部品の種類として選ぶ (数字は書かない)。
    enum Size {
        /// 押せる所の最小。
        static let touch: CGFloat = 44
        /// チップの高さ。
        static let chip: CGFloat = 32
        /// 札の高さ。
        static let badge: CGFloat = 20
        /// リードバーの幅。
        static let leadBar: CGFloat = 3
    }
}

// MARK: - 文字の役割

/// 文字の役割。部品はこの名前で書体と色を引く (`.imasText(_:)`)。
///
/// 値は iOS の文字の段 (`Font.imas*`) から選んでいる。Dynamic Type とアプリ内の
/// 文字サイズ倍率の両方に追従する。
enum ImasTextRole {
    /// 詳細の頭の名前 (30pt 極太・詰め組み)。
    case heroTitle
    /// 区画の見出し・大 (20pt 太字・詰め組み)。詳細とハブの区画。
    case sectionTitle
    /// 区画の見出し・小 (13pt 中太・灰)。一覧・設定・フォーム・カードの中の小分け。
    case sectionLabel
    /// カードの題 (19pt 太字・詰め組み)。
    case cardTitle
    /// 行の題 (16pt 中太)。曲・アイドル・ライブなど「もの」の名前。
    case rowTitle
    /// 操作・設定の行の題 (16pt 標準)。入口・スイッチ・選択肢・行の形のボタン。
    case rowLabel
    /// 行の副題 (13pt・灰)。
    case rowSubtitle
    /// 行の下段・日付・回数 (12pt・薄灰)。
    case meta
    /// 本文 (17pt)。
    case body
    /// 項目と値の行の文字 (15pt)。
    case value
    /// 補足文 (13pt・灰)。囲まない。
    case note
    /// 目印 (12pt 太字)。カードの上の「担当」「あと 37 日」など。
    case eyebrow
    /// 札の文字 (11pt 太字)。
    case badge
    /// チップの文字 (14pt 中太)。
    case chip
    /// 英字の印字 (10.5pt 等幅・大文字・字間)。チケットの「ADMIT ONE」、見出しの横の「PLAY」、
    /// 頭の「PRODUCE · 2026.10.01 THU」。日本語の見出しと並べて、印刷物の手触りを出す。
    case imprint
    /// 目一杯小さい札 (8pt 太字)。月カレンダーの単日バー・受付帯・あふれ件数「+n」など、
    /// 枠の高さが決まっていて文字を詰め込むしかない場所専用 (一般の文字サイズには使わない)。
    case micro

    var font: Font {
        switch self {
        // 見出しは かなを詰めて組む (`imasHeading`)。本文・行は詰めない。
        case .heroTitle: return .imasHeading(30, weight: .heavy)
        case .sectionTitle: return .imasHeading(20, weight: .bold)
        case .sectionLabel: return .imasFootnote.weight(.semibold)
        case .cardTitle: return .imasHeading(19, weight: .bold)
        case .rowTitle: return .imasCallout.weight(.semibold)
        case .rowLabel: return .imasCallout
        case .rowSubtitle: return .imasFootnote
        case .meta: return .imasCaption
        case .body: return .imasBody
        case .value: return .imasSubhead
        case .note: return .imasFootnote
        case .eyebrow: return .imasCaption.weight(.bold)
        case .badge: return .imasCaption2.weight(.bold)
        case .chip: return .imasScaled(14, weight: .semibold)
        case .imprint: return .imasMono(10.5, weight: .medium)
        case .micro: return .imasScaled(8, weight: .semibold)
        }
    }

    /// 既定の文字色。部品が明示しない限りこれを使う。
    var color: Color {
        switch self {
        case .heroTitle, .sectionTitle, .cardTitle, .rowTitle, .rowLabel, .body, .value: return DS.ink
        case .sectionLabel, .rowSubtitle, .note, .chip: return DS.ink2
        case .meta, .micro: return DS.ink3
        case .eyebrow, .badge, .imprint: return DS.ink2
        }
    }
}

extension View {
    /// 文字の役割を当てる (書体 + 色)。部品の中で使う。
    /// 色を替えるときは `color:` で渡す (後ろに `.foregroundStyle` を足しても内側の色が勝つので効かない)。
    /// 印字 (`.imprint`) は字間を空ける。大文字にはしない: ブランド名 (SideM) や公演名のような値の綴りを
    /// 変えないため。ADMIT ONE・SETLIST のような決まった英字は、呼び出し側で大文字のまま書く。
    func imasText(_ role: ImasTextRole, color: Color? = nil) -> some View {
        font(role.font)
            .foregroundStyle(color ?? role.color)
            .tracking(role == .imprint ? 0.6 : 0)
    }
}

// MARK: - 数字

/// 数字の書体の大きさ。ゲームのステージ (`QS.num`) と同じ「細長い太字・等幅」の系統。
/// 会場の電光掲示板とチケットの日付の数字。数字はこれだけで組む (本文の書体で大きくしない)。
enum ImasNumeralSize {
    /// 大きいチケットのカウントダウン (76pt)。画面に 1 つだけ。
    case poster
    /// チケットの半券のカウントダウン・月の見出し (54pt)。
    case countdown
    /// 半券の日付・年の見出し (28pt)。
    case date
    /// 統計タイル・回収率・掲示板 (30pt)。
    case large
    /// 行の末尾の票・確率・回数 (20pt)。
    case medium
    /// 曲順・下段の回数 (15pt)。
    case small

    var font: Font {
        switch self {
        // 大きい数字はステージと同じ compressed。小さい数字は詰まりすぎないよう condensed。
        case .poster: return Font.imasScaled(76, weight: .black).width(.compressed).monospacedDigit()
        case .countdown: return Font.imasScaled(54, weight: .black).width(.compressed).monospacedDigit()
        case .date: return Font.imasScaled(28, weight: .heavy).width(.compressed).monospacedDigit()
        case .large: return Font.imasScaled(30, weight: .heavy).width(.compressed).monospacedDigit()
        case .medium: return Font.imasScaled(20, weight: .bold).width(.condensed).monospacedDigit()
        case .small: return Font.imasScaled(15, weight: .semibold).width(.condensed).monospacedDigit()
        }
    }

    /// 単位の書体。
    var unitFont: Font {
        switch self {
        case .poster, .countdown: return .imasMono(10.5, weight: .medium)
        case .date, .large: return .imasFootnote.weight(.semibold)
        case .medium: return .imasCaption.weight(.semibold)
        case .small: return .imasCaption2.weight(.semibold)
        }
    }
}

// MARK: - 動き

extension Animation {
    /// 選択・開閉など、状態が切り替わるときの標準の動き。
    static var imasStandard: Animation { .snappy(duration: 0.22) }
}

/// 押せるカード・セル・ボタンの押し心地。押すと少し縮んで暗くなる。
///
/// クイズの `QuizPressStyle` (0.97) とイントロドンの `IDPressStyle` (0.96 + 不透明 0.82) が
/// 別々にあったのを 1 つにする。
struct ImasPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.imasStandard, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ImasPressStyle {
    /// 押せるカード・セル用の押し心地。
    static var imasPress: ImasPressStyle { ImasPressStyle() }
}

// MARK: - OS の枠

/// ナビバーなど OS の枠の見た目。起動時に 1 回だけかける。
enum ImasChrome {
    /// ナビバーの題を詰め組みにする (「プロデュース」「スケジュール」のかなが間延びしないように)。
    /// 大きさと太さは OS の既定のまま、Dynamic Type の段に合わせて拡大する。
    @MainActor static func apply() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle)
                .scaledFont(for: Font.imasProportionalUIFont(34, weight: .bold)),
        ]
        bar.titleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .headline)
                .scaledFont(for: Font.imasProportionalUIFont(17, weight: .semibold)),
        ]
    }
}

// MARK: - 実体の色が環境にあるか

extension ImasTheme {
    /// 主ボタン・選択の塗りに使う色。実体の色が無い (ニュートラルな) 画面では白黒 (`DS.sys`)。
    var actionFill: Color { isNeutral ? DS.sys : accent }
    /// `actionFill` の上の文字色。
    var onActionFill: Color { isNeutral ? DS.onSys : onAccent }
    /// ペンライトの色。実体の色が無ければ墨。
    var penlight: Color { isNeutral ? DS.ink : dot }
}

// MARK: - 縞 (虹色)

/// 単色で表せない目印 (合同ライブ) の虹色。色は溶かさず、くっきり区切った縞にする
/// (ぼんやり移ろうグラデーションは使わない)。
enum ImasStripes {
    static func vertical(_ colors: [Color]) -> LinearGradient {
        LinearGradient(stops: stops(colors), startPoint: .top, endPoint: .bottom)
    }

    static func horizontal(_ colors: [Color]) -> LinearGradient {
        LinearGradient(stops: stops(colors), startPoint: .leading, endPoint: .trailing)
    }

    private static func stops(_ colors: [Color]) -> [Gradient.Stop] {
        guard !colors.isEmpty else { return [] }
        let n = CGFloat(colors.count)
        return colors.enumerated().flatMap { i, c in
            [Gradient.Stop(color: c, location: CGFloat(i) / n), Gradient.Stop(color: c, location: CGFloat(i + 1) / n)]
        }
    }
}

// MARK: - 遷移の後に読み込む

extension View {
    /// 画面の読み込みを、押し込み・シートの出る動きが終わってから始める。
    /// 動きの最中に重い読み込みと再描画が重なると、出る動きがカクつく (中身は読み込み中の表示で先に出す)。
    func imasLoadAfterTransition(_ action: @escaping @Sendable () async -> Void) -> some View {
        task {
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

// MARK: - タブを切り替えたときのスクロール

extension View {
    /// 印を付けた位置 (タブの見出しの直前) が、スクロールで画面の上より上へ流れているか。
    /// タブを切り替えたとき、前のタブのスクロール位置のまま次のタブの途中が出ないよう、
    /// 流れていればタブの見出しまで戻す判断に使う ([space] はスクロール面の名前付き座標空間)。
    func imasTracksScrolledPast(in space: String, _ passed: Binding<Bool>) -> some View {
        onGeometryChange(for: Bool.self) { $0.frame(in: .named(space)).minY < -1 } action: { passed.wrappedValue = $0 }
    }
}
