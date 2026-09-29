import Foundation
import os

/// MyPageView のデータ取得担当。
///
/// 役割分担:
/// - **VM (ここ)**: ポート越しの診断値 (`diagnosticsReading`)・ブランド・担当アイドル取得と、
///   画像一括インポート用の型紙ファイル生成。
/// - **View 側**: `@AppStorage` の各設定、シート/アラート等の UI 状態、通知権限、
///   バックアップ/引き継ぎコードの操作。
///   担当テーマ色は `@AppStorage` を書くので View 側に残す (計算規則は `resolveOshiTheme`)。
@MainActor
@Observable
final class MyPageViewModel {
    private(set) var schemaVersion: String = "..."
    private(set) var dataVersion: String = "..."
    private(set) var dbStats: DatabaseStats?
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

    /// 画面表示に必要な値を読む。失敗しても画面は開けるようにログだけ残す
    /// (設定画面が DB エラーで真っ白になる方が困る)。
    ///
    /// 診断の値と、ブランド・担当は別々に読む。以前は 1 つの do にまとめていて、
    /// 診断を読み損ねると、テーマ色の選択肢になるブランドと担当まで読めなくなった。
    func load() async {
        do {
            schemaVersion = try await diagnosticsReading.metaValue(forKey: "schema_version") ?? "不明"
            dataVersion = try await diagnosticsReading.metaValue(forKey: "data_version") ?? "不明"
            dbStats = try await diagnosticsReading.databaseStats()
        } catch {
            Logger.database.error("load_failed settings_diagnostics: \(error.localizedDescription)")
        }
        do {
            brands = try await brandReading.brands()
            let pickIds = try await markReading.markedEntityIds(entity: .idol, kind: .myPick)
            pickIdols = try await idolReading.idols(ids: pickIds)
        } catch {
            Logger.database.error("load_failed settings: \(error.localizedDescription)")
        }

        await regenerateImportTemplates()
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
