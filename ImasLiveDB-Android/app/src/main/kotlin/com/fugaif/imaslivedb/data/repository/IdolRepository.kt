package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.CastShowCount
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolPerformedSong
import com.fugaif.imaslivedb.data.model.ImasUnit

class IdolRepository(private val db: AppDatabase) {

    suspend fun fetchIdols(brandId: String? = null): List<Idol> {
        return if (brandId != null) {
            db.idolDao().fetchIdolsByBrand(brandId)
        } else {
            db.idolDao().fetchIdols()
        }
    }

    /** 一覧画面用。外部ゲスト演者 (is_external) を除外する (iOS `idols(brandId:)` と同一条件)。 */
    suspend fun fetchIdolsForList(brandId: String? = null): List<Idol> {
        return if (brandId != null) {
            db.idolDao().fetchIdolsForListByBrand(brandId)
        } else {
            db.idolDao().fetchIdolsForList()
        }
    }

    suspend fun fetchIdol(id: String): Idol? {
        return db.idolDao().fetchIdol(id)
    }

    /** タグが似ているアイドルランキング表示用。N+1を避けてIN句で一括取得する。 */
    suspend fun fetchIdolsByIds(ids: List<String>): List<Idol> {
        if (ids.isEmpty()) return emptyList()
        return db.idolDao().fetchIdolsByIds(ids)
    }

    suspend fun fetchIdolUnits(idolId: String): List<ImasUnit> {
        return db.idolDao().fetchIdolUnits(idolId)
    }

    /** このアイドルが出演した公演一覧 (show_cast 経由)。 */
    suspend fun fetchIdolShows(idolId: String): List<CastShowRow> {
        return db.idolDao().fetchIdolShows(idolId)
    }

    /** 出演公演数ランキング (idol 単位)。 */
    suspend fun fetchIdolShowCountRanking(limit: Int = 20): List<CastShowCount> {
        return db.idolDao().fetchIdolShowCountRanking(limit)
    }

    /** ライブ歌唱曲 (実演記録) + 披露回数。 */
    suspend fun fetchIdolPerformedSongs(idolId: String): List<IdolPerformedSong> {
        return db.idolDao().fetchIdolPerformedSongs(idolId)
    }

    /** このアイドルの所属ユニットのうち楽曲が紐づいているものの id 集合。 */
    suspend fun fetchIdolUnitIdsWithSongs(idolId: String): Set<String> {
        return db.idolDao().fetchIdolUnitIdsWithSongs(idolId).toSet()
    }

    suspend fun fetchBrand(brandId: String): Brand? {
        return db.brandDao().fetchBrand(brandId)
    }

    suspend fun fetchUnit(id: String): ImasUnit? {
        return db.unitDao().fetchUnit(id)
    }

    suspend fun fetchUnitMembers(unitId: String): List<Idol> {
        return db.idolDao().fetchUnitMembers(unitId)
    }
}
