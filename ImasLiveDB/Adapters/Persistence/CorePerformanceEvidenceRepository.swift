import Foundation

/// `PerformanceEvidenceReading` の共有コア (imas-core スナップショット) アダプタ。
///
/// 曲詳細を 1 回開くのに叩く FFI は **3 回だけ**:
/// 1. `songPerformanceInsights` — 共起と歌唱者を束ねて 1 回
///    (セトリ 13,777 件・出演者 60,383 件の走査。実測 6ms なので事前計算しない)
/// 2. `songRecordsByIds` — 共起相手の曲名をまとめて 1 回
/// 3. `idolRecordsByIds` — 歌唱者の名前をまとめて 1 回
///
/// 2 と 3 を行ごとに引かないこと。コア側は id しか返さないので名前の解決は必要だが、
/// 集合で 1 回引けば足りる (`imas-core/src/inbound/performance_stats.rs` の注記と同じ約束)。
///
/// 他の `Core*Repository` と同じく、未ロード時は GRDB 経路へ落ちる。セトリと出演者は
/// SQL でも同じ集計が書けるので (`AppDatabase+PerformanceEvidenceQueries`)、
/// スナップショットの有無で節が出たり消えたりする理由が無い。とくに iOS は
/// メモリ警告で `unload()` するため、フォールバックが無いと「さっきまで出ていた節が
/// 説明なく消える」状態が実機で普通に起きる。
struct CorePerformanceEvidenceRepository: PerformanceEvidenceReading {
    let snapshot: CoreSnapshotManager
    let fallback: any PerformanceEvidenceReading

    func songPerformanceEvidence(
        songId: String,
        coLimit: Int,
        singerLimit: Int
    ) async throws -> SongPerformanceEvidence {
        // withStore は未ロード時と SnapshotError 時に fallbackTo を呼ぶ。
        try await snapshot.withStore(fallbackTo: {
            try await fallback.songPerformanceEvidence(
                songId: songId, coLimit: coLimit, singerLimit: singerLimit
            )
        }) { store in
            let raw = try store.songPerformanceInsights(
                songId: songId,
                coLimit: UInt32(max(0, coLimit)),
                singerLimit: UInt32(max(0, singerLimit))
            )
            let coOccurring = try Self.resolveSongs(store: store, rows: raw.coOccurring)
            let singers = try Self.resolveIdols(store: store, rows: raw.singers)
            return SongPerformanceEvidence(coOccurring: coOccurring, singers: singers)
        }
    }

    // MARK: - id → エンティティの解決 (どちらも集合で 1 回だけ引く)

    /// 共起曲を 1 回の `songRecordsByIds` で実体化する。
    ///
    /// マスタから消えた曲 id は素通しで落とす。回数だけ出しても曲名が無い行は読めないし、
    /// プレースホルダを出すと「知らない曲がよく一緒に来る」という無意味な行になる。
    private static func resolveSongs(
        store: SnapshotStore,
        rows: [CoOccurrence]
    ) throws -> [CoOccurringSong] {
        guard !rows.isEmpty else { return [] }
        let byId = Dictionary(
            try store.songRecordsByIds(songIds: rows.map(\.songId)).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return rows.compactMap { row in
            guard let record = byId[row.songId] else { return nil }
            return CoOccurringSong(
                song: CoreRecordMapping.song(from: record),
                together: Int(row.together),
                performances: Int(row.performances)
            )
        }
    }

    /// 歌唱者を 1 回の `idolRecordsByIds` で実体化する (解決できない id は落とす)。
    private static func resolveIdols(
        store: SnapshotStore,
        rows: [SingerTally]
    ) throws -> [SongSingerTally] {
        guard !rows.isEmpty else { return [] }
        let byId = Dictionary(
            try store.idolRecordsByIds(idolIds: rows.map(\.idolId)).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return rows.compactMap { row in
            guard let record = byId[row.idolId] else { return nil }
            return SongSingerTally(
                idol: CoreRecordMapping.idol(from: record),
                times: Int(row.times),
                total: Int(row.total)
            )
        }
    }
}
