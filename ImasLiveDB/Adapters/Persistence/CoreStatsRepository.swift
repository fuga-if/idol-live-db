import Foundation

/// `StatsReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
/// スナップショットがまだなら、ロードを待ってから答える (`CoreSnapshotManager.withStore`)。
struct CoreStatsRepository: StatsReading {
    let snapshot: CoreSnapshotManager

    func brandSongCounts() async throws -> [BrandSongCount] {
        try await snapshot.withStore { store in
            try store.brandSongCounts().map(CoreRecordMapping.brandSongCount(from:))
        }
    }

    func songPlayCountRanking(limit: Int) async throws -> [SongPlayCount] {
        try await snapshot.withStore { store in
            try store.songPlayCountRanking(limit: UInt32(max(0, limit))).map(CoreRecordMapping.songPlayCount(from:))
        }
    }

    func castShowCountRanking(limit: Int) async throws -> [CastShowCount] {
        try await snapshot.withStore { store in
            try store.castShowCountRanking(limit: UInt32(max(0, limit))).map(CoreRecordMapping.castShowCount(from:))
        }
    }

    func yearlyShowCounts() async throws -> [YearlyShowCount] {
        try await snapshot.withStore { store in
            try store.yearlyShowCounts().map(CoreRecordMapping.yearlyShowCount(from:))
        }
    }

    func collectionDashboard(
        collectedSongIds: Set<String>, pickIdolIds: Set<String>, today: String, chanceLimit: Int
    ) async throws -> CollectionDashboard {
        try await snapshot.withStore { store in
            let record = try store.collectionDashboard(
                collectedSongIds: Array(collectedSongIds), pickIdolIds: Array(pickIdolIds),
                today: today, chanceLimit: UInt32(max(0, chanceLimit)))
            return CollectionDashboard(
                overallCollected: Int(record.overallCollected),
                overallTotal: Int(record.overallTotal),
                brandProgress: record.brandProgress.map {
                    BrandCollectionProgress(
                        brandId: $0.brandId, shortName: $0.shortName, color: $0.color,
                        collected: Int($0.collected), total: Int($0.total))
                },
                myPickCollected: Int(record.myPickCollected),
                myPickTotal: Int(record.myPickTotal),
                pickUncollected: record.pickUncollected.map(Self.uncollected(from:)),
                allUncollected: record.allUncollected.map(Self.uncollected(from:)),
                catchChances: record.catchChances.map {
                    UpcomingCatchChance(
                        show: CoreRecordMapping.show(from: $0.show),
                        eventName: $0.eventName, eventShortName: $0.eventShortName,
                        brandId: $0.brandId, brandColor: $0.brandColor,
                        likelyCount: Int($0.likelyCount))
                })
        }
    }

    private static func uncollected(from record: UncollectedSongRecord) -> UncollectedSong {
        UncollectedSong(
            song: CoreRecordMapping.song(from: record.song), playCount: Int(record.playCount),
            frequency: record.frequency, frequencyLabel: record.frequencyLabel)
    }
}
