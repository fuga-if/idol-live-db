import SwiftUI

/// ブランド ID → イメージカラー hex の単一の真実源。
/// 以前は SongRowView / BrandColorBar に同じ辞書が重複し、876/961 のキーが欠落
/// (→ グレー表示) し、存在しない "valiv" キーが残っていた。ここに集約する。
///
/// 色は各ブランド公式のキーカラーに準拠:
///   学マス=#f39800(オレンジ) / 876(DEARLY STARS/vα-liv)=#656a75 / 961=#520000 等。
/// master.sqlite brands.color とも一致させること (EventListView はそちらを参照)。
enum BrandPalette {
    static let colors: [String: String] = [
        "765as": "#fe0000",
        "961": "#520000",
        "876": "#656a75",
        "cg": "#2681c8",
        "ml": "#ffc30b",
        "sidem": "#0fbe94",
        "sc": "#6bb6b9",
        "gakuen": "#f39800",
        "other": "#8E8E93",
    ]

    /// 既知ブランドの hex。未知/nil は nil。
    static func hex(for brandId: String?) -> String? {
        guard let brandId else { return nil }
        return colors[brandId]
    }
}
