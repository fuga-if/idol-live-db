package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song

/**
 * 横断検索。
 *
 * 「すべて」スコープ用の浅い検索 (各20件) と、スコープ指定時の深い検索 (limit 指定) を分ける。
 * スコープを絞って探しているのに20件で頭打ちになると取りこぼすため。
 */
@Dao
interface SearchDao {

    @Query("""
        SELECT * FROM songs
        WHERE title LIKE :pattern OR title_kana LIKE :pattern
        LIMIT :limit
    """)
    suspend fun searchSongs(pattern: String, limit: Int = 20): List<Song>

    // CV 名 (voice_actors) と別名 (aliases) も対象にする。声優名でアイドルを引くのは
    // このアプリでは主要な探し方なので、名前系カラムだけだと取りこぼす。
    @Query("""
        SELECT * FROM idols
        WHERE name LIKE :pattern
           OR name_kana LIKE :pattern
           OR name_romaji LIKE :pattern
           OR voice_actors LIKE :pattern
           OR aliases LIKE :pattern
        ORDER BY sort_order
        LIMIT :limit
    """)
    suspend fun searchIdols(pattern: String, limit: Int = 20): List<Idol>

    // 会場 (shows.venue) 一致も含める。ライブは会場名で探されることが多い。
    @Query("""
        SELECT DISTINCT e.* FROM events e
        LEFT JOIN shows sh ON sh.event_id = e.id
        WHERE e.name LIKE :pattern OR IFNULL(sh.venue, '') LIKE :pattern
        LIMIT :limit
    """)
    suspend fun searchEvents(pattern: String, limit: Int = 20): List<Event>
}
