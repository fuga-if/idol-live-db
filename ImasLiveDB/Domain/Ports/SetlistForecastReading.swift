import Foundation

/// セトリの機械予測の読み取りポート (driven port)。
///
/// 点数・順位・理由・公演の印はすべてコア (`imas-core` の `setlist_forecast`) の判断なので、
/// ここは公演 id と件数を渡して 1 回で受け取るだけの口。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol SetlistForecastReading: Sendable {
    /// 点数の高い順に最大 `limit` 曲。予測の対象でない公演 (リアルライブでない等) なら nil。
    /// 初回は下ごしらえと学習で数百 ms かかるので、実装はメインスレッドの外で計算すること。
    func setlistForecast(showId: String, limit: Int) async throws -> SetlistForecastRecord?
}
