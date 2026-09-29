import Foundation
import Observation
import os

/// 起動時に端末の DB を開く流れ。開いている間は起動画面の続きを出し、開けなければ復旧画面を出す。
///
/// 以前は App の init で main thread のまま開いていた (初回の同梱 DB のコピーと移行、アプデ後の
/// reseed の間、画面が固まる)。失敗すると `fatalError` で落ち、利用者には直す手段が無かった。
///
/// 復旧は「もう一度試す」だけにする。DB を消して作り直すと、端末にしかないデータ
/// (担当・マイタグ・家計簿) が戻らなくなるので、そういう手段は出さない。
@MainActor @Observable
final class DatabaseBoot {
    enum State {
        case preparing
        case ready(AppDatabase)
        /// 開けなかった。値は利用者に見せる詳細。
        case failed(String)
    }

    private(set) var state: State = .preparing
    /// 開いている途中か (画面の出し直しで `.task` がもう一度走っても、二重に開かない)。
    private var isOpening = false
    private let open: @Sendable () throws -> AppDatabase

    /// - Parameter open: DB を開く処理。テストは失敗や成功を差し替える。
    init(open: @escaping @Sendable () throws -> AppDatabase = AppDatabase.prepare) {
        self.open = open
    }

    /// DB を開く。開き終えた後や、開いている途中に呼んでも何もしない。
    /// 失敗の後に呼ぶと開き直す (復旧画面の「もう一度試す」)。
    func prepare() async {
        if case .ready = state { return }
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        state = .preparing

        let open = self.open
        let result = await Task.detached(priority: .userInitiated) {
            Result { try open() }
        }.value
        switch result {
        case .success(let database):
            state = .ready(database)
        case .failure(let error):
            Logger.database.error("database_prepare_failed: \(String(describing: error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}
