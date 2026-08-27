package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.CastShowCount
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolPerformedSong
import com.fugaif.imaslivedb.data.model.Song
import uniffi.imas_core.IdolShowRecord

/**
 * アイドルの読み取り口。
 *
 * 読み取りは共有コア (imas-core) のインメモリスナップショットを第一経路とし、
 * 未ロード・利用不可のときだけ従来の Room/SQL 経路へフォールバックする
 * (SongRepository と同じ「呼び出し単位のフォールバック」)。
 *
 * コアの IdolRecord は idols 表の射影で、Room の [Idol] が持つ voice_actors
 * (CV 名のカンマ区切り = `currentVoiceActor` の素) を持たない。そのため一覧系は
 * **コアから表示順の id 列だけ受け取り、実体は Room で引き直す** (hydration)。
 */
class IdolRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null
) {

    suspend fun fetchIdols(brandId: String? = null): List<Idol> {
        if (brandId == null) {
            // 外部ゲストも含む全件 (ピッカー用) はコアに同条件の API がある。
            snapshots?.query { store -> store.allIdolsForPicker().map { it.id } }
                ?.let { return hydrateIdols(it) }
            return db.idolDao().fetchIdols()
        }
        // 「ブランド絞り込み かつ 外部ゲストを含む」に相当するコア API が無い
        // (idolList は is_external を必ず落とす)。母集団が変わるので SQL 経路のまま。
        return db.idolDao().fetchIdolsByBrand(brandId)
    }

    /** 一覧画面用。外部ゲスト演者 (is_external) を除外する (iOS `idols(brandId:)` と同一条件)。 */
    suspend fun fetchIdolsForList(brandId: String? = null): List<Idol> {
        // コアの idolList は brand 指定時に idol_brands JOIN + is_external 除外 + sort_order 順で、
        // Room の fetchIdolsForList(ByBrand) と同一条件。
        snapshots?.query { store -> store.idolList(brandId).map { it.id } }
            ?.let { return hydrateIdols(it) }
        return if (brandId != null) {
            db.idolDao().fetchIdolsForListByBrand(brandId)
        } else {
            db.idolDao().fetchIdolsForList()
        }
    }

    /**
     * 誕生月 (1..12) で絞ったアイドル。プロフィールの誕生日行から開く一覧の母集団。
     *
     * 母集団と並びはコアの `idolsByBirthMonth` が正 (元 SQL: `birthday LIKE '--MM-%'
     * ORDER BY sort_order`)。一覧系と違い is_external を落とさないのもコアに合わせる。
     * 範囲外の月は前方一致がどのみち空になるので、コア/SQL どちらの経路でも 0 件で揃う。
     */
    suspend fun fetchIdolsByBirthMonth(month: Int): List<Idol> {
        snapshots?.query { store -> store.idolsByBirthMonth(month.toUInt()).map { it.id } }
            ?.let { return hydrateIdols(it) }
        // 0 埋めは padStart で作る (String.format はロケールによって数字が ASCII でなくなる)。
        return db.idolDao().fetchIdolsByBirthdayPrefix("--${month.toString().padStart(2, '0')}-%")
    }

    // ---- 絞り込み一覧 (FilteredIdols) の母集団 ----
    //
    // 母集団と並びはコア (idolsByConstellation / idolsByBirthPlace / idolsByBloodType) が正。
    // [fetchIdolsByBirthMonth] と同じく is_external を落とさない (プロフィールの属性から辿る
    // 一覧なので、一覧画面の母集団ではなく「同じ属性の人を全員」が期待値)。
    // ブランド絞り込みだけは一覧画面と同じ母集団が正しいので [fetchIdolsForList] を使う。

    /** 星座で絞ったアイドル。 */
    suspend fun fetchIdolsByConstellation(constellation: String): List<Idol> {
        snapshots?.query { store -> store.idolsByConstellation(constellation).map { it.id } }
            ?.let { return hydrateIdols(it) }
        return db.idolDao().fetchIdolsByConstellation(constellation)
    }

    /** 出身地で絞ったアイドル。 */
    suspend fun fetchIdolsByBirthPlace(birthPlace: String): List<Idol> {
        snapshots?.query { store -> store.idolsByBirthPlace(birthPlace).map { it.id } }
            ?.let { return hydrateIdols(it) }
        return db.idolDao().fetchIdolsByBirthPlace(birthPlace)
    }

    /** 血液型で絞ったアイドル。 */
    suspend fun fetchIdolsByBloodType(bloodType: String): List<Idol> {
        snapshots?.query { store -> store.idolsByBloodType(bloodType).map { it.id } }
            ?.let { return hydrateIdols(it) }
        return db.idolDao().fetchIdolsByBloodType(bloodType)
    }

    // アイドル実体の単発/一括取得はスナップショットの hydration 先そのものなので Room 直のまま。
    suspend fun fetchIdol(id: String): Idol? {
        return db.idolDao().fetchIdol(id)
    }

    /** タグが似ているアイドルランキング表示用。N+1を避けてIN句で一括取得する。 */
    suspend fun fetchIdolsByIds(ids: List<String>): List<Idol> {
        if (ids.isEmpty()) return emptyList()
        return db.idolDao().fetchIdolsByIds(ids)
    }

    /** このアイドルが出演した公演一覧 (show_cast 経由)。 */
    suspend fun fetchIdolShows(idolId: String): List<CastShowRow> {
        snapshots?.query { store -> store.idolShows(idolId).map { it.toRow() } }
            ?.let { return it }
        return db.idolDao().fetchIdolShows(idolId)
    }

    /**
     * このアイドルが「その曲」を披露した公演だけ (新しい順)。
     *
     * [fetchIdolShows] (出演した全公演) の部分集合ではない — あちらは show_cast も母集団に
     * 入れるが、こちらは歌唱記録 (setlist_performers) がある公演に限る。
     */
    suspend fun fetchIdolSongHistory(idolId: String, songId: String): List<CastShowRow> {
        snapshots?.query { store ->
            store.idolSongHistoryRecords(idolId, songId).map {
                CastShowRow(
                    showId = it.showId, eventId = it.eventId, eventName = it.eventName,
                    showName = it.showName, date = it.date, venue = it.venue, castRole = it.castRole
                )
            }
        }?.let { return it }
        return db.idolDao().fetchIdolSongHistory(idolId, songId)
    }

    /** 出演公演数ランキング (idol 単位)。 */
    suspend fun fetchIdolShowCountRanking(limit: Int = 20): List<CastShowCount> {
        snapshots?.query { store ->
            store.castShowCountRanking(limit.toUInt())
                .map { CastShowCount(id = it.id, name = it.name, showCount = it.showCount.toInt()) }
        }?.let { return it }
        return db.idolDao().fetchIdolShowCountRanking(limit)
    }

    /** ライブ歌唱曲 (実演記録) + 披露回数。 */
    suspend fun fetchIdolPerformedSongs(idolId: String): List<IdolPerformedSong> {
        // コアは曲の一覧射影 (タイトル/ジャケ等) しか返さないが、この口の戻り値は Song 実体を
        // 埋め込むので、id と披露回数だけ使って Room で引き直す。並びはコアが正。
        snapshots?.query { store ->
            store.idolPerformedSongRecords(idolId).map { it.songId to it.performCount.toInt() }
        }?.let { pairs ->
            val songs = hydrateInOrder(pairs.map { it.first }, Song::id) { db.songDao().fetchSongsByIds(it) }
                .associateBy { it.id }
            return pairs.mapNotNull { (songId, count) ->
                songs[songId]?.let { IdolPerformedSong(song = it, performCount = count) }
            }
        }
        return db.idolDao().fetchIdolPerformedSongs(idolId)
    }

    suspend fun fetchBrand(brandId: String): Brand? {
        // ブランドは全件でも十数件なので、専用 API (brandRecords) の全件から引く方が
        // 呼び出しを増やさずに済む。未知 id のときは null が返り、SQL 経路が引き直すが
        // 結果は同じ null なので観測差は無い。
        snapshots?.query { store -> store.brandRecords().firstOrNull { it.id == brandId }?.toBrand() }
            ?.let { return it }
        return db.brandDao().fetchBrand(brandId)
    }

    // ---- スナップショット経路のヘルパ ----

    private suspend fun hydrateIdols(ids: List<String>): List<Idol> =
        hydrateInOrder(ids, Idol::id) { db.idolDao().fetchIdolsByIds(it) }

    private fun IdolShowRecord.toRow(): CastShowRow = CastShowRow(
        showId = showId,
        eventId = eventId,
        eventName = eventName,
        showName = showName,
        date = date,
        venue = venue,
        castRole = castRole
    )
}
