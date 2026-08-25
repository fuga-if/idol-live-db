import Foundation

/// `TimelineReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則)。
struct CoreTimelineRepository: TimelineReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時の受け皿 (Strangler の旧経路)。
    let fallback: GRDBTimelineRepository

    func timelineBars(brandId: String?) async throws -> [TimelineBar] {
        try await snapshot.withStore(fallbackTo: { try await fallback.timelineBars(brandId: brandId) }) { store in
            try store.timelineBars(brandId: brandId).map { record in
                let bar = CoreRecordMapping.timelineBar(from: record)
                // イベント帯のラベルだけ表示用の作品名省略を掛け直す。
                // core は events.name の正式名称のまま返す (省略の可否は UserDefaults 設定に
                // 依存し、共有コアからは読めないため)。GRDB 経路はフェッチ時に掛けていたので、
                // ここで揃えないと年表のイベント名だけフル表記に戻る回帰になる。
                guard case .event = bar.target else { return bar }
                return TimelineBar(
                    id: bar.id,
                    lane: bar.lane,
                    title: eventDisplayName(bar.title),
                    start: bar.start,
                    end: bar.end,
                    marks: bar.marks,
                    seedHex: bar.seedHex,
                    categoryKey: bar.categoryKey,
                    badge: bar.badge,
                    target: bar.target
                )
            }
        }
    }
}
