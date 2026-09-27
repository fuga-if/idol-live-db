import Foundation
import Observation
import os

/// セトリ画面 (`SetlistView`) の読み込み。
///
/// 以前は View の 1 つの do の中で 9 回 await していて、途中の 1 つが失敗すると、
/// それより後ろ (衣装・券種・ブランド色・イベント名・いいね) が読まれないまま
/// 中途半端な画面が残った。ここでは読み込みの単位ごとに失敗を独立させる。
/// どれかが失敗しても、ほかの単位は出す。
///
/// 表示の組み立て (行・札・要約の文言) は、これまでどおり View とコアが持つ。
@MainActor
@Observable
final class SetlistViewModel {
    // MARK: - セトリ本体
    private(set) var setlist: [SetlistRow] = []
    private(set) var performersByItemId: [String: [PerformerRow]] = [:]
    private(set) var idolsById: [String: Idol] = [:]

    // MARK: - 添え物
    /// この公演の券種 (マスタ)。
    private(set) var tickets: [ShowTicket] = []
    /// brand_id → イメージカラー hex。曲のフォールバックジャケ/チップ色のシード。
    private(set) var brandHexById: [String: String] = [:]
    /// brand_id → 短い表示名。パンくずの 1 段目に出す。
    private(set) var brandNameById: [String: String] = [:]
    /// 親イベント (開催形態の出し分け・シェア文のイベント名)。
    private(set) var event: Event?
    /// 公演内の各曲への「良かった」の状態 (song_id 索引)。
    private(set) var likesBySongId: [String: SetlistLikeService.LikeEntry] = [:]
    /// セトリ 1 行ぶんの添え物 (名義・ユニットのチップ・全員・何回目・いつぶり)。
    /// **中身を決めるのは imas-core。**
    private(set) var rowMetaByItemId: [String: SetlistRowMetaRecord] = [:]
    /// `rowMetaByItemId` がどの公演の答えか。
    private var rowMetaShowId: String?
    /// 公演の頭に出す「自分の回収」の要約。**出すかどうかも文言も imas-core が決める。**
    private(set) var collectionSummary: ShowCollectionRecord?
    /// 会場マスタ。当時名とキャパの解決に使う。
    private(set) var venueDirectory: VenueDirectory = .empty

    /// この公演自体のブランド色 hex。
    var showBrandHex: String? { event?.brandId.flatMap { brandHexById[$0] } }

    private let showReading: any ShowReading
    private let idolReading: any IdolReading
    private let brandReading: any BrandReading
    private let eventReading: any EventReading
    /// 「良かった」の件数と自分の状態 (サーバ)。テストでは差し替える。
    private let fetchLikes: @Sendable (String) async throws -> [SetlistLikeService.LikeEntry]

    nonisolated init(
        showReading: any ShowReading = AppContainer.shared.showReading,
        idolReading: any IdolReading = AppContainer.shared.idolReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading,
        eventReading: any EventReading = AppContainer.shared.eventReading,
        fetchLikes: @escaping @Sendable (String) async throws -> [SetlistLikeService.LikeEntry] = { showId in
            try await SetlistLikeService.shared.fetch(showId: showId)
        }
    ) {
        self.showReading = showReading
        self.idolReading = idolReading
        self.brandReading = brandReading
        self.eventReading = eventReading
        self.fetchLikes = fetchLikes
    }

    // MARK: - 読み込み

    /// 画面を開いたとき・編集から戻ったときに読む。単位ごとに失敗を閉じ込める。
    func load(show: Show) async {
        await loadSetlist(showId: show.id)
        await loadTickets(showId: show.id)
        await loadBrands()
        await loadEvent(eventId: show.eventId)
        await loadLikes(showId: show.id)
    }

    /// 行の添え物と回収の要約を読み直す。歌唱者の表示名の設定・表示モード・参加記録・
    /// 「配信も回収に含める」設定で答えが変わるので、変わるたびに呼ぶ。
    func loadRowMeta(showId: String, nameMode: PerformerNameMode, displayMode: SetlistDisplayMode) async {
        do {
            let bundle = try await showReading.setlistRowMeta(
                showId: showId, nameMode: nameMode, displayMode: displayMode)
            rowMetaByItemId = Dictionary(uniqueKeysWithValues: bundle.rows.map { ($0.itemId, $0) })
            collectionSummary = bundle.collection
            rowMetaShowId = showId
        } catch {
            Logger.database.error("load_failed setlist_row_meta: \(error.localizedDescription)")
            // 同じ公演の読み直し (設定の切り替え等) で落ちたときは、前の答えを残す。
            // 消すと区切りの見出しが全部「本編」に潰れ、落ちたことが画面の形の変化として出る。
            guard rowMetaShowId != showId else { return }
            rowMetaByItemId = [:]
            collectionSummary = nil
            rowMetaShowId = nil
        }
    }

    func loadVenueDirectory() async {
        do {
            venueDirectory = try await showReading.venueDirectory()
        } catch {
            Logger.database.error("load_failed setlist_venues: \(error.localizedDescription)")
        }
    }

    /// 「良かった」を押した結果を反映する (サーバに送るのは行の View)。
    func setLike(songId: String, likeCount: Int, hasUserLiked: Bool) {
        likesBySongId[songId] = SetlistLikeService.LikeEntry(
            songId: songId, likeCount: likeCount, hasUserLiked: hasUserLiked)
    }

    // MARK: - 単位ごとの読み込み

    /// セトリの行と、行に要るもの (出演者・アイドルの実体)。
    /// 行が読めなければ、ほかは意味が無いので読まない。
    private func loadSetlist(showId: String) async {
        do {
            setlist = try await showReading.setlist(showId: showId)
        } catch {
            Logger.database.error("load_failed setlist: \(error.localizedDescription)")
            return
        }
        do {
            performersByItemId = try await showReading.allPerformers(showId: showId)
        } catch {
            Logger.database.error("load_failed setlist_performers: \(error.localizedDescription)")
        }
        // 全 performer の idolId をまとめて 1 回で引く (N+1 にしない)。
        let idolIds = Array(Set(performersByItemId.values.flatMap { $0 }.compactMap(\.idolId)))
        do {
            let idols = try await idolReading.idols(ids: idolIds)
            idolsById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0) })
        } catch {
            Logger.database.error("load_failed setlist_idols: \(error.localizedDescription)")
        }
    }

    private func loadTickets(showId: String) async {
        do {
            tickets = try await showReading.tickets(showId: showId)
        } catch {
            Logger.database.error("load_failed setlist_tickets: \(error.localizedDescription)")
        }
    }

    private func loadBrands() async {
        do {
            let brands = try await brandReading.brands()
            brandHexById = Dictionary(uniqueKeysWithValues: brands.compactMap { brand in
                brand.color.map { (brand.id, $0) }
            })
            brandNameById = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0.shortName) })
        } catch {
            Logger.database.error("load_failed setlist_brands: \(error.localizedDescription)")
        }
    }

    private func loadEvent(eventId: String) async {
        do {
            event = try await eventReading.event(id: eventId)
        } catch {
            Logger.database.error("load_failed setlist_event: \(error.localizedDescription)")
        }
    }

    /// セトリが埋まっている公演だけ取る (空のセトリには付けようがない)。
    private func loadLikes(showId: String) async {
        guard !setlist.isEmpty else { return }
        do {
            let entries = try await fetchLikes(showId)
            likesBySongId = Dictionary(uniqueKeysWithValues: entries.map { ($0.songId, $0) })
        } catch {
            Logger.database.warning("setlist_likes_fetch_failed: \(error.localizedDescription)")
        }
    }
}
