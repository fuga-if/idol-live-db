import Foundation

/// 公演 (Show) / セットリストの読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/CoreShowRepository` (共有コアのスナップショット)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol ShowReading: Sendable {
    /// イベント配下の公演一覧。
    func shows(eventId: String) async throws -> [Show]
    /// 単一公演。
    func show(id: String) async throws -> Show?
    /// 最新公演 (日付最大)。
    func latestShow() async throws -> Show?
    /// 公演のセットリスト。
    func setlist(showId: String) async throws -> [SetlistRow]
    /// セトリ項目 id → 出演者行。
    func allPerformers(showId: String) async throws -> [String: [PerformerRow]]
    /// セトリ 1 行ぶんの添え物 (名義・ユニットのチップ・全員・何回目・いつぶり・
    /// 自分の回収) と、公演の頭に出す回収の要約。
    /// 行の並びは `setlist(showId:)` と同じなので、受け側は zip するだけでよい。
    ///
    /// **名義の決め方 (その披露の名義 → 曲の名義 → 個人名併記 → 顔ぶれ推論 → 名前) も、
    /// 「N 年ぶり」の言い回しも、「初回収 / 回収 N 回目 / 未回収」の判断も imas-core が
    /// 持つ。** 画面でユニットを逆引きしたり間隔を組み立てたり、参加記録と突き合わせたり
    /// しないこと (同じ規則を Android にも写経することになる)。
    ///
    /// 参加マークの解決はアダプタの仕事 (`CollectionAttendance`)。画面は渡さない。
    ///
    /// `displayMode` は「どこまで詳しく出すか」。履歴の札・回収の札・要約を出すかどうかも
    /// コアがこれで決めるので、モードが変わったら読み直すこと。
    func setlistRowMeta(
        showId: String,
        nameMode: PerformerNameMode,
        displayMode: SetlistDisplayMode
    ) async throws -> SetlistRowMetaBundle
    /// 公演の全出演キャスト idol_id 集合 (「全員」表記の判定用)。
    func showIdolIds(showId: String) async throws -> Set<String>
    /// song_id → 原曲アーティスト idol_id 集合 (一部カバー判定用)。
    func originalArtistIds(songIds: [String]) async throws -> [String: Set<String>]
    /// フィルタ条件で絞った公演。
    func shows(criterion: ShowFilterCriterion) async throws -> [Show]
    /// ピッカー用の公演一覧 (イベント名つき・新しい順)。
    func allShows(limit: Int) async throws -> [ShowWithEventName]
    /// ピッカー用の公演検索 (イベント名つき)。
    func searchShows(query: String, limit: Int) async throws -> [ShowWithEventName]
    /// 公演の出演キャストを Idol として取得 (出演者予想の対象一覧用)。
    func showCastIdols(showId: String) async throws -> [Idol]
    /// 公演の券種と価格 (チケット代の記録・セトリ画面の価格表示)。
    /// 券種はスナップショットに載らないので、実装は端末の DB を読む。
    func tickets(showId: String) async throws -> [ShowTicket]
    /// そのイベントで着られた衣装 (共通・個別に分けて進行順)。記録が無ければ両方空。
    ///
    /// 衣装の畳み方 (同じ衣装が複数曲・複数公演に出たら 1 件にまとめる)・共通と個別の
    /// 分け方・「どの公演で着たか」の 1 行は imas-core が持つ。画面側で組み直さないこと。
    func eventCostumes(eventId: String) async throws -> EventCostumesRecord
    /// その衣装が着られた公演 (イベントごとに束ね、イベントは新しい順)。
    func costumeEvents(costumeId: String) async throws -> [CostumeEventRecord]
    /// 会場マスタ一式 (施設・改名履歴・ホール)。当時名やキャパの解決に使う。
    func venueDirectory() async throws -> VenueDirectory
    /// 指定会場 (venue_id) で公演があったイベントの id 集合 (ライブ一覧の会場絞り込み用)。
    func eventIdsAtVenue(_ venueId: String) async throws -> Set<String>
    /// 公演 id 群 → 所属イベント id 集合。参加記録 (show 単位) から
    /// event 単位の絞り込みを作るために使う。1 件ずつ引くと参加数ぶん
    /// 往復が増えるので、必ずこの一括版を使うこと。
    func eventIds(forShows showIds: [String]) async throws -> Set<String>
    /// 検索語に一致した会場を event_id ごとに 1 件返す (検索結果に一致理由を出すため)。
    func venuesMatching(query: String, eventIds: [String]) async throws -> [String: String]
}
