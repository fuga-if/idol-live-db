package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.CastShowCount
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit

@Dao
interface IdolDao {

    @Query("SELECT * FROM idols ORDER BY sort_order")
    suspend fun fetchIdols(): List<Idol>

    @Query("""
        SELECT DISTINCT i.* FROM idols i
        JOIN idol_brands ib ON i.id = ib.idol_id
        WHERE ib.brand_id = :brandId
        ORDER BY i.sort_order
    """)
    suspend fun fetchIdolsByBrand(brandId: String): List<Idol>

    @Query("SELECT * FROM idols WHERE id = :id LIMIT 1")
    suspend fun fetchIdol(id: String): Idol?

    @Query("""
        SELECT u.* FROM units u
        JOIN unit_members um ON u.id = um.unit_id
        WHERE um.idol_id = :idolId
        ORDER BY u.name
    """)
    suspend fun fetchIdolUnits(idolId: String): List<ImasUnit>

    @Query("""
        SELECT i.* FROM idols i
        JOIN unit_members um ON i.id = um.idol_id
        WHERE um.unit_id = :unitId
        ORDER BY i.sort_order
    """)
    suspend fun fetchUnitMembers(unitId: String): List<Idol>

    @Query("""
        SELECT * FROM idols
        WHERE (name LIKE :pattern OR name_kana LIKE :pattern)
        LIMIT 20
    """)
    suspend fun searchIdols(pattern: String): List<Idol>

    @Query("SELECT COUNT(*) FROM idols")
    suspend fun fetchIdolCount(): Int

    @Query("""
        SELECT sh.id AS show_id, e.id AS event_id,
               e.name AS event_name, sh.name AS show_name, sh.date, sh.venue
        FROM show_cast sc
        JOIN shows sh ON sc.show_id = sh.id
        JOIN events e ON sh.event_id = e.id
        WHERE sc.idol_id = :idolId
        ORDER BY sh.date DESC
    """)
    suspend fun fetchIdolShows(idolId: String): List<CastShowRow>

    @Query("""
        SELECT i.id, i.name, COUNT(DISTINCT sc.show_id) AS show_count
        FROM idols i
        JOIN show_cast sc ON i.id = sc.idol_id
        GROUP BY i.id
        ORDER BY show_count DESC
        LIMIT :limit
    """)
    suspend fun fetchIdolShowCountRanking(limit: Int = 20): List<CastShowCount>
}
