import Foundation
import Observation
import UIKit

@Observable @MainActor
final class BulkImageImporter {
    var isImporting = false
    var progress: Double = 0
    var statusMessage = ""
    var importedCount = 0
    var failedCount = 0
    /// 失敗内訳 (キー名, 理由)。最後のインポートのみ保持。
    var failures: [Failure] = []

    struct Failure: Identifiable, Equatable {
        var id: String { key }
        let key: String
        let reason: String
    }

    private let imageService = CustomImageService.shared

    /// ブランド画像 JSON を取得し、各ブランドの画像を Documents/custom_images_brands/{brandId}.jpg に保存。
    /// JSON 形式: { "ブランド名 or short_name or brand_id": "https://画像URL" }
    func importBrandImagesFromURL(_ urlString: String, database: AppDatabase) async {
        await runImport(
            urlString: urlString,
            label: "ブランド",
            run: { _ in
                let brands = try database.fetchBrands()
                var nameToId: [String: String] = [:]
                func register(_ key: String, _ id: String) {
                    nameToId[key] = id
                    nameToId[Self.normalizeName(key)] = id
                }
                for brand in brands {
                    register(brand.id, brand.id)
                    register(brand.name, brand.id)
                    register(brand.shortName, brand.id)
                }
                return (nameToId, { id, image in
                    try await self.imageService.saveBrandImage(image, for: id)
                })
            }
        )
    }

    /// アイドル画像 JSON を取得して一括ダウンロード。既存画像は上書きする。
    func importFromURL(_ urlString: String, database: AppDatabase) async {
        await runImport(
            urlString: urlString,
            label: "アイドル",
            run: { _ in
                let idols = try database.fetchIdols()
                var nameToId: [String: String] = [:]
                func register(_ key: String, _ id: String) {
                    nameToId[key] = id
                    nameToId[Self.normalizeName(key)] = id
                }
                for idol in idols {
                    register(idol.name, idol.id)
                    if let kana = idol.nameKana { register(kana, idol.id) }
                    if let nick = idol.nickname { register(nick, idol.id) }
                    for alias in idol.aliasList {
                        register(alias, idol.id)
                    }
                }
                return (nameToId, { id, image in
                    try await self.imageService.saveImage(image, for: id)
                })
            }
        )
    }

    /// アイドル/ブランドカスタム画像をすべて削除。
    func clearAllImages() async {
        do {
            try await imageService.clearAllIdolImages()
            try await imageService.clearAllBrandImages()
            statusMessage = "カスタム画像を全削除しました"
            failures = []
            importedCount = 0
            failedCount = 0
        } catch {
            statusMessage = "削除エラー: \(error.localizedDescription)"
        }
    }

    /// 名前マッチングのゆらぎ吸収:
    /// - NFKC 正規化 (全角/半角・互換等価字 ＝→= Ⅱ→II 等)
    /// - 空白 (ASCII / 全角) と一般的な区切り (・ ／ /) を除去
    /// - 小文字化
    nonisolated private static func normalizeName(_ s: String) -> String {
        let nfkc = s.precomposedStringWithCompatibilityMapping
        let stripped = nfkc.unicodeScalars.filter { sc in
            // 区切り類は落とす
            if sc == " " || sc == "　" || sc == "・" || sc == "/" || sc == "／" || sc == "=" || sc == "＝" {
                return false
            }
            return true
        }
        return String(String.UnicodeScalarView(stripped)).lowercased()
    }

    // MARK: - Private

    private func runImport(
        urlString: String,
        label: String,
        run: @escaping ([String: String]) async throws -> (nameToId: [String: String], save: @MainActor (String, UIImage) async throws -> Void)
    ) async {
        guard let url = URL(string: urlString) else {
            statusMessage = "無効なURLです"
            return
        }

        isImporting = true
        progress = 0
        importedCount = 0
        failedCount = 0
        failures = []
        statusMessage = "データ取得中..."

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let mapping = try? JSONDecoder().decode([String: String].self, from: data) else {
                statusMessage = "JSONの形式が正しくありません"
                isImporting = false
                return
            }

            let (nameToId, save) = try await run(mapping)

            let total = mapping.count
            var current = 0
            for (key, imageURLString) in mapping {
                current += 1
                progress = Double(current) / Double(total)

                let trimmed = imageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    // 空 URL はスキップ (型紙そのまま埋めずアップしたケース) — failure 扱いにしない
                    continue
                }

                let normalizedKey = Self.normalizeName(key)
                guard let id = nameToId[key] ?? nameToId[normalizedKey] else {
                    failedCount += 1
                    failures.append(Failure(key: key, reason: "\(label) ID が見つからない"))
                    continue
                }

                guard let imageURL = URL(string: trimmed) else {
                    failedCount += 1
                    failures.append(Failure(key: key, reason: "URL が不正"))
                    continue
                }

                do {
                    let (imageData, response) = try await URLSession.shared.data(from: imageURL)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        failedCount += 1
                        failures.append(Failure(key: key, reason: "HTTP \(http.statusCode)"))
                        continue
                    }
                    guard let image = UIImage(data: imageData) else {
                        failedCount += 1
                        failures.append(Failure(key: key, reason: "画像デコード失敗"))
                        continue
                    }
                    try await save(id, image)
                    importedCount += 1
                    statusMessage = "\(importedCount)/\(total) ダウンロード中..."
                } catch {
                    failedCount += 1
                    failures.append(Failure(key: key, reason: error.localizedDescription))
                }

                try? await Task.sleep(for: .milliseconds(100))
            }

            statusMessage = "完了: \(importedCount)件成功, \(failedCount)件失敗"
        } catch {
            statusMessage = "エラー: \(error.localizedDescription)"
        }

        isImporting = false
    }
}
