import Foundation

/// 公演日 (`"yyyy-MM-dd"`) を統計タイルに載る短縮表記 `"24.08"` にする。
///
/// タイルは横 3 つ並ぶので、フル日付だと確実に溢れる。年は下 2 桁で足りる
/// (このアプリが扱うのは 2005 年以降のライブなので 20xx で衝突しない)。
///
/// 部分日付 (`"2024"` や `"2024-08"`) や空文字が DB に入ることがあるため、
/// 短縮できない入力はそのまま返す (捏造しない・クラッシュしない)。
enum ShortYearMonth {
    static func format(_ date: String) -> String {
        let comps = date.split(separator: "-")
        guard comps.count >= 2 else { return date }
        return "\(comps[0].suffix(2)).\(comps[1])"
    }
}
