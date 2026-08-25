import XCTest

/// 実機で報告された「ライブ一覧で検索してスクロールすると固まる」を自動再現する。
/// 固まった時点でテストは待機し続けるので、別シェルから `sample` でスタックを採る。
final class EventListFreezeUITests: XCTestCase {

    func testSearchThenScrollDoesNotFreeze() throws {
        let app = XCUIApplication()
        app.launch()

        // お知らせシートが出ていたら閉じる
        let close = app.buttons["閉じる"]
        if close.waitForExistence(timeout: 10) { close.tap() }

        // ライブタブへ
        let liveTab = app.buttons["ライブ"].firstMatch
        XCTAssertTrue(liveTab.waitForExistence(timeout: 15), "ライブタブが見つからない")
        liveTab.tap()

        // 検索欄に「初」
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "検索欄が見つからない")
        field.tap()
        field.typeText("初")
        sleep(2)

        // スクロール (何度か)
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "スクロールビューが見つからない")
        for i in 0..<8 {
            scroll.swipeUp(velocity: .fast)
            print("UIPROBE swipe \(i) done")
            usleep(300_000)
        }
        for i in 0..<4 {
            scroll.swipeDown(velocity: .fast)
            print("UIPROBE swipeDown \(i) done")
            usleep(300_000)
        }
        print("UIPROBE finished without freeze")
    }
}
