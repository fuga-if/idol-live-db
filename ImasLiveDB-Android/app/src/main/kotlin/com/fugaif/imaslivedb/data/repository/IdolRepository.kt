package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.CastShowCount
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit

class IdolRepository(private val db: AppDatabase) {

    suspend fun fetchIdols(brandId: String? = null): List<Idol> {
        return if (brandId != null) {
            db.idolDao().fetchIdolsByBrand(brandId)
        } else {
            db.idolDao().fetchIdols()
        }
    }

    suspend fun fetchIdol(id: String): Idol? {
        return db.idolDao().fetchIdol(id)
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

    suspend fun fetchUnit(id: String): ImasUnit? {
        return db.unitDao().fetchUnit(id)
    }

    suspend fun fetchUnitMembers(unitId: String): List<Idol> {
        return db.idolDao().fetchUnitMembers(unitId)
    }
}
