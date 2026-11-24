import SwiftUI

// =============================================================================
// 機能 1: 楽曲回収率シェアカード
// 現地参加ライブで聴けた曲 (UserMarkService の自動回収) の回収率をカード化する。
// =============================================================================

/// カードに焼く回収率データ。
struct CollectionShareStats {
    struct IdolLine: Identifiable {
        let id: String
        let name: String
        let color: String?
        let collected: Int
        let total: Int

        var ratio: Double { total > 0 ? Double(collected) / Double(total) : 0 }
    }

    var overallCollected: Int
    var overallTotal: Int
    /// 担当アイドル別の回収状況 (カードに乗せるのは先頭 4 人まで)
    var idolLines: [IdolLine]

    var overallRatio: Double { overallTotal > 0 ? Double(overallCollected) / Double(overallTotal) : 0 }
    var overallPercentText: String { String(format: "%.1f", overallRatio * 100) }
    /// メンバーカラー seed: 先頭の担当カラー → なければニュートラル。
    var seed: String? { idolLines.first?.color }

    /// 現在のマーク状態から回収率を集計する。数え方は回収ダッシュボードと同じ
    /// (imas-core `collection_dashboard`。ver 違いは原曲にまとめる)。
    @MainActor
    static func load() async -> CollectionShareStats {
        let pickIds = UserMarkService.shared.allMarked(kind: .myPick, entity: .idol)
        let dashboard = try? await AppContainer.shared.statsReading.collectionDashboard(
            collectedSongIds: UserMarkService.shared.autoCollectedSongIds(),
            pickIdolIds: Set(pickIds), today: JSTDay.today(), chanceLimit: 0)
        let pickIdols = (try? await AppContainer.shared.idolReading.idols(ids: pickIds)) ?? []
        let lines = pickIdols.prefix(4).map { idol in
            let progress = dashboard?.pickProgress[idol.id]
            return IdolLine(id: idol.id, name: idol.name, color: idol.color,
                            collected: progress?.collected ?? 0, total: progress?.total ?? 0)
        }
        return CollectionShareStats(
            overallCollected: dashboard?.overall.collected ?? 0,
            overallTotal: dashboard?.overall.total ?? 0,
            idolLines: lines
        )
    }

}

/// 回収率カード本体 (4:5 縦長 540×675pt)。
/// 曲が無いのでジャケ写なし。単色 near-black 地 + 大きな幾何透かしの編集レイアウト。
/// 巨大な回収率 % を明朝でヒーローに。メンバーカラーは担当ドット + バーの差し色のみ。
struct CollectionShareCard: View {
    let stats: CollectionShareStats
    var size: ShareCard.Size = ShareCard.portrait
    private var palette: ShareCardPalette { ShareCardPalette(seed: stats.seed) }

    /// 白基調の固定色 (near-black 地)。
    private let ink = Color.white
    private var ink2: Color { .white.opacity(0.66) }

    var body: some View {
        let palette = self.palette
        SoloShareScaffold(palette: palette, size: size, badge: "楽曲回収率") {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 16)

                Text("ライブで聴けた曲")
                    .font(.imasScaled( 18, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(ink2)
                    .padding(.bottom, DS.sp2)

                // ヒーロー: 巨大な回収率を明朝で。
                HStack(alignment: .firstTextBaseline, spacing: DS.sp1) {
                    Text(stats.overallPercentText)
                        .font(.imasScaled( 132, weight: .bold, design: .serif).monospacedDigit())
                        .foregroundStyle(ink)
                    Text("%")
                        .font(.imasScaled( 44, weight: .regular, design: .serif))
                        .foregroundStyle(ink2)
                }
                .minimumScaleFactor(0.7)
                .lineLimit(1)

                Text("\(stats.overallCollected) / \(stats.overallTotal) 曲を回収")
                    .font(.imasScaled( 17, weight: .medium).monospacedDigit())
                    .foregroundStyle(ink2)
                    .padding(.top, DS.sp2)

                progressBar(ratio: stats.overallRatio, height: 10)
                    .padding(.top, DS.sp6)

                if !stats.idolLines.isEmpty {
                    Rectangle().fill(ink.opacity(0.14)).frame(height: 0.75).padding(.top, DS.sp8)
                    VStack(alignment: .leading, spacing: DS.sp5) {
                        ForEach(stats.idolLines) { line in
                            idolRow(line)
                        }
                    }
                    .padding(.top, 26)
                }

                Spacer(minLength: 16)
            }
        }
    }

    private func idolRow(_ line: CollectionShareStats.IdolLine) -> some View {
        let fill = Color(hexString: line.color, default: palette.accent)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Circle()
                    .fill(fill)
                    .frame(width: 10, height: 10)
                Text(line.name)
                    .font(.imasScaled( 16, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer()
                Text("\(line.collected)/\(line.total)曲")
                    .font(.imasScaled( 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(ink2)
            }
            progressBar(ratio: line.ratio, height: 5, fill: fill)
        }
    }

    /// プログレスバー。塗りはメンバーカラー (差し色)、地は白の薄塗り。
    private func progressBar(ratio: Double, height: CGFloat, fill: Color? = nil) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.14))
                Capsule()
                    .fill(fill ?? palette.accent)
                    .frame(width: max(height, geo.size.width * min(max(ratio, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// Stats タブから開く回収率シェア sheet。
struct CollectionShareSheet: View {
    @State private var stats: CollectionShareStats?

    var body: some View {
        ShareCardSheet(title: "回収率をシェア", screenName: "collection_share") {
            if let stats {
                ShareCardActionPane { size in
                    CollectionShareCard(stats: stats, size: size)
                }
            } else {
                ImasInlineLoading()
            }
        }
        .task { stats = await CollectionShareStats.load() }
    }
}
