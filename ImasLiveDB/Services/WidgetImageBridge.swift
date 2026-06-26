import Foundation
import WidgetKit

/// アイドルギャラリー画像を App Group コンテナへミラーし、担当画像ウィジェットへ供給する。
/// ウィジェット拡張はアプリの Documents を読めないため、対象画像とカタログ (名前/色) を
/// 共有コンテナへ書き出す。ギャラリー変更時・起動時に呼ぶ。
enum WidgetImageBridge {
    /// 現在のギャラリー全体を App Group へ同期する (全消し → コピー)。
    /// 画像枚数はユーザーの担当数 × 数枚程度なので全同期で十分。
    static func sync(database: AppDatabase) async {
        guard let imagesDir = WidgetShared.imagesDir,
              let catalogURL = WidgetShared.catalogURL else { return }

        // スライドショー対象に選ばれた画像だけをミラーする (未選択なら全件にフォールバック)。
        let sources: [(id: String, urls: [URL])] = await MainActor.run {
            let service = CustomImageService.shared
            return Array(service.idolsWithImages).map { ($0, service.slideshowURLs(for: $0)) }
        }
        let ids = sources.map { $0.id }

        // 名前・色・ブランドは DB から解決 (カタログ = AppIntent のアイドル選択肢に使う)。
        let idols = (try? database.fetchIdols(ids: ids)) ?? []
        let idolById = Dictionary(uniqueKeysWithValues: idols.map { ($0.id, $0) })
        let brands = (try? database.fetchBrands()) ?? []
        let brandById = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0) })

        // ピッカーで探しやすいよう、ブランド順 → アイドルの sort_order 順に並べる。
        func brand(of id: String) -> Brand? { idolById[id].flatMap { brandById[$0.brandId] } }
        let sortedSources = sources.sorted { a, b in
            let (ba, bb) = (brand(of: a.id)?.sortOrder ?? .max, brand(of: b.id)?.sortOrder ?? .max)
            if ba != bb { return ba < bb }
            return (idolById[a.id]?.sortOrder ?? .max) < (idolById[b.id]?.sortOrder ?? .max)
        }

        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            try? fm.removeItem(at: imagesDir)
            try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

            var entries: [OshiWidgetEntry] = []
            for src in sortedSources {
                guard !src.urls.isEmpty, let idol = idolById[src.id] else { continue }
                let dest = imagesDir.appendingPathComponent(src.id, isDirectory: true)
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
                var names: [String] = []
                for url in src.urls {
                    let name = url.lastPathComponent
                    try? fm.copyItem(at: url, to: dest.appendingPathComponent(name))
                    names.append(name)
                }
                let brandName = brandById[idol.brandId]?.shortName
                entries.append(OshiWidgetEntry(id: src.id, name: idol.name, colorHex: idol.color, images: names, brandName: brandName))
            }
            if let data = try? JSONEncoder().encode(OshiWidgetCatalog(idols: entries)) {
                try? data.write(to: catalogURL)
            }
        }.value

        WidgetCenter.shared.reloadAllTimelines()
    }
}
