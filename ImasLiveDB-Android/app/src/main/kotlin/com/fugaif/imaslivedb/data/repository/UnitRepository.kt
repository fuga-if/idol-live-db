package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit

/** ユニット関連のクエリ。IdolRepository から切り出し (タグ/似てる/投票等、今後の拡張を見据えて独立)。 */
class UnitRepository(private val db: AppDatabase) {

    suspend fun fetchUnit(id: String): ImasUnit? {
        return db.unitDao().fetchUnit(id)
    }

    suspend fun fetchUnitMembers(unitId: String): List<Idol> {
        return db.idolDao().fetchUnitMembers(unitId)
    }

    /** このアイドルが所属するユニット一覧。 */
    suspend fun fetchUnitsForIdol(idolId: String): List<ImasUnit> {
        return db.idolDao().fetchIdolUnits(idolId)
    }

    /** [fetchUnitsForIdol] のうち楽曲が紐づいているユニットの id 集合 (「楽曲なし」ユニットの区別用)。 */
    suspend fun fetchUnitIdsForIdolWithSongs(idolId: String): Set<String> {
        return db.idolDao().fetchIdolUnitIdsWithSongs(idolId).toSet()
    }

    /** ユニット一覧画面用。曲ありユニットのみ返す (ブランドでのグルーピングは呼び出し側で行う)。 */
    suspend fun fetchUnitsForList(): List<ImasUnit> {
        return db.unitDao().fetchUnitsWithSongs()
    }

    /** タグが似ているユニットランキング表示用。N+1を避けてIN句で一括取得する。 */
    suspend fun fetchUnitsByIds(ids: List<String>): List<ImasUnit> {
        if (ids.isEmpty()) return emptyList()
        return db.unitDao().fetchUnitsByIds(ids)
    }
}
