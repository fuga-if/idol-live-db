import SwiftUI

/// イメージカラードット — アイドル名の前に表示
struct ColorDotView: View {
    let hex: String?
    var size: CGFloat = 8
    /// 装飾目的のみの場合 true にして VoiceOver から隠す
    var isDecorative: Bool = false
    /// VoiceOver 用カラー名（省略時は hex から自動生成）
    var accessibilityColorName: String? = nil

    var body: some View {
        Circle()
            .fill(Color(hexString: hex))
            .frame(width: size, height: size)
            .accessibilityElement()
            .modifier(ColorDotAccessibility(
                isDecorative: isDecorative,
                label: accessibilityColorName ?? colorName(for: hex)
            ))
    }

    /// HEX を日本語色名に変換する。主要色のみマッピングし、それ以外は HEX をそのまま返す。
    private func colorName(for hex: String?) -> String {
        guard let hex else { return "不明" }
        let normalized = hex.trimmingCharacters(in: .init(charactersIn: "#")).uppercased()
        let colorMap: [String: String] = [
            "FF0000": "赤", "FF3333": "赤", "CC0000": "赤",
            "0000FF": "青", "3333FF": "青", "0033CC": "青",
            "FFFF00": "黄", "FFCC00": "黄",
            "00FF00": "緑", "33CC33": "緑", "008000": "緑",
            "FF69B4": "ピンク", "FF1493": "ピンク", "FF66B2": "ピンク",
            "FFA500": "オレンジ", "FF8C00": "オレンジ",
            "800080": "紫", "9B59B6": "紫", "8B008B": "紫",
            "FFFFFF": "白", "F5F5F5": "白",
            "000000": "黒", "1A1A1A": "黒",
            "808080": "グレー", "A9A9A9": "グレー",
            "00FFFF": "水色", "00CED1": "水色",
            "8B4513": "茶", "A0522D": "茶",
        ]
        if let name = colorMap[normalized] { return name }
        // 部分一致で近い色を探す（先頭4文字で照合）
        let prefix = String(normalized.prefix(4))
        for (key, name) in colorMap {
            if key.hasPrefix(prefix) { return name }
        }
        return "#\(normalized)"
    }
}

/// アクセシビリティ修飾子を切り替えるモディファイア
private struct ColorDotAccessibility: ViewModifier {
    let isDecorative: Bool
    let label: String

    func body(content: Content) -> some View {
        if isDecorative {
            content.accessibilityHidden(true)
        } else {
            content.accessibilityLabel("カラー: \(label)")
        }
    }
}
