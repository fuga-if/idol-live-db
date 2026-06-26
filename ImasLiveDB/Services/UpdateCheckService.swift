import Foundation
import SwiftUI

/// App Store に新しいバージョンが出ていたら起動時にお知らせする。
/// iTunes Lookup API で「現在 App Store にある版」を取得し、インストール版と比較。
/// バックエンド不要・リリースごとの手動バージョン更新も不要。
@MainActor
@Observable
final class UpdateCheckService {
    static let shared = UpdateCheckService()

    private(set) var availableVersion: String?
    private(set) var storeURL: URL?
    private let dismissedKey = "updateNoticeDismissedVersion"

    /// 新版があり、かつそのバージョンをまだ「後で」していない時だけ true。
    var shouldNotify: Bool {
        guard let v = availableVersion else { return false }
        return UserDefaults.standard.string(forKey: dismissedKey) != v
    }

    func dismiss() {
        if let v = availableVersion {
            UserDefaults.standard.set(v, forKey: dismissedKey)
        }
    }

    func check() async {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.fugaif.ImasLiveDB"
        let region = Locale.current.region?.identifier.lowercased() ?? "jp"
        guard let url = URL(string:
            "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=\(region)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Lookup: Decodable {
                struct Result: Decodable { let version: String; let trackViewUrl: String }
                let results: [Result]
            }
            guard let r = try JSONDecoder().decode(Lookup.self, from: data).results.first else { return }
            let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            if Self.isNewer(r.version, than: installed) {
                availableVersion = r.version
                storeURL = URL(string: r.trackViewUrl)
            }
        } catch {
            // ネットワーク不通等は黙って無視 (お知らせは次回起動で再試行)
        }
    }

    /// セマンティックバージョン比較 ("1.7.10" > "1.7.2")。
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
