import Foundation
import os

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "CoreSnapshot")

/// 共有コア (imas-core) のインメモリスナップショットのライフサイクル管理。
///
/// UniFFI 生成の `SnapshotStore` (Rust 側 RwLock で内部同期・差し替えは原子的) をアプリで
/// 1 個だけ持ち、以下を束ねる:
/// - 起動時: バックグラウンドで Documents の master.sqlite を読み切ってロード
/// - CloudKit sync 完了時: 再ロード (読み手はロック待ちなしで新スナップショットへ切り替わる)
/// - メモリ警告時: 破棄 (以後の読み取りは GRDB 経路へフォールバック)
///
/// 読み取りアダプタ (`CoreSongRepository` 等) は `storeIfLoaded` 越しに掴む。
/// ロードは DB 全読みで重いため必ずバックグラウンドで行い、実行中の再要求は
/// 「終わったらもう 1 回だけ」に潰す (sync 完了が連続しても読み直しが積み上がらない)。
final class CoreSnapshotManager: Sendable {
    private let store = SnapshotStore()

    /// ロードの直列化 + 追走要求の記録。
    /// running 中に来た要求は pending に畳み、走っているロードの完了後に 1 回だけ再実行する
    /// (ロード中に sync が完了した場合、その sync の書き込みを読み直さないと古いまま固定される)。
    private struct LoadState {
        var running = false
        var pending = false
    }
    private let loadState = OSAllocatedUnfairLock(initialState: LoadState())

    /// ロード済みならストアを返す。未ロード (起動直後 / ロード失敗 / メモリ警告後) は nil。
    /// 呼び出し側はこの nil を「GRDB へフォールバック」の合図として使う (スライス並走の原則)。
    var storeIfLoaded: SnapshotStore? {
        // 診断スイッチ: UserDefaults の "snapshot_disabled" が true の間はスナップショットを
        // 使わず必ず GRDB 経路へ落とす。実機でしか出ない不具合の切り分け用
        // (移行が原因か既存問題かを、同じビルドのまま比較できるようにする)。
        if UserDefaults.standard.bool(forKey: "snapshot_disabled") { return nil }
        return store.isLoaded() ? store : nil
    }

    /// バックグラウンドでのロード/再ロードを要求する (何度呼んでも安全)。
    /// `SnapshotStore.load` は成功時のみ差し替えるので、失敗しても現行スナップショット
    /// (あれば) は生き続け、未ロードなら GRDB 経路が答え続ける。
    func requestLoad() {
        let shouldStart = loadState.withLock { state -> Bool in
            if state.running {
                state.pending = true
                return false
            }
            state.running = true
            return true
        }
        guard shouldStart else { return }

        // .utility: 完了までは GRDB が同じ答えを返せるため、UI 描画やユーザー操作より優先度を下げる。
        Task.detached(priority: .utility) { [self] in
            repeat {
                loadOnce()
            } while loadState.withLock { state -> Bool in
                if state.pending {
                    state.pending = false
                    return true
                }
                state.running = false
                return false
            }
        }
    }

    /// メモリ警告時の明示破棄。次の requestLoad (sync 完了 or 再起動) まで未ロードに戻る。
    /// ロード実行中に呼ばれた場合は直後に新スナップショットが入り直すことがあるが、
    /// 警告時の解放はベストエフォートで良い (整合性は store 側の原子差し替えが守る)。
    func unload() {
        store.unload()
        logger.notice("snapshot_unloaded (memory warning)")
    }

    // MARK: - Private

    private func loadOnce() {
        let path = Self.masterDatabasePath()
        do {
            let stats = try store.load(dbPath: path)
            logger.info("snapshot_loaded songs=\(stats.songs) idols=\(stats.idols)")
        } catch {
            // 初回起動の DB コピー前・ファイル破損など。ここで落としても得るものが無いので
            // ログだけ残して GRDB 経路に委ねる (次の sync 完了時に自動で再挑戦する)。
            logger.error("snapshot_load_failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `AppDatabase.openDatabase()` と同じ Documents/master.sqlite。
    /// (パス構築ロジックはあちらが private のため同じ規則をここに書いている。変更時は両方を揃えること)
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
// - スナップショットが読まない表 (song_calls / song_videos。imas-core の sqlite_loader 参照)
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

    func upsertSetlistItems(_ items: [SetlistItem]) async throws {
        try await base.upsertSetlistItems(items)
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

    /// song_calls はスナップショット対象外 (sqlite_loader が読まない) なので再ロードは促さない。
    func upsertSongCalls(_ calls: [SongCall]) async throws {
        try await base.upsertSongCalls(calls)
    }

    /// song_videos も同様にスナップショット対象外。
    func upsertSongVideos(_ videos: [SongVideo]) async throws {
        try await base.upsertSongVideos(videos)
    }
}
