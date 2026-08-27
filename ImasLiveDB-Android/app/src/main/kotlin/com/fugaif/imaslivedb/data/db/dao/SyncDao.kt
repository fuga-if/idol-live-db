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
import com.fugaif.imaslivedb.data.model.Venue
import com.fugaif.imaslivedb.data.model.VenueHall
import com.fugaif.imaslivedb.data.model.Creator
import com.fugaif.imaslivedb.data.model.UnitVersion
import com.fugaif.imaslivedb.data.model.VenueName

/**
 * CloudKit 差分同期の書き込み口。upsert は REPLACE で冪等。
 *
 * 削除伝搬は単一 PK (recordName == id) と複合 PK の junction テーブルの両方に対応する。
 * 複合 PK の recordName `"{table}-{pk1}-{pk2}"` の分解は共有コア
 * (`syncTableInfo` + `syncParseCompositeRecordName`) が担い、ここには分解済みの PK 値だけが
 * 渡る。Room は SQL を文字列で組み立てられないので、テーブルごとに DELETE を 1 本ずつ持つ。
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
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertVenues(rows: List<Venue>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertCreators(rows: List<Creator>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertUnitVersions(rows: List<UnitVersion>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertVenueNames(rows: List<VenueName>)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertVenueHalls(rows: List<VenueHall>)

    @Query("DELETE FROM brands WHERE id IN (:ids)") suspend fun deleteBrands(ids: List<String>)
    @Query("DELETE FROM idols WHERE id IN (:ids)") suspend fun deleteIdols(ids: List<String>)
    @Query("DELETE FROM events WHERE id IN (:ids)") suspend fun deleteEvents(ids: List<String>)
    @Query("DELETE FROM shows WHERE id IN (:ids)") suspend fun deleteShows(ids: List<String>)
    @Query("DELETE FROM songs WHERE id IN (:ids)") suspend fun deleteSongs(ids: List<String>)
    @Query("DELETE FROM units WHERE id IN (:ids)") suspend fun deleteUnits(ids: List<String>)
    @Query("DELETE FROM setlist_items WHERE id IN (:ids)") suspend fun deleteSetlistItems(ids: List<String>)
    @Query("DELETE FROM song_calls WHERE id IN (:ids)") suspend fun deleteSongCalls(ids: List<String>)
    @Query("DELETE FROM song_videos WHERE id IN (:ids)") suspend fun deleteSongVideos(ids: List<String>)
    @Query("DELETE FROM venues WHERE id IN (:ids)") suspend fun deleteVenues(ids: List<String>)
    @Query("DELETE FROM creators WHERE id IN (:ids)") suspend fun deleteCreators(ids: List<String>)
    @Query("DELETE FROM unit_versions WHERE id IN (:ids)") suspend fun deleteUnitVersions(ids: List<String>)
    @Query("DELETE FROM venue_names WHERE id IN (:ids)") suspend fun deleteVenueNames(ids: List<String>)
    @Query("DELETE FROM venue_halls WHERE id IN (:ids)") suspend fun deleteVenueHalls(ids: List<String>)

    // 複合 PK の tombstone。列の並びはコアの syncTableInfo(pkColumns) と同順にしてある
    // (呼び出し側は分解結果を先頭から順に渡すだけでよい)。
    @Query("DELETE FROM idol_brands WHERE idol_id = :idolId AND brand_id = :brandId")
    suspend fun deleteIdolBrand(idolId: String, brandId: String)

    @Query("DELETE FROM unit_members WHERE unit_id = :unitId AND idol_id = :idolId")
    suspend fun deleteUnitMember(unitId: String, idolId: String)

    @Query("DELETE FROM song_artists WHERE song_id = :songId AND idol_id = :idolId AND role = :role")
    suspend fun deleteSongArtist(songId: String, idolId: String, role: String)

    @Query("DELETE FROM show_cast WHERE show_id = :showId AND idol_id = :idolId")
    suspend fun deleteShowCast(showId: String, idolId: String)

    @Query("DELETE FROM setlist_performers WHERE setlist_item_id = :setlistItemId AND idol_id = :idolId")
    suspend fun deleteSetlistPerformer(setlistItemId: String, idolId: String)

    @Query("SELECT COUNT(*) FROM brands") suspend fun brandCount(): Int

    // v8→v9 移行 (MIGRATION_8_9) の取りこぼし検出用。移行は shows.venue_id を NULL のまま
    // 追加するので、増分同期しか走らない端末では会場 ID が永久に埋まらない。
    // 「公演はあるのに venue_id を持つ行が 1 件も無い」= その状態。
    @Query("SELECT COUNT(*) FROM shows") suspend fun showCount(): Int
    @Query("SELECT COUNT(*) FROM shows WHERE venue_id IS NOT NULL") suspend fun showsWithVenueIdCount(): Int

    // 単一PK (id) テーブルのローカル全ID。フル同期完走後の孤児掃除 (CloudKit側でtombstone無しに
    // 物理削除されたレコードの検出) に使う。iOS AppDatabase.deleteOrphans の Android 版。
    @Query("SELECT id FROM brands") suspend fun brandIds(): List<String>
    @Query("SELECT id FROM idols") suspend fun idolIds(): List<String>
    @Query("SELECT id FROM events") suspend fun eventIds(): List<String>
    @Query("SELECT id FROM shows") suspend fun showIds(): List<String>
    @Query("SELECT id FROM songs") suspend fun songIds(): List<String>
    @Query("SELECT id FROM units") suspend fun unitIds(): List<String>
    @Query("SELECT id FROM setlist_items") suspend fun setlistItemIds(): List<String>
    @Query("SELECT id FROM song_calls") suspend fun songCallIds(): List<String>
    @Query("SELECT id FROM song_videos") suspend fun songVideoIds(): List<String>
    @Query("SELECT id FROM venues") suspend fun venueIds(): List<String>
    @Query("SELECT id FROM creators") suspend fun creatorIds(): List<String>
    @Query("SELECT id FROM unit_versions") suspend fun unitVersionIds(): List<String>
    @Query("SELECT id FROM venue_names") suspend fun venueNameIds(): List<String>
    @Query("SELECT id FROM venue_halls") suspend fun venueHallIds(): List<String>
}
