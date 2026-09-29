package com.fugaif.imaslivedb.testing

import android.content.Context
import androidx.room.Room
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine
import com.fugaif.imaslivedb.data.sync.SeedImporter
import kotlinx.coroutines.runBlocking
import java.io.Closeable

/**
 * 本番と同じ設定の Room DB (ファイル) に本物の seed を入れ、そこからコアのスナップショットを読んだもの。
 *
 * リポジトリをスナップショット経路で動かすテストの土台。DB 名は本番と同じ `master.sqlite`
 * (スナップショットはこの名前のファイルを読む)。Robolectric の実行ごとに別のディレクトリになる。
 */
class SeededDatabase(context: Context) : Closeable {

    val db: AppDatabase = AppDatabase.configure(Room.databaseBuilder(context, AppDatabase::class.java, DB_NAME))
        .allowMainThreadQueries()
        .build()

    val snapshots: SnapshotStoreProvider = SnapshotStoreProvider(context, CloudKitSyncEngine(context, db))

    init {
        runBlocking {
            check(SeedImporter.importIfNeeded(context, db)) { "seed を入れられない: ${SeedImporter.lastImportError}" }
            snapshots.reload()
        }
    }

    override fun close() = db.close()

    private companion object {
        const val DB_NAME = "master.sqlite"
    }
}
