import GRDB
import XCTest
@testable import ImasLiveDB

/// イントロドンの出題プールが、どの入口 (ブランド指定 / 曲一覧の絞り込み) から来ても
/// コアの出題可否 (`introQuizPlayableIndices`) を通ることのテスト。
///
/// ブランド指定の経路だけが SQL で「apple_music_id がある曲」に絞っていて、
/// Apple Music を契約していない端末で preview の無い曲が出題され、無音になっていた。
final class IntroQuestionPoolTests: XCTestCase {

    /// - `s_preview` : preview あり (誰でも鳴る)
    /// - `s_catalog` : カタログ再生しかできない (契約が要る)
    /// - `s_derived` : 派生曲 (選択肢が重複するので出さない)
    /// - `s_other`   : 選んでいないブランド
    private func makeDatabase() throws -> AppDatabase {
        let queue = try makeMigratedDatabase()
        try queue.write { db in
            for brand in ["765as", "ml"] {
                try db.execute(
                    sql: "INSERT INTO brands (id, name, short_name, sort_order) VALUES (?, ?, ?, 1)",
                    arguments: [brand, brand, brand])
            }
            for (id, brand, appleMusicId, previewUrl, parent) in [
                ("s_preview", "765as", "1", "https://example.com/1.m4a", nil),
                ("s_catalog", "765as", "2", nil, nil),
                ("s_derived", "765as", "3", "https://example.com/3.m4a", "s_preview"),
                ("s_other", "ml", "4", "https://example.com/4.m4a", nil),
            ] as [(String, String, String, String?, String?)] {
                try db.execute(
                    sql: """
                        INSERT INTO songs (id, title, brand_id, song_type, apple_music_id, preview_url, parent_song_id)
                        VALUES (?, ?, ?, 'solo', ?, ?, ?)
                        """,
                    arguments: [id, id, brand, appleMusicId, previewUrl, parent])
            }
        }
        return try AppDatabase(dbQueue: queue)
    }

    private func poolIds(subscribed: Bool, preset: [Song]? = nil) throws -> Set<String> {
        let pool = try IntroGameSession.questionPool(
            preset: preset, brandIds: ["765as"], database: makeDatabase(),
            hasAppleMusicSubscription: subscribed)
        return Set(pool.map(\.id))
    }

    /// 契約が無い端末では、preview の無い曲をブランド指定の経路でも出さない。
    func testBrandPoolWithoutSubscriptionHasOnlySongsWithPreview() throws {
        XCTAssertEqual(try poolIds(subscribed: false), ["s_preview"])
    }

    /// 契約があればカタログで鳴らせるので、preview の無い曲も出す。派生曲と他ブランドは出さない。
    func testBrandPoolWithSubscriptionIncludesCatalogOnlySongs() throws {
        XCTAssertEqual(try poolIds(subscribed: true), ["s_preview", "s_catalog"])
    }
}
