import Foundation
import os

/// 年表 (ブランド史) 画面の ViewModel。
///
/// ポートにだけ依存し、GRDB/AppDatabase を知らない。ズーム倍率やスクロール位置のような
/// 「見え方の状態」は View 側に置き、ここはデータ取得と選択ブランドだけを持つ。
@Observable
@MainActor
final class BrandTimelineViewModel {
    private let timelineReading: any TimelineReading
    private let brandReading: any BrandReading

    /// 表示順ソート済みのブランド。年表を持たないブランドは除く。
    private(set) var brands: [Brand] = []
    /// 現在選択中のブランドの帯。
    private(set) var bars: [TimelineBar] = []
    private(set) var isLoading = false

    /// nil = 全ブランド横断。
    private(set) var selectedBrandId: String?

    /// brandId → Brand。帯の色フォールバックとチップ表示に使う。
    private(set) var brandsById: [String: Brand] = [:]

    /// 初回ロード時に選ぶブランド (呼び出し元の文脈があるとき)。
    private let initialBrandId: String?

    nonisolated init(
        timelineReading: any TimelineReading = AppContainer.shared.timelineReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading,
        initialBrandId: String? = nil
    ) {
        self.timelineReading = timelineReading
        self.brandReading = brandReading
        self.initialBrandId = initialBrandId
    }

    /// 選択中ブランドの Brand (全ブランド表示なら nil)。
    var selectedBrand: Brand? {
        selectedBrandId.flatMap { brandsById[$0] }
    }

    /// 画面タイトル下に出すサマリ ("1,338公演 ・ 2,685曲" のような密度表示ではなく、
    /// 「いつからいつまでを見ているか」を示す)。
    var periodLabel: String? {
        guard let range = TimelineLayout.yearRange(of: bars, calendar: TimelineDateParser.calendar) else { return nil }
        return "\(range.lowerBound)年 〜 \(range.upperBound)年"
    }

    func loadIfNeeded() async {
        guard brands.isEmpty else { return }
        await load()
    }

    func select(brandId: String?) async {
        guard brandId != selectedBrandId else { return }
        selectedBrandId = brandId
        await loadBars()
    }

    private func load() async {
        do {
            let all = try await brandReading.brands()
            brandsById = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            // "other" は寄せ集めで年表として読めないので選択肢から外す (全ブランド表示には含む)。
            brands = all.filter { $0.id != "other" }
        } catch {
            Logger.database.error("load_failed timeline_brands: \(error.localizedDescription)")
        }
        // 初期表示は 1 ブランド。全ブランドは 20 年 × 全レーンで段数が多くなりすぎ、
        // 「最初の一目」で歴史を感じ取らせるという目的に対して情報過多になる。
        selectedBrandId = initialBrandId ?? brands.first?.id
        await loadBars()
    }

    private func loadBars() async {
        isLoading = true
        defer { isLoading = false }
        do {
            bars = try await timelineReading.timelineBars(brandId: selectedBrandId)
        } catch {
            Logger.database.error("load_failed timeline_bars: \(error.localizedDescription)")
            bars = []
        }
    }
}
