import Foundation
import os

/// MyPageView のデータ取得担当。
///
/// 役割分担:
/// - **VM (ここ)**: ポート越しの診断値 (`diagnosticsReading`)・ブランド・担当アイドル取得と、
///   画像一括インポート用の型紙ファイル生成。
/// - **View 側**: `@AppStorage` の各設定、シート/アラート等の UI 状態、通知権限、
///   バックアップ/引き継ぎコードの操作、CloudKit の debug probe。
///   担当テーマ色は `@AppStorage` を書くので View 側に残す (計算規則は `resolveOshiTheme`)。
///
/// CloudKit 同期エンジンは方針としてポート化しない (docs/ARCHITECTURE.md「現実的判断」) ため、
/// probe は View に置き、その後の診断値の取り直しだけ `refreshSyncDiagnostics()` で受ける。
@MainActor
@Observable
final class MyPageViewModel {
    private(set) var schemaVersion: String = "..."
    private(set) var dataVersion: String = "..."
    private(set) var dbStats: DatabaseStats?
    private(set) var syncDiagnostics: SyncDiagnostics?
    private(set) var brands: [Brand] = []
    /// 「担当」としてマークされているアイドル。テーマ色の選択肢にもなる。
    private(set) var pickIdols: [Idol] = []

    private(set) var idolTemplateURL: URL?
    private(set) var brandTemplateURL: URL?
    private(set) var unitTemplateURL: URL?

    private let diagnosticsReading: any DiagnosticsReading
    private let brandReading: any BrandReading
    private let idolReading: any IdolReading
    private let markReading: any MarkReading
    private let unitReading: any UnitReading

    nonisolated init(
        diagnosticsReading: any DiagnosticsReading = AppContainer.shared.diagnosticsReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading,
        idolReading: any IdolReading = AppContainer.shared.idolReading,
        markReading: any MarkReading = AppContainer.shared.markReading,
        unitReading: any UnitReading = AppContainer.shared.unitReading
    ) {
        self.diagnosticsReading = diagnosticsReading
        self.brandReading = brandReading
        self.idolReading = idolReading
        self.markReading = markReading
        self.unitReading = unitReading
    }

    /// 画面表示に必要な値を一括で読む。失敗しても画面は開けるようにログだけ残す
    /// (設定画面が DB エラーで真っ白になる方が困る)。
    func load() async {
        do {
            schemaVersion = try await diagnosticsReading.metaValue(forKey: "schema_version") ?? "不明"
            dataVersion = try await diagnosticsReading.metaValue(forKey: "data_version") ?? "不明"
            dbStats = try await diagnosticsReading.databaseStats()
            syncDiagnostics = try await diagnosticsReading.syncDiagnostics()
            brands = try await brandReading.brands()
            let pickIds = try await markReading.markedEntityIds(entity: .idol, kind: .myPick)
            pickIdols = try await idolReading.idols(ids: pickIds)
        } catch {
            Logger.database.error("load_failed settings: \(error.localizedDescription)")
        }

        await regenerateImportTemplates()
    }

    /// CloudKit probe 後など、同期診断だけ取り直したいとき用。
    func refreshSyncDiagnostics() async {
        syncDiagnostics = try? await diagnosticsReading.syncDiagnostics()
    }

    /// 画像一括インポート用の型紙 JSON を一時ファイルに書き出す。
    private func regenerateImportTemplates() async {
        do {
            let idols = try await idolReading.idols(brandId: nil)
            idolTemplateURL = try Self.writeJSONTemplate(
                pairs: idols.map { ($0.name, "") },
                fileName: "idol_images_template.json"
            )

            brandTemplateURL = try Self.writeJSONTemplate(
                pairs: brands.map { ($0.shortName, "") },
                fileName: "brand_images_template.json"
            )

            // ユニットは常設のみ。 公演ごとの臨時ユニット (「〇〇 + 〇〇」等) まで並べると
            // 型紙が数百行になり、 アイコンを用意したい常設ユニットが埋もれる。
            let units = try await unitReading.unitIndex().units
            unitTemplateURL = try Self.writeJSONTemplate(
                pairs: units.filter(\.isPermanent).map { ($0.name, "") },
                fileName: "unit_images_template.json"
            )
        } catch {
            Logger.database.error("template_generation_failed: \(error.localizedDescription)")
        }
    }

    /// 型紙 JSON を一時ファイルへ。JSON の組み立て・エスケープは
    /// `imageTemplateJSON` (Domain/UseCases) 側でテスト済み。
    private static func writeJSONTemplate(pairs: [(String, String)], fileName: String) throws -> URL {
        let json = imageTemplateJSON(pairs: pairs)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try json.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
