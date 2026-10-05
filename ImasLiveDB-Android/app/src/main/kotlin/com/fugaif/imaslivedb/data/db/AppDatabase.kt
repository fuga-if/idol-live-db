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
import com.fugaif.imaslivedb.data.db.dao.ExpenseDao
import com.fugaif.imaslivedb.data.db.dao.ShowTicketDao
import com.fugaif.imaslivedb.data.db.dao.IdolDao
import com.fugaif.imaslivedb.data.db.dao.MetaDao
import com.fugaif.imaslivedb.data.db.dao.PersonalTagDao
import com.fugaif.imaslivedb.data.db.dao.PlaylistDao
import com.fugaif.imaslivedb.data.db.dao.SearchDao
import com.fugaif.imaslivedb.data.db.dao.SetlistDao
import com.fugaif.imaslivedb.data.db.dao.ShowDao
import com.fugaif.imaslivedb.data.db.dao.SongDao
import com.fugaif.imaslivedb.data.db.dao.StatsDao
import com.fugaif.imaslivedb.data.db.dao.SyncDao
import com.fugaif.imaslivedb.data.db.dao.UnitDao
import com.fugaif.imaslivedb.data.db.dao.UserMarkDao
import com.fugaif.imaslivedb.data.model.Anniversary
import com.fugaif.imaslivedb.data.model.Venue
import com.fugaif.imaslivedb.data.model.VenueHall
import com.fugaif.imaslivedb.data.model.Costume
import com.fugaif.imaslivedb.data.model.CostumeWear
import com.fugaif.imaslivedb.data.model.Creator
import com.fugaif.imaslivedb.data.model.UnitVersion
import com.fugaif.imaslivedb.data.model.VenueName
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Expense
import com.fugaif.imaslivedb.data.model.ShowTicket
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolBrand
import com.fugaif.imaslivedb.data.model.IdolVoiceActor
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Meta
import com.fugaif.imaslivedb.data.model.PersonalTag
import com.fugaif.imaslivedb.data.model.Playlist
import com.fugaif.imaslivedb.data.model.PlaylistItem
import com.fugaif.imaslivedb.data.model.SetlistItem
import com.fugaif.imaslivedb.data.model.SetlistPerformer
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.ShowCast
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.SongArtist
import com.fugaif.imaslivedb.data.model.SongVideo
import com.fugaif.imaslivedb.data.model.Staff
import com.fugaif.imaslivedb.data.model.TicketSale
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
        SongVideo::class,
        UserMark::class,
        Meta::class,
        Staff::class,
        Anniversary::class,
        PersonalTag::class,
        Venue::class,
        VenueName::class,
        VenueHall::class,
        UnitVersion::class,
        Creator::class,
        Costume::class,
        CostumeWear::class,
        Expense::class,
        ShowTicket::class,
        IdolVoiceActor::class,
        TicketSale::class,
        Playlist::class,
        PlaylistItem::class
    ],
    version = 26,
    // 確定スキーマを app/schemas へ JSON で吐く。共有コア (imas-core) が持つ
    // マスタ DDL と突き合わせて、片方だけスキーマを変えた事故を CI で捕まえるため。
    exportSchema = true
)
abstract class AppDatabase : RoomDatabase() {

    abstract fun brandDao(): BrandDao
    abstract fun calendarDao(): CalendarDao
    abstract fun communityDao(): CommunityDao
    abstract fun songDao(): SongDao
    abstract fun showDao(): ShowDao
    abstract fun setlistDao(): SetlistDao
    abstract fun idolDao(): IdolDao
    abstract fun unitDao(): UnitDao
    abstract fun statsDao(): StatsDao
    abstract fun searchDao(): SearchDao
    abstract fun metaDao(): MetaDao
    abstract fun syncDao(): SyncDao
    abstract fun userMarkDao(): UserMarkDao
    abstract fun personalTagDao(): PersonalTagDao
    abstract fun expenseDao(): ExpenseDao
    abstract fun showTicketDao(): ShowTicketDao
    abstract fun playlistDao(): PlaylistDao

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
            //
            // ⚠️ ここでコア (imas-core) の `ensureMasterSchema()` を流してはいけない。
            // iOS の AppDatabase は GRDB の移行を流し終えた**後**に当てているが、Android は
            // 順序をどう入れ替えても**必ず起動不能になる** (問題は順序ではなく Room の照合そのもの)。
            // Room 2.6.1 は自分が知る表について実 DB と @Entity 定義を厳密一致で照合する
            // (androidx.room.util.TableInfo.equals は columns を Map 等価・indices を Set 等価で比べ、
            //  索引の読み取りは origin='c' で絞るだけで名前による除外をしない)。
            // コアの正本 DDL は追加しかしないが、その追加分が Room から見て「余分」になる:
            //   - songs.jasrac_code (コアにあり Song entity に無い) → columns 不一致
            //   - idx_events_is_solo / idx_idols_attribute / idx_idols_is_external /
            //     idx_show_cast_idol / idx_songs_series_group → indices 不一致
            // 一度でも流すと差分が DB に残り、次に version を上げた瞬間 onUpgrade 後の
            // validateMigration が IllegalStateException を投げて既存ユーザ全員が起動できなくなる。
            // 新規インストールも同じで、Room の onCreate は「ファイルが空でない」と見た時点で
            // 同じ照合を走らせるため、Room より先に流すと初回起動が落ちる。
            //
            // 流せるようにする条件は 2 つのどちらか:
            //   a) Room 側が上記の列と索引を宣言して版を上げる (コアの KNOWN_GAPS からも消す)
            //   b) コアが「呼び手が持たない表だけ作る」適用モードを持つ
            // なお idol_voice_actors / song_units は Room が知らない表なので照合対象外であり、
            // コア適用の実利はいまのところこの 2 表だけ (どちらも Android では空のまま)。
            return configure(
                Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "master.sqlite"
                )
            ).build()
        }

        /**
         * 本番と同じ設定 (移行) を付ける。テストはこれを通してメモリ上の DB を
         * 本番と同じ条件で作る (付け忘れた設定のせいでテストだけ通る、を防ぐ)。
         *
         * 新規作成時の初期データは SeedImporter が seed から入れる。作成時のコールバックで
         * 直書きの値を先に入れると、seed の INSERT OR IGNORE に勝ってしまい、古い肩書きが
         * 残ったり記念日が欠けたりする (以前はそうなっていた)。
         */
        internal fun configure(builder: RoomDatabase.Builder<AppDatabase>): RoomDatabase.Builder<AppDatabase> =
            // スキーマ変更時は破壊的再構築せず Room Migration を書く (iOS の DatabaseMigrations と対)。
            // UserMark 等のローカル唯一データを保全するため (.fallbackToDestructiveMigration は使わない)。
            builder.addMigrations(*ALL_MIGRATIONS)

        // ---- seed helpers -------------------------------------------------------

        /**
         * staff と anniversaries の初期データ投入。MIGRATION_4_5 からだけ呼ぶ
         * (seed の無かった旧版から上がってくる端末に、表を作るのと同時に入れるため)。
         */
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

        /** idols に iOS Idol.swift 相当のプロフィール/属性フィールドを追加 (アイドル一覧のCV名表示・属性フィルタに必要)。 */
        val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE idols ADD COLUMN family_name TEXT")
                db.execSQL("ALTER TABLE idols ADD COLUMN given_name TEXT")
                db.execSQL("ALTER TABLE idols ADD COLUMN nickname TEXT")
                db.execSQL("ALTER TABLE idols ADD COLUMN debut_date TEXT")
                db.execSQL("ALTER TABLE idols ADD COLUMN attribute TEXT")
                db.execSQL("ALTER TABLE idols ADD COLUMN is_external INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE idols ADD COLUMN aliases TEXT")
                db.execSQL("ALTER TABLE idols ADD COLUMN voice_actors TEXT")
            }
        }

        /** 個人用タグ (personal_tags) を追加。コミュニティタグと違いサーバーには一切送信しない端末ローカル専用データ。 */
        val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS personal_tags (" +
                        "entity_type TEXT NOT NULL, " +
                        "entity_id TEXT NOT NULL, " +
                        "tag_name TEXT NOT NULL, " +
                        "created_at TEXT NOT NULL, " +
                        "PRIMARY KEY(entity_type, entity_id, tag_name))"
                )
            }
        }

        /**
         * 会場を ID で管理する (iOS v27_venues と対応)。
         *
         * それまで shows.venue は自由文字列で、同じ会場が最大14通りに割れていた。
         * 改名する会場もある (武蔵野の森総合スポーツプラザ → 京王アリーナTOKYO) ため、
         * 名前ではなく ID で同一性を持たせて履歴が分断されないようにする。
         */
        val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS venues (" +
                        "id TEXT NOT NULL, name TEXT NOT NULL, name_kana TEXT, " +
                        "prefecture TEXT, city TEXT, aliases TEXT, capacity INTEGER, " +
                        "sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(id))"
                )
                // 改名履歴。表示は「公演日時点の名前」なので有効期間で引く。
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS venue_names (" +
                        "id TEXT NOT NULL, venue_id TEXT NOT NULL, name TEXT NOT NULL, " +
                        "valid_from TEXT, valid_to TEXT, PRIMARY KEY(id))"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_venue_names_venue ON venue_names(venue_id)")
                // ホール/構成。キャパは構成で変わるので施設と分ける。
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS venue_halls (" +
                        "id TEXT NOT NULL, venue_id TEXT NOT NULL, name TEXT NOT NULL, " +
                        "capacity INTEGER, PRIMARY KEY(id))"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_venue_halls_venue ON venue_halls(venue_id)")
                // shows 側。venue (生文字列) は当時名のフォールバックとして残す。
                db.execSQL("ALTER TABLE shows ADD COLUMN venue_id TEXT")
                db.execSQL("ALTER TABLE shows ADD COLUMN hall TEXT")
                db.execSQL("ALTER TABLE shows ADD COLUMN stream_platform TEXT")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_shows_venue_id ON shows(venue_id)")
            }
        }

        /**
         * ユニットにバージョンを内包させる (iOS / コアの unit_versions と対応)。
         *
         * リブート企画 (Project“ReLight”AXE8) はロゴ・キャッチコピー・曲調が変わっても
         * ユニット自体は同一。units を 2 行に割るとメンバーも過去曲も分断されるので、
         * 会場の改名を venue_names に内包させたのと同じ形で版を内包させる。
         * どの版の曲かは songs 側が指す (null = 無印)。
         */
        val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS unit_versions (" +
                        "id TEXT NOT NULL, unit_id TEXT NOT NULL, code TEXT, " +
                        "name TEXT NOT NULL, catchphrase TEXT, logo_url TEXT, " +
                        "valid_from TEXT, valid_to TEXT, " +
                        "sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(id))"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_unit_versions_unit ON unit_versions(unit_id)")
                db.execSQL("ALTER TABLE songs ADD COLUMN unit_version_id TEXT")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_songs_unit_version ON songs(unit_version_id)")
            }
        }

        /**
         * 読み仮名の置き場を足す (iOS / コアと対応)。
         *
         * ライブ名は events に列で持つ。作詞作曲は別表にする — 読みは人 (表記) の属性で、
         * 同じ作家が数十曲に出るため曲側に持たせると複製になる。
         */
        val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE events ADD COLUMN name_kana TEXT")
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS creators (" +
                        "id TEXT NOT NULL, name TEXT NOT NULL, name_kana TEXT NOT NULL, " +
                        "aliases TEXT, PRIMARY KEY(id))"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_creators_name ON creators(name)")
            }
        }

        /** ユニット名の読み。漢字のユニット名をかなで引けるようにする。 */
        val MIGRATION_11_12 = object : Migration(11, 12) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE units ADD COLUMN name_kana TEXT")
            }
        }

        /**
         * コーレス (song_calls) を廃止。CloudKit のレコードタイプごと撤去され同期でも
         * 取り込まなくなったので、ローカルの表も落とす (中身は CloudKit の写しだけで、
         * 端末ローカル唯一のデータは無い)。
         */
        val MIGRATION_12_13 = object : Migration(12, 13) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("DROP TABLE IF EXISTS song_calls")
            }
        }

        /**
         * 合同曲 (コラボ曲) の 2 列を songs に足す。VOY@GER・なんどでも笑おう のような
         * シリーズ横断の曲を、参加ブランド全部の曲一覧に出すため
         * (events の joint_brand_ids と同じ形)。
         */
        val MIGRATION_13_14 = object : Migration(13, 14) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE songs ADD COLUMN joint_brand_ids TEXT")
                db.execSQL("ALTER TABLE songs ADD COLUMN is_collab INTEGER NOT NULL DEFAULT 0")
            }
        }

        /**
         * 衣装の目録 (costumes) と着用記録 (costume_wears) を足す。
         *
         * FK 制約は宣言しない。他のマスタ表と揃えてあり、親が後から届く差分同期で
         * 子行が 1 件ずつ落ちるのを避けるため (整合はコアのローダが読む時に見る)。
         */
        val MIGRATION_14_15 = object : Migration(14, 15) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS costumes (" +
                        "id TEXT PRIMARY KEY NOT NULL, " +
                        "brand_id TEXT, " +
                        "name TEXT NOT NULL, " +
                        "name_kana TEXT, " +
                        "unit_id TEXT, " +
                        "idol_id TEXT, " +
                        "description TEXT, " +
                        "source_url TEXT, " +
                        "sort_order INTEGER NOT NULL DEFAULT 0)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_costumes_brand ON costumes(brand_id)")

                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS costume_wears (" +
                        "id TEXT PRIMARY KEY NOT NULL, " +
                        "costume_id TEXT NOT NULL, " +
                        "show_id TEXT NOT NULL, " +
                        "setlist_item_id TEXT, " +
                        "idol_id TEXT, " +
                        "sort_order INTEGER NOT NULL DEFAULT 0)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_costume_wears_costume ON costume_wears(costume_id)")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_costume_wears_show ON costume_wears(show_id)")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_costume_wears_item ON costume_wears(setlist_item_id)")
            }
        }

        /**
         * KAMISABI (音楽カードゲーム) の収録札を songs に足す。カード番号は非公表・
         * ノーマル/レアは同曲の版違いなので「この曲のカードがあるか」の真偽値 1 本で足りる。
         */
        val MIGRATION_15_16 = object : Migration(15, 16) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE songs ADD COLUMN has_kamisabi_card INTEGER NOT NULL DEFAULT 0")
            }
        }

        // 収支 (家計簿)。iOS `v32_expenses` (GRDB) と同一スキーマ。
        val MIGRATION_16_17 = object : Migration(16, 17) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS expenses (
                        id TEXT NOT NULL PRIMARY KEY,
                        date TEXT NOT NULL,
                        category TEXT NOT NULL,
                        amount INTEGER NOT NULL,
                        show_id TEXT,
                        event_id TEXT,
                        note TEXT,
                        updated_at TEXT NOT NULL
                    )
                    """.trimIndent()
                )
                // 期間の集計と公演別の集計がそれぞれ全表走査にならないように。
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)")
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_expenses_show ON expenses(show_id)")
            }
        }

        /**
         * 公演のチケット価格 (マスタ)。同期で後から入るので、器だけ作る。
         *
         * 端末ローカルの収支と違い**みんなで共有する事実**なので、
         * CloudKit から降ってくる行を受ける表として作っておく。
         */
        val MIGRATION_17_18 = object : Migration(17, 18) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS show_tickets (
                        id TEXT NOT NULL PRIMARY KEY,
                        show_id TEXT NOT NULL,
                        kind TEXT NOT NULL DEFAULT 'live',
                        name TEXT NOT NULL,
                        price INTEGER NOT NULL,
                        is_estimate INTEGER NOT NULL DEFAULT 0,
                        note TEXT,
                        sort_order INTEGER NOT NULL DEFAULT 0
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_show_tickets_show ON show_tickets(show_id)")
            }
        }

        /**
         * songs の unit_version_id 索引を、どの経路で来た DB にも揃える。
         *
         * MIGRATION_9_10 はこの索引を作るのに、Song の `@Entity` は宣言していなかった。
         * Room 2.6.1 は索引も集合として厳密に照合するので、v9 以前 (配布済みの 4 / 7) から
         * 上がった端末は「Migration didn't properly handle: songs」で起動のたびに落ち、
         * データ消去 (= 担当・お気に入り・家計簿の喪失) でしか抜けられなかった。
         * 宣言を足した上で、v10〜v18 を新規に作った端末 (索引が無い) にもここで作る。
         * v9 以前から来た端末では既にあるので IF NOT EXISTS で何もしない。
         */
        val MIGRATION_18_19 = object : Migration(18, 19) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_songs_unit_version ON songs(unit_version_id)")
            }
        }

        /**
         * v20: 声優の履歴 (idol_voice_actors) をコアのマスタ DDL と同じ形で持つ (Q-12 / R-A-18)。
         * CloudKit では配らず、seed の初回投入とアプリ更新時の入れ直しで入る。上がってくる端末では
         * 表が空なので、最後に取り込んだ seed の指紋 (meta.content_hash) を消して、次の起動で
         * 同梱の seed から入れ直させる (コアの reseedNeeded は指紋が違えば入れ直す)。
         */
        val MIGRATION_19_20 = object : Migration(19, 20) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `idol_voice_actors` (`id` TEXT NOT NULL, `idol_id` TEXT NOT NULL, " +
                        "`name` TEXT NOT NULL, `valid_from` TEXT, `valid_to` TEXT, PRIMARY KEY(`id`))"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `idx_idol_voice_actors_idol` ON `idol_voice_actors` (`idol_id`)")
                db.execSQL("DELETE FROM meta WHERE key = 'content_hash'")
            }
        }

        /**
         * v21: 曲の補足 (songs.note、自由文) を足す。iOS の v34_songs_note と対。
         */
        val MIGRATION_20_21 = object : Migration(20, 21) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE songs ADD COLUMN note TEXT")
            }
        }

        /**
         * v22: 公演の会場の形態 (shows.venue_mode) を足す。iOS の v35_shows_venue_mode と対。
         * 配信だけのライブ ("online") を披露回数から外すのに使う。
         */
        val MIGRATION_21_22 = object : Migration(21, 22) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE shows ADD COLUMN venue_mode TEXT")
            }
        }

        /**
         * v23: チケット受付 (ticket_sales) を足す。共有コア (imas-core) が段階判定・並び・
         * 注目受付・期間文字列・検査文言を持ち、この表は CloudKit の写しを保存するだけ。
         *
         * events の ticket_open_date / ticket_deadline / ticket_lottery_date は正本ではなく
         * なったが、旧版のアプリがまだ読み書きするので列は残す (Event.kt の注記を参照)。
         *
         * FK は宣言しない (show_tickets の v17→v18 / costumes の v14→v15 と同じ理由:
         * 親が後から届く差分同期で子行が 1 件ずつ落ちるのを避ける)。
         */
        val MIGRATION_22_23 = object : Migration(22, 23) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS ticket_sales (" +
                        "id TEXT NOT NULL PRIMARY KEY, " +
                        "event_id TEXT NOT NULL, " +
                        "show_ids TEXT, " +
                        "kind TEXT NOT NULL, " +
                        "name TEXT NOT NULL, " +
                        "starts_at TEXT, " +
                        "ends_at TEXT, " +
                        "result_at TEXT, " +
                        "url TEXT, " +
                        "note TEXT, " +
                        "source_url TEXT NOT NULL, " +
                        "sort_order INTEGER NOT NULL DEFAULT 0)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_ticket_sales_event ON ticket_sales(event_id)")
            }
        }

        /**
         * v24: プレイリスト (playlists / playlist_items) を足す。iOS の v37_playlists と対。
         * **端末ローカル唯一データ**なので、expenses (v16→v17) と同じく FK を宣言しない
         * (他のマスタ表と違い親子とも端末ローカルなので壊れる心配はないが、揃えておく)。
         */
        val MIGRATION_23_24 = object : Migration(23, 24) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS playlists (" +
                        "id TEXT NOT NULL PRIMARY KEY, " +
                        "name TEXT NOT NULL, " +
                        "created_at TEXT NOT NULL, " +
                        "updated_at TEXT NOT NULL)"
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS playlist_items (" +
                        "playlist_id TEXT NOT NULL, " +
                        "song_id TEXT NOT NULL, " +
                        "position INTEGER NOT NULL, " +
                        "PRIMARY KEY(playlist_id, song_id))"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS idx_playlist_items_playlist ON playlist_items(playlist_id)")
            }
        }

        /**
         * v25: 端末のプレイリストと、それを公開した「みんなのプレイリスト」の id の紐づけ。
         * 公開を差し替える・やめるときに使う。NULL = 公開していない。iOS の v38_playlists_published_id と対。
         */
        val MIGRATION_24_25 = object : Migration(24, 25) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE playlists ADD COLUMN published_id TEXT")
            }
        }

        /**
         * v26: チケット価格に配信アーカイブの視聴期間 (始まり・終わり) を足す。NULL = 公式に出ていない。
         * iOS の show_tickets 追加列と対。
         */
        val MIGRATION_25_26 = object : Migration(25, 26) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE show_tickets ADD COLUMN archive_starts_at TEXT")
                db.execSQL("ALTER TABLE show_tickets ADD COLUMN archive_ends_at TEXT")
            }
        }

        /** 登録する移行の全部 (古い順)。本番の builder と移行テストが同じ並びを使う。 */
        val ALL_MIGRATIONS: Array<Migration> = arrayOf(
            MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9,
            MIGRATION_9_10, MIGRATION_10_11, MIGRATION_11_12, MIGRATION_12_13, MIGRATION_13_14,
            MIGRATION_14_15, MIGRATION_15_16, MIGRATION_16_17, MIGRATION_17_18, MIGRATION_18_19,
            MIGRATION_19_20, MIGRATION_20_21, MIGRATION_21_22, MIGRATION_22_23, MIGRATION_23_24,
            MIGRATION_24_25, MIGRATION_25_26
        )
    }
}
