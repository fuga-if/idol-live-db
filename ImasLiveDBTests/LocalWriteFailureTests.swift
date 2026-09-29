import XCTest
@testable import ImasLiveDB

/// 端末にしか無いデータの書き込み失敗の知らせ (`LocalWriteFailure`)。
///
/// 出し方 (UIKit のアラート) は差し替えて、失敗が知らせの口まで届くことと文面を見る。
@MainActor
final class LocalWriteFailureTests: XCTestCase {

    /// アプリの起動で、知らせの出し方が差し込まれている (差し忘れるとログにしか残らない)。
    func testAppInstallsThePresenterAtLaunch() {
        XCTAssertNotNil(LocalWriteFailure.presenter)
    }

    func testReportHandsTheNoticeForTheActionToThePresenter() {
        let original = LocalWriteFailure.presenter
        defer { LocalWriteFailure.presenter = original }
        var received: [LocalWriteFailure.Notice] = []
        LocalWriteFailure.presenter = { received.append($0) }

        LocalWriteFailure.report(NSError(domain: "test", code: 1), action: "メモの保存")

        XCTAssertEqual(received.map(\.title), ["保存できませんでした"])
        XCTAssertEqual(
            received.map(\.message),
            ["メモの保存に失敗しました。変更は保存されていません。もう一度お試しください。"])
    }
}
