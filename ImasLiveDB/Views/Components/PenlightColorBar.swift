import SwiftUI

/// 複数のペンライト色を横並びの帯で表示するコンポーネント
struct PenlightColorBar: View {
    let colors: [String]
    var height: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let w = colors.isEmpty ? 0 : geo.size.width / CGFloat(colors.count)
            HStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                    Rectangle()
                        .fill(Color(hexString: hex, default: .gray))
                        .frame(width: w, height: height)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ペンライト: \(colors.count)色 \(colorNamesLabel)")
    }

    private var colorNamesLabel: String {
        colors.map { colorName(for: $0) }.joined(separator: "、")
    }

    private func colorName(for hex: String) -> String {
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
        let prefix = String(normalized.prefix(4))
        for (key, name) in colorMap {
            if key.hasPrefix(prefix) { return name }
        }
        return "#\(normalized)"
    }
}
