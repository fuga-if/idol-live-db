import XCTest
@testable import ImasLiveDB

/// ギャラリー manifest の解釈 (新/旧形式) と、ウィジェットスライドショー対象の選択ロジックのテスト。
/// どちらも FS 非依存の純粋関数なので単体テスト可能。
final class GalleryManifestTests: XCTestCase {

    // MARK: - parseManifest (後方互換)

    func testParseNewFormatPreservesFlags() {
        let json = """
        [{"name":"a.jpg","inSlideshow":true},{"name":"b.jpg","inSlideshow":false}]
        """.data(using: .utf8)!
        let entries = CustomImageService.parseManifest(json)
        XCTAssertEqual(entries.map(\.name), ["a.jpg", "b.jpg"])
        XCTAssertEqual(entries.map(\.inSlideshow), [true, false])
    }

    func testParseLegacyStringArrayDefaultsToIncluded() {
        // 旧形式 (純粋な [String]) → 全件スライドショー対象として移行。
        let json = #"["a.jpg","b.jpg","c.jpg"]"#.data(using: .utf8)!
        let entries = CustomImageService.parseManifest(json)
        XCTAssertEqual(entries.map(\.name), ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertTrue(entries.allSatisfy(\.inSlideshow))
    }

    func testParseGarbageReturnsEmpty() {
        XCTAssertTrue(CustomImageService.parseManifest(Data("not json".utf8)).isEmpty)
    }

    func testNewFormatRoundTrip() {
        let original = [GalleryImageMeta(name: "x.jpg", inSlideshow: false),
                        GalleryImageMeta(name: "y.jpg")]
        let data = try! JSONEncoder().encode(original)
        XCTAssertEqual(CustomImageService.parseManifest(data), original)
    }

    // MARK: - slideshowFiltered (フォールバック)

    func testSlideshowFilteredKeepsOnlyIncluded() {
        let entries = [GalleryImageMeta(name: "a.jpg", inSlideshow: true),
                       GalleryImageMeta(name: "b.jpg", inSlideshow: false),
                       GalleryImageMeta(name: "c.jpg", inSlideshow: true)]
        XCTAssertEqual(CustomImageService.slideshowFiltered(entries).map(\.name), ["a.jpg", "c.jpg"])
    }

    func testSlideshowFilteredFallsBackToAllWhenNoneSelected() {
        // 全部外したらウィジェットが空にならないよう全件にフォールバック。
        let entries = [GalleryImageMeta(name: "a.jpg", inSlideshow: false),
                       GalleryImageMeta(name: "b.jpg", inSlideshow: false)]
        XCTAssertEqual(CustomImageService.slideshowFiltered(entries).map(\.name), ["a.jpg", "b.jpg"])
    }

    func testSlideshowFilteredEmptyStaysEmpty() {
        XCTAssertTrue(CustomImageService.slideshowFiltered([]).isEmpty)
    }

    // MARK: - dedupedByName (重複エントリ除去)

    func testDedupKeepsFirstOccurrencePreservingOrder() {
        // 同名が複数あっても最初の1件だけ残す (順序維持)。
        let entries = [GalleryImageMeta(name: "a.jpg", inSlideshow: true),
                       GalleryImageMeta(name: "b.jpg", inSlideshow: false),
                       GalleryImageMeta(name: "a.jpg", inSlideshow: false),
                       GalleryImageMeta(name: "b.jpg", inSlideshow: true)]
        let deduped = CustomImageService.dedupedByName(entries)
        XCTAssertEqual(deduped.map(\.name), ["a.jpg", "b.jpg"])
        // 最初の出現が残るので a の inSlideshow は true のまま。
        XCTAssertEqual(deduped.first?.inSlideshow, true)
    }

    func testDedupNoDuplicatesIsIdentity() {
        let entries = [GalleryImageMeta(name: "a.jpg"), GalleryImageMeta(name: "b.jpg")]
        XCTAssertEqual(CustomImageService.dedupedByName(entries), entries)
    }
}
