import SwiftUI

// =============================================================================
// コール文言のパレット
//
// ここにあるのは**初期値にすぎない**。実際のコールは曲ごと・現場ごとに変わるので、
// 編集シートでは常に自由入力を許すこと (パレットから選ぶのは近道でしかない)。
//
// 表記は実物のコール表 (くわね氏のコール表 等) に合わせてある。半角/全角の混在や
// 空白の入り方も含めて「現場でそう書かれている形」を優先していて、正規化していない。
//
// MIX (「タイガー・ファイヤー…」) は **意図的に入れていない**。アイマスのコール文化では
// 使われないため、パレットに置くと誤用を促す。
// =============================================================================

struct CallPaletteGroup: Identifiable {
    let id: String
    let title: String
    let items: [String]
}

enum CallPalette {
    static let groups: [CallPaletteGroup] = [
        CallPaletteGroup(id: "voice", title: "発声", items: [
            "(Hi!)", "(Oi!)", "(Hey!!)", "(Fuu!)", "(FuFuu!)", "(Fuu--!)",
            "(u--)", "（ふぅっ）", "(Fuwa × 4)", "(Yeah!)", "(Wow)", "(Woooo,Yeah!!)",
        ]),
        CallPaletteGroup(id: "clap", title: "クラップ", items: [
            "x　Pan! x Pan!", "Pan Pan Pan Pan!", "(Pan Pan Pan PaPan)",
            "Pan Pa Pan Hyu-!", "Oooo Hyu!",
        ]),
        CallPaletteGroup(id: "oh", title: "オーイング / 警報", items: [
            "(o-- Hi!)", "(-- Hi!)", "（ハーイハーイハイハイハイハイ）", "（せーの！）",
        ]),
        CallPaletteGroup(id: "count", title: "カウント", items: [
            "3・2・1・GO!!",
            "（いち・にの・さん・レッツ・ゴー！）",
            "（いち・に・ついて・よ〜い・ドン！）",
        ]),
        CallPaletteGroup(id: "section", title: "セクション", items: [
            "（前奏）", "（間奏）",
        ]),
    ]

    /// 「歌詞コール」= 選択した歌詞語をそのまま繰り返すコール。
    /// 固定文言では表現できないので、選択範囲から動的に組み立てる。
    /// 実物の表記に合わせて**全角括弧**で包む。
    static func lyricCall(anchorText: String) -> String? {
        let trimmed = anchorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "（\(trimmed)）"
    }
}

// MARK: - 強調度の配色

extension CallEmphasis {
    /// 強調度の色。凡例・コール文言・アンカーのハイライトで同じ色を使う。
    /// `normal` は本文と同じ扱いにせず、少しだけ落とした ink2 で「コール行」だと分かるようにする。
    var color: Color {
        switch self {
        case .normal:           return DS.ink
        case .optional:         return DS.success
        case .performerRequest: return DS.danger
        }
    }
}
