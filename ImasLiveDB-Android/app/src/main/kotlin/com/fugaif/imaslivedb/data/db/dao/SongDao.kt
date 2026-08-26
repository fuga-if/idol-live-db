package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.RawQuery
import androidx.sqlite.db.SupportSQLiteQuery
import com.fugaif.imaslivedb.data.model.CoOccurrenceRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.PerformanceHistoryRow
import com.fugaif.imaslivedb.data.model.SingerTallyRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SoloOriginalSingerRow
import com.fugaif.imaslivedb.data.model.SongPerfCount
import com.fugaif.imaslivedb.data.model.SongPlayCount

@Dao
interface SongDao {

    @Query("SELECT * FROM songs WHERE id = :id LIMIT 1")
    suspend fun fetchSong(id: String): Song?

    @Query("SELECT * FROM songs WHERE id IN (:ids)")
    suspend fun fetchSongsByIds(ids: List<String>): List<Song>

    /**
     * スナップショット (共有コア) が返した idol id 列を Idol 実体へ引き直すための一括取得。
     * 並びはコアが返した id 列が正なので、呼び出し側 (SongRepository) で並べ直す。
     */
    @Query("SELECT * FROM idols WHERE id IN (:ids)")
    suspend fun fetchIdolsByIds(ids: List<String>): List<Idol>

    /**
     * 現地参加 (text_value NULL または 'live') でマークした show の id 集合。
     * user_marks はスナップショットに載せない規約のため、回収バッジ系のスナップショット
     * クエリ (songCollectedCountMap) へ渡す入力をプラットフォーム側で解決する。
     * 曲スライスの都合で使う解決クエリなので UserMarkDao ではなくここに置く。
     */
    @Query("""
        SELECT entity_id FROM user_marks
        WHERE entity_type = 'show' AND kind = 'attended' AND bool_value = 1
          AND (text_value IS NULL OR text_value = 'live')
    """)
    suspend fun fetchAttendedLiveShowIds(): List<String>

    @RawQuery
    suspend fun fetchSongsRaw(query: SupportSQLiteQuery): List<Song>

    @Query("""
        SELECT i.* FROM idols i
        JOIN song_artists sa ON i.id = sa.idol_id
        WHERE sa.song_id = :songId
        ORDER BY i.sort_order
    """)
    suspend fun fetchSongArtists(songId: String): List<Idol>

    @Query("""
        SELECT i.* FROM idols i
        JOIN song_artists sa ON i.id = sa.idol_id
        WHERE sa.song_id = :songId AND sa.role = :role
        ORDER BY i.sort_order
    """)
    suspend fun fetchSongArtistsByRole(songId: String, role: String): List<Idol>

    @Query("""
        SELECT sh.id AS show_id, e.id AS event_id,
               e.name AS event_name, sh.name AS show_name, sh.date, sh.venue,
               si.position, si.section
        FROM setlist_items si
        JOIN shows sh ON si.show_id = sh.id
        JOIN events e ON sh.event_id = e.id
        WHERE si.song_id = :songId
        ORDER BY sh.date DESC
    """)
    suspend fun fetchSongPerformanceHistory(songId: String): List<PerformanceHistoryRow>

    /**
     * 現地回収済み公演一覧 (参加したリアルライブでこの曲が披露された公演)。
     * iOS AppDatabase.fetchCollectedShows と同じ判定 (show/event 単位の attended マーク)。
     */
    @Query(
        """
        SELECT DISTINCT sh.id AS show_id, e.id AS event_id,
               e.name AS event_name, sh.name AS show_name, sh.date, sh.venue,
               si.position, si.section
        FROM setlist_items si
        JOIN shows sh ON si.show_id = sh.id
        JOIN events e ON sh.event_id = e.id
        WHERE si.song_id = :songId
        AND (
            sh.id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'show' AND kind = 'attended' AND bool_value = 1
            )
            OR sh.event_id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'event' AND kind = 'attended' AND bool_value = 1
            )
        )
        ORDER BY sh.date DESC
        """
    )
    suspend fun fetchCollectedShows(songId: String): List<PerformanceHistoryRow>

    @Query("SELECT series_group FROM songs WHERE id = :songId LIMIT 1")
    suspend fun fetchSeriesGroup(songId: String): String?

    @Query("SELECT * FROM songs WHERE series_group = :seriesGroup")
    suspend fun fetchSongsBySeriesGroup(seriesGroup: String): List<Song>

    @Query("""
        SELECT DISTINCT s.* FROM songs s
        JOIN song_artists sa ON s.id = sa.song_id
        WHERE sa.role = 'original' AND sa.idol_id IN (
            SELECT idol_id FROM song_artists WHERE song_id = :songId AND role = 'original'
        )
    """)
    suspend fun fetchSongsSharingOriginalArtist(songId: String): List<Song>

    @Query("""
        SELECT s.id, s.title, COUNT(si.id) AS play_count, s.brand_id
        FROM songs s
        JOIN setlist_items si ON s.id = si.song_id
        GROUP BY s.id
        ORDER BY play_count DESC
        LIMIT :limit
    """)
    suspend fun fetchSongPlayCountRanking(limit: Int = 20): List<SongPlayCount>

    @Query("SELECT song_id, COUNT(*) as cnt FROM setlist_items GROUP BY song_id")
    suspend fun fetchSongPerfCounts(): List<SongPerfCount>

    // MARK: - 披露実績の集計 (共起曲 / 歌唱者) — スナップショットが使えないときの SQL 経路
    //
    // ⚠️ 数え方はコア (imas-core/src/domain/performance_stats.rs) と 1:1 に揃えること。
    // 経路によって根拠の数字が変わると、どちらが本当なのかを読み手が判断できなくなる。
    // 揃えている点:
    //  1. 共起は「公演数」(COUNT(DISTINCT show_id))。1 公演で 2 回演奏されても 1。
    //  2. 歌唱者は「セトリ行数」(COUNT(*))。同じ公演での 2 回目も別の 1 回。
    //  3. shows / songs / idols への JOIN は FK 孤児落とし。コアのローダも参照先が
    //     無い行を読み飛ばすので、外すと孤児が残った DB でだけ数字がズレる。
    //  4. 並びは「回数降順 → id 昇順」。SQLite の TEXT 既定照合 BINARY は Rust の
    //     str 比較と同じバイト順なので、同数のときの順序も一致する。

    /** この曲と同じ公演で歌われた曲を、一緒に来た**公演数**の多い順に。 */
    @Query("""
        WITH item AS (
            SELECT si.id AS item_id, si.show_id AS show_id, si.song_id AS song_id
              FROM setlist_items si
              JOIN shows sh ON sh.id = si.show_id
              JOIN songs so ON so.id = si.song_id
        ),
        target AS (SELECT DISTINCT show_id FROM item WHERE song_id = :songId)
        SELECT i.song_id AS song_id, COUNT(DISTINCT i.show_id) AS together
          FROM item i
          JOIN target t ON t.show_id = i.show_id
         WHERE i.song_id <> :songId
         GROUP BY i.song_id
         ORDER BY together DESC, i.song_id ASC
         LIMIT :limit
    """)
    suspend fun fetchCoOccurringSongs(songId: String, limit: Int): List<CoOccurrenceRow>

    /**
     * 共起行の分母 — 指定曲それぞれの総披露公演数。
     * 共起クエリの相関サブクエリにすると 13,777 行をグループごとに舐め直すことになるので、
     * 上位数件が決まってから 1 回だけ引く。
     */
    @Query("""
        WITH item AS (
            SELECT si.id AS item_id, si.show_id AS show_id, si.song_id AS song_id
              FROM setlist_items si
              JOIN shows sh ON sh.id = si.show_id
              JOIN songs so ON so.id = si.song_id
        )
        SELECT song_id, COUNT(DISTINCT show_id) AS cnt
          FROM item
         WHERE song_id IN (:songIds)
         GROUP BY song_id
    """)
    suspend fun fetchSongShowCounts(songIds: List<String>): List<SongPerfCount>

    /**
     * この曲を歌ったアイドルを、歌った**セトリ行数**の多い順に。
     * 分母 total は歌唱者が誰であれ同じ値で、出演者が 1 人も紐づいていない披露も数える。
     */
    @Query("""
        WITH item AS (
            SELECT si.id AS item_id, si.show_id AS show_id, si.song_id AS song_id
              FROM setlist_items si
              JOIN shows sh ON sh.id = si.show_id
              JOIN songs so ON so.id = si.song_id
        )
        SELECT sp.idol_id AS idol_id, COUNT(*) AS times,
               (SELECT COUNT(*) FROM item x WHERE x.song_id = :songId) AS total
          FROM item i
          JOIN setlist_performers sp ON sp.setlist_item_id = i.item_id
          JOIN idols idl ON idl.id = sp.idol_id
         WHERE i.song_id = :songId
         GROUP BY sp.idol_id
         ORDER BY times DESC, sp.idol_id ASC
         LIMIT :limit
    """)
    suspend fun fetchSongSingerTallies(songId: String, limit: Int): List<SingerTallyRow>

    /**
     * song_id → 現地回収回数 (参加したリアルライブ(live/festival)で披露された distinct 公演数)。
     * iOS AppDatabase.fetchSongCollectedCounts と同一クエリ。参加種別は既定(現地のみ)固定
     * (iOS の配信含む設定トグルは Android 未移植)。
     */
    @Query(
        """
        SELECT si.song_id AS song_id, COUNT(DISTINCT si.show_id) AS cnt
        FROM setlist_items si
        JOIN shows sh ON sh.id = si.show_id
        JOIN events e ON e.id = sh.event_id
        WHERE e.kind IN ('live', 'festival')
        AND (
            si.show_id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'show' AND kind = 'attended' AND bool_value = 1
                  AND (text_value IS NULL OR text_value = 'live')
            ) OR si.show_id IN (
                SELECT id FROM shows WHERE event_id IN (
                    SELECT entity_id FROM user_marks
                    WHERE entity_type = 'event' AND kind = 'attended' AND bool_value = 1
                )
            )
        )
        GROUP BY si.song_id
        """
    )
    suspend fun fetchSongCollectedCounts(): List<SongPerfCount>

    /**
     * song_id → 参加公演での披露回数。楽曲一覧の「回収数順 / 回収率順」ソート専用。
     * iOS AppDatabase.attendedSongCountMap と同一クエリ。バッジ用 fetchSongCollectedCounts と
     * 違い、参加種別 (text_value) もイベント kind も**絞らない** — 配信参加マークや
     * リアルライブ以外のイベントの参加分も数える。スナップショット経路は songList へ
     * 全 attended id を渡す (= 無制限) ので、ここを絞るとフォールバック時だけ並び順が
     * 食い違う。バッジの母集合とソートの母集合は別物、が iOS 確定仕様。
     */
    @Query(
        """
        SELECT si.song_id AS song_id, COUNT(DISTINCT si.show_id) AS cnt
        FROM setlist_items si
        WHERE si.show_id IN (
            SELECT entity_id FROM user_marks
            WHERE entity_type = 'show' AND kind = 'attended' AND bool_value = 1
        ) OR si.show_id IN (
            SELECT id FROM shows WHERE event_id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'event' AND kind = 'attended' AND bool_value = 1
            )
        )
        GROUP BY si.song_id
        """
    )
    suspend fun fetchAttendedSongCounts(): List<SongPerfCount>

    /**
     * 指定アイドルのいずれかが**歌唱者 (role='original')** の song_id 集合 (担当マーク由来の「担当」表示用)。
     * role を見ないとライブで一度歌っただけの曲まで「担当の曲」になってしまう (iOS 側は元から original 限定)。
     */
    @Query("SELECT DISTINCT song_id FROM song_artists WHERE role = 'original' AND idol_id IN (:idolIds)")
    suspend fun fetchSongIdsWithAnyArtist(idolIds: List<String>): List<String>

    @Query("""
        SELECT DISTINCT cd_series FROM songs
        WHERE cd_series IS NOT NULL AND cd_series != ''
        ORDER BY cd_series
    """)
    suspend fun fetchCdSeriesList(): List<String>

    @Query("SELECT name FROM events ORDER BY name")
    suspend fun fetchEventNames(): List<String>

    @Query("SELECT * FROM songs WHERE unit_id = :unitId ORDER BY release_date")
    suspend fun fetchUnitSongs(unitId: String): List<Song>

    @Query("""
        SELECT s.* FROM songs s
        JOIN song_artists sa ON s.id = sa.song_id
        WHERE sa.idol_id = :idolId
        ORDER BY s.release_date DESC
    """)
    suspend fun fetchIdolSongs(idolId: String): List<Song>

    @Query("""
        SELECT s.* FROM songs s
        JOIN song_artists sa ON s.id = sa.song_id
        WHERE sa.idol_id = :idolId AND sa.role = :role
        ORDER BY s.release_date DESC
    """)
    suspend fun fetchIdolSongsByRole(idolId: String, role: String): List<Song>

    @Query("""
        SELECT * FROM songs
        WHERE (title LIKE :pattern OR title_kana LIKE :pattern)
        LIMIT 20
    """)
    suspend fun searchSongs(pattern: String): List<Song>

    /** ソロ曲クイズ用: ソロ曲 (リミックス除く) と原唱アイドルの対応。song_id 単位で複数行になり得る (原唱が複数人の曲)。 */
    @Query("""
        SELECT s.id AS song_id, sa.idol_id AS idol_id
        FROM songs s
        JOIN song_artists sa ON s.id = sa.song_id
        WHERE s.song_type = 'solo' AND s.parent_song_id IS NULL AND sa.role = 'original'
    """)
    suspend fun fetchSoloOriginalSingers(): List<SoloOriginalSingerRow>
}
