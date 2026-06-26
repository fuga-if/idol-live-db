package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.CalBirthdayRow
import com.fugaif.imaslivedb.data.model.CalReleaseRow
import com.fugaif.imaslivedb.data.model.CalShowRow

@Dao
interface CalendarDao {

    /** ym = "YYYY-MM"。その月の公演をイベント名付きで。 */
    @Query("""
        SELECT sh.id AS show_id, sh.date AS date, sh.name AS show_name,
               sh.event_id AS event_id, e.name AS event_name, e.brand_id AS brand_id
        FROM shows sh
        JOIN events e ON sh.event_id = e.id
        WHERE sh.date LIKE :ym || '%'
        ORDER BY sh.date
    """)
    suspend fun showsInMonth(ym: String): List<CalShowRow>

    /** その月にリリースされた曲 (リミックス等の別バージョンは除外)。 */
    @Query("""
        SELECT id, title, release_date, brand_id
        FROM songs
        WHERE release_date LIKE :ym || '%' AND parent_song_id IS NULL
        ORDER BY release_date
    """)
    suspend fun releasesInMonth(ym: String): List<CalReleaseRow>

    /** mm = "MM"。その月に誕生日のアイドル (birthday は "--MM-DD")。 */
    @Query("""
        SELECT id, name, brand_id, birthday
        FROM idols
        WHERE birthday LIKE '--' || :mm || '-%'
        ORDER BY birthday
    """)
    suspend fun birthdaysInMonth(mm: String): List<CalBirthdayRow>
}
