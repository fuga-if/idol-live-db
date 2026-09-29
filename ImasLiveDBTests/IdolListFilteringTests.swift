import XCTest
@testable import ImasLiveDB

/// `filterIdols` (純粋ロジック) の単体テスト。DB に依存しない。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class IdolListFilteringTests: XCTestCase {

    private func makeIdol(_ id: String, name: String = "", brandId: String = "cg",
                          nameKana: String? = nil, attribute: String? = nil,
                          aliases: String? = nil, nickname: String? = nil) -> Idol {
        Idol(
            id: id, brandId: brandId, name: name.isEmpty ? id : name, nameKana: nameKana,
            nameRomaji: nil, familyName: nil, givenName: nil, nickname: nickname, color: nil,
            sortOrder: 0, birthday: nil, bloodType: nil, height: nil, weight: nil,
            birthPlace: nil, age: nil, bust: nil, waist: nil, hip: nil, constellation: nil,
            hobbies: nil, talents: nil, description: nil, gender: nil, handedness: nil,
            debutDate: nil, attribute: attribute, aliases: aliases)
    }

    /// 検索欄の語は `searchTarget` の側にだけ当たる (名前と CV 名を混ぜない)。
    func testSearchTargetSelectsNameOrCastName() {
        let idols = [makeIdol("a", name: "島村卯月"), makeIdol("b", name: "渋谷凛")]
        var ctx = IdolFilterContext()
        ctx.searchText = "大橋" // 名前には無いがキャスト名で一致
        ctx.castNames = ["a": "大橋彩香", "b": "福原綾香"]
        XCTAssertTrue(filterIdols(idols, ctx).isEmpty, "既定 (アイドル名) では CV 名に当てない")

        ctx.searchTarget = .voiceActor
        XCTAssertEqual(filterIdols(idols, ctx).map(\.id), ["a"])

        ctx.searchText = "島村"
        XCTAssertTrue(filterIdols(idols, ctx).isEmpty, "CV 名の検索ではアイドル名に当てない")

        let counts = idolSearchCounts(idols, ctx)
        XCTAssertEqual(counts.name, 1)
        XCTAssertEqual(counts.voiceActor, 0)
    }

    /// 表示名を短くしたアイドルを、別名 (フルネーム) でも引けること。
    /// レトラは表示名を「レトラ」に縮め、「サラ・レトラ・オリヴェイラ・ウタガワ」を
    /// aliases に退避した。検索が name しか見ていないとフルネームで辿れなくなる。
    func testSearchMatchesAlias() {
        let idols = [
            makeIdol("retla", name: "レトラ", nameKana: "れとら",
                     aliases: "サラ・レトラ・オリヴェイラ・ウタガワ,さら・れとら・おりゔぇいら・うたがわ"),
            makeIdol("other", name: "渋谷凛"),
        ]
        var ctx = IdolFilterContext()

        ctx.searchText = "オリヴェイラ"
        XCTAssertEqual(filterIdols(idols, ctx).map(\.id), ["retla"], "別名の一部で引けること")

        ctx.searchText = "おりゔぇいら"
        XCTAssertEqual(filterIdols(idols, ctx).map(\.id), ["retla"], "別名のよみでも引けること")

        ctx.searchText = "レトラ"
        XCTAssertEqual(filterIdols(idols, ctx).map(\.id), ["retla"], "表示名でも従来どおり引けること")
    }
}
