import XCTest
@testable import ImasLiveDB

/// タグのカテゴリは読んだ生値のまま持つ (アイドル・ユニットのカテゴリを「フリー」に倒さない)。
///
/// 以前は曲タグの 4 値の enum で、`charm` / `appearance` などが `.free` に化け、
/// 編集シートがそれを初期値にして保存するのでカテゴリが消えていた。
final class TagCategoryDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> CommunityTag {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(CommunityTag.self, from: Data(json.utf8))
    }

    func testIdolCategoriesSurviveDecoding() throws {
        for raw in ["appearance", "charm", "personality", "mood", "brand_new_category"] {
            let tag = try decode(#"{"id":"t","name":"黒髪","category":"\#(raw)","created_at":1}"#)
            XCTAssertEqual(tag.category?.rawValue, raw)
        }
        XCTAssertNil(try decode(#"{"id":"t","name":"x","created_at":1}"#).category)
    }

    func testCategoryRoundTripsThroughEncoding() throws {
        let tag = try decode(#"{"id":"t","name":"黒髪","category":"appearance","created_at":1}"#)
        let encoded = try JSONEncoder().encode(tag)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(object?["category"] as? String, "appearance")
    }
}
