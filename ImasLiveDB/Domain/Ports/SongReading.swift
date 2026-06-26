import Foundation

/// 楽曲マスタの読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/GRDBSongRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol SongReading: Sendable {
    /// フィルタ + ソート済みの一覧 (アーティスト名つき)。
    func songs(filter: SongSearchFilter, sortOrder: SongSortOrder, ascending: Bool?) async throws -> [SongWithArtists]
    /// 単一楽曲。
    func song(id: String) async throws -> Song?
    /// id 集合に該当する楽曲。
    func songs(ids: [String]) async throws -> [Song]
    /// 指定アイドル集合のいずれかが歌唱に関わる曲 id 集合 (担当絞り込み用)。
    func songIdsWithAnyArtist(idolIds: Set<String>) async throws -> Set<String>
    /// 一覧行アイコン用の出演アイドル一括解決 (song_id → idols)。
    func songPerformerIdolsMap(songIds: [String]) async throws -> [String: [Idol]]
    /// song_id → 回収数。
    func songCollectedCounts() async throws -> [String: Int]
    /// 検索サジェスト。
    func songSuggestions(query: String, limit: Int) async throws -> [SearchSuggestionItem]
    /// ライブ名/曲名検索。
    func searchSongs(query: String, limit: Int) async throws -> [Song]

    // MARK: - 楽曲詳細

    /// 披露履歴 (どの公演で披露されたか)。
    func songPerformanceHistory(songId: String) async throws -> [PerformanceHistoryRow]
    /// 歌唱アーティスト (role 指定: "original" / "performer" 等)。
    func songArtists(songId: String, role: String?) async throws -> [Idol]
    /// 関連曲 (同シリーズ/同ユニット等)。
    func relatedSongs(to song: Song, limit: Int) async throws -> [Song]
    /// この曲を回収した公演 (イベント名つき)。
    func collectedShows(for songId: String) async throws -> [ShowWithEventName]
    /// フィルタ条件 (ブランド/シリーズ/曲ID集合等) で絞った楽曲。
    func songs(criterion: SongFilterCriterion) async throws -> [SongWithArtists]
    /// 作詞/作曲/編曲者名で引いた楽曲 (担当ロールつき)。
    func songsByCreator(_ name: String) async throws -> [SongWithRoles]
    /// ピッカー用の全楽曲 (軽量表現)。
    func allSongsForPicker() async throws -> [PickedSong]

    // MARK: - カタログ (アルバム/シリーズ)

    /// アルバム一覧 (CDシリーズ単位の集計)。
    func albums(brandIds: Set<String>, query: String?) async throws -> [AlbumSummary]
    /// シリーズ一覧。
    func series(brandIds: Set<String>, query: String?) async throws -> [SeriesSummary]
    /// CDシリーズ名の一覧 (フィルタ用)。
    func cdSeriesList() async throws -> [String]
    /// シリーズグループ名の一覧 (フィルタ用)。
    func seriesGroups(brandIds: Set<String>) async throws -> [String]
    /// ブランドの曲 id 一覧。
    func songIds(brandId: String, includeCovers: Bool, excludeRemixes: Bool) async throws -> [String]
    /// 指定公演のキャストが原曲を歌う曲 id 集合。
    func originalSongIds(forShowCastOf showId: String) async throws -> Set<String>
    /// ブランド公式曲の id 集合。
    func brandedSongIds() async throws -> Set<String>

    // MARK: - コミュニティ構造化 (コーレス/参考動画。CloudKit 同期のローカルミラー)

    /// この曲のコーレス。
    func songCalls(songId: String) async throws -> [SongCall]
    /// この曲の参考動画。
    func songVideos(songId: String) async throws -> [SongVideo]
}
