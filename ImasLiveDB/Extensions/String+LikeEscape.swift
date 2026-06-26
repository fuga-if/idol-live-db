import Foundation

extension String {
    /// SQLite LIKE パターン中の特殊文字をエスケープする。
    /// SQL側で `ESCAPE '\\'` 句を付けて使用すること。
    var likeEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
