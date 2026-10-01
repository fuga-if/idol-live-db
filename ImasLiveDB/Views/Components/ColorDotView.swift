import os
import SwiftUI

/// イメージカラードット — アイドル名の前に表示。中身は DesignSystem の `ImasSwatch`。
struct ColorDotView: View {
    let hex: String?
    var size: CGFloat = 8
    /// 装飾目的のみの場合 true にして VoiceOver から隠す
    var isDecorative: Bool = false
    /// VoiceOver 用カラー名（省略時は hex から自動生成）
    var accessibilityColorName: String? = nil

    var body: some View {
        // ImasSwatch 自身が「カラー: <名前>」の読み上げ/非表示 (isDecorative) を持つ。
        // 名前を明示されたときだけ、その名前で上書きする。
        let swatch = ImasSwatch(hex: hex, diameter: size, isDecorative: isDecorative)
        if let accessibilityColorName, !isDecorative {
            swatch.accessibilityLabel("カラー: \(accessibilityColorName)")
        } else {
            swatch
        }
    }
}

/// 色の読み上げ名 (VoiceOver)。名前の付け方はコア (`color_accessibility_name`)。
/// 色の数は有界なので hex ごとに覚え、行ごとに FFI を呼ばない。
enum ColorAccessibilityName {
    private static let cache = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    static func of(_ hex: String?) -> String {
        let key = hex ?? ""
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let name = colorAccessibilityName(hex: hex)
        cache.withLock { $0[key] = name }
        return name
    }
}
