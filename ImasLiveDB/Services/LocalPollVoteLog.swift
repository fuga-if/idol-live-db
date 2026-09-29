import Foundation
import Observation

/// 自分が「みんなの投票」のお題に投票した履歴をローカル (UserDefaults) に残す。
/// サーバ側に my-votes API が無いため、クライアントで投票成功時に書き込み、
/// プロデュースタブの「投票」タイル → 投票履歴画面のソースにする。
/// 1お題で複数エントリ (推し3票) に投票できるため、`pollId -> 選んだ entityId の Set` で持つ。
@Observable
@MainActor
final class LocalPollVoteLog {
    static let shared = LocalPollVoteLog()

    private let key = "local_poll_vote_log_v1"

    /// pollId -> 自分が投票した entityId のセット。
    private(set) var votes: [String: Set<String>] = [:]

    /// 投票済みのお題 ID 一覧 (投票履歴画面の母集団)。
    var pollIds: [String] { Array(votes.keys) }
    /// 投票したユニーク お題数 (タイル表示用)。
    var votedPollCount: Int { votes.count }

    private init() { load() }

    func entityIds(forPoll pollId: String) -> Set<String> {
        votes[pollId] ?? []
    }

    func recordVote(pollId: String, entityId: String) {
        var current = votes[pollId] ?? []
        guard current.insert(entityId).inserted else { return }
        votes[pollId] = current
        save()
    }

    func removeVote(pollId: String, entityId: String) {
        guard var current = votes[pollId] else { return }
        guard current.remove(entityId) != nil else { return }
        if current.isEmpty {
            votes.removeValue(forKey: pollId)
        } else {
            votes[pollId] = current
        }
        save()
    }

    /// サインアウト/アカウント切替時に呼ぶ。投票履歴はユーザー固有なので、
    /// 永続化キーと内部状態を消して別アカウントに前ユーザーの投票済みが残らないようにする。
    func clear() {
        votes = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - バックアップ

    /// バックアップ書き出し用に現在の投票履歴を並べ替え済みの配列で返す。
    func allEntries() -> [BackupPollVote] {
        votes.map { BackupPollVote(pollId: $0.key, entityIds: Array($0.value).sorted()) }
    }

    /// バックアップからの復元 (非破壊): 既存に無い entityId のみ追加する。戻り値は追加件数。
    @discardableResult
    func mergeIfAbsent(_ entries: [BackupPollVote]) -> Int {
        var added = 0
        for entry in entries {
            var current = votes[entry.pollId] ?? []
            for entityId in entry.entityIds where current.insert(entityId).inserted {
                added += 1
            }
            if !current.isEmpty {
                votes[entry.pollId] = current
            }
        }
        if added > 0 { save() }
        return added
    }

    // MARK: - 永続化 (UserDefaults)

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }
        votes = decoded.mapValues { Set($0) }
    }

    private func save() {
        let serializable = votes.mapValues { Array($0).sorted() }
        if let data = try? JSONEncoder().encode(serializable) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
