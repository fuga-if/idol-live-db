package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.AllPerformerRow
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.EventAttendance
import com.fugaif.imaslivedb.data.model.EventInfo
import com.fugaif.imaslivedb.data.model.ShowInfo
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.data.model.Venue
import com.fugaif.imaslivedb.data.model.VenueHall
import com.fugaif.imaslivedb.data.model.VenueName
import com.fugaif.imaslivedb.data.model.ShowWithEventName
import com.fugaif.imaslivedb.data.model.Vocab
import uniffi.imas_core.PerformerNameMode
import uniffi.imas_core.SetlistDisplayMode
import uniffi.imas_core.SetlistRowMetaRecord
import uniffi.imas_core.CostumeEventRecord
import uniffi.imas_core.CostumeRecord
import uniffi.imas_core.EventCostumesRecord
import uniffi.imas_core.EventDetailRecord
import uniffi.imas_core.EventListRecord
import uniffi.imas_core.EventWithDateRecord
import uniffi.imas_core.SetlistPerformerRecord
import uniffi.imas_core.ShowCollectionRecord
import uniffi.imas_core.ShowRecord
import uniffi.imas_core.AttendanceMarkRecord
import uniffi.imas_core.TimelineBarRecord
import uniffi.imas_core.EventHeroRecord
import uniffi.imas_core.TicketSale
import uniffi.imas_core.TicketSaleTimeline
import com.fugaif.imaslivedb.data.model.JstDay
import java.time.Instant

/**
 * [EventRepository.fetchSetlistRowMeta] の結果。行の添え物と、公演の頭に出す
 * 自分の回収の要約を 1 回で返す (要約は行の回収から数えるので、別の呼び出しに
 * 分けるとズレを作れてしまう — 共有コアの `SetlistRowMetaBundle` と同じ理由)。
 */
data class SetlistRowMetaResult(
    val rowsByItemId: Map<String, SetlistRowMetaRecord> = emptyMap(),
    val collection: ShowCollectionRecord? = null
)

/**
 * ライブ (イベント/公演/セトリ/会場) の読み取り口。
 *
 * 読み取りは共有コア (imas-core) のインメモリスナップショットが答える (SQL の代わりの経路は
 * 持たない)。Room で読むのは、セトリ編集の差分の基準 ([fetchSetlist]) だけ。
 * Event / Show / Venue はコアの射影と Room のエンティティが列 1:1 なので、
 * 曲やアイドルと違って実体をそのまま組み立てられる。
 */
class EventRepository(
    private val db: AppDatabase,
    private val snapshots: SnapshotStoreProvider
) {

    suspend fun fetchEvents(brandId: String? = null): List<Event> =
        snapshots.query { store -> store.eventRecords(brandId).map { it.toEvent() } }

    /**
     * ライブ一覧の母集合 (公演の無いイベントも出す)。種別は語彙の 6 種 (最後が「その他」) を
     * 全部渡して、実質絞らない。知らない種別はコアが「その他」に寄せて比べるので、
     * 種別が増えても一覧から消えない (Q-08l)。
     */
    suspend fun fetchEventsWithFirstDate(): List<EventWithDateRange> {
        val kinds = Vocab.table.eventKinds.map { it.value }
        return snapshots.query { store ->
            store.eventsWithFirstDate(null, true, false, kinds).map { it.toEventWithDateRange() }
        }
    }

    // ---- 絞り込み一覧 (FilteredEvents / FilteredShows) の母集団 ----

    /**
     * ブランドで絞ったライブ一覧 (最初の公演日の降順)。
     *
     * kind はコアの既定 (live + festival) に任せる。「kind を一切絞らない」一覧である
     * [fetchEventsWithFirstDate] とはここが違う — こちらは iOS の
     * `EventFilterCriterion.brand` を写したもので、iOS もラジオや発売記念イベントを混ぜない。
     * 公演が 1 本も無いイベントも出す (includeEmpty=true) のは iOS FilteredEventsView と同じ。
     */
    suspend fun fetchEventsWithDateByBrand(brandId: String): List<EventWithDateRange> =
        snapshots.query { store ->
            store.eventsWithFirstDate(brandId, true, false, null).map { it.toEventWithDateRange() }
        }

    /**
     * 開催年で絞ったライブ一覧。
     *
     * last_date は返さない (SQL 時代の年フィルタが SELECT していなかった挙動をコアがそのまま
     * 写している)。行の日付が「最初の公演日」だけでレンジ ("first〜last") にならないのは
     * iOS と揃った現行挙動。
     */
    suspend fun fetchEventsWithDateByYear(year: Int): List<EventWithDateRange> =
        snapshots.query { store ->
            store.eventsWithDateByYear(year, true).map { it.toEventWithDateRange() }
        }

    // ---- 自分のマークから引くイベント (マークは Room、イベントの形はコア) ----

    /** お気に入りのライブ (イベント)。最初の公演日の降順。 */
    suspend fun fetchFavoriteEvents(): List<EventWithDateRange> {
        val ids = db.userMarkDao().idsFor(UserMark.EVENT, UserMark.FAVORITE)
        if (ids.isEmpty()) return emptyList()
        return snapshots.query { store -> store.eventsWithDateByIds(ids).map { it.toEventWithDateRange() } }
    }

    /**
     * 参加したライブ (イベント) を重複なしで、最初の公演日の降順。イベント単位の参加マークと、
     * 公演単位の参加マーク (その公演のイベント) の両方を拾う (束ね方はコア)。
     */
    suspend fun fetchAttendedEvents(): List<EventWithDateRange> {
        val eventIds = db.userMarkDao().idsFor(UserMark.EVENT, UserMark.ATTENDED)
        val showIds = db.userMarkDao().idsFor(UserMark.SHOW, UserMark.ATTENDED)
        return snapshots.query { store ->
            store.attendedEventsWithDate(eventIds, showIds).map { it.toEventWithDateRange() }
        }
    }

    /**
     * 参加したイベントを「現地参加を含む」「配信参加を含む」「LV 参加を含む」に分ける。
     * 1 イベント内で現地と配信が混在すれば両方に入る。種別なし (旧データ) は現地扱い (規則はコア)。
     */
    suspend fun fetchAttendedEventTypeSets(): AttendedEventTypeSets {
        val eventMarks = attendanceMarks(UserMark.EVENT)
        val showMarks = attendanceMarks(UserMark.SHOW)
        val sets = snapshots.query { store -> store.attendedEventTypeSets(eventMarks, showMarks) }
        return AttendedEventTypeSets(sets.live.toSet(), sets.stream.toSet(), sets.liveViewing.toSet())
    }

    /** [type] の参加マーク (ON のもの) と参加種別。 */
    private suspend fun attendanceMarks(type: String): List<AttendanceMarkRecord> =
        db.userMarkDao().marksOf(type, UserMark.ATTENDED)
            .filter { it.boolValue }
            .map { AttendanceMarkRecord(it.entityId, it.textValue) }

    /** 会場での公演一覧 (新しい順)。`venue` は会場マスタの ID (`venue_...`)。 */
    suspend fun fetchShowsAtVenue(venue: String): List<Show> =
        snapshots.query { store -> store.showsAtVenue(venue).map { it.toShow() } }

    /** 指定日 (YYYY-MM-DD) の公演一覧。 */
    suspend fun fetchShowsOnDate(date: String): List<Show> =
        snapshots.query { store -> store.showsOnDate(date).map { it.toShow() } }

    suspend fun fetchEventStats(eventId: String): EventStats =
        snapshots.query { store ->
            val s = store.eventStats(eventId)
            EventStats(
                showCount = s.showCount.toInt(),
                totalSongs = s.totalSongs.toInt(),
                uniqueSongs = s.uniqueSongs.toInt(),
                castCount = s.castCount.toInt()
            )
        }

    /**
     * DAY 別の出演状況 (出席・欠席・主演・ゲスト)。イベントにブランドが無いときや、
     * 母集団が空のときは null。
     *
     * 母集団 (外部ゲスト・合同ブランド・デビュー日) と出席 (show_cast ∪ 歌唱) の規則は
     * コアの `eventAttendance` が持つ (iOS と同じ)。母集団は表示順 (sort_order) の
     * idol_id 列で返るので、並びを保ったまま実体化する。
     */
    suspend fun fetchEventAttendance(eventId: String): EventAttendance? {
        val record = snapshots.query { store -> store.eventAttendance(eventId) } ?: return null
        return EventAttendance(
            brandIdols = hydrateInOrder(record.brandIdolIds, Idol::id) { db.idolDao().fetchIdolsByIds(it) },
            shows = record.shows.map { it.toShow() },
            presenceByShow = record.presenceByShow.mapValues { it.value.toSet() },
            leadByShow = record.leadByShow.mapValues { it.value.toSet() },
            guestByShow = record.guestByShow.mapValues { it.value.toSet() },
            groupRecords = record.groups
        )
    }

    /** ヒーロー配色に使うブランド情報 (color hex)。 */
    suspend fun fetchBrand(brandId: String): Brand? =
        snapshots.query { store -> store.brandRecords().firstOrNull { it.id == brandId }?.toBrand() }

    // コアは (date, sort_order) 順 (iOS と同じ並び)。
    suspend fun fetchShows(eventId: String): List<Show> =
        snapshots.query { store -> store.showsByEvent(eventId).map { it.toShow() } }

    /**
     * イベント詳細のヒーロー (開催期間・会場・今後か・参加の札)。参加の札の判定
     * (公演単位のマーク優先、無ければイベント単位のマークで全公演) もコア。
     */
    suspend fun fetchEventHero(eventId: String, attendedShowIds: Collection<String>, eventMarked: Boolean): EventHeroRecord? =
        snapshots.query { store -> store.eventHero(eventId, attendedShowIds.toList(), eventMarked, JstDay.today()) }

    /** イベントと、コアが決めた属性 (合同か)。 */
    suspend fun fetchEventInfo(id: String): EventInfo? =
        snapshots.query { store -> store.eventRecord(id)?.let { EventInfo(it.toEvent(), it.isJoint) } }

    /** 公演と、コアが決めた属性 (キャラライブか)。 */
    suspend fun fetchShowInfo(id: String): ShowInfo? =
        snapshots.query { store -> store.showRecord(id)?.let { ShowInfo(it.toShow(), it.isCharacterLive) } }

    /** id で引くイベント (日付・合同か付き)。 */
    suspend fun fetchEventsWithDateByIds(ids: List<String>): List<EventWithDateRange> =
        if (ids.isEmpty()) emptyList()
        else snapshots.query { store -> store.eventsWithDateByIds(ids).map { it.toEventWithDateRange() } }

    suspend fun fetchEvent(id: String): Event? =
        snapshots.query { store -> store.eventRecord(id)?.toEvent() }

    suspend fun fetchLatestShow(): Show? =
        snapshots.query { store -> store.latestShow()?.toShow() }

    /**
     * 会場マスタ一式。244施設 + 名前245件 + ホール39件と小さいので一括で読み、
     * 当時名やキャパの解決はメモリ上 (VenueDirectory) で行う (公演ごとの N+1 を避ける)。
     */
    suspend fun fetchVenueDirectory(): VenueDirectory =
        snapshots.query { store ->
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
        }

    /**
     * 年表 (ブランド史) の帯。`brandId` が null なら全ブランド横断。
     *
     * 節目・ライブ・楽曲シリーズの束ね方も、帯の色シード・バッジ・遷移先も**すべてコアが決める**。
     * ここは射影をそのまま渡すだけで、画面側は返ってきた帯を並べるだけにすること
     * (束ね方を UI で書き直すと iOS と黙ってズレる)。
     */
    suspend fun fetchTimelineBars(brandId: String?): List<TimelineBarRecord> =
        snapshots.query { store -> store.timelineBars(brandId) }

    /** 指定会場 (venue_id) で公演があったイベントの id 集合 (ライブ一覧の会場絞り込み用)。 */
    suspend fun fetchEventIdsAtVenue(venueId: String): Set<String> =
        snapshots.query { store -> store.eventIdsAtVenue(venueId).toSet() }

    /** オープン編集「セトリ編集」の対象公演を選ぶピッカー用。 */
    suspend fun searchShows(query: String, limit: Int = 30): List<ShowWithEventName> {
        val trimmed = query.trim()
        val records = snapshots.query { store ->
            if (trimmed.isEmpty()) {
                store.allShowsWithEventName(limit.toUInt())
            } else {
                store.searchShowsWithEventName(trimmed, limit.toUInt())
            }
        }
        // コアの射影はピッカー表示に要る列 (venue_city / start_time / sort_order /
        // performer_type) を持たない。選択後は toShow() で公演実体として使われるので、
        // 欠けたまま組み立てず Room から id で引き直す。並びはコアが正。
        val shows = hydrateInOrder(records.map { it.id }, Show::id) { db.showDao().fetchShowsByIds(it) }
            .associateBy { it.id }
        return records.mapNotNull { r -> shows[r.id]?.toShowWithEventName(r.eventName) }
    }

    /**
     * セトリ編集画面が読む「いまローカルに保存されているセトリ」。**Room 経路のまま残す。**
     *
     * [MasterEditRepository.replaceSetlist] はスナップショットを作り直すが、その reload が失敗すると
     * 旧スナップショットが残る。ここが
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
     * 編集直後にここが古い値を返さないのは [MasterEditRepository.replaceSetlist] が reload を撃つため。
     *
     * 曲ごとのグループ化と並びはコアが担う。Room の SQL には ORDER BY が無く並びが未規定
     * だったので、iOS と同じ「アイドルの sort_order 順」に揃う。
     *
     * 表示名 (`PerformerRow.name`) はコアでは現任 CV 名で、不在ならアイドル名に落ちる
     * (声優の履歴 idol_voice_actors は seed で入る)。
     */
    suspend fun fetchPerformersByItem(showId: String): Map<String, List<PerformerRow>> =
        snapshots.query { store ->
            store.showSetlistPerformers(showId).mapValues { (_, rows) -> rows.map { it.toPerformerRow() } }
        }

    /**
     * セトリ 1 行ぶんの添え物 (名義・ユニットの札・全員・何回目・いつぶり・自分の回収) と、
     * 公演の頭に出す回収の要約。並びは [fetchPerformersByItem] の元と同じセトリ順で、
     * 行のキーは setlist_items.id。
     *
     * **名義の決め方 (その披露の名義 → 曲の名義 → 個人名併記 → 顔ぶれ推論 → 名前) も、
     * 「N 年ぶり」の言い回しも、「初回収 / 回収 N 回目 / 未回収」の判断もコアが持つ。**
     * 画面で組み立てないこと — iOS にだけ規則を書いていた時代に、同じ規則が両 OS で
     * 食い違った (imas-core/src/domain/performer_label.rs)。
     *
     * 参加マーク (user_marks) の解決は [CollectionAttendance] へ寄せてある
     * (どのマークを回収に数えるかの規則はコア一本)。`includeStreamInCollection` は
     * 設定「配信参加も回収に含める」の現在値で、変わったら呼び直すこと。
     */
    suspend fun fetchSetlistRowMeta(
        showId: String,
        mode: PerformerNameMode,
        displayMode: SetlistDisplayMode,
        includeStreamInCollection: Boolean
    ): SetlistRowMetaResult {
        val attendedShowIds = CollectionAttendance.showIds(db, includeStreamInCollection)
        val attendedEventIds = CollectionAttendance.eventIds(db, includeStreamInCollection)
        val bundle = snapshots.query { store ->
            store.showSetlistRowMeta(showId, mode, displayMode, attendedShowIds, attendedEventIds)
        }
        return SetlistRowMetaResult(
            rowsByItemId = bundle.rows.associateBy { it.itemId },
            collection = bundle.collection
        )
    }

    /**
     * そのイベントで着られた衣装 (共通・個別に分けて進行順)。記録が無ければ両方空。
     *
     * 衣装の畳み方 (同じ衣装が複数曲・複数公演に出たら 1 件にまとめる)・共通と個別の
     * 分け方・「どの公演で着たか」の 1 行は共有コア (`costume_queries`) が持つ。
     * 画面側で組み直すと iOS と表記が割れるので、受け取ったものをそのまま出すこと。
     */
    suspend fun fetchEventCostumes(eventId: String): EventCostumesRecord =
        snapshots.query { store -> store.eventCostumeRecords(eventId) }

    /** 衣装 1 着の見出し。未知 id は null。 */
    suspend fun fetchCostume(costumeId: String): CostumeRecord? =
        snapshots.query { store -> store.costumeRecord(costumeId) }

    /** その衣装が着られた公演 (イベントごとに束ね、イベントは新しい順)。 */
    suspend fun fetchCostumeEvents(costumeId: String): List<CostumeEventRecord> =
        snapshots.query { store -> store.costumeEventRecords(costumeId) }

    /**
     * そのイベントのチケット受付一覧。段階・並び・期間文字列・当落文字列はすべてコアが
     * 決め切って渡すので、ここでは組み立てない (画面はそのまま出す)。
     */
    suspend fun fetchTicketSales(eventId: String): List<TicketSale> =
        snapshots.query { store -> store.ticketSalesForEvent(eventId, Instant.now().epochSecond) }

    /** 一番近い注目受付 1 件 (無ければ null)。イベント詳細のヒーロー相当に使う。 */
    /** チケット受付を帯の時間軸 (ガント) に並べたもの。受付が無ければ null (位置の計算はコア)。 */
    suspend fun fetchTicketSaleTimeline(eventId: String): TicketSaleTimeline? =
        snapshots.query { store -> store.ticketSaleTimeline(eventId, Instant.now().epochSecond) }

    suspend fun fetchTicketSaleSpotlight(eventId: String): TicketSale? =
        snapshots.query { store -> store.ticketSaleSpotlight(eventId, Instant.now().epochSecond) }
}

// ---- コアの射影 → Room エンティティ (列は 1:1) ----

private fun EventListRecord.toEvent(): Event = Event(
    id = id, brandId = brandId, name = name, eventType = eventType, isStreaming = isStreaming,
    isSolo = isSolo, kind = kind, ticketUrl = ticketUrl, jointBrandIds = jointBrandIds
)

/**
 * 日付つきイベント射影 → [EventWithDateRange]。
 * `lastDate` は年フィルタ経路では常に null (コアが SQL 時代の挙動をそのまま写している)。
 */
private fun EventWithDateRecord.toEventWithDateRange(): EventWithDateRange = EventWithDateRange(
    event = event.toEvent(),
    firstDate = firstDate,
    lastDate = lastDate,
    isJoint = event.isJoint
)

private fun EventDetailRecord.toEvent(): Event = Event(
    id = id, brandId = brandId, name = name, eventType = eventType, isStreaming = isStreaming,
    isSolo = isSolo, kind = kind, ticketUrl = ticketUrl, jointBrandIds = jointBrandIds
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

private fun Show.toShowWithEventName(eventName: String): ShowWithEventName = ShowWithEventName(
    id = id, eventId = eventId, name = name, date = date, venue = venue, venueCity = venueCity,
    startTime = startTime, sortOrder = sortOrder, performerType = performerType, eventName = eventName
)
