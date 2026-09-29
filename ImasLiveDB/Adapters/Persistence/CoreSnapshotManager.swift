import Foundation
import os

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "CoreSnapshot")

extension Notification.Name {
    /// スナップショットを (読み直しを含めて) ロードし終えた。main で届く。
    /// マスタから作る派生物 (情報ウィジェットのスナップショット等) を作り直す合図に使う。
    /// `.masterDataDidSync` の直後はまだ古いスナップショットなので、そちらでは作り直さない。
    static let coreSnapshotDidLoad = Notification.Name("coreSnapshotDidLoad")
}

/// 共有コア (imas-core) のインメモリスナップショットのライフサイクル管理。
///
/// UniFFI 生成の `SnapshotStore` (Rust 側 RwLock で内部同期・差し替えは原子的) をアプリで
/// 1 個だけ持ち、以下を束ねる:
/// - 起動時: バックグラウンドで Documents の master.sqlite を読み切ってロード
/// - CloudKit sync 完了時・ローカル編集の後: 再ロード (読み手はロック待ちなしで新スナップショットへ切り替わる)
///
/// マスタの読み取りはすべてスナップショットが答える (OS 側の SQL の代わりの経路は持たない。
/// 同じ問いに 2 つの実装が答えると、規則が必ず食い違う)。まだロードできていない間
/// (起動直後・ロードの失敗の後) の読み取りは、`loadedStore()` でロードを待つ。
/// メモリ警告でも手放さない (手放すと、次の読み取りが全部ロード待ちになる)。
///
/// ロードは DB 全読みで重いため必ずバックグラウンドで行い、実行中の再要求は
/// 「終わったらもう 1 回だけ」に潰す (sync 完了が連続しても読み直しが積み上がらない)。
final class CoreSnapshotManager: Sendable {
    private let store = SnapshotStore()

    /// ロードの直列化 + 追走要求 + ロード待ちの記録。
    /// running 中に来た再ロードの要求は pending に畳み、走っているロードの完了後に 1 回だけ
    /// 再実行する (ロード中に sync が完了した場合、その sync の書き込みを読み直さないと古いまま固定される)。
    private struct LoadState {
        var running = false
        var pending = false
        /// ロードを待っている読み取り。ロードが 1 回終わるたびに、成否を渡してまとめて起こす。
        var waiters: [CheckedContinuation<SnapshotStore, any Error>] = []
    }
    private let loadState = OSAllocatedUnfairLock(initialState: LoadState())

    /// ロード待ちに入った読み取りが次にすること。
    private enum WaitStep { case ready, wait, start }

    /// ロード済みのストア。まだなら (起動直後・前のロードの失敗の後) ロードを待つ。
    ///
    /// ロードに失敗したら投げる。画面は既存の読み込み失敗の表示になり、次の読み取りで
    /// もう一度ロードを試す。
    func loadedStore() async throws -> SnapshotStore {
        if store.isLoaded() { return store }
        return try await withCheckedThrowingContinuation { continuation in
            let step = loadState.withLock { state -> WaitStep in
                // ロックの外で確かめた後に、ちょうどロードが終わっていることがある。
                if store.isLoaded() { return .ready }
                state.waiters.append(continuation)
                if state.running { return .wait }
                state.running = true
                return .start
            }
            switch step {
            case .ready: continuation.resume(returning: store)
            case .wait: break
            case .start: startLoading()
            }
        }
    }

    /// 描画のように待てない場面用。ロード済みならストア、まだなら nil (ロードは起こさない)。
    /// 読み取りの口 (ポート) では使わないこと — そちらは `loadedStore()` で待つ。
    func storeIfReady() -> SnapshotStore? {
        store.isLoaded() ? store : nil
    }

    /// バックグラウンドでのロード/再ロードを要求する (何度呼んでも安全)。
    /// `SnapshotStore.load` は成功時のみ差し替えるので、失敗しても現行スナップショット
    /// (あれば) は生き続ける。
    func requestLoad() {
        let shouldStart = loadState.withLock { state -> Bool in
            if state.running {
                state.pending = true
                return false
            }
            state.running = true
            return true
        }
        if shouldStart { startLoading() }
    }

    // MARK: - Private

    /// ロードを回す (呼ぶ前に running を立てておくこと)。
    ///
    /// 1 回終わるたびに、待っている読み取りを起こす。起こす相手の取り出しと running を
    /// 下ろすのは同じロックの中で行う。間に来た読み取りは、取り出しに間に合えばこの結果で
    /// 起き、間に合わなければ running が下りているので自分で次のロードを始める (取り残されない)。
    ///
    /// 優先度は .userInitiated。読み取りがロードを待つので、画面の表示を待たせている。
    private func startLoading() {
        Task.detached(priority: .userInitiated) { [self] in
            while true {
                let outcome = loadOnce()
                let (waiters, again) = loadState.withLock { state in
                    let waiters = state.waiters
                    state.waiters = []
                    if state.pending {
                        state.pending = false
                        return (waiters, true)
                    }
                    state.running = false
                    return (waiters, false)
                }
                for waiter in waiters { waiter.resume(with: outcome) }
                if !again { return }
            }
        }
    }

    /// 1 回ロードする。読み直しに失敗しても、前のスナップショットがあればそれを返す
    /// (`SnapshotStore.load` は成功したときだけ差し替える)。
    private func loadOnce() -> Result<SnapshotStore, any Error> {
        let path = Self.masterDatabasePath()
        do {
            let stats = try store.load(dbPath: path)
            logger.info("snapshot_loaded songs=\(stats.songs) idols=\(stats.idols)")
            Task { @MainActor in
                NotificationCenter.default.post(name: .coreSnapshotDidLoad, object: nil)
            }
            return .success(store)
        } catch {
            // ファイル破損など。待っている読み取りには失敗を返し、次の読み取りか
            // 次の sync 完了のときにもう一度試す。
            logger.error("snapshot_load_failed: \(error.localizedDescription, privacy: .public)")
            return store.isLoaded() ? .success(store) : .failure(error)
        }
    }

    /// `AppDatabase.prepare()` が開くのと同じ Documents/master.sqlite。
    /// (パスの組み立てはあちらにもある。変更時は両方を揃えること)
    private static func masterDatabasePath() -> String {
        let documentsURL = URL.documentsDirectory
        return documentsURL.appendingPathComponent("master.sqlite").path
    }
}

// MARK: - ローカル編集によるスナップショット無効化 (Writing デコレータ)
//
// CloudKit sync がマスタを書き換えた時は CloudKitSyncEngine が `.masterDataDidSync` を post し
// 再ロードに繋がるが、モデレーター編集の .applied 経路 (SongEditView 等) やセトリ取込は
// GRDB へ直接 upsert するだけで通知が無い。素通しにすると、次の totalFetched>0 な sync か
// アプリ再起動までスナップショット (曲一覧/曲詳細の core 経路) が古いまま残り、
// 「編集直後に自分の編集が見えない」回帰になる。そこで書き込みポートをこのデコレータで包み、
// 書き込み成功後に再ロードを促す。
//
// - `invalidate` には合成ルート (AppContainer) が `{ snapshot.requestLoad() }` を渡す。
//   CoreSnapshotManager へ直接依存させずクロージャで受けるのは、単体テストで
//   「どの書き込みが再ロードを促すか」を観測可能にするため。
// - 失敗時 (throw) は呼ばない: DB が変わっていないのに全読みを走らせない
//   (0 件同期で post しない CloudKitSyncEngine と同じ精神)。
// - スナップショットが読まない表 (song_videos。imas-core の sqlite_loader 参照)
//   だけの書き込みでも呼ばない。DB 全読みは重く、無関係な編集で走らせない。

struct SnapshotInvalidatingEventWriting: EventWriting {
    let base: any EventWriting
    let invalidate: @Sendable () -> Void

    func upsertEvents(_ events: [Event]) async throws {
        try await base.upsertEvents(events)
        invalidate()
    }
}

struct SnapshotInvalidatingShowWriting: ShowWriting {
    let base: any ShowWriting
    let invalidate: @Sendable () -> Void

    func upsertShows(_ shows: [Show]) async throws {
        try await base.upsertShows(shows)
        invalidate()
    }

    func replaceSetlist(showId: String, items: [SetlistItem], performers: [SetlistPerformer]) async throws {
        try await base.replaceSetlist(showId: showId, items: items, performers: performers)
        invalidate()
    }
}

struct SnapshotInvalidatingIdolWriting: IdolWriting {
    let base: any IdolWriting
    let invalidate: @Sendable () -> Void

    func upsertIdols(_ idols: [Idol]) async throws {
        try await base.upsertIdols(idols)
        invalidate()
    }
}

struct SnapshotInvalidatingSongWriting: SongWriting {
    let base: any SongWriting
    let invalidate: @Sendable () -> Void

    func upsertSongs(_ songs: [Song]) async throws {
        try await base.upsertSongs(songs)
        invalidate()
    }

    func upsertSongArtists(_ songArtists: [SongArtist]) async throws {
        try await base.upsertSongArtists(songArtists)
        invalidate()
    }

    /// song_videos はスナップショット対象外 (sqlite_loader が読まない) なので再ロードは促さない。
    func upsertSongVideos(_ videos: [SongVideo]) async throws {
        try await base.upsertSongVideos(videos)
    }
}
