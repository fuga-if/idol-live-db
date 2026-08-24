import XCTest
@testable import ImasLiveDB

/// マイページに埋まっていた純粋ロジックの単体テスト。
/// 担当テーマ色の解決 / バックアップ復元の文面 / 画像型紙 JSON の 3 つ。DB・UI に依存しない。
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

    /// OFF のときは色だけ消し、選んだ担当は残す (ON に戻したとき選び直しにならないように)。
    func testDisabledClearsColorButKeepsSelection() {
        let result = resolveOshiTheme(
            isEnabled: false, currentIdolId: "a", picks: [makeIdol("a", color: "#FF0000")])
        XCTAssertNil(result.idolId, "OFF では担当 ID を書き換えない")
        XCTAssertEqual(result.colorHex, "")
    }

    func testEnabledUsesSelectedIdolColor() {
        let result = resolveOshiTheme(
            isEnabled: true, currentIdolId: "b",
            picks: [makeIdol("a", color: "#FF0000"), makeIdol("b", color: "#00FF00")])
        XCTAssertEqual(result.idolId, "b")
        XCTAssertEqual(result.colorHex, "#00FF00")
    }

    /// 未選択なら先頭の担当を既定にする。
    func testEmptySelectionFallsBackToFirstPick() {
        let result = resolveOshiTheme(
            isEnabled: true, currentIdolId: "",
            picks: [makeIdol("a", color: "#FF0000"), makeIdol("b", color: "#00FF00")])
        XCTAssertEqual(result.idolId, "a")
        XCTAssertEqual(result.colorHex, "#FF0000")
    }

    /// 選択中の担当を解除したら先頭に寄せる (テーマ色だけ残り続けるのを防ぐ)。
    func testSelectionNoLongerPickedFallsBackToFirst() {
        let result = resolveOshiTheme(
            isEnabled: true, currentIdolId: "removed",
            picks: [makeIdol("a", color: "#FF0000")])
        XCTAssertEqual(result.idolId, "a")
        XCTAssertEqual(result.colorHex, "#FF0000")
    }

    /// 担当が 0 人なら空にする (クラッシュも既定値の捏造もしない)。
    func testNoPicksResultsInEmpty() {
        let result = resolveOshiTheme(isEnabled: true, currentIdolId: "a", picks: [])
        XCTAssertEqual(result.idolId, "")
        XCTAssertEqual(result.colorHex, "")
    }

    /// 色が未設定の担当を選んでいる場合は空 (nil を "nil" 等に文字列化しない)。
    func testPickWithoutColorResultsInEmptyHex() {
        let result = resolveOshiTheme(
            isEnabled: true, currentIdolId: "a", picks: [makeIdol("a", color: nil)])
        XCTAssertEqual(result.idolId, "a")
        XCTAssertEqual(result.colorHex, "")
    }

    // MARK: - backupImportSummary

    /// 0 件の項目は文面に出さない (ノイズを増やさない)。
    func testSummaryOmitsZeroSections() {
        let s = backupImportSummary(
            addedMarks: 3, addedVotes: 2, addedPersonalTags: 0,
            skippedMarks: 0, deviceIdRestored: false)
        XCTAssertEqual(s, "担当/お気に入り等を 3 件、投票履歴を 2 件 追加しました。")
    }

    func testSummaryIncludesPersonalTagsWhenPresent() {
        let s = backupImportSummary(
            addedMarks: 1, addedVotes: 0, addedPersonalTags: 5,
            skippedMarks: 0, deviceIdRestored: false)
        XCTAssertTrue(s.contains("マイタグを 5 件 追加しました。"))
    }

    func testSummaryIncludesSkippedAndDeviceId() {
        let s = backupImportSummary(
            addedMarks: 1, addedVotes: 1, addedPersonalTags: 2,
            skippedMarks: 4, deviceIdRestored: true)
        XCTAssertEqual(s, """
            担当/お気に入り等を 1 件、投票履歴を 1 件 追加しました。
            マイタグを 2 件 追加しました。
            (4 件は形式不正のためスキップされました)
            端末IDも復元しました。
            """)
    }

    /// 全部 0 でも「何も入らなかった」ことが分かる文面になる。
    func testSummaryWithNothingImported() {
        let s = backupImportSummary(
            addedMarks: 0, addedVotes: 0, addedPersonalTags: 0,
            skippedMarks: 0, deviceIdRestored: false)
        XCTAssertEqual(s, "担当/お気に入り等を 0 件、投票履歴を 0 件 追加しました。")
    }

    // MARK: - imageTemplateJSON

    func testTemplateIsValidJSONAndKeepsOrder() {
        let json = imageTemplateJSON(pairs: [("あ", ""), ("い", ""), ("う", "")])
        let data = json.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        // 並びは一覧の順のまま (数百行から目的の名前を探せるように)
        let keyOrder = json.split(separator: "\n").dropFirst().dropLast().map { line in
            String(line.split(separator: ":")[0]).trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(keyOrder, ["\"あ\"", "\"い\"", "\"う\""])
    }

    /// 名前に " や \ が入っても壊れない (手書きエスケープではなく JSONSerialization 任せ)。
    func testTemplateEscapesQuotesAndBackslashes() throws {
        let json = imageTemplateJSON(pairs: [("a\"b\\c", "")])
        let obj = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: String]
        XCTAssertEqual(obj?.keys.first, "a\"b\\c")
    }

    func testTemplateWithEmptyPairsIsStillValidJSON() throws {
        let json = imageTemplateJSON(pairs: [])
        let obj = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: String]
        XCTAssertEqual(obj, [:])
    }

    func testTemplateKeepsFilledValues() throws {
        let json = imageTemplateJSON(pairs: [("名前", "https://example.com/a.png")])
        let obj = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: String]
        XCTAssertEqual(obj?["名前"], "https://example.com/a.png")
    }
}
