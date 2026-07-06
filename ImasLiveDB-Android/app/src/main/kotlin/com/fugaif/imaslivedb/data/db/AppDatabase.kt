package com.fugaif.imaslivedb.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
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
import com.fugaif.imaslivedb.data.model.Anniversary
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
import com.fugaif.imaslivedb.data.model.Staff
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
        Meta::class,
        Staff::class,
        Anniversary::class
    ],
    version = 6,
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
                .addMigrations(MIGRATION_4_5, MIGRATION_5_6)
                .addCallback(seedCallback)
                .build()
        }

        // ---- seed helpers -------------------------------------------------------

        /** staff と anniversaries の初期データ投入。Migration / onCreate 双方から呼ぶ。 */
        private fun insertStaffAndAnniversarySeeds(db: SupportSQLiteDatabase) {
            // staff (8件)
            db.execSQL("INSERT OR IGNORE INTO staff (id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order) VALUES ('staff_kotori_otonashi', '765as', '音無小鳥', 'おとなしことり', 'Kotori Otonashi', '765プロダクション事務員 / プロデューサー補佐', '--09-09', 0)")
            db.execSQL("INSERT OR IGNORE INTO staff (id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order) VALUES ('staff_takagi_junichiro', '765as', '高木順一朗', 'たかぎじゅんいちろう', 'Junichiro Takagi', '765プロダクション初代代表取締役社長 (後に会長)', '--07-06', 1)")
            db.execSQL("INSERT OR IGNORE INTO staff (id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order) VALUES ('staff_takagi_junjiro', '765as', '高木順二朗', 'たかぎじゅんじろう', 'Junjiro Takagi', '765プロダクション代表取締役社長', '--07-06', 2)")
            db.execSQL("INSERT OR IGNORE INTO staff (id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order) VALUES ('staff_kuroi_takao', '961', '黒井崇男', 'くろいたかお', 'Takao Kuroi', '961プロダクション代表取締役社長', '--09-06', 3)")
            db.execSQL("INSERT OR IGNORE INTO staff (id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order) VALUES ('staff_chihiro_senkawa', 'cg', '千川ちひろ', 'せんかわちひろ', 'Chihiro Senkawa', '346プロダクション事務員 / シンデレラプロジェクト統括', '--11-28', 4)")
            db.execSQL("INSERT OR IGNORE INTO staff (id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order) VALUES ('staff_misaki_aoba', 'ml', '青羽美咲', 'あおばみさき', 'Misaki Aoba', '765プロライブ劇場 劇場事務員 (プロデューサー補佐)', '--06-29', 5)")
            db.execSQL("INSERT OR IGNORE INTO staff (id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order) VALUES ('staff_hazuki_nanakusa', 'sc', '七草はづき', 'ななくさはづき', 'Hazuki Nanakusa', '283プロダクション事務員 (プロデューサー補佐)', '--02-03', 6)")
            db.execSQL("INSERT OR IGNORE INTO staff (id, brand_id, name, name_kana, name_romaji, role, birthday, sort_order) VALUES ('staff_ken_yamamura', 'sidem', '山村賢', 'やまむらけん', 'Ken Yamamura', '315プロダクション事務員 (プロデューサーアシスタント、学生アルバイト)', '--07-02', 7)")

            // anniversaries (21件)
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_765as_20050726_service_start', '765as', 'アーケード版稼働', '2005-07-26', 'service_start', 0)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_765as_20050928_cd_debut', '765as', 'シリーズ初CD「MASTERPIECE 01」発売', '2005-09-28', 'cd_debut', 1)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_765as_20110707_anime_start', '765as', 'TVアニメ放映開始', '2011-07-07', 'anime_start', 2)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_765as_20140125_movie_release', '765as', '劇場版「輝きの向こう側へ！」公開', '2014-01-25', 'movie_release', 3)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_876_20090917_service_start', '876', '「アイドルマスター ディアリースターズ」(DS)発売', '2009-09-17', 'service_start', 4)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_961_20090219_service_start', '961', '「アイドルマスターSP」発売(961プロ初登場)', '2009-02-19', 'service_start', 5)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_cg_20111128_service_start', 'cg', 'モバマス配信開始', '2011-11-28', 'service_start', 6)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_cg_20150109_anime_start', 'cg', 'TVアニメ放映開始', '2015-01-09', 'anime_start', 7)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_cg_20150903_app_start', 'cg', 'デレステ配信開始', '2015-09-03', 'app_start', 8)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_ml_20130227_service_start', 'ml', 'グリマス配信開始', '2013-02-27', 'service_start', 9)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_ml_20170629_app_start', 'ml', 'ミリシタ配信開始', '2017-06-29', 'app_start', 10)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_ml_20230818_movie_release', 'ml', '劇場版「ミリオンライブ！第1幕」公開', '2023-08-18', 'movie_release', 11)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_ml_20231008_anime_start', 'ml', 'TVアニメ放映開始', '2023-10-08', 'anime_start', 12)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_sidem_20140717_service_start', 'sidem', 'モバゲー版SideM正式サービス開始', '2014-07-17', 'service_start', 13)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_sidem_20170830_app_start', 'sidem', 'エムステ配信開始', '2017-08-30', 'app_start', 14)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_sidem_20171007_anime_start', 'sidem', 'TVアニメ放映開始', '2017-10-07', 'anime_start', 15)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_sc_20180424_service_start', 'sc', 'シャニマス(enza)配信開始', '2018-04-24', 'service_start', 16)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_sc_20240405_anime_start', 'sc', 'シャニアニ1st season放映開始', '2024-04-05', 'anime_start', 17)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_sc_20241004_anime_start', 'sc', 'シャニアニ2nd season放映開始', '2024-10-04', 'anime_start', 18)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_sc_20231114_app_start', 'sc', 'シャニソン配信開始', '2023-11-14', 'app_start', 19)")
            db.execSQL("INSERT OR IGNORE INTO anniversaries (id, brand_id, label, date, kind, sort_order) VALUES ('ann_gakuen_20240516_app_start', 'gakuen', '学マス配信開始', '2024-05-16', 'app_start', 20)")
        }

        // ---- Callback (新規インストール時の seed) --------------------------------

        private val seedCallback = object : RoomDatabase.Callback() {
            override fun onCreate(db: SupportSQLiteDatabase) {
                super.onCreate(db)
                insertStaffAndAnniversarySeeds(db)
            }
        }

        // ---- Migrations ---------------------------------------------------------

        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS staff (" +
                        "id TEXT PRIMARY KEY NOT NULL, " +
                        "brand_id TEXT NOT NULL, " +
                        "name TEXT NOT NULL, " +
                        "name_kana TEXT, " +
                        "name_romaji TEXT, " +
                        "role TEXT, " +
                        "birthday TEXT, " +
                        "sort_order INTEGER NOT NULL DEFAULT 0)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_staff_brand ON staff(brand_id)")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_staff_birthday ON staff(birthday)")

                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS anniversaries (" +
                        "id TEXT PRIMARY KEY NOT NULL, " +
                        "brand_id TEXT NOT NULL, " +
                        "label TEXT NOT NULL, " +
                        "date TEXT NOT NULL, " +
                        "kind TEXT NOT NULL, " +
                        "sort_order INTEGER NOT NULL DEFAULT 0)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_anniversaries_brand ON anniversaries(brand_id)")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_anniversaries_date ON anniversaries(date)")

                insertStaffAndAnniversarySeeds(db)
            }
        }

        /** events のチケット情報/kind/is_solo/合同ブランド、songs の series_group を追加 (iOS 側で先行実装済みのフィールドに追いつく)。 */
        val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE events ADD COLUMN is_solo INTEGER NOT NULL DEFAULT 1")
                db.execSQL("ALTER TABLE events ADD COLUMN kind TEXT NOT NULL DEFAULT 'live'")
                db.execSQL("ALTER TABLE events ADD COLUMN ticket_open_date TEXT")
                db.execSQL("ALTER TABLE events ADD COLUMN ticket_deadline TEXT")
                db.execSQL("ALTER TABLE events ADD COLUMN ticket_lottery_date TEXT")
                db.execSQL("ALTER TABLE events ADD COLUMN ticket_url TEXT")
                db.execSQL("ALTER TABLE events ADD COLUMN joint_brand_ids TEXT")
                db.execSQL("ALTER TABLE songs ADD COLUMN series_group TEXT")
            }
        }
    }
}
