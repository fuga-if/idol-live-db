import XCTest
@testable import ImasLiveDB

/// 担当ブランド (アプリ全体の設定) の保存とバックアップ。段・既定・保存の形の規則はコアのテストが持つので、
/// ここは端末の設定への読み書きとバックアップの経路だけを見る。
@MainActor
final class BrandRoleStoreTests: XCTestCase {
    private var saved: (json: String?, prompted: Bool)!

    override func setUp() async throws {
        saved = (UserDefaults.standard.string(forKey: BrandRoleStore.key),
                 UserDefaults.standard.bool(forKey: BrandRoleStore.promptedKey))
        clear()
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(saved.json, forKey: BrandRoleStore.key)
        UserDefaults.standard.set(saved.prompted, forKey: BrandRoleStore.promptedKey)
    }

    private func clear() {
        UserDefaults.standard.removeObject(forKey: BrandRoleStore.key)
        UserDefaults.standard.removeObject(forKey: BrandRoleStore.promptedKey)
    }

    private func row(_ id: String, _ role: BrandRole) -> BrandRoleRow {
        BrandRoleRow(brandId: id, label: id, color: nil, role: role)
    }

    /// スライダーの段の番号と段は行って戻る (端は寄せる)。
    func testStepIndexRoundTrips() {
        for step in brandRoleSteps() {
            XCTAssertEqual(brandRoleFromIndex(index: Int64(step.index)), step.role)
        }
        XCTAssertEqual(brandRoleSteps().map(\.label), ["なし", "担当", "メイン"])
        XCTAssertEqual(brandRoleFromIndex(index: 7), .main)
    }

    func testSaveMarksConfiguredAndPrompted() {
        XCTAssertFalse(BrandRoleStore.isConfigured)
        XCTAssertTrue(BrandRoleStore.shouldPrompt)
        BrandRoleStore.save([row("765", .main), row("ml", .main), row("cg", .oshi), row("sc", .none)])
        XCTAssertTrue(BrandRoleStore.isConfigured)
        XCTAssertFalse(BrandRoleStore.shouldPrompt)
        let record = BrandRoleRecord(
            today: "2026-10-06",
            brands: ["765", "cg", "ml", "sc"].enumerated().map {
                BrandRoleBrand(id: $1, label: $1, color: nil, sortOrder: Int64($0))
            },
            oshiBrandIds: [], visits: [])
        let settings = brandRoleSettings(json: BrandRoleStore.json, record: record)
        XCTAssertEqual(settings.rows.map(\.role), [.main, .oshi, .main, .none], "メインは複数")

        // 飛ばしただけなら決めていない (既定のまま) が、もう案内しない。
        clear()
        BrandRoleStore.markPrompted()
        XCTAssertFalse(BrandRoleStore.isConfigured)
        XCTAssertFalse(BrandRoleStore.shouldPrompt)
    }

    /// バックアップで運び、まだ決めていない端末にだけ戻す。
    func testBackupCarriesBrandRolesIntoAnUnsetDevice() throws {
        let db = try AppDatabase(dbQueue: makeMigratedDatabase())
        BrandRoleStore.save([row("765", .main), row("cg", .oshi)])
        let json = try BackupExportImportService.buildEnvelopeJSON(database: db)
        let exported = BrandRoleStore.json

        clear()
        _ = try BackupExportImportService.importEnvelopeJSON(json, database: db, restoreDeviceId: false)
        XCTAssertEqual(BrandRoleStore.json, exported)

        // 端末で決め直していれば戻さない。
        BrandRoleStore.save([row("sc", .main)])
        let mine = BrandRoleStore.json
        _ = try BackupExportImportService.importEnvelopeJSON(json, database: db, restoreDeviceId: false)
        XCTAssertEqual(BrandRoleStore.json, mine)
    }
}
