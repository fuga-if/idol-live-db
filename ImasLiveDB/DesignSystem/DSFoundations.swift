import SwiftUI

// =============================================================================
// 意味で引く決まり (docs/DESIGN_SYSTEM.md §4・§9・§10)
//
// `DS.sp*` / `DS.r*` / `Font.imas*` は「値の段」。ここはその上に「役割の名前」を付ける。
// 部品はここの名前で寸法と文字を引き、画面のコードは部品だけを使う (数字を書かない)。
// =============================================================================

// MARK: - 面の角丸

extension DS {
    /// カードの角丸。OS の表 (inset grouped) と同じ値にする。
    ///
    /// iOS 26 で OS の表の角が 26pt に丸くなり (iOS 17/18 は 10pt)、自前のカード (14pt) が
    /// フォームや設定と並ぶと形が揃わなくなった。OS の値に合わせれば、どの版でも同じ形に見える。
    /// 値は iOS 26.4 シミュレータで表の角を実測 (26.2pt) して決めた。
    static var rCard: CGFloat {
        if #available(iOS 26, *) { return 26 } else { return 10 }
    }

    /// カードの中に入れる面の角丸。外の角丸から内側の余白を引いて同心円にする。
    static var rInner: CGFloat { max(6, rCard - Space.card) }

    /// 記号を入れる角丸四角 (`ImasIconTile`) の角丸。大きさに対する比率で、アプリアイコンに近い形。
    static func rIconTile(_ size: CGFloat) -> CGFloat { (size * 0.28).rounded() }

    /// ジャケットの角丸。大きさに対する比率 (小さいジャケでも角が潰れないよう下限 6)。
    static func rArtwork(_ size: CGFloat) -> CGFloat { max(6, (size * 0.18).rounded()) }
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
    /// 詳細の頭の名前 (28pt 太字)。
    case heroTitle
    /// 区画の見出し・大 (20pt 太字)。詳細とハブの区画。
    case sectionTitle
    /// 区画の見出し・小 (13pt 中太・灰)。一覧・設定・フォーム・カードの中の小分け。
    case sectionLabel
    /// カードの題 (17pt 太字)。
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

    var font: Font {
        switch self {
        case .heroTitle: return .imasTitle1
        case .sectionTitle: return .imasTitle3.weight(.bold)
        case .sectionLabel: return .imasFootnote.weight(.semibold)
        case .cardTitle: return .imasHeadline.weight(.bold)
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
        }
    }

    /// 既定の文字色。部品が明示しない限りこれを使う。
    var color: Color {
        switch self {
        case .heroTitle, .sectionTitle, .cardTitle, .rowTitle, .rowLabel, .body, .value: return DS.ink
        case .sectionLabel, .rowSubtitle, .note, .chip: return DS.ink2
        case .meta: return DS.ink3
        case .eyebrow, .badge: return DS.ink2
        }
    }
}

extension View {
    /// 文字の役割を当てる (書体 + 既定の色)。部品の中で使う。
    func imasText(_ role: ImasTextRole) -> some View {
        font(role.font).foregroundStyle(role.color)
    }
}

// MARK: - 数字

/// 数字の書体の大きさ。ゲームのステージ (`QS.num`) と同じ「細長い太字・等幅」の系統。
enum ImasNumeralSize {
    /// 統計タイル・回収率 (30pt)。
    case large
    /// 行の末尾の票・確率・回数 (20pt)。
    case medium
    /// 曲順・下段の回数 (15pt)。
    case small

    var font: Font {
        switch self {
        // 大きい数字はステージと同じ compressed。小さい数字は詰まりすぎないよう condensed。
        case .large: return Font.imasScaled(30, weight: .heavy).width(.compressed).monospacedDigit()
        case .medium: return Font.imasScaled(20, weight: .bold).width(.condensed).monospacedDigit()
        case .small: return Font.imasScaled(15, weight: .semibold).width(.condensed).monospacedDigit()
        }
    }

    /// 単位の書体。
    var unitFont: Font {
        switch self {
        case .large: return .imasFootnote.weight(.semibold)
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

// MARK: - 実体の色が環境にあるか

extension ImasTheme {
    /// 主ボタン・選択の塗りに使う色。実体の色が無い (ニュートラルな) 画面では白黒 (`DS.sys`)。
    var actionFill: Color { isNeutral ? DS.sys : accent }
    /// `actionFill` の上の文字色。
    var onActionFill: Color { isNeutral ? DS.onSys : onAccent }
}
