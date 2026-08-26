//  披露実績の集計 (共起曲 / 歌唱者) の SQL 経路。
//
//  共有コア (imas-core) のスナップショットが使えない局面 —— 起動直後のロード前、
//  メモリ警告での unload 後、ロード失敗、ネイティブ未同梱ビルド —— でも曲詳細から
//  同じ節が消えないようにするためのフォールバック。
//
//  ⚠️ 数え方はコア (imas-core/src/domain/performance_stats.rs) と 1:1 に揃えること。
//  経路によって根拠の数字が変わると、「39 公演」と「64 回」のどちらが本当なのかを
//  読み手が判断できなくなる。揃えている点は 3 つ:
//   1. 共起は「公演数」。1 公演で 2 回演奏されても 1 (アンコール再演の二重計上を避ける)。
//   2. 歌唱者は「セトリ行数」。同じ公演での 2 回目も 1 回として数える。
//   3. shows / songs / idols への JOIN は FK 孤児落とし。コアのローダも
//      (sqlite_loader.load_setlist_items) 参照先が無い行を読み飛ばすので、
//      JOIN を外すと孤児が残っている DB でだけ数字がズレる。

import Foundation
import GRDB

extension AppDatabase {

    /// 曲詳細の披露実績 (共起曲 + 歌唱者) を **1 トランザクション**で取る。
    ///
    /// 発行するステートメントは 4 本 (共起 / 共起相手の分母 / 歌唱者 / 実体の一括解決)
    /// で、行ごとには引かない。1 回の読み取りに閉じてあるので共起と歌唱者が
    /// 別時点の DB を見ることもない。
    func fetchSongPerformanceEvidenceAsync(
        songId: String,
        coLimit: Int,
        singerLimit: Int
    ) async throws -> SongPerformanceEvidence {
        try await dbQueue.read { db in
            SongPerformanceEvidence(
                coOccurring: try Self.coOccurringQuery(db, songId: songId, limit: coLimit),
                singers: try Self.singersQuery(db, songId: songId, limit: singerLimit)
            )
        }
    }

    /// 集計の母集団。参照先が消えている行 (FK 孤児) をここで落とす。
    /// コア側のローダと同じ範囲にするための共通 CTE。
    private static let validSetlistItems = """
        WITH item AS (
            SELECT si.id AS item_id, si.show_id AS show_id, si.song_id AS song_id
              FROM setlist_items si
              JOIN shows sh ON sh.id = si.show_id
              JOIN songs so ON so.id = si.song_id
        )
        """

    /// 同じ公演で歌われた曲を、一緒に来た**公演数**の多い順に。
    ///
    /// 並びはコアと同じ「together 降順 → song_id 昇順」。SQLite の TEXT 既定照合は
    /// BINARY で Rust の `str` 比較と同じバイト順なので、同数のときの順序も一致する。
    private static func coOccurringQuery(
        _ db: Database, songId: String, limit: Int
    ) throws -> [CoOccurringSong] {
        guard limit > 0 else { return [] }
        let rows = try Row.fetchAll(db, sql: """
            \(validSetlistItems),
            target AS (SELECT DISTINCT show_id FROM item WHERE song_id = ?)
            SELECT i.song_id AS song_id, COUNT(DISTINCT i.show_id) AS together
              FROM item i
              JOIN target t ON t.show_id = i.show_id
             WHERE i.song_id <> ?
             GROUP BY i.song_id
             ORDER BY together DESC, i.song_id ASC
             LIMIT ?
            """, arguments: [songId, songId, limit])
        guard !rows.isEmpty else { return [] }

        let partnerIds = rows.map { (row: Row) -> String in row["song_id"] }
        // 分母 (相手の曲自身の総披露公演数) は上位数件ぶんだけ後追いで引く。
        // 相関サブクエリにすると 13,777 行の CTE をグループごとに舐め直すことになる。
        let placeholders = partnerIds.map { _ in "?" }.joined(separator: ",")
        var performances: [String: Int] = [:]
        for row in try Row.fetchAll(db, sql: """
            \(validSetlistItems)
            SELECT song_id, COUNT(DISTINCT show_id) AS performances
              FROM item
             WHERE song_id IN (\(placeholders))
             GROUP BY song_id
            """, arguments: StatementArguments(partnerIds)) {
            let id: String = row["song_id"]
            let count: Int = row["performances"]
            performances[id] = count
        }

        let songsById = try fetchSongsByIds(db, ids: partnerIds)
        // 曲名を引けなかった id は落とす。回数だけ出しても読めない行になる。
        return rows.compactMap { (row: Row) -> CoOccurringSong? in
            let id: String = row["song_id"]
            guard let song = songsById[id] else { return nil }
            let together: Int = row["together"]
            return CoOccurringSong(song: song, together: together, performances: performances[id] ?? 0)
        }
    }

    /// この曲を歌ったアイドルを、歌った**セトリ行数**の多い順に。
    ///
    /// 分母 `total` は歌唱者が誰であれ同じ値 (= この曲の総披露回数)。出演者が 1 人も
    /// 紐づいていない披露も分母には数える (コアと同じ)。
    private static func singersQuery(
        _ db: Database, songId: String, limit: Int
    ) throws -> [SongSingerTally] {
        guard limit > 0 else { return [] }
        let rows = try Row.fetchAll(db, sql: """
            \(validSetlistItems)
            SELECT sp.idol_id AS idol_id, COUNT(*) AS times,
                   (SELECT COUNT(*) FROM item x WHERE x.song_id = ?) AS total
              FROM item i
              JOIN setlist_performers sp ON sp.setlist_item_id = i.item_id
              JOIN idols idl ON idl.id = sp.idol_id
             WHERE i.song_id = ?
             GROUP BY sp.idol_id
             ORDER BY times DESC, sp.idol_id ASC
             LIMIT ?
            """, arguments: [songId, songId, limit])
        guard !rows.isEmpty else { return [] }

        let idolIds = rows.map { (row: Row) -> String in row["idol_id"] }
        let idolsById = try fetchIdolsByIds(db, ids: idolIds)
        return rows.compactMap { (row: Row) -> SongSingerTally? in
            let id: String = row["idol_id"]
            guard let idol = idolsById[id] else { return nil }
            let times: Int = row["times"]
            let total: Int = row["total"]
            return SongSingerTally(idol: idol, times: times, total: total)
        }
    }

    // MARK: - 実体の一括解決 (id ごとに引かない)

    private static func fetchSongsByIds(_ db: Database, ids: [String]) throws -> [String: Song] {
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let songs = try Song.fetchAll(db, sql: "SELECT * FROM songs WHERE id IN (\(placeholders))",
                                      arguments: StatementArguments(ids))
        return Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func fetchIdolsByIds(_ db: Database, ids: [String]) throws -> [String: Idol] {
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let idols = try Idol.fetchAll(db, sql: "SELECT * FROM idols WHERE id IN (\(placeholders))",
                                      arguments: StatementArguments(ids))
        return Dictionary(idols.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
