import SwiftUI

extension Color {
    /// Color を "#RRGGBB" 形式の HEX 文字列に変換する (ColorPicker の選択値保存用)。
    /// アルファは無視し、sRGB 8bit に丸める。
    func tagHexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (v: CGFloat) -> Int in max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    /// HexColor 型から Color を生成。バリデーション済みの値専用。
    init(hexColor: HexColor) {
        self.init(rawHex: hexColor.rawValue)
    }

    /// DB / API 由来の Optional な HEX 文字列から Color を生成する。
    /// パース失敗時は default を返す。HexColor のバリデーションを通す。
    init(hexString: String?, default fallback: Color = .gray) {
        guard let raw = hexString,
              let validated = HexColor(rawValue: raw) else {
            self = fallback
            return
        }
        self.init(rawHex: validated.rawValue)
    }

    /// HEX 文字列パース実装。バリデーション済みの値だけを受け取る。
    private init(rawHex: String) {
        let hex = rawHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)

        let r, g, b: Double
        if hex.count == 8 {
            // RRGGBBAA: アルファは捨て、RGB を上位バイトから取る
            // (下位6桁だけ読むと GGBBAA を RGB と誤読して色化けする)。
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >> 8) / 255.0
        } else {
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
        }

        self.init(red: r, green: g, blue: b)
    }
}
