import Foundation

/// YouTube URL から videoId を取り出すユーティリティ。
/// 対応: watch?v= / youtu.be/ / embed/ / shorts/ / live/ 形式 + 余分なクエリ。
enum YouTube {
    /// 11 文字の videoId を抽出。取れなければ nil。
    static func videoID(from urlString: String) -> String? {
        guard let url = URL.safeHTTP(string: urlString),
              let host = url.host?.lowercased() else { return nil }

        // youtu.be/<id>
        if host.contains("youtu.be") {
            return normalize(url.pathComponents.dropFirst().first)
        }

        // youtube.com 系
        guard host.contains("youtube.com") else { return nil }

        // watch?v=<id>
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
           let id = normalize(v) {
            return id
        }

        // /embed/<id>, /shorts/<id>, /live/<id>
        let parts = url.pathComponents.dropFirst() // 先頭の "/" を除去
        if let first = parts.first, ["embed", "shorts", "live", "v"].contains(first) {
            return normalize(parts.dropFirst().first)
        }
        return nil
    }

    /// 埋め込み用サムネイル URL。
    /// hqdefault(480x360) は 4:3 で上下に黒帯が入り 16:9 枠に合わないため、
    /// 真の 16:9 である maxresdefault(1280x720) を使う。
    static func thumbnailURL(for videoID: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/maxresdefault.jpg")
    }

    /// maxresdefault が無い (HD 未アップロード) 動画向けのフォールバック。
    /// mqdefault(320x180) も 16:9 で黒帯が無く、必ず存在する。
    static func fallbackThumbnailURL(for videoID: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }

    /// 候補文字列を 11 文字英数記号の videoId として検証して返す。
    private static func normalize(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        // 余分なクエリ/フラグメントが混ざっても先頭の id 部分だけ取る。
        let id = raw.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard id.count == 11, id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return String(id)
    }
}
