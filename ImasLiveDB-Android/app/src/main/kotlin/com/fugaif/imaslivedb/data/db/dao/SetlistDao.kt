package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.AllPerformerRow
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.model.SetlistRow

@Dao
interface SetlistDao {

    @Query("""
        SELECT si.id, si.position, si.section, si.notes, si.unit_name,
               s.id AS song_id, s.title AS song_title, s.apple_music_id,
               s.artwork_url, s.preview_url, s.brand_id AS song_brand_id
        FROM setlist_items si
        JOIN songs s ON si.song_id = s.id
        WHERE si.show_id = :showId
        ORDER BY si.position
    """)
    suspend fun fetchSetlist(showId: String): List<SetlistRow>

    @Query("""
        SELECT i.id AS id, i.name AS name, i.color AS idol_color, i.name AS idol_name, i.id AS idol_id
        FROM setlist_performers sp
        JOIN idols i ON sp.idol_id = i.id
        WHERE sp.setlist_item_id = :setlistItemId
    """)
    suspend fun fetchPerformers(setlistItemId: String): List<PerformerRow>

    @Query("""
        SELECT sp.setlist_item_id AS setlist_item_id,
               i.id AS cast_id, i.name AS name, i.color AS idol_color, i.name AS idol_name, i.id AS idol_id
        FROM setlist_items si
        JOIN setlist_performers sp ON si.id = sp.setlist_item_id
        JOIN idols i ON sp.idol_id = i.id
        WHERE si.show_id = :showId
    """)
    suspend fun fetchAllPerformers(showId: String): List<AllPerformerRow>
}
