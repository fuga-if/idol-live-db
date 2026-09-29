package com.fugaif.imaslivedb.data.sync

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import uniffi.imas_core.SnapshotStore

/**
 * 起動時のマスタの準備の順番 (RedTeam A-M3)。
 *
 * 1. seed の投入・入れ直し ([CloudKitSyncEngine.ensureLocalData])
 * 2. データがあれば、スナップショットを**読み直してから**返す
 *
 * 先に誰か (通知の積み直し・ウィジェットなど) がスナップショットを読んでいると、
 * 「読み込み済み」の空または入れ直し前のストアがそのまま返り、最初の画面が空・古いまま出る。
 * 投入・入れ直しの後は必ず読み直す。スナップショットを読む起動時の処理 (通知の積み直し) は
 * この後に回すこと。
 */
object LocalDataStartup {

    /**
     * データがあれば読み直したストアを、無ければ null を返す。読み込めなければ
     * [com.fugaif.imaslivedb.data.core.SnapshotUnavailableException] を投げる。
     */
    suspend fun prepare(sync: CloudKitSyncEngine, snapshots: SnapshotStoreProvider): SnapshotStore? {
        if (!sync.ensureLocalData()) return null
        snapshots.reload()
        return snapshots.loadedStore()
    }
}
