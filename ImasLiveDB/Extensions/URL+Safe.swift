import Foundation

extension URL {
    /// http(s) スキームの URL のみ返す。ユーザ投稿の出典 URL 等で
    /// javascript: / data: / file:// を弾くための allowlist。
    static func safeHTTP(string: String?) -> URL? {
        guard let s = string, !s.isEmpty,
              let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}
