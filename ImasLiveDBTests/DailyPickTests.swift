import XCTest
@testable import ImasLiveDB

/// `DailyPick` の単体テスト。
///
/// 主目的は「アプリ内の日替わりピックとウィジェット用スナップショットが同じ曲を選ぶ」契約の固定。
/// 以前は日付キー・FNV-1a・種文字列が 2 か所にコピーされていて、片方だけ直すと
/// ウィジェットとアプリが黙って違う曲を出す状態だった。
final class DailyPickTests: XCTestCase {

    /// 端末ローカル日なので、テストも端末ローカルの成分から Date を組む
    /// (ここで固定 TZ を使うと「ローカル日である」ことを検証できない)。
    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    // MARK: - dayKey

    func testDayKeyIsZeroPadded() {
        XCTAssertEqual(DailyPick.dayKey(local(2026, 1, 9)), "2026-01-09")
    }

    /// 端末ローカルの日付をそのまま使う (JST 固定ではない)。
    /// `JSTDay` と用途が違うことをここで明示しておく。
    func testDayKeyFollowsDeviceCalendar() {
        let date = local(2026, 7, 26)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(
            DailyPick.dayKey(date),
            String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!))
    }

    /// 深夜 0 時直後と 23:59 は同じ日。
    func testDayKeyIsStableWithinTheSameLocalDay() {
        XCTAssertEqual(
            DailyPick.dayKey(local(2026, 7, 26, 0, 1)),
            DailyPick.dayKey(local(2026, 7, 26, 23, 59)))
    }

    // MARK: - previousDayKey

    func testPreviousDayKey() {
        XCTAssertEqual(DailyPick.previousDayKey(local(2026, 7, 26)), "2026-07-25")
    }

    /// 月またぎ / 年またぎ / うるう日でカレンダー任せの引き算になっている。
    func testPreviousDayKeyAcrossBoundaries() {
        XCTAssertEqual(DailyPick.previousDayKey(local(2026, 8, 1)), "2026-07-31")
        XCTAssertEqual(DailyPick.previousDayKey(local(2026, 1, 1)), "2025-12-31")
        XCTAssertEqual(DailyPick.previousDayKey(local(2028, 3, 1)), "2028-02-29")
    }

    // MARK: - stableIndex

    /// 同じ入力なら常に同じ値 (プロセスをまたいでも同じである必要がある)。
    /// Swift の `hashValue` は起動ごとに seed が変わるので使えない、という前提の確認。
    func testStableIndexIsDeterministic() {
        XCTAssertEqual(
            DailyPick.stableIndex("2026-07-26|cg", mod: 100),
            DailyPick.stableIndex("2026-07-26|cg", mod: 100))
    }

    /// 出荷済みの実装が出す既知値を固定する。
    ///
    /// ここが変わると全ユーザーの「今日の1曲」が一斉に入れ替わる。特に offset basis は
    /// 標準 FNV-1a (14695981039346656037) から 1 桁欠けた値のまま出荷されているので、
    /// 「定数が間違っている」と気づいた人が直したくなる。直すとこのテストが落ちる。
    /// 落ちたら実装ではなくこのテストの意図 (`DailyPick` のコメント) を先に読むこと。
    func testStableIndexMatchesShippedValues() {
        XCTAssertEqual(DailyPick.stableIndex("a", mod: 500), 366)
        XCTAssertEqual(DailyPick.stableIndex("", mod: 7), 3)
        XCTAssertEqual(DailyPick.stableIndex("2026-07-26|cg", mod: 500), 362)
    }

    func testStableIndexIsWithinRange() {
        for i in 0..<200 {
            let idx = DailyPick.stableIndex("2026-07-26|brand\(i)", mod: 13)
            XCTAssertTrue((0..<13).contains(idx), "範囲外: \(idx)")
        }
    }

    /// 候補 0 件でも落ちない (剰余のゼロ除算を踏まない)。
    func testStableIndexWithZeroModIsSafe() {
        XCTAssertEqual(DailyPick.stableIndex("x", mod: 0), 0)
        XCTAssertEqual(DailyPick.stableIndex("x", mod: -3), 0)
    }

    // MARK: - songIndex (アプリ ↔ ウィジェットの契約)

    /// 種文字列は `"日付|ブランドID"`。
    /// アプリ側とウィジェット側がこの組み立てを別々に持っていたのが元のバグ要因。
    func testSongIndexUsesDayPipeBrandSeed() {
        XCTAssertEqual(
            DailyPick.songIndex(dayKey: "2026-07-26", brandId: "cg", count: 50),
            DailyPick.stableIndex("2026-07-26|cg", mod: 50))
    }

    /// 日が変われば (基本的に) 選ぶ曲も変わる。日替わりとして機能していることの確認。
    func testSongIndexVariesByDay() {
        let a = DailyPick.songIndex(dayKey: "2026-07-26", brandId: "cg", count: 500)
        let b = DailyPick.songIndex(dayKey: "2026-07-27", brandId: "cg", count: 500)
        XCTAssertNotEqual(a, b)
    }

    /// 同じ日でもブランドが違えば別の曲を選ぶ (全ブランド同じ番号にならない)。
    func testSongIndexVariesByBrand() {
        let cg = DailyPick.songIndex(dayKey: "2026-07-26", brandId: "cg", count: 500)
        let ml = DailyPick.songIndex(dayKey: "2026-07-26", brandId: "ml", count: 500)
        XCTAssertNotEqual(cg, ml)
    }

    /// 候補が空でも 0 を返して落ちない。
    func testSongIndexWithNoCandidates() {
        XCTAssertEqual(DailyPick.songIndex(dayKey: "2026-07-26", brandId: "cg", count: 0), 0)
    }
}
