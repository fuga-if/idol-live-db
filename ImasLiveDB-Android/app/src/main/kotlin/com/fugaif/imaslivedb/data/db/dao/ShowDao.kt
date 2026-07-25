package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowWithEventName

@Dao
interface ShowDao {

    @Query("SELECT * FROM shows WHERE event_id = :eventId ORDER BY sort_order")
    suspend fun fetchShows(eventId: String): List<Show>

    @Query("SELECT * FROM shows WHERE id = :id LIMIT 1")
    suspend fun fetchShow(id: String): Show?

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

    /**
     * 会場名の一覧 (ピッカー用)。空文字・NULL は除く。
     * 会場は "千葉・幕張メッセ国際展示場" のように「都道府県・会場名」形式なので、
     * 名前順で並べると地域ごとにまとまる。
     */
    @Query("""
        SELECT DISTINCT venue FROM shows
        WHERE venue IS NOT NULL AND venue <> ''
        ORDER BY venue
    """)
    suspend fun fetchVenueNames(): List<String>

    /**
     * 指定会場で公演があったイベントの id 一覧。
     * 会場は show 単位・絞り込み対象は event 単位なので逆引きが要る
     * (1 イベントが複数会場をまたぐツアーもある)。
     */
    @Query("SELECT DISTINCT event_id FROM shows WHERE venue = :venue")
    suspend fun fetchEventIdsAtVenue(venue: String): List<String>
}
