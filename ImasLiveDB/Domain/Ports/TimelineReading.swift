import Foundation

// =============================================================================
// 年表 (ブランド史) の読み取りポート + そのドメインモデル。
//
// 「ライブ / 楽曲シリーズ / 節目」を同じ時間軸のスイムレーンに並べ、ブランドの歴史を
// 1 枚で俯瞰させるための入力。UI は帯 (TimelineBar) の集合だけを受け取り、レーンへの
// 行詰め・座標変換は Presentation 側 (TimelineLayout) が純粋関数で行う。
//
// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
// =============================================================================

/// 年表の横帯グループ (スイムレーン)。
enum TimelineLane: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// サービス開始・アニメ放映・劇場版などの節目 (単日)。
    case milestone
    /// ライブ・フェス。
    case live
    /// 楽曲の CD シリーズ (期間を持つ)。
    case music
    /// リリイベ・ラジオ・配信番組など。
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .milestone: return "節目"
        case .live: return "ライブ"
        case .music: return "楽曲"
        case .other: return "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .milestone: return "flag.fill"
        case .live: return "music.mic"
        case .music: return "opticaldisc.fill"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

/// 年表の帯をタップしたときの遷移先。
enum TimelineTarget: Sendable, Hashable {
    case event(id: String)
    case seriesGroup(String)
    /// `series_group` 未設定だが同じ CD にまとまっている塊。
    case cdSeries(String)
    /// 束ねる相手のいない単発リリースの年。
    case releaseYear(String)
    /// 遷移先を持たない (節目など)。
    case none
}

/// 年表に置く 1 本の帯。単日の出来事は `start == end` で表す。
///
/// 帯そのものは「期間」を、`marks` は「その期間内で実際に何かがあった日」(公演日・
/// リリース日) を表す。参照デザインの「棒の上に打たれた点」がこれにあたる。
struct TimelineBar: Identifiable, Sendable, Hashable {
    let id: String
    let lane: TimelineLane
    let title: String
    /// 期間の開始 (JST 日付の 0 時)。
    let start: Date
    /// 期間の終了。単日なら start と同値。
    let end: Date
    /// 帯上に打つ点。公演日 / リリース日。
    let marks: [Date]
    /// 色シード (ブランドカラー hex)。nil のときは `categoryKey` から安定色を導出する。
    let seedHex: String?
    /// 実体色を持たない帯 (楽曲シリーズ等) に安定した色を割り当てるためのキー。
    let categoryKey: String
    /// 帯の右肩に出す小バッジ ("25曲" など)。
    let badge: String?
    let target: TimelineTarget

    /// 期間の長さ (日)。単日は 0。
    var durationDays: Double { end.timeIntervalSince(start) / 86_400 }
}

/// 年表 (ブランド史) の読み取りポート (driven port)。
///
/// 実装は `Adapters/Persistence/GRDBTimelineRepository`。
protocol TimelineReading: Sendable {
    /// 指定ブランド (nil = 全ブランド) の年表帯を全レーン分まとめて返す。
    func timelineBars(brandId: String?) async throws -> [TimelineBar]
}
