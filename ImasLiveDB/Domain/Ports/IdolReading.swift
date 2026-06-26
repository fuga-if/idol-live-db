import Foundation

/// アイドル(キャスト)マスタの読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/GRDBIdolRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol IdolReading: Sendable {
    /// ブランド絞り込み (nil で全件) のアイドル一覧。
    func idols(brandId: String?) async throws -> [Idol]
    /// 単一アイドル。
    func idol(id: String) async throws -> Idol?
    /// id 集合に該当するアイドル。
    func idols(ids: [String]) async throws -> [Idol]
    /// フィルタ条件で絞ったアイドル。
    func idols(criterion: IdolFilterCriterion) async throws -> [Idol]
    /// idol_id → キャスト(声優)名。
    func idolCastNames() async throws -> [String: String]
    /// 声優名でアイドルを引く。
    func idolsByVoiceActor(name: String) async throws -> [Idol]
    /// 名前 / かな / ローマ字での部分一致検索。
    func searchIdols(query: String, limit: Int) async throws -> [Idol]

    // MARK: - アイドル詳細

    /// アイドルが歌唱に関わる曲 (role 指定で絞り込み: "original" 等)。
    func idolSongs(idolId: String, role: String?) async throws -> [Song]
    /// アイドルがライブで披露した曲 (披露履歴つき)。
    func idolPerformedSongs(idolId: String) async throws -> [IdolPerformedSong]
    /// 所属ユニット。
    func idolUnits(idolId: String) async throws -> [Unit]
    /// 出演公演一覧。
    func idolShows(idolId: String) async throws -> [CastShowRow]
    /// ピッカー用の全アイドル。
    func allIdolsForPicker() async throws -> [Idol]
    /// あるアイドルが特定曲を披露した公演履歴。
    func idolSongHistory(idolId: String, songId: String) async throws -> [CastShowRow]
}
