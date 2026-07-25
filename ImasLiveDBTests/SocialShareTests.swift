import XCTest
@testable import ImasLiveDB

/// 投票シェア (文面 / X intent URL) と、お題 deeplink の解析を検証する。
final class SocialShareTests: XCTestCase {

    // MARK: - 文面

    func testPredictionVotesMessage() {
        let message = ShareMessage.predictionVotes(
            showName: "MOIW2026 DAY1",
            songTitles: ["READY!!", "M@STERPIECE"]
        )
        XCTAssertEqual(
            message,
            "MOIW2026 DAY1 のセトリ予想で「READY!!」「M@STERPIECE」に投票しました！ #アイドルライブDB"
        )
    }

    func testPollVotesMessage() {
        let message = ShareMessage.pollVotes(
            pollTitle: "一緒にラーメンに行きたいアイドル",
            entityNames: ["黛冬優子"]
        )
        XCTAssertEqual(
            message,
            "お題「一緒にラーメンに行きたいアイドル」で「黛冬優子」に投票しました！ #アイドルライブDB"
        )
    }

    /// 締切なし (終了済みお題など) では締切文を足さない。
    func testPollInviteWithoutDeadline() {
        XCTAssertEqual(
            ShareMessage.pollInvite(title: "推しの1曲", endsAt: nil),
            "お題「推しの1曲」に投票しよう！ #アイドルライブDB"
        )
    }

    func testPollInviteWithDeadline() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 3
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let endsAt = calendar.date(from: components)!
        XCTAssertEqual(
            ShareMessage.pollInvite(title: "推しの1曲", endsAt: endsAt),
            "お題「推しの1曲」に投票しよう！ 締切は8月3日！ #アイドルライブDB"
        )
    }

    // MARK: - X intent URL

    /// 本文と URL は別クエリで渡す (X 側でリンクカードになる)。
    func testXPostURLCarriesMessageAndURL() throws {
        let payload = SocialSharePayload(
            message: "お題「推しの1曲」に投票しよう！ #アイドルライブDB",
            url: DeeplinkBuilder.pollURL(id: "abc-123")
        )
        let url = try XCTUnwrap(SocialShare.xPostURL(payload))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "x.com")
        XCTAssertEqual(components.path, "/intent/post")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "text" })?.value, payload.message)
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "url" })?.value,
            "https://imas-live-api.tokata3011.workers.dev/app/polls/abc-123"
        )
    }

    func testPlainTextJoinsMessageAndURL() {
        let payload = SocialSharePayload(
            message: "投票しました！",
            url: URL(string: "https://example.com/x")!
        )
        XCTAssertEqual(payload.plainText, "投票しました！\nhttps://example.com/x")
    }

    // MARK: - Deeplink

    func testParsePollUniversalLink() {
        let url = DeeplinkBuilder.pollURL(id: "46987cdb-0bca")
        XCTAssertEqual(DeeplinkRouter.parse(url), .poll(id: "46987cdb-0bca"))
    }

    func testParsePollCustomScheme() {
        let url = URL(string: "imaslivedb://polls/46987cdb-0bca")!
        XCTAssertEqual(DeeplinkRouter.parse(url), .poll(id: "46987cdb-0bca"))
    }

    /// 既存の events/shows はそのまま解釈できる (お題ケース追加の巻き添えがない)。
    func testParseShowLinkStillWorks() {
        XCTAssertEqual(
            DeeplinkRouter.parse(DeeplinkBuilder.showURL(id: "show_1")),
            .show(id: "show_1")
        )
    }

    func testUnknownKindIsIgnored() {
        XCTAssertNil(DeeplinkRouter.parse(URL(string: "imaslivedb://unknown/1")!))
    }
}
