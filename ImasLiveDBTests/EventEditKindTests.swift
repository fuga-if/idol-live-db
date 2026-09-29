import XCTest
@testable import ImasLiveDB

final class EventEditKindTests: XCTestCase {
    func testUnknownKindIsSentBackUnchangedUnlessReselected() {
        XCTAssertEqual(EventEditView.kindToSend(selected: .other, unlistedRaw: "future_kind"), "future_kind")
        XCTAssertEqual(EventEditView.kindToSend(selected: .live, unlistedRaw: "future_kind"), "live")
        XCTAssertEqual(EventEditView.kindToSend(selected: .festival, unlistedRaw: nil), "festival")
    }
}
