import Foundation

/// `IdolReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則):
/// - ロード済み → UniFFI 越しに `SnapshotStore` のクエリを呼ぶ
/// - 未ロード / ロード失敗 / メモリ警告で破棄後 → 従来の `GRDBIdolRepository` に委ねる
///
/// FFI 形状の規約:
/// - `IdolSongRecord` / `IdolPerformedSongRecord` は一覧表示用の射影しか持たない (brand_id や
///   作家名を欠く) が、ポートの戻り値は完全な `Song`。よって core からは「表示順の song_id 列」
///   だけ受け取り、実体化は `songRecordsByIds` で行う (`CoreRecordMapping.songs`)。
/// - `idolRecordsByIds` は入力 id 順・初出のみを返すので、id 列の並びがそのまま表示順になる。
struct CoreIdolRepository: IdolReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時と未移送クエリの受け皿 (Strangler の旧経路)。
    let fallback: GRDBIdolRepository

    // MARK: - 一覧

    func idols(brandId: String?) async throws -> [Idol] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idols(brandId: brandId) }) { store in
            try store.idolList(brandId: brandId).map(CoreRecordMapping.idol(from:))
        }
    }

    func idol(id: String) async throws -> Idol? {
        try await snapshot.withStore(fallbackTo: { try await fallback.idol(id: id) }) { store in
            try store.idolRecordsByIds(idolIds: [id]).first.map(CoreRecordMapping.idol(from:))
        }
    }

    func idols(ids: [String]) async throws -> [Idol] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idols(ids: ids) }) { store in
            try store.idolRecordsByIds(idolIds: ids).map(CoreRecordMapping.idol(from:))
        }
    }

    func idols(criterion: IdolFilterCriterion) async throws -> [Idol] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idols(criterion: criterion) }) { store in
            let records: [IdolRecord]
            switch criterion {
            case .brand(let id, _):
                // SQL 時代も brand 絞り込みは通常の一覧クエリと同じ経路だった。
                records = try store.idolList(brandId: id)
            case .birthMonth(let month):
                records = try store.idolsByBirthMonth(month: UInt32(month))
            case .constellation(let name):
                records = try store.idolsByConstellation(constellation: name)
            case .birthPlace(let place):
                records = try store.idolsByBirthPlace(birthPlace: place)
            case .bloodType(let type):
                records = try store.idolsByBloodType(bloodType: type)
            }
            return records.map(CoreRecordMapping.idol(from:))
        }
    }

    func idolCastNames() async throws -> [String: String] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idolCastNames() }) { store in
            try store.idolCastNames()
        }
    }

    func idolsByVoiceActor(name: String) async throws -> [Idol] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idolsByVoiceActor(name: name) }) { store in
            try store.idolsByVoiceActor(name: name).map(CoreRecordMapping.idol(from:))
        }
    }

    func searchIdols(query: String, limit: Int) async throws -> [Idol] {
        try await snapshot.withStore(fallbackTo: { try await fallback.searchIdols(query: query, limit: limit) }) { store in
            try store.searchIdols(query: query, limit: UInt32(max(0, limit))).map(CoreRecordMapping.idol(from:))
        }
    }

    func allIdolsForPicker() async throws -> [Idol] {
        try await snapshot.withStore(fallbackTo: { try await fallback.allIdolsForPicker() }) { store in
            try store.allIdolsForPicker().map(CoreRecordMapping.idol(from:))
        }
    }

    // MARK: - アイドル詳細

    func idolSongs(idolId: String, role: String?) async throws -> [Song] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idolSongs(idolId: idolId, role: role) }) { store in
            // role 未指定だと role 違いで同じ song_id が複数行返る (SQL の JOIN と同じ挙動)。
            // 重複も並びもそのまま保つため、id 列を作ってから実体化する。
            let ids = try store.idolSongRecords(idolId: idolId, role: role).map(\.songId)
            return try CoreRecordMapping.songs(store: store, orderedIds: ids)
        }
    }

    func idolPerformedSongs(idolId: String) async throws -> [IdolPerformedSong] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idolPerformedSongs(idolId: idolId) }) { store in
            let records = try store.idolPerformedSongRecords(idolId: idolId)
            let songs = try CoreRecordMapping.songs(store: store, orderedIds: records.map(\.songId))
            let songsById = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // 披露回数は core の集計 (このアイドルが歌唱者として立った setlist_items 数) を使う。
            return records.compactMap { record in
                songsById[record.songId].map {
                    IdolPerformedSong(song: $0, performCount: Int(record.performCount))
                }
            }
        }
    }

    func idolUnits(idolId: String) async throws -> [Unit] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idolUnits(idolId: idolId) }) { store in
            try store.idolUnits(idolId: idolId).map(CoreRecordMapping.unit(from:))
        }
    }

    func idolShows(idolId: String) async throws -> [CastShowRow] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idolShows(idolId: idolId) }) { store in
            try store.idolShows(idolId: idolId).map(CoreRecordMapping.castShowRow(from:))
        }
    }

    func idolSongHistory(idolId: String, songId: String) async throws -> [CastShowRow] {
        try await snapshot.withStore(fallbackTo: { try await fallback.idolSongHistory(idolId: idolId, songId: songId) }) { store in
            try store.idolSongHistoryRecords(idolId: idolId, songId: songId).map(CoreRecordMapping.castShowRow(from:))
        }
    }
}
