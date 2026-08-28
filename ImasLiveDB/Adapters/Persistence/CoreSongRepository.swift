import Foundation
import GRDB

/// `SongReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (曲スライス並走の原則):
/// - ロード済み → UniFFI 越しに `SnapshotStore` のクエリを呼ぶ
/// - 未ロード / ロード失敗 / メモリ警告で破棄後 → 従来の `GRDBSongRepository` に委ねる
///
/// FFI 形状の規約 (imas-core/src/inbound/song_list_queries.rs 冒頭):
/// - 一覧はエンティティ全体でなく「表示順の song_id 列」で返る。実体化 (Song / Idol の
///   組み立て) はこのアダプタが担う。
/// - user_marks (担当/お気に入り/参加/回収) はスナップショットに**含まれない**。回収系の
///   クエリには、ここで解決した参加 show/event id 集合を引数で渡す。
///
/// GRDB 経路に**残す**と決めたクエリは 4 つだけ (`songSpellings` / `collectedShows` /
/// `songCalls` / `songVideos`)。どれも「スナップショットに載せない設計」の側に理由があり、
/// コアに API を生やせば済む話ではない。各メソッドのコメントに理由を書く。
struct CoreSongRepository: SongReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時と未移送クエリの受け皿 (Strangler の旧経路)。
    let fallback: GRDBSongRepository

    private var database: AppDatabase { fallback.database }

    // MARK: - 切り替えヘルパ

    /// 切り替え規則の実体は `CoreSnapshotManager.withStore` (全 Core*Repository 共通)。
    /// 呼び出し側の記述を短く保つためここで薄く包む。
    private func withStore<T: Sendable>(
        fallbackTo grdb: () async throws -> T,
        _ body: (SnapshotStore) async throws -> T
    ) async throws -> T {
        try await snapshot.withStore(fallbackTo: grdb, body)
    }

    // MARK: - 一覧

    func songs(filter: SongSearchFilter, sortOrder: SongSortOrder, ascending: Bool?) async throws -> [SongWithArtists] {
        try await withStore(fallbackTo: { try await fallback.songs(filter: filter, sortOrder: sortOrder, ascending: ascending) }) { store in
            // 回収系ソートだけ参加マークの解決が要る (user_marks はスナップショットに無い)。
            // 並び替え用は SQL 時代の attendedSongCountMap と同じく「参加種別条件なし」の全 attended id。
            var attendedShowIds: [String] = []
            var attendedEventIds: [String] = []
            if sortOrder == .collectedCount || sortOrder == .collectedRate {
                attendedShowIds = try await database.fetchMarkedEntityIdsAsync(entity: .show, kind: .attended)
                attendedEventIds = try await database.fetchMarkedEntityIdsAsync(entity: .event, kind: .attended)
            }
            let ids = try store.songList(
                filter: Self.coreFilter(from: filter),
                sort: Self.coreSort(from: sortOrder),
                ascending: ascending,
                attendedShowIds: attendedShowIds,
                attendedEventIds: attendedEventIds
            )
            return try Self.songsWithArtists(store: store, orderedIds: ids)
        }
    }

    func song(id: String) async throws -> Song? {
        try await withStore(fallbackTo: { try await fallback.song(id: id) }) { store in
            try store.songRecordsByIds(songIds: [id]).first.map(Self.song(from:))
        }
    }

    func songs(ids: [String]) async throws -> [Song] {
        try await withStore(fallbackTo: { try await fallback.songs(ids: ids) }) { store in
            try store.songRecordsByIds(songIds: ids).map(Self.song(from:))
        }
    }

    /// 担当アイドルの原唱曲を一括で逆引きする。
    ///
    /// id 集合をまるごと 1 回で渡す (「1 ユーザー操作 = 1 FFI 呼び出し」の規約。
    /// 1 idol ずつ往復すると担当が多い人ほど遅くなる)。
    /// 返りは集合として使うので、コア側は入力順に依らない固定順で返す。
    func songIdsWithAnyArtist(idolIds: Set<String>) async throws -> Set<String> {
        try await snapshot.withStore(fallbackTo: { try await fallback.songIdsWithAnyArtist(idolIds: idolIds) }) { store in
            Set(try store.songIdsWithAnyArtist(idolIds: Array(idolIds)))
        }
    }

    func songPerformerIdolsMap(songIds: [String]) async throws -> [String: [Idol]] {
        guard !songIds.isEmpty else { return [:] }
        return try await withStore(fallbackTo: { try await fallback.songPerformerIdolsMap(songIds: songIds) }) { store in
            let idsMap = try store.songPerformerIdolIdsMap(songIds: songIds)
            // Idol の実体はプラットフォーム側の store で解決する規約 (アイドルスライス未移行のため GRDB)。
            let idols = try await database.fetchIdolsAsync(ids: Array(Set(idsMap.values.flatMap { $0 })))
            let idolsById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0) })
            // core が返す sort_order 順を保つ (IN 句での一括 fetch は順序を失うため)。
            return idsMap.mapValues { ids in ids.compactMap { idolsById[$0] } }
        }
    }

    func songCollectedCounts() async throws -> [String: Int] {
        try await withStore(fallbackTo: { try await fallback.songCollectedCounts() }) { store in
            // バッジ用は「参加種別 (現地のみ等) の条件を適用済み」の show id を渡す規約。
            // event の attended マークには種別条件を掛けない (SQL 時代の fetchSongCollectedCountsQuery と同じ)。
            let showIds = try await attendedShowIdsForCollection()
            let eventIds = try await database.fetchMarkedEntityIdsAsync(entity: .event, kind: .attended)
            return try store.songCollectedCountMap(
                attendedShowIds: showIds,
                attendedEventIds: eventIds,
                realLiveOnly: true
            ).mapValues(Int.init)
        }
    }

    func songPerformanceCounts() async throws -> [String: Int] {
        try await withStore(fallbackTo: { try await fallback.songPerformanceCounts() }) { store in
            try store.songPerformanceCountMap().mapValues(Int.init)
        }
    }

    /// 曲名検索 (検索画面のスコープ「曲」)。
    ///
    /// 「完全一致が 1 件でもあればそれだけ・無いときだけ部分一致を limit 件」という
    /// 枝の切り替えはコアが持つ (完全一致の枝に上限は無い)。
    func searchSongs(query: String, limit: Int) async throws -> [Song] {
        try await snapshot.withStore(fallbackTo: { try await fallback.searchSongs(query: query, limit: limit) }) { store in
            try store.searchSongs(query: query, limit: UInt32(max(0, limit))).map(Self.song(from:))
        }
    }

    /// あいまい検索 (「もしかして」) の母集団になる綴り表。**移送しない**。
    ///
    /// 編集距離の照合そのものはコアが持っている (`domain/fuzzy_search.rs`)。
    /// ここが渡すのは「どの曲を候補に入れるか」という母集団で、その線引き
    /// (SQL 側の `WHERE brand_id IS NOT 'other'` = 曲一覧が既定で隠すものと揃える)
    /// はプラットフォーム側の都合で決まる。照合はコア・母集団の供給はプラットフォーム、
    /// という分担を保つために意図的に残している (技術的に移せないわけではない)。
    func songSpellings() async throws -> [SongSpelling] {
        try await fallback.songSpellings()
    }

    // MARK: - 楽曲詳細

    func songPerformanceHistory(songId: String) async throws -> [PerformanceHistoryRow] {
        try await withStore(fallbackTo: { try await fallback.songPerformanceHistory(songId: songId) }) { store in
            try store.songPerformanceHistory(songId: songId).map {
                PerformanceHistoryRow(
                    showId: $0.showId,
                    eventId: $0.eventId,
                    eventName: $0.eventName,
                    showName: $0.showName,
                    date: $0.date,
                    venue: $0.venue,
                    position: Int($0.position),
                    section: $0.section
                )
            }
        }
    }

    func songArtists(songId: String, role: String?) async throws -> [Idol] {
        try await withStore(fallbackTo: { try await fallback.songArtists(songId: songId, role: role) }) { store in
            let ids = try store.songArtistIds(songId: songId, role: role)
            guard !ids.isEmpty else { return [] }
            let idolsById = Dictionary(
                uniqueKeysWithValues: try await database.fetchIdolsAsync(ids: ids).map { ($0.id, $0) }
            )
            // core の sort_order 順を保って実体化する。
            return ids.compactMap { idolsById[$0] }
        }
    }

    /// 関連楽曲 (同シリーズ 3 点 + 同ユニット 2 点 + 原唱者共有 1 点の加算順)。
    ///
    /// コアは曲 id だけを受け、シリーズもユニットもスナップショットの行から読む。
    /// 元実装は `unit_id` だけ引数の `Song` から読んでいたが、呼び出し側は DB から
    /// 読んだ行を渡しているので値は同じ。
    func relatedSongs(to song: Song, limit: Int) async throws -> [Song] {
        try await snapshot.withStore(fallbackTo: { try await fallback.relatedSongs(to: song, limit: limit) }) { store in
            try store.relatedSongs(songId: song.id, limit: UInt32(max(0, limit))).map(Self.song(from:))
        }
    }

    func listableSongs(ids: [String]) async throws -> [Song] {
        try await withStore(fallbackTo: { try await fallback.listableSongs(ids: ids) }) { store in
            try store.listableSongRecordsByIds(songIds: ids).map(Self.song(from:))
        }
    }

    func variantSongs(of song: Song) async throws -> [Song] {
        try await withStore(fallbackTo: { try await fallback.variantSongs(of: song) }) { store in
            try store.variantSongRecords(songId: song.id).map(Self.song(from:))
        }
    }

    /// この曲を回収した公演。**移送しない**。
    ///
    /// `user_marks` (参加マーク) を主語にした結合で、ユーザーデータはプラットフォーム側が
    /// 正という分担の側に置いてある。技術的には他の回収系 (`songCollectedCounts`) と同じく
    /// 「解決済みの参加 id 集合を引数で渡す」形で移せるが、曲詳細を 1 回開くたびに参加マーク
    /// 全件を FFI 越しに運ぶことになり、既にある SQL に対して得るものが無い
    /// (一覧のように全曲ぶんを 1 回でさばく必要も無い)。
    func collectedShows(for songId: String) async throws -> [ShowWithEventName] {
        try await fallback.collectedShows(for: songId)
    }

    func songs(criterion: SongFilterCriterion) async throws -> [SongWithArtists] {
        switch criterion {
        case .brand(let id, _):
            // SQL 時代と同じく通常フィルタ経路に合流させる (デフォルトソート = 五十音順)。
            return try await songs(filter: SongSearchFilter(brandId: id), sortOrder: .titleKana, ascending: nil)
        case .songType(let type):
            return try await songs(filter: SongSearchFilter(songType: type), sortOrder: .titleKana, ascending: nil)
        case .cdSeries(let series):
            return try await withStore(fallbackTo: { try await fallback.songs(criterion: criterion) }) { store in
                try Self.songsWithArtists(store: store, orderedIds: store.songsByCdSeries(series: series))
            }
        case .seriesGroup(let name):
            return try await withStore(fallbackTo: { try await fallback.songs(criterion: criterion) }) { store in
                try Self.songsWithArtists(store: store, orderedIds: store.songsBySeriesGroup(name: name))
            }
        case .releaseYear(let year):
            return try await withStore(fallbackTo: { try await fallback.songs(criterion: criterion) }) { store in
                try Self.songsWithArtists(store: store, orderedIds: store.songsByReleaseYear(year: year))
            }
        case .creator(let name):
            // SQL 時代と同じく songsByCreator に合流させ、ロールを落として一覧行にする。
            return try await songsByCreator(name).map {
                SongWithArtists(song: $0.song, artistNames: $0.song.singerLabel ?? "")
            }
        case .songIds(let ids, _):
            guard !ids.isEmpty else { return [] }
            return try await withStore(fallbackTo: { try await fallback.songs(criterion: criterion) }) { store in
                try Self.songsWithArtists(store: store, orderedIds: store.songsByIdsOrdered(ids: ids))
            }
        }
    }

    /// 作詞/作曲/編曲からの逆引き (担当ロールつき)。
    ///
    /// 「候補は部分一致・役割は区切りで割った断片との完全一致」という 2 段構えは
    /// コアが持つ (`domain/song_detail_queries.rs`)。`artists` は SQL 時代から常に空
    /// (表示は `song.singerLabel` を見る) なので FFI にも載せていない。
    func songsByCreator(_ name: String) async throws -> [SongWithRoles] {
        try await snapshot.withStore(fallbackTo: { try await fallback.songsByCreator(name) }) { store in
            try store.songsByCreator(name: name).map {
                SongWithRoles(song: Self.song(from: $0.song), artists: [], roles: $0.roles)
            }
        }
    }

    /// 編集 UI の曲ピッカー用の全曲 (id + title だけ)。
    ///
    /// 並びは `title` のバイト列昇順で、曲一覧の 50 音順とは別物。SQL 時代からの
    /// 挙動なのでコア側でも揃えていない (直すとピッカーの並びが黙って変わる)。
    func allSongsForPicker() async throws -> [PickedSong] {
        try await snapshot.withStore(fallbackTo: { try await fallback.allSongsForPicker() }) { store in
            try store.allSongsForPicker().map {
                PickedSong(id: $0.id, title: $0.title, titleKana: $0.titleKana)
            }
        }
    }

    // MARK: - カタログ (アルバム/シリーズ)

    func albums(brandIds: Set<String>, query: String?) async throws -> [AlbumSummary] {
        try await withStore(fallbackTo: { try await fallback.albums(brandIds: brandIds, query: query) }) { store in
            // Set は列挙順が不定なので sorted で FFI 入力を決定化する (core 側は IN 相当なので順不同で等価)。
            try store.albumSummaries(brandIds: brandIds.sorted(), query: query).map {
                AlbumSummary(
                    cdSeries: $0.cdSeries,
                    artworkUrl: $0.artworkUrl,
                    songCount: Int($0.songCount),
                    earliestDate: $0.earliestDate,
                    latestDate: $0.latestDate,
                    brandIds: $0.brandIds
                )
            }
        }
    }

    func series(brandIds: Set<String>, query: String?) async throws -> [SeriesSummary] {
        try await withStore(fallbackTo: { try await fallback.series(brandIds: brandIds, query: query) }) { store in
            try store.seriesSummaries(brandIds: brandIds.sorted(), query: query).map {
                SeriesSummary(
                    name: $0.name,
                    songCount: Int($0.songCount),
                    cdCount: Int($0.cdCount),
                    earliestDate: $0.earliestDate,
                    latestDate: $0.latestDate,
                    artworkUrl: $0.artworkUrl,
                    brandIds: $0.brandIds
                )
            }
        }
    }

    /// CD シリーズ名の全列挙 (ピッカーの母集団)。
    ///
    /// 並びは元 SQL の BINARY 順のまま。かな/漢字が音読み順に並ばないのは SQL 時代からの
    /// 挙動で、直すとピッカーの並びが黙って変わるのでコア側でも触っていない。
    func cdSeriesList() async throws -> [String] {
        try await snapshot.withStore(fallbackTo: { try await fallback.cdSeriesList() }) { store in
            try store.cdSeriesList()
        }
    }

    func seriesGroups(brandIds: Set<String>) async throws -> [String] {
        try await withStore(fallbackTo: { try await fallback.seriesGroups(brandIds: brandIds) }) { store in
            try store.seriesGroupNames(brandIds: brandIds.sorted())
        }
    }

    /// 今日の 1 曲の候補列 (id 昇順)。
    ///
    /// 番号を引く `DailyPick.songIndices` と**対**でコアが持つ (`domain/daily_pick.rs`)。
    /// 候補列と番号のどちらか片方だけを共有しても、列がずれれば同じ日に別の曲が出る。
    /// Android の `SongDao.fetchDailyPickSongIds` に同じ SQL が二重に書かれていたのを
    /// この移送で 1 実装に寄せた。
    func songIds(brandId: String, includeCovers: Bool, excludeRemixes: Bool) async throws -> [String] {
        try await snapshot.withStore(fallbackTo: {
            try await fallback.songIds(brandId: brandId, includeCovers: includeCovers, excludeRemixes: excludeRemixes)
        }) { store in
            try store.dailyPickSongIds(brandId: brandId, includeCovers: includeCovers, excludeRemixes: excludeRemixes)
        }
    }

    /// 指定公演の出演キャストがオリメンの曲 id 集合 (予想ピッカーの絞り込み)。
    ///
    /// コアは `DISTINCT` の未規定な並びを曲の添字昇順で決定化して返す。ここでは
    /// 集合として使うので順序は問わない (元 SQL も Swift 側で Set にしていた)。
    func originalSongIds(forShowCastOf showId: String) async throws -> Set<String> {
        try await snapshot.withStore(fallbackTo: { try await fallback.originalSongIds(forShowCastOf: showId) }) { store in
            Set(try store.originalSongIdsForShowCast(showId: showId))
        }
    }

    /// ブランドに属する曲の id 集合 (統計スライスがコアに持っている)。
    ///
    /// コア側 (`inbound/stats_queries.rs` の `branded_song_ids`) は 8/25 に移送済みだったのに
    /// ここだけ GRDB 経路のまま残っていた。集合として使う側なので順序は問わない。
    func brandedSongIds() async throws -> Set<String> {
        try await snapshot.withStore(fallbackTo: { try await fallback.brandedSongIds() }) { store in
            Set(try store.brandedSongIds())
        }
    }

    // MARK: - コミュニティ構造化 (CloudKit 同期のローカルミラー)
    //
    // コーレスと参考動画は **移送しない**。スナップショットが載せていないのは容量の話では
    // なく、ローカル編集経路がスナップショット再ロードを促さない契約 (`CoreSnapshotManager`
    // の `SnapshotInvalidatingSongWriting` が対象にしていない) だから。載せると「投稿した
    // 直後に自分の投稿が見えない」回帰になる。読み取りは SQL 経路に残すのが正しい
    // (`imas-core/src/domain/snapshot.rs` の同じ注記と対)。

    func songCalls(songId: String) async throws -> [SongCall] {
        try await fallback.songCalls(songId: songId)
    }

    func songVideos(songId: String) async throws -> [SongVideo] {
        try await fallback.songVideos(songId: songId)
    }

    // MARK: - user_marks の解決 (スナップショットに無いユーザーデータ)

    /// 回収バッジ用の参加 show id (参加種別条件を適用済み)。
    /// `AppDatabase+UserMarks` の `attendedTypeCondition` と同じ規則:
    /// 既定は現地参加のみ (text_value 無し = 旧 bool 参加も現地扱い)、
    /// 「配信参加も回収に含める」設定 ON なら全種別。
    /// (原本が private のため規則をここに複製している。変更時は両方を揃えること)
    private func attendedShowIdsForCollection() async throws -> [String] {
        let marks = try await database.dbQueue.read { db in
            try UserMark.filter(
                UserMark.Columns.entityType == UserMarkEntity.show.rawValue &&
                UserMark.Columns.kind == UserMarkKind.attended.rawValue &&
                UserMark.Columns.boolValue == true
            ).fetchAll(db)
        }
        if UserDefaults.standard.bool(forKey: AppDatabase.collectionIncludeStreamKey) {
            return marks.map(\.entityId)
        }
        return marks
            .filter { $0.textValue == nil || $0.textValue == AttendanceType.live.rawValue }
            .map(\.entityId)
    }

    // MARK: - FFI 型 ⇄ iOS 型の変換

    /// core の表示順 id 列を `SongWithArtists` に実体化する。
    /// `songRecordsByIds` は入力 id 順を保って返すので、並びはそのまま表示順になる。
    private static func songsWithArtists(store: SnapshotStore, orderedIds: [String]) throws -> [SongWithArtists] {
        try store.songRecordsByIds(songIds: orderedIds).map { record in
            let song = Self.song(from: record)
            // SQL 時代の fetchSongs と同じく、一覧のアーティスト表記は singer_label を使う
            // (performerIdols は必要な画面だけ songPerformerIdolsMap で別途解決)。
            return SongWithArtists(song: song, artistNames: song.singerLabel ?? "")
        }
    }

    /// 変換規則は `CoreRecordMapping` が正 (他スライスのアダプタと共有する)。
    private static func song(from record: SongDetailRecord) -> Song {
        CoreRecordMapping.song(from: record)
    }

    private static func coreFilter(from filter: SongSearchFilter) -> SongListFilter {
        SongListFilter(
            brandIds: filter.brandIds.sorted(),
            title: filter.title,
            idolName: filter.idolName,
            // iOS は nil も [] も「指定なし」なので core は Vec で受ける (song_list_queries.rs)。
            idolIds: filter.idolIds ?? [],
            songwriter: filter.songwriter,
            cdSeries: filter.cdSeries,
            seriesGroup: filter.seriesGroup,
            liveName: filter.liveName,
            songType: filter.songType,
            includeRemixes: filter.includeRemixes,
            includeOtherBrand: filter.includeOtherBrand,
            excludeLiveOnly: filter.excludeLiveOnly
        )
    }

    private static func coreSort(from sort: SongSortOrder) -> SongListSort {
        switch sort {
        case .titleKana: return .titleKana
        case .releaseDate: return .releaseDate
        case .performanceCount: return .performanceCount
        case .collectedCount: return .collectedCount
        case .collectedRate: return .collectedRate
        }
    }
}
