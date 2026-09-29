import XCTest
@testable import ImasLiveDB

/// 共有の文面と URL はコア (imas-core `share_text.rs`) が作り、そちらのテストが規則を持つ。
/// ここで見るのは、Swift の包み (`DeeplinkBuilder` / `SharePayload`) がコアを通っていることと、
/// コアが作ったリンクを Swift の `DeeplinkRouter` が読み戻せること。
final class SocialShareTests: XCTestCase {

    // MARK: - 包みのスモークテスト

    /// URL・投票の共有・シェアシートの本文が、どれもコアの答えそのものであること。
    func testShareWrappersReturnWhatTheCoreBuilds() throws {
        let showId = "sh_the_idolm@ster_20th_anniversary_2026_1"
        XCTAssertEqual(DeeplinkBuilder.showURL(id: showId).absoluteString, shareShowUrl(id: showId))
        XCTAssertEqual(DeeplinkBuilder.eventURL(id: "ev_1").absoluteString, shareEventUrl(id: "ev_1"))
        XCTAssertEqual(DeeplinkBuilder.pollURL(id: "p_1").absoluteString, sharePollUrl(id: "p_1"))

        let payload = sharePollVotesPayload(pollId: "p_1", pollTitle: "推しの1曲", entityNames: ["黛冬優子"])
        XCTAssertEqual(payload.url, sharePollUrl(id: "p_1"))
        XCTAssertTrue(sharePayloadPlainText(payload: payload).hasPrefix(payload.message))
        XCTAssertNotNil(URL(string: sharePayloadXPostUrl(payload: payload)))
    }

    // MARK: - リンクの読み戻し (DeeplinkRouter)

    func testParsePollCustomScheme() {
        let url = URL(string: "imaslivedb://polls/46987cdb-0bca")!
        XCTAssertEqual(DeeplinkRouter.parse(url), .poll(id: "46987cdb-0bca"))
    }

    func testUnknownKindIsIgnored() {
        XCTAssertNil(DeeplinkRouter.parse(URL(string: "imaslivedb://unknown/1")!))
    }

    /// ID に `@` を含む公演のリンクは、コアが `%40` にして作る。受け側 (pathComponents が
    /// percent-decode する) で元の ID に戻ること。
    func testEncodedShareURLRoundTripsToOriginalId() {
        let id = "sh_the_idolm@ster_20th_anniversary_2026_1"
        guard case .show(let parsed)? = DeeplinkRouter.parse(DeeplinkBuilder.showURL(id: id)) else {
            return XCTFail("show として解析できること")
        }
        XCTAssertEqual(parsed, id)
    }
}
