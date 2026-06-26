package com.fugaif.imaslivedb.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.fugaif.imaslivedb.data.db.dao.BrandDao
import com.fugaif.imaslivedb.data.db.dao.CalendarDao
import com.fugaif.imaslivedb.data.db.dao.CommunityDao
import com.fugaif.imaslivedb.data.db.dao.EventDao
import com.fugaif.imaslivedb.data.db.dao.IdolDao
import com.fugaif.imaslivedb.data.db.dao.MetaDao
import com.fugaif.imaslivedb.data.db.dao.SearchDao
import com.fugaif.imaslivedb.data.db.dao.SetlistDao
import com.fugaif.imaslivedb.data.db.dao.ShowDao
import com.fugaif.imaslivedb.data.db.dao.SongDao
import com.fugaif.imaslivedb.data.db.dao.StatsDao
import com.fugaif.imaslivedb.data.db.dao.SyncDao
import com.fugaif.imaslivedb.data.db.dao.UnitDao
import com.fugaif.imaslivedb.data.db.dao.UserMarkDao
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolBrand
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Meta
import com.fugaif.imaslivedb.data.model.SetlistItem
import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowCast
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongArtist
import com.fugaif.imaslivedb.data.model.SongCall
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.data.model.UnitMember
import com.fugaif.imaslivedb.data.model.UserMark

@Database(
    entities = [
        Brand::class,
        Song::class,
        Event::class,
        Show::class,
        SetlistItem::class,
        SetlistPerformer::class,
        ShowCast::class,
        Idol::class,
        IdolBrand::class,
        ImasUnit::class,
        UnitMember::class,
        SongArtist::class,
        SongCall::class,
        SongVideo::class,
        UserMark::class,
        Meta::class
    ],
    version = 4,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {

    abstract fun brandDao(): BrandDao
    abstract fun calendarDao(): CalendarDao
    abstract fun communityDao(): CommunityDao
    abstract fun songDao(): SongDao
    abstract fun eventDao(): EventDao
    abstract fun showDao(): ShowDao
    abstract fun setlistDao(): SetlistDao
    abstract fun idolDao(): IdolDao
    abstract fun unitDao(): UnitDao
    abstract fun statsDao(): StatsDao
    abstract fun searchDao(): SearchDao
    abstract fun metaDao(): MetaDao
    abstract fun syncDao(): SyncDao
    abstract fun userMarkDao(): UserMarkDao

    companion object {
        @Volatile
        private var instance: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase {
            return instance ?: synchronized(this) {
                instance ?: buildDatabase(context).also { instance = it }
            }
        }

        private fun buildDatabase(context: Context): AppDatabase {
            // バンドル同梱を廃止。Room がエンティティから空DBを生成し、
            // 初回起動で CloudKitSyncEngine がフル同期して投入する。
            // これにより createFromAsset のスキーマ検証クラッシュリスクを排除する。
            return Room.databaseBuilder(
                context.applicationContext,
                AppDatabase::class.java,
                "master.sqlite"
            )
                // スキーマ変更時は破壊的再構築せず Room Migration を書く (iOS の DatabaseMigrations と対)。
                // UserMark 等のローカル唯一データを保全するため (.fallbackToDestructiveMigration は使わない)。
                .build()
        }
    }
}
