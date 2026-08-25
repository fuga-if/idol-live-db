package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.AllPerformerRow
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.model.SetlistItem
import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.data.model.Venue
import com.fugaif.imaslivedb.data.model.VenueHall
import com.fugaif.imaslivedb.data.model.VenueName
import com.fugaif.imaslivedb.data.model.ShowCast
import com.fugaif.imaslivedb.data.model.ShowWithEventName
import uniffi.imas_core.EventDetailRecord
import uniffi.imas_core.EventListRecord
import uniffi.imas_core.SetlistPerformerRecord
import uniffi.imas_core.ShowRecord

/**
 * ライブ (イベント/公演/セトリ/会場) の読み取り口。
 *
 * 読み取りは共有コア (imas-core) のインメモリスナップショットを第一経路とし、
 * 未ロード・利用不可のときだけ従来の Room/SQL 経路へ委譲する (呼び出し単位のフォールバック)。
 * Event / Show / Venue はコアの射影と Room のエンティティが列 1:1 なので、
 * 曲やアイドルと違って実体をそのまま組み立てられる。
 */
class EventRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null
) {

    suspend fun fetchEvents(brandId: String? = null): List<Event> {
        snapshots?.query { store -> store.eventRecords(brandId).map { it.toEvent() } }?.let { return it }
        return if (brandId != null) {
            db.eventDao().fetchEventsByBrand(brandId)
        } else {
            db.eventDao().fetchEvents()
        }
    }

    /**
     * ライブ一覧の母集合。kind を一切絞らない (live/festival だけでなく radio や
     * release_event も並べる) のが Android の一覧仕様。
     *
     * コアの eventsWithFirstDate は kind をホワイトリストでしか受けられず、
     * 「絞らない」を表現できない。全 kind を列挙して渡すと、将来 kind が増えたときに
     * その分だけ一覧から静かに消えるので、SQL 経路のまま残す。
     */
    suspend fun fetchEventsWithFirstDate(): List<EventWithDateRange> {
        return db.eventDao().fetchEventsWithFirstDate().map { it.toEventWithDateRange() }
    }

    suspend fun fetchEventStats(eventId: String): EventStats {
        snapshots?.query { store ->
            val s = store.eventStats(eventId)
            EventStats(
                showCount = s.showCount.toInt(),
                totalSongs = s.totalSongs.toInt(),
                uniqueSongs = s.uniqueSongs.toInt(),
                castCount = s.castCount.toInt()
            )
        }?.let { return it }
        return db.eventDao().fetchEventStats(eventId)
    }

    /**
     * イベント配下の show_cast 全行 (主演/ゲスト/DAY別出演の判定用)。
     *
     * コアの eventAttendance は「DAY 別出席表」という別形の集計射影で、show_cast の生行は
     * 返さない。この口の戻り値 (ShowCast のリスト) に無理に畳み込むと呼び出し側の判定が
     * 変わるため、対応 API が生えるまで SQL 経路のまま。
     */
    suspend fun fetchEventShowCast(eventId: String): List<ShowCast> {
        return db.eventDao().fetchEventShowCast(eventId)
    }

    /**
     * ブランド全体のアイドル名簿 (出演/欠席の対象集合)。
     *
     * コアの idolList は is_external を必ず落とすため、外部ゲストを含むこの名簿とは
     * 母集団が変わる (欠席側に出ていた演者が消える)。SQL 経路のまま。
     */
    suspend fun fetchBrandRoster(brandId: String): List<Idol> {
        return db.idolDao().fetchIdolsByBrand(brandId)
    }

    /** ヒーロー配色に使うブランド情報 (color hex)。 */
    suspend fun fetchBrand(brandId: String): Brand? {
        snapshots?.query { store -> store.brandRecords().firstOrNull { it.id == brandId }?.toBrand() }
            ?.let { return it }
        return db.brandDao().fetchBrand(brandId)
    }

    suspend fun fetchShows(eventId: String): List<Show> {
        // コアは (date, sort_order) 順。Room の `ORDER BY sort_order` は同じイベント内で
        // 日付が前後する編成のときだけ並びが変わり得るが、iOS と同じ並びに揃うのが正。
        snapshots?.query { store -> store.showsByEvent(eventId).map { it.toShow() } }?.let { return it }
        return db.showDao().fetchShows(eventId)
    }

    suspend fun fetchEvent(id: String): Event? {
        snapshots?.query { store -> store.eventRecord(id)?.toEvent() }?.let { return it }
        return db.eventDao().fetchEvent(id)
    }

    suspend fun fetchShow(id: String): Show? {
        snapshots?.query { store -> store.showRecord(id)?.toShow() }?.let { return it }
        return db.showDao().fetchShow(id)
    }

    suspend fun fetchLatestShow(): Show? {
        snapshots?.query { store -> store.latestShow()?.toShow() }?.let { return it }
        return db.showDao().fetchLatestShow()
    }

    /**
     * 会場マスタ一式。244施設 + 名前245件 + ホール39件と小さいので一括で読み、
     * 当時名やキャパの解決はメモリ上 (VenueDirectory) で行う (公演ごとの N+1 を避ける)。
     */
    suspend fun fetchVenueDirectory(): VenueDirectory {
        // コアなら 3 テーブルぶんが 1 呼び出しで揃う (SQL 経路は 3 クエリ)。
        snapshots?.query { store ->
            val d = store.venueDirectory()
            VenueDirectory(
                venues = d.venues.map {
                    Venue(
                        id = it.id, name = it.name, nameKana = it.nameKana,
                        prefecture = it.prefecture, city = it.city, aliases = it.aliases,
                        capacity = it.capacity?.toInt(), sortOrder = it.sortOrder.toInt()
                    )
                },
                names = d.names.map {
                    VenueName(
                        id = it.id, venueId = it.venueId, name = it.name,
                        validFrom = it.validFrom, validTo = it.validTo
                    )
                },
                halls = d.halls.map {
                    VenueHall(id = it.id, venueId = it.venueId, name = it.name, capacity = it.capacity?.toInt())
                }
            )
        }?.let { return it }
        return VenueDirectory(
            venues = db.showDao().fetchVenues(),
            names = db.showDao().fetchVenueNameRecords(),
            halls = db.showDao().fetchVenueHalls()
        )
    }

    /** 指定会場 (venue_id) で公演があったイベントの id 集合 (ライブ一覧の会場絞り込み用)。 */
    suspend fun fetchEventIdsAtVenue(venueId: String): Set<String> {
        snapshots?.query { store -> store.eventIdsAtVenue(venueId).toSet() }?.let { return it }
        return db.showDao().fetchEventIdsAtVenue(venueId).toSet()
    }

    /** オープン編集「セトリ編集」の対象公演を選ぶピッカー用。 */
    suspend fun searchShows(query: String, limit: Int = 30): List<ShowWithEventName> {
        val trimmed = query.trim()
        snapshots?.query { store ->
            if (trimmed.isEmpty()) {
                store.allShowsWithEventName(limit.toUInt())
            } else {
                store.searchShowsWithEventName(trimmed, limit.toUInt())
            }
        }?.let { records ->
            // コアの射影はピッカー表示に要る列 (venue_city / start_time / sort_order /
            // performer_type) を持たない。選択後は toShow() で公演実体として使われるので、
            // 欠けたまま組み立てず Room から引き直す。並びはコアが正。
            val shows = hydrateInOrder(records.map { it.id }, Show::id) { db.showDao().fetchShowsByIds(it) }
                .associateBy { it.id }
            return records.mapNotNull { r -> shows[r.id]?.toShowWithEventName(r.eventName) }
        }
        return if (trimmed.isEmpty()) {
            db.showDao().fetchRecentShowsWithEventName(limit)
        } else {
            db.showDao().searchShowsWithEventName("%$trimmed%", limit)
        }
    }

    /**
     * セトリ編集画面が読む「いまローカルに保存されているセトリ」。**Room 経路のまま残す。**
     *
     * [replaceSetlist] はスナップショットを作り直すが、その reload は失敗を握り潰して
     * 旧スナップショットを維持する (load 失敗時も機能を落とさないための設計)。ここが
     * 旧スナップショットを読むと、その値が次回保存時の差分ベースライン
     * (SetlistEditScreen の initialItemIds / originalItems) になるため、削除済み項目への
     * DELETE や既存項目への CREATE を投げる壊れた差分を生む。書き込み結果を差分の基準に
     * する口だけは、失敗しようのない書き込み先 (Room) から読むのが正しい。
     *
     * 表示側 (SetlistViewModel) は [fetchPerformersByItem] を通るので、こことは別経路。
     */
    suspend fun fetchSetlist(showId: String): List<SetlistRow> {
        return db.setlistDao().fetchSetlist(showId)
    }

    /** [fetchSetlist] と同じ理由 (保存後の再読込・差分ベースライン) で Room 経路のまま。 */
    suspend fun fetchAllPerformers(showId: String): List<AllPerformerRow> {
        return db.setlistDao().fetchAllPerformers(showId)
    }

    /**
     * セトリ**表示**の出演者 (setlist_item_id → 出演者)。編集画面が使う [fetchAllPerformers]
     * とは用途が違うので経路も分ける (あちらは差分の基準なので Room が正)。
     * 編集直後にここが古い値を返さないのは [replaceSetlist] が reload を撃つため。
     *
     * 曲ごとのグループ化と並びはコアが担う。Room の SQL には ORDER BY が無く並びが未規定
     * だったので、iOS と同じ「アイドルの sort_order 順」に揃う。
     *
     * 表示名 (`PerformerRow.name`) はコアでは現任 CV 名で、不在ならアイドル名に落ちる。
     * Android の Room には idol_voice_actors が無く、コアのローダは欠損テーブルを空として
     * 読むため当面かならずアイドル名になる (= 現行の SQL 経路と同じ文字列)。将来
     * idol_voice_actors を持たせると、この画面のチップだけ先に CV 名へ切り替わる。
     */
    suspend fun fetchPerformersByItem(showId: String): Map<String, List<PerformerRow>> {
        snapshots?.query { store ->
            store.showSetlistPerformers(showId).mapValues { (_, rows) -> rows.map { it.toPerformerRow() } }
        }?.let { return it }
        return db.setlistDao().fetchAllPerformers(showId)
            .groupBy { it.setlistItemId }
            .mapValues { (_, rows) -> rows.map { it.toPerformerRow() } }
    }

    /**
     * セトリ編集の保存後、サーバ確定値でローカル DB を全置換する (iOS `showWriting.replaceSetlist` と同じ)。
     * ローカル反映は admin が直接反映 (POST /edits) できた場合のみ呼ばれる想定。
     *
     * 書き込み先は Room (スナップショットは読み取り専用)。書き込んだら**その場で**
     * スナップショットを作り直す。これを省くと、スナップショット経由で読む口
     * ([fetchPerformersByItem]) だけが次の同期完了まで編集前の値を返し、
     * 「編集直後に自分の編集が見えない」回帰になる (iOS の
     * `SnapshotInvalidatingShowWriting` と同じ役割)。
     *
     * reload は DB 全読みで数百 ms かかるが、await して完了させる。保存は「保存中…」を
     * 出したままの操作で、戻った時点で全経路が新しい値を返すことのほうが重要。
     * 失敗しても現行スナップショットが維持されるだけなので投げ直さない。
     */
    suspend fun replaceSetlist(
        deletedItemIds: List<String>,
        deletedPerformers: List<Pair<String, String>>,
        items: List<SetlistItem>,
        performers: List<SetlistPerformer>
    ) {
        if (deletedItemIds.isNotEmpty()) db.setlistDao().deleteItems(deletedItemIds)
        for ((itemId, idolId) in deletedPerformers) db.setlistDao().deletePerformer(itemId, idolId)
        if (items.isNotEmpty()) db.setlistDao().upsertItems(items)
        if (performers.isNotEmpty()) db.setlistDao().upsertPerformers(performers)
        snapshots?.reload()
    }
}

// ---- コアの射影 → Room エンティティ (列は 1:1) ----

private fun EventListRecord.toEvent(): Event = Event(
    id = id, brandId = brandId, name = name, eventType = eventType, isStreaming = isStreaming,
    isSolo = isSolo, kind = kind, ticketOpenDate = ticketOpenDate, ticketDeadline = ticketDeadline,
    ticketLotteryDate = ticketLotteryDate, ticketUrl = ticketUrl, jointBrandIds = jointBrandIds
)

private fun EventDetailRecord.toEvent(): Event = Event(
    id = id, brandId = brandId, name = name, eventType = eventType, isStreaming = isStreaming,
    isSolo = isSolo, kind = kind, ticketOpenDate = ticketOpenDate, ticketDeadline = ticketDeadline,
    ticketLotteryDate = ticketLotteryDate, ticketUrl = ticketUrl, jointBrandIds = jointBrandIds
)

private fun ShowRecord.toShow(): Show = Show(
    id = id, eventId = eventId, name = name, date = date, venue = venue, venueId = venueId,
    hall = hall, streamPlatform = streamPlatform, venueCity = venueCity, startTime = startTime,
    sortOrder = sortOrder.toInt(), performerType = performerType
)

/** `PerformerRow.id` は SQL 時代も idol_id をそのまま返していた (iOS CoreRecordMapping と同じ)。 */
private fun SetlistPerformerRecord.toPerformerRow(): PerformerRow = PerformerRow(
    id = idolId, name = displayName, idolColor = idolColor, idolName = idolName, idolId = idolId
)

private fun AllPerformerRow.toPerformerRow(): PerformerRow = PerformerRow(
    id = castId, name = name, idolColor = idolColor, idolName = idolName, idolId = idolId
)

private fun Show.toShowWithEventName(eventName: String): ShowWithEventName = ShowWithEventName(
    id = id, eventId = eventId, name = name, date = date, venue = venue, venueCity = venueCity,
    startTime = startTime, sortOrder = sortOrder, performerType = performerType, eventName = eventName
)
