package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SQLITE_BINARY_ORDER
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.ImasUnit
import uniffi.imas_core.IdolUnitRecord
import uniffi.imas_core.UnitRecord

/**
 * ユニット関連のクエリ。IdolRepository から切り出し (タグ/似てる/投票等、今後の拡張を見据えて独立)。
 *
 * 読み取りは共有コア (imas-core) のスナップショットを第一経路とし、未ロード・利用不可の
 * ときだけ Room へフォールバックする。units は Room の [ImasUnit] とコアの UnitRecord が
 * 列 1:1 なので、アイドルや曲と違い実体をそのまま組み立てられる。
 */
class UnitRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null
) {

    suspend fun fetchUnit(id: String): ImasUnit? {
        // 未知 id では null が返って SQL 経路が引き直すが、結果も null なので観測差は無い
        // (逆に同期直後でスナップショットが 1 世代古いときは Room が拾ってくれる)。
        snapshots?.query { store -> store.unitRecord(id)?.toUnit() }?.let { return it }
        return db.unitDao().fetchUnit(id)
    }

    suspend fun fetchUnitMembers(unitId: String): List<Idol> {
        // コアは idol id 列 (sort_order 順) を返す。Idol 実体は voice_actors を持つ Room が正。
        snapshots?.query { store -> store.unitMemberIdolIds(unitId) }
            ?.let { return hydrateInOrder(it, Idol::id) { ids -> db.idolDao().fetchIdolsByIds(ids) } }
        return db.idolDao().fetchUnitMembers(unitId)
    }

    /** このアイドルが所属するユニット一覧。 */
    suspend fun fetchUnitsForIdol(idolId: String): List<ImasUnit> {
        snapshots?.query { store -> store.idolUnits(idolId).map { it.toUnit() } }?.let { return it }
        return db.idolDao().fetchIdolUnits(idolId)
    }

    /** [fetchUnitsForIdol] のうち楽曲が紐づいているユニットの id 集合 (「楽曲なし」ユニットの区別用)。 */
    suspend fun fetchUnitIdsForIdolWithSongs(idolId: String): Set<String> {
        // 所属ユニット → 曲ありユニットの 2 段引き。SQL の
        // `units JOIN unit_members JOIN songs` の DISTINCT と同じ集合になる。
        // 1 ユーザー操作 = provider.query 1 回に収めるため、2 呼び出しは同じブロック内で行う。
        snapshots?.query { store ->
            store.unitIdsWithSongs(store.idolUnits(idolId).map { it.id }).toSet()
        }?.let { return it }
        return db.idolDao().fetchIdolUnitIdsWithSongs(idolId).toSet()
    }

    /** ユニット一覧画面用。曲ありユニットのみ返す (ブランドでのグルーピングは呼び出し側で行う)。 */
    suspend fun fetchUnitsForList(): List<ImasUnit> {
        snapshots?.query { store ->
            // unitIndexRecord は「全ユニット + 曲ありユニット id」を 1 呼び出しで返す。
            // ただし並びはスナップショット順 (rowid) なので、SQL の `ORDER BY u.name`
            // (BINARY 照合) に戻してから返す — 一覧の並びは UI がそのまま使う。
            val index = store.unitIndexRecord()
            val withSongs = index.songUnitIds.toSet()
            index.units
                .filter { it.id in withSongs }
                .map { it.toUnit() }
                .sortedWith(compareBy(SQLITE_BINARY_ORDER, ImasUnit::name))
        }?.let { return it }
        return db.unitDao().fetchUnitsWithSongs()
    }

    /** タグが似ているユニットランキング表示用。N+1を避けてIN句で一括取得する。 */
    suspend fun fetchUnitsByIds(ids: List<String>): List<ImasUnit> {
        if (ids.isEmpty()) return emptyList()
        // id 群の一括取得に対応するコア API が無く (unitRecord は単発 = N+1 になる)、
        // 呼び出し側も並び順を見ないため Room 直のまま。
        return db.unitDao().fetchUnitsByIds(ids)
    }
}

private fun UnitRecord.toUnit(): ImasUnit =
    ImasUnit(id = id, brandId = brandId, name = name, isPermanent = isPermanent, nameAlt = nameAlt)

private fun IdolUnitRecord.toUnit(): ImasUnit =
    ImasUnit(id = id, brandId = brandId, name = name, isPermanent = isPermanent, nameAlt = nameAlt)
