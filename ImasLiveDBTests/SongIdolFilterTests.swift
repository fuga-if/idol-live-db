import XCTest
import GRDB
@testable import ImasLiveDB

/// 楽曲一覧の「アイドルで絞り込み」が **持ち曲 (song_artists.role='original')** だけを返すことのテスト。
///
/// `song_artists` には 2 つの role がある:
/// - `original`  … その曲の原唱者 (= 持ち曲)
/// - `performer` … ライブでその曲を歌った実績 (カバー・合同ライブでの披露など)
///
/// 以前は JOIN で role を見ておらず、アイドルで絞り込むと「ライブで一度歌っただけの他人の持ち曲」
/// まで並んでいた (実データで 渋谷凛 120曲 → 48曲 と 6割が混入)。担当アイドル絞り込み側は
/// 元から original 限定だったので、同じ「このアイドルの曲」でも経路によって結果が違っていた。
final class SongIdolFilterTests: XCTestCase {

    /// 最小スキーマ + 固定データの in-memory DB。
    ///
    /// - `s_own`    : haruka の持ち曲 (original)
    /// - `s_shared` : haruka と chihaya 両方が original (ユニット曲)
    /// - `s_cover`  : chihaya の持ち曲を haruka がライブで歌っただけ (haruka は performer のみ)
    private func makeDatabase() throws -> AppDatabase {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE songs(
                    id TEXT PRIMARY KEY, brand_id TEXT, title TEXT, title_kana TEXT,
                    parent_song_id TEXT, release_date TEXT, cd_series TEXT, series_group TEXT,
                    song_type TEXT NOT NULL, unit_id TEXT, unit_name TEXT, singer_label TEXT,
                    apple_music_id TEXT, artwork_url TEXT, lyrics_url TEXT,
                    lyricist TEXT, composer TEXT, arranger TEXT
                )
                """)
            try db.execute(sql: "CREATE TABLE idols(id TEXT PRIMARY KEY, brand_id TEXT, name TEXT, name_kana TEXT, sort_order INTEGER NOT NULL DEFAULT 0, is_external INTEGER NOT NULL DEFAULT 0)")
            try db.execute(sql: "CREATE TABLE song_artists(song_id TEXT, idol_id TEXT, role TEXT, PRIMARY KEY(song_id, idol_id, role))")
            try db.execute(sql: "CREATE TABLE setlist_items(song_id TEXT, show_id TEXT)")
            try db.execute(sql: "CREATE TABLE shows(id TEXT PRIMARY KEY, event_id TEXT)")
            try db.execute(sql: "CREATE TABLE events(id TEXT PRIMARY KEY, name TEXT)")

            try db.execute(sql: "INSERT INTO idols(id, brand_id, name, name_kana, sort_order) VALUES('haruka','765as','天海春香','あまみはるか',1)")
            try db.execute(sql: "INSERT INTO idols(id, brand_id, name, name_kana, sort_order) VALUES('chihaya','765as','如月千早','きさらぎちはや',2)")

            try db.execute(sql: "INSERT INTO songs(id, brand_id, title, title_kana, song_type) VALUES('s_own','765as','持ち曲','もちきよく','solo')")
            try db.execute(sql: "INSERT INTO songs(id, brand_id, title, title_kana, song_type) VALUES('s_shared','765as','ユニット曲','ゆにつときよく','unit')")
            try db.execute(sql: "INSERT INTO songs(id, brand_id, title, title_kana, song_type) VALUES('s_cover','765as','カバーした曲','かはあしたきよく','solo')")

            try db.execute(sql: "INSERT INTO song_artists VALUES('s_own','haruka','original')")
            try db.execute(sql: "INSERT INTO song_artists VALUES('s_shared','haruka','original')")
            try db.execute(sql: "INSERT INTO song_artists VALUES('s_shared','chihaya','original')")
            // chihaya の持ち曲を haruka がライブで披露しただけ
            try db.execute(sql: "INSERT INTO song_artists VALUES('s_cover','chihaya','original')")
            try db.execute(sql: "INSERT INTO song_artists VALUES('s_cover','haruka','performer')")
        }
        return try AppDatabase(dbQueue: queue)
    }

    private func titles(_ rows: [SongWithArtists]) -> Set<String> {
        Set(rows.map(\.song.id))
    }

    // MARK: - idolIds

    func testIdolIdFilterReturnsOnlyOriginalSongs() throws {
        let db = try makeDatabase()
        let rows = try db.fetchSongs(filter: SongSearchFilter(idolIds: ["haruka"]))

        // 持ち曲とユニット曲だけ。ライブで歌っただけの s_cover は出ない。
        XCTAssertEqual(titles(rows), ["s_own", "s_shared"])
    }

    func testIdolIdFilterExcludesLiveOnlyPerformance() throws {
        let db = try makeDatabase()
        let rows = try db.fetchSongs(filter: SongSearchFilter(idolIds: ["haruka"]))

        XCTAssertFalse(
            titles(rows).contains("s_cover"),
            "ライブで歌っただけの曲 (role='performer') が持ち曲として混ざっている"
        )
    }

    func testOtherIdolKeepsOwnSong() throws {
        let db = try makeDatabase()
        let rows = try db.fetchSongs(filter: SongSearchFilter(idolIds: ["chihaya"]))

        // s_cover は chihaya にとっては持ち曲なので残る (haruka から見た時だけ消える)。
        XCTAssertEqual(titles(rows), ["s_shared", "s_cover"])
    }

    func testMultipleIdolsAreOrCombined() throws {
        let db = try makeDatabase()
        let rows = try db.fetchSongs(filter: SongSearchFilter(idolIds: ["haruka", "chihaya"]))

        XCTAssertEqual(titles(rows), ["s_own", "s_shared", "s_cover"])
    }

    // MARK: - idolName (同じ JOIN を通るので同条件になること)

    func testIdolNameFilterAlsoReturnsOnlyOriginalSongs() throws {
        let db = try makeDatabase()
        let rows = try db.fetchSongs(filter: SongSearchFilter(idolName: "天海"))

        XCTAssertEqual(titles(rows), ["s_own", "s_shared"])
    }

    // MARK: - 絞り込み無しでは全件出ること (JOIN 条件が全体に波及していないこと)

    func testNoIdolFilterReturnsAllSongs() throws {
        let db = try makeDatabase()
        let rows = try db.fetchSongs(filter: SongSearchFilter())

        XCTAssertEqual(titles(rows), ["s_own", "s_shared", "s_cover"])
    }
}
