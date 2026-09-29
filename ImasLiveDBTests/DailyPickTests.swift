import XCTest
@testable import ImasLiveDB

/// `DailyPick` の単体テスト。
///
/// 主目的は「アプリ内の日替わりピックとウィジェット用スナップショットが同じ曲を選ぶ」契約の固定。
/// 以前は日付キー・FNV-1a・種文字列が 2 か所にコピーされていて、片方だけ直すと
/// ウィジェットとアプリが黙って違う曲を出す状態だった。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class DailyPickTests: XCTestCase {

    /// 端末ローカル日なので、テストも端末ローカルの成分から Date を組む
    /// (ここで固定 TZ を使うと「ローカル日である」ことを検証できない)。
    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    // MARK: - dayKey

    /// 端末ローカルの日付をそのまま使う (JST 固定ではない)。
    /// `JSTDay` と用途が違うことをここで明示しておく。
    func testDayKeyFollowsDeviceCalendar() {
        let date = local(2026, 7, 26)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(
            DailyPick.dayKey(date),
            String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!))
    }

    // MARK: - previousDayKey

    /// 月またぎ / 年またぎ / うるう日でカレンダー任せの引き算になっている。
    func testPreviousDayKeyAcrossBoundaries() {
        XCTAssertEqual(DailyPick.previousDayKey(local(2026, 8, 1)), "2026-07-31")
        XCTAssertEqual(DailyPick.previousDayKey(local(2026, 1, 1)), "2025-12-31")
        XCTAssertEqual(DailyPick.previousDayKey(local(2028, 3, 1)), "2028-02-29")
    }

    // MARK: - stableIndex

    // MARK: - songIndex (アプリ ↔ ウィジェットの契約)

    /// 一括版 (アプリの日替わり投票が使う) はスカラー版 (ウィジェットが使う) と
    /// 必ず同じ答えを出す。順序も入力と同じ。ここが割れると再び別々の曲を出す。
    func testSongIndicesMatchScalarSongIndex() {
        let brands: [(brandId: String, count: Int)] = [("cg", 500), ("ml", 321), ("sc", 1), ("empty", 0)]
        XCTAssertEqual(
            DailyPick.songIndices(dayKey: "2026-07-26", brands: brands),
            brands.map { DailyPick.songIndex(dayKey: "2026-07-26", brandId: $0.brandId, count: $0.count) })
    }
}
