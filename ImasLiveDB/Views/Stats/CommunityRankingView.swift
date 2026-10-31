import os
import SwiftUI

// みんなの曲ランキング。順位の付け方・数え方はコア (`communityRanking`)。
// ここは種類の名前・単位と描画だけ。

extension CommunityRankingKind: CaseIterable, Identifiable {
    public static let allCases: [CommunityRankingKind] = [.popular, .trending, .favorites, .preview, .full]
    public var id: Self { self }

    var label: String {
        switch self {
        case .popular: "人気"
        case .trending: "急上昇"
        case .favorites: "お気に入り"
        case .preview: "試聴"
        case .full: "フル再生"
        }
    }

    var unit: String {
        switch self {
        case .popular: "pt"
        case .trending: "回/今週"
        case .favorites: "★"
        case .preview, .full: "回"
        }
    }

    var emptyIcon: String { self == .favorites ? "star" : "chart.bar" }

    /// 再生回数が根拠の種類 (数え始めた日を添える)。
    var isPlayBased: Bool { self != .favorites }
}

/// ブランドの絞り込み (すべて + 各ブランド)。
struct CommunityBrandChips: View {
    let brands: [Brand]
    @Binding var selection: String?

    var body: some View {
        ImasChipRow {
            chip(label: "すべて", brandId: nil, seed: nil)
            ForEach(brands) { brand in
                chip(label: brand.shortName, brandId: brand.id, seed: brand.color)
            }
        }
    }

    private func chip(label: String, brandId: String?, seed: String?) -> some View {
        ImasFilterChip(text: label, isSelected: selection == brandId, seed: seed) {
            selection = brandId
        }
    }
}

/// 順位の行の並び (読み込み・空・行)。種類・ブランド・件数が変わるたびに読み直す。
struct CommunityRankingList: View {
    let kind: CommunityRankingKind
    let brandId: String?
    let limit: Int
    let brands: [Brand]
    let onSelect: (String) -> Void

    @State private var rows: [Row] = []
    @State private var playsSince: String?
    @State private var isLoading = true
    @State private var failed = false

    struct Row: Identifiable {
        let ranked: RankedSong
        let song: Song?
        var id: String { ranked.songId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.gap) {
            if isLoading && rows.isEmpty {
                ImasInlineLoading()
            } else if failed {
                ImasCard {
                    ImasEmptyState(
                        .failed,
                        title: "ランキングを取得できませんでした",
                        message: "通信を確かめてもう一度開いてください。"
                    )
                }
            } else if rows.isEmpty {
                ImasCard {
                    ImasEmptyState(
                        systemImage: kind.emptyIcon,
                        title: "まだデータがありません",
                        message: "お気に入りや再生が増えると、ここにランキングが表示されます。"
                    )
                }
            } else {
                ImasCardList {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onSelect(row.ranked.songId)
                        } label: {
                            ImasRankingRow(
                                rank: Int(row.ranked.rank),
                                lead: .artwork(title: row.song?.title ?? row.ranked.songId,
                                               imageURL: row.song?.artworkUrl.flatMap { URL(string: $0) }),
                                title: row.song?.title ?? row.ranked.songId,
                                sub: brandName(row.song?.brandId),
                                metric: row.ranked.value.formatted(),
                                unit: kind.unit,
                                brand: brandHex(row.song?.brandId)
                            )
                        }
                        .buttonStyle(.plain)
                        if index < rows.count - 1 {
                            ImasRowDivider(inset: 52)
                        }
                    }
                }
            }
            if kind.isPlayBased, let since = Self.sinceLabel(playsSince) {
                Text(since).imasText(.meta)
            }
        }
        .task(id: "\(kind.label)|\(brandId ?? "-")|\(limit)") { await load() }
    }

    private func load() async {
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            let stats = try await CommunityAPI.shared.songStats()
            let kind = kind, brandId = brandId, limit = limit
            let ranked = try await CommunityRankingLoader.rank(
                snapshot: AppContainer.shared.coreSnapshot, stats: stats, kind: kind, brandId: brandId, limit: limit)
            let songs = (try? AppDatabase.shared.fetchSongs(ids: ranked.map(\.songId))) ?? []
            let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            rows = ranked.map { Row(ranked: $0, song: byId[$0.songId]) }
            playsSince = stats.playsSince
        } catch {
            if !(error is CancellationError) {
                Logger.database.error("load_failed community_ranking: \(error.localizedDescription)")
                rows = []
                failed = true
            }
        }
    }

    private func brandName(_ id: String?) -> String? {
        id.flatMap { id in brands.first { $0.id == id }?.shortName }
    }

    private func brandHex(_ id: String?) -> String? {
        id.flatMap { id in brands.first { $0.id == id }?.color }
    }

    /// "2026-10-20" → "2026年10月20日から集計"
    static func sinceLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return "\(parts[0])年\(parts[1])月\(parts[2])日から集計"
    }
}

/// すべて見る: 種類の切り替え + ブランド + 上位 100 件。
struct CommunityRankingView: View {
    @Environment(AppDatabase.self) private var database

    @State var kind: CommunityRankingKind
    @State var brandId: String?
    @State private var brands: [Brand] = []
    @State private var selectedSong: Song?

    private static let limit = 100

    var body: some View {
        ImasPage {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                ImasTabs(options: CommunityRankingKind.allCases, selection: $kind) { $0.label }
                CommunityBrandChips(brands: brands, selection: $brandId)
                CommunityRankingList(kind: kind, brandId: brandId, limit: Self.limit, brands: brands) { songId in
                    Task { selectedSong = try? await AppContainer.shared.songReading.song(id: songId) }
                }
            }
        }
        .navigationTitle("みんなの曲ランキング")
        .navigationBarTitleDisplayMode(.inline)
        .task { brands = (try? await AppContainer.shared.brandReading.brands()) ?? [] }
        .sheet(item: $selectedSong) { song in
            DetailSheetView(destination: .song(song))
                .environment(database)
        }
        .trackScreen("community_ranking")
    }
}

/// 順位づけはコア。スナップショットを借りて 1 回呼ぶだけ (画面の isolation を持ち込まない)。
private enum CommunityRankingLoader {
    static func rank(snapshot: CoreSnapshotManager, stats: CommunityStats, kind: CommunityRankingKind,
                     brandId: String?, limit: Int) async throws -> [RankedSong] {
        try await snapshot.withStore { store in
            try store.communityRanking(stats: stats, kind: kind, brandId: brandId, limit: UInt32(limit))
        }
    }
}
