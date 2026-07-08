import Foundation
import Observation

/// 自分が投稿した貢献の累計をローカル (UserDefaults) に記録する。
/// プロデュースタブ「投稿」タイル → 投稿履歴画面の指標源。
/// サーバの badges API に内訳が無いため、クライアントで投稿成功時に +1 する。
/// 再インストールで消える点はマイ投票履歴と同様の割り切り。
@Observable
@MainActor
final class LocalContributionLog {
    static let shared = LocalContributionLog()

    enum Kind: String, CaseIterable, Codable, Sendable {
        case setlistEdit    // セトリ編集
        case callResponse   // コーレス
        case video          // 動画
        case tag            // タグ追加

        var label: String {
            switch self {
            case .setlistEdit:  return "セトリ編集"
            case .callResponse: return "コーレス"
            case .video:        return "動画"
            case .tag:          return "タグ"
            }
        }
        var systemImage: String {
            switch self {
            case .setlistEdit:  return "square.and.pencil"
            case .callResponse: return "megaphone.fill"
            case .video:        return "play.rectangle.fill"
            case .tag:          return "tag.fill"
            }
        }
    }

    private let key = "local_contribution_log_v1"
    private(set) var counts: [Kind: Int] = [:]

    var total: Int { counts.values.reduce(0, +) }

    private init() { load() }

    func count(of kind: Kind) -> Int { counts[kind] ?? 0 }

    func record(_ kind: Kind) {
        counts[kind, default: 0] += 1
        save()
    }

    /// サインアウト/アカウント切替時に呼ぶ。投稿履歴はユーザー固有なので、
    /// 永続化キーと内部状態を消して別アカウントに前ユーザーの投稿累計が残らないようにする。
    func clear() {
        counts = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - 永続化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return }
        var rebuilt: [Kind: Int] = [:]
        for (raw, n) in decoded {
            if let k = Kind(rawValue: raw) { rebuilt[k] = n }
        }
        counts = rebuilt
    }

    private func save() {
        let serializable = Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(serializable) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
