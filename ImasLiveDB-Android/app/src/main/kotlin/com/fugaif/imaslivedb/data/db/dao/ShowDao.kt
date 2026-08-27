package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowWithEventName
import com.fugaif.imaslivedb.data.model.Venue
import com.fugaif.imaslivedb.data.model.VenueHall
import com.fugaif.imaslivedb.data.model.VenueName

@Dao
interface ShowDao {

    @Query("SELECT * FROM shows WHERE event_id = :eventId ORDER BY sort_order")
    suspend fun fetchShows(eventId: String): List<Show>

    @Query("SELECT * FROM shows WHERE id = :id LIMIT 1")
    suspend fun fetchShow(id: String): Show?

    /**
     * 公演実体の一括取得。スナップショット経路が返す「表示順の show_id 列」を
     * Room の [Show] へ引き直す (hydration) ために使う。並びは呼び出し側が id 列で戻す。
     */
    @Query("SELECT * FROM shows WHERE id IN (:ids)")
    suspend fun fetchShowsByIds(ids: List<String>): List<Show>

    @Query("SELECT * FROM shows ORDER BY date DESC LIMIT 1")
    suspend fun fetchLatestShow(): Show?

    @Query("SELECT COUNT(*) FROM shows")
    suspend fun fetchShowCount(): Int

    /** オープン編集「セトリ編集」の公演ピッカー: 最近の公演 (検索語なし)。 */
    @Query("""
        SELECT sh.*, ev.name AS event_name
        FROM shows sh JOIN events ev ON sh.event_id = ev.id
        ORDER BY sh.date DESC, sh.sort_order DESC
        LIMIT :limit
    """)
    suspend fun fetchRecentShowsWithEventName(limit: Int): List<ShowWithEventName>

    /** 公演名 or 所属イベント名で検索 (オープン編集の公演ピッカー用)。 */
    @Query("""
        SELECT sh.*, ev.name AS event_name
        FROM shows sh JOIN events ev ON sh.event_id = ev.id
        WHERE sh.name LIKE :pattern OR ev.name LIKE :pattern
        ORDER BY sh.date DESC, sh.sort_order DESC
        LIMIT :limit
    """)
    suspend fun searchShowsWithEventName(pattern: String, limit: Int): List<ShowWithEventName>

    /** 会場マスタ (施設)。表示順は公演数順に振ってある。 */
    @Query("SELECT * FROM venues ORDER BY sort_order")
    suspend fun fetchVenues(): List<Venue>

    /** 改名履歴。当時名の解決に使う。 */
    @Query("SELECT * FROM venue_names")
    suspend fun fetchVenueNameRecords(): List<VenueName>

    /** ホール/構成。キャパは構成で変わるので施設と分けて持つ。 */
    @Query("SELECT * FROM venue_halls")
    suspend fun fetchVenueHalls(): List<VenueHall>

    /**
     * 指定会場 (venue_id) で公演があったイベントの id 一覧。
     * 会場は show 単位・絞り込み対象は event 単位なので逆引きが要る
     * (1 イベントが複数会場をまたぐツアーもある)。
     */
    @Query("SELECT DISTINCT event_id FROM shows WHERE venue_id = :venueId")
    suspend fun fetchEventIdsAtVenue(venueId: String): List<String>

    /**
     * 会場での公演一覧 (新しい順)。コア `showsAtVenue` のフォールバック。
     *
     * 会場を ID 管理にする前は生の会場文字列 (`shows.venue`) で突き合わせていた。表記ゆれで
     * 同じ会場が分断されるため venue_id を正とするが、ID が付いていない公演 (会場を特定
     * できなかったもの) は生文字列でしか辿れないので「ID 一致 または 生文字列一致」の OR
     * にしておく (iOS showsByVenueQuery と同一条件)。
     */
    @Query("SELECT * FROM shows WHERE venue_id = :venue OR venue = :venue ORDER BY date DESC")
    suspend fun fetchShowsAtVenue(venue: String): List<Show>

    /** 指定日 (YYYY-MM-DD) の公演一覧。コア `showsOnDate` のフォールバック。 */
    @Query("SELECT * FROM shows WHERE date = :date ORDER BY sort_order")
    suspend fun fetchShowsOnDate(date: String): List<Show>
}
