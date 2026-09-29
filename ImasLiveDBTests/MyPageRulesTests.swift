import XCTest
@testable import ImasLiveDB

/// マイページに埋まっていた純粋ロジックの単体テスト。
/// 担当テーマ色の解決 / バックアップ復元の文面 / 画像型紙 JSON の 3 つ。DB・UI に依存しない。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class MyPageRulesTests: XCTestCase {

    private func makeIdol(_ id: String, color: String? = nil) -> Idol {
        Idol(
            id: id, brandId: "cg", name: id, nameKana: nil,
            nameRomaji: nil, familyName: nil, givenName: nil, nickname: nil, color: color,
            sortOrder: 0, birthday: nil, bloodType: nil, height: nil, weight: nil,
            birthPlace: nil, age: nil, bust: nil, waist: nil, hip: nil, constellation: nil,
            hobbies: nil, talents: nil, description: nil, gender: nil, handedness: nil,
            debutDate: nil, attribute: nil, aliases: nil)
    }

    // MARK: - resolveOshiTheme

    /// 選択中の担当を解除したら先頭に寄せる (テーマ色だけ残り続けるのを防ぐ)。
    func testSelectionNoLongerPickedFallsBackToFirst() {
        let result = resolveOshiTheme(
            isEnabled: true, currentIdolId: "removed",
            picks: [makeIdol("a", color: "#FF0000")])
        XCTAssertEqual(result.idolId, "a")
        XCTAssertEqual(result.colorHex, "#FF0000")
    }

    // MARK: - backupImportSummary

    func testSummaryIncludesSkippedAndDeviceId() {
        let s = backupImportSummary(
            addedMarks: 1, addedVotes: 1, addedPersonalTags: 2, addedExpenses: 0,
            skippedMarks: 4, deviceIdRestored: true)
        XCTAssertEqual(s, """
            担当/お気に入り等を 1 件、投票履歴を 1 件 追加しました。
            マイタグを 2 件 追加しました。
            (4 件は形式不正のためスキップされました)
            端末IDも復元しました。
            """)
    }

    // MARK: - imageTemplateJSON

    /// 名前に " や \ が入っても壊れない (手書きエスケープではなく JSONSerialization 任せ)。
    func testTemplateEscapesQuotesAndBackslashes() throws {
        let json = imageTemplateJSON(pairs: [("a\"b\\c", "")])
        let obj = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: String]
        XCTAssertEqual(obj?.keys.first, "a\"b\\c")
    }
}
