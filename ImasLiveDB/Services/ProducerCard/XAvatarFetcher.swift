import Foundation
import UIKit

/// 名刺の写真の欄の「X のアイコンを使う」。名刺のリンクの X の ID から、公開のプロフィールを
/// 端末が読み、アイコンの画像を取ってくる (ログインはしない・サーバを通さない)。
///
/// どの ID を使うか・どこを読むか・返事の分け方・画像の大きさの選び方・取れなかったときの案内は
/// コア (`cardXAvatarHandle` / `xProfileApiUrl` / `xAvatarLookup` / `xAvatarLookupMessage`)。
/// ここは通信だけ。
enum XAvatarFetcher {
    enum Outcome {
        case image(UIImage)
        /// 取れなかった。`message` は画面に出す案内 (写真から選ぶ形に戻る)。
        case failed(message: String)
    }

    /// 控えを残さない (他人のプロフィールの返事・画像を端末に貯めない)。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// 画像の大きさの上限 (アイコンは数百 KB まで。誤って大きなものを受け取らない)。
    private static let maxImageBytes = 8 * 1024 * 1024

    static func fetch(handle: String) async -> Outcome {
        let lookup = await lookup(handle: handle)
        if case let .found(imageUrls) = lookup {
            for raw in imageUrls {
                if let image = await image(at: raw) { return .image(image) }
            }
            return .failed(message: xAvatarLookupMessage(lookup: .unavailable, handle: handle) ?? "")
        }
        return .failed(message: xAvatarLookupMessage(lookup: lookup, handle: handle) ?? "")
    }

    private static func lookup(handle: String) async -> XAvatarLookup {
        guard let raw = xProfileApiUrl(handle: handle), let url = URL(string: raw) else { return .notFound }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .unavailable }
        return xAvatarLookup(handle: handle, status: UInt16(clamping: http.statusCode),
                             body: String(decoding: data, as: UTF8.self))
    }

    private static func image(at raw: String) async -> UIImage? {
        guard let url = URL(string: raw),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= maxImageBytes else { return nil }
        return UIImage(data: data)
    }
}
