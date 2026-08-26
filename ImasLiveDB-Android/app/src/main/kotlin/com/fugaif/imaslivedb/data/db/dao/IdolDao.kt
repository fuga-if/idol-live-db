package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.CastShowCount
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolPerformedSong
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

    /**
     * 一覧・検索・統計用。外部ゲスト演者 (is_external) を除外する。
     * iOS `fetchIdols(brandId:)` と同一条件。setlist/poll 等の picker 系は
     * fetchIdols() (無条件) を使うこと (ゲストも選択肢に含める必要があるため)。
     */
    @Query("SELECT * FROM idols WHERE is_external = 0 ORDER BY sort_order")
    suspend fun fetchIdolsForList(): List<Idol>

    @Query("""
        SELECT DISTINCT i.* FROM idols i
        JOIN idol_brands ib ON i.id = ib.idol_id
        WHERE ib.brand_id = :brandId AND i.is_external = 0
        ORDER BY i.sort_order
    """)
    suspend fun fetchIdolsForListByBrand(brandId: String): List<Idol>

    @Query("SELECT * FROM idols WHERE id = :id LIMIT 1")
    suspend fun fetchIdol(id: String): Idol?

    /** タグが似ているアイドルの解決用。N+1を避けてIN句で一括取得する (SongDao.fetchSongsByIds と同型)。 */
    @Query("SELECT * FROM idols WHERE id IN (:ids)")
    suspend fun fetchIdolsByIds(ids: List<String>): List<Idol>

    /**
     * 誕生月フィルタのフォールバック経路 (コア `idols_by_birth_month` と同一条件)。
     *
     * birthday は年なしの '--MM-DD' 形式なので、'--MM-%' の前方一致で月が取れる。
     * パターンは呼び出し側 (IdolRepository) が組む — 月の 0 埋めをここでやると
     * SQL 側の文字列連結になり、コアと条件が一致しているか読んで確かめられなくなる。
     * 一覧系と違い is_external を絞らないのは、SQL 時代の条件をコアがそのまま写しているため。
     */
    @Query("SELECT * FROM idols WHERE birthday LIKE :birthdayPrefix ORDER BY sort_order")
    suspend fun fetchIdolsByBirthdayPrefix(birthdayPrefix: String): List<Idol>

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

    /**
     * このアイドルが出演した公演一覧。show_cast の直接出演に加え、setlist_performers 経由
     * (セットリストの歌唱者としてのみ記録されている公演) も含む (iOS fetchIdolShows と同一条件)。
     */
    @Query("""
        SELECT sh.id AS show_id, e.id AS event_id,
               e.name AS event_name, sh.name AS show_name, sh.date, sh.venue,
               COALESCE(
                   (SELECT cast_role FROM show_cast WHERE show_id = sh.id AND idol_id = :idolId),
                   'member'
               ) AS cast_role
        FROM shows sh
        JOIN events e ON sh.event_id = e.id
        WHERE sh.id IN (
            SELECT DISTINCT si.show_id
            FROM setlist_performers sp
            JOIN setlist_items si ON si.id = sp.setlist_item_id
            WHERE sp.idol_id = :idolId
            UNION
            SELECT show_id FROM show_cast WHERE idol_id = :idolId
        )
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

    /** ライブ歌唱曲 (setlist_performers 経由の実演記録) + 披露回数。iOS fetchIdolPerformedSongs と同一。 */
    @Query("""
        SELECT s.*, COUNT(DISTINCT si.id) AS perform_count
        FROM songs s
        JOIN setlist_items si ON s.id = si.song_id
        JOIN setlist_performers sp ON si.id = sp.setlist_item_id
        WHERE sp.idol_id = :idolId
        GROUP BY s.id
        ORDER BY perform_count DESC, s.title_kana
    """)
    suspend fun fetchIdolPerformedSongs(idolId: String): List<IdolPerformedSong>

    /** このアイドルの所属ユニットのうち、楽曲が1曲以上紐づいているユニットの id 集合。 */
    @Query("""
        SELECT DISTINCT u.id
        FROM units u
        JOIN unit_members um ON u.id = um.unit_id
        JOIN songs s ON s.unit_id = u.id
        WHERE um.idol_id = :idolId
    """)
    suspend fun fetchIdolUnitIdsWithSongs(idolId: String): List<String>
}
