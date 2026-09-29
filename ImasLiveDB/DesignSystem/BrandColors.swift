import Foundation
import os

/// ブランド ID → マスタ (`brands.color`) の色 hex。
///
/// 以前は ID → 色の表を Swift に手書きしていた (Android にも同じ表があった)。表は OS に
/// 持たず、スナップショットのブランドから引いて覚える。描画から同期で呼ぶので、
/// スナップショットがまだ無い間は nil (= ニュートラル) を返し、覚えない。
/// 色からテーマへの導き方 (アイドル色 → ブランド色 → ニュートラル) はコアの `themeDerive`。
enum BrandColors {
    private static let cache = OSAllocatedUnfairLock<[String: String]?>(initialState: nil)

    /// スナップショットを読み直したら (同期でブランドの色が変わりうる) 表を捨てる。
    /// 起動時に 1 回呼ぶ。
    static func startObservingReloads() {
        NotificationCenter.default.addObserver(
            forName: .coreSnapshotDidLoad, object: nil, queue: nil
        ) { _ in
            cache.withLock { $0 = nil }
        }
    }

    /// そのブランドの色 hex。未知の ID・色の無いブランド・nil は nil。
    static func hex(for brandId: String?) -> String? {
        guard let brandId else { return nil }
        return table()?[brandId]
    }

    private static func table() -> [String: String]? {
        if let table = cache.withLock({ $0 }) { return table }
        guard let store = AppContainer.shared.coreSnapshot.storeIfReady(),
              let records = try? store.brandRecords() else { return nil }
        let table = Dictionary(
            records.compactMap { record in record.color.map { (record.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        cache.withLock { $0 = table }
        return table
    }
}
