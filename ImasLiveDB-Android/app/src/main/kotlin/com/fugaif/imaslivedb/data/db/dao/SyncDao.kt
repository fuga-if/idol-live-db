package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolBrand
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.SetlistItem
import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowCast
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongArtist
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.data.model.UnitMember

/**
 * CloudKit 差分同期の書き込み口。upsert は REPLACE で冪等。
 * 削除伝搬は単一PK (recordName=id) のテーブルのみ対応。junction テーブルの
 * tombstone は recordName 分解が曖昧なため v1 では非対応 (親レコード再同期で概ね収束)。
 */
@Dao
interface SyncDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertBrands(rows: List<Brand>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertIdols(rows: List<Idol>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertEvents(rows: List<Event>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertShows(rows: List<Show>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertSongs(rows: List<Song>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertUnits(rows: List<ImasUnit>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertIdolBrands(rows: List<IdolBrand>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertUnitMembers(rows: List<UnitMember>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertSongArtists(rows: List<SongArtist>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertShowCasts(rows: List<ShowCast>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertSetlistItems(rows: List<SetlistItem>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertSetlistPerformers(rows: List<SetlistPerformer>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertSongCalls(rows: List<SongCall>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertSongVideos(rows: List<SongVideo>)

    @Query("DELETE FROM brands WHERE id IN (:ids)") suspend fun deleteBrands(ids: List<String>)
    @Query("DELETE FROM idols WHERE id IN (:ids)") suspend fun deleteIdols(ids: List<String>)
    @Query("DELETE FROM events WHERE id IN (:ids)") suspend fun deleteEvents(ids: List<String>)
    @Query("DELETE FROM shows WHERE id IN (:ids)") suspend fun deleteShows(ids: List<String>)
    @Query("DELETE FROM songs WHERE id IN (:ids)") suspend fun deleteSongs(ids: List<String>)
    @Query("DELETE FROM units WHERE id IN (:ids)") suspend fun deleteUnits(ids: List<String>)
    @Query("DELETE FROM setlist_items WHERE id IN (:ids)") suspend fun deleteSetlistItems(ids: List<String>)
    @Query("DELETE FROM song_calls WHERE id IN (:ids)") suspend fun deleteSongCalls(ids: List<String>)
    @Query("DELETE FROM song_videos WHERE id IN (:ids)") suspend fun deleteSongVideos(ids: List<String>)

    @Query("SELECT COUNT(*) FROM brands") suspend fun brandCount(): Int
}
