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
                overall: CollectionProgress(
                    collected: Int(record.overallCollected), total: Int(record.overallTotal),
                    performedCollected: Int(record.overallPerformedCollected),
                    performedTotal: Int(record.overallPerformedTotal)),
                brandProgress: record.brandProgress.map {
                    BrandCollectionProgress(
                        brandId: $0.brandId, shortName: $0.shortName, color: $0.color,
                        progress: CollectionProgress(
                            collected: Int($0.collected), total: Int($0.total),
                            performedCollected: Int($0.performedCollected), performedTotal: Int($0.performedTotal)))
                },
                myPickCollected: Int(record.myPickCollected),
                myPickTotal: Int(record.myPickTotal),
                pickProgress: Dictionary(
                    record.pickProgress.map { ($0.idolId, (collected: Int($0.collected), total: Int($0.total))) },
                    uniquingKeysWith: { first, _ in first }),
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

    func uncollectedSongs(collectedSongIds: Set<String>, scope: CollectionScope) async throws -> UncollectedSongList {
        try await snapshot.withStore { store in
            let record = try store.uncollectedSongs(collectedSongIds: Array(collectedSongIds), scope: scope)
            return UncollectedSongList(
                progress: CollectionProgress(
                    collected: Int(record.collected), total: Int(record.total),
                    performedCollected: Int(record.performedCollected), performedTotal: Int(record.performedTotal)),
                performed: record.performed.map(Self.uncollected(from:)),
                unperformed: record.unperformed.map(Self.uncollected(from:)))
        }
    }

    func collectedOriginalSongCount(collectedSongIds: Set<String>) async throws -> Int {
        try await snapshot.withStore { store in
            Int(try store.collectedOriginalSongCount(collectedSongIds: Array(collectedSongIds)))
        }
    }

    private static func uncollected(from record: UncollectedSongRecord) -> UncollectedSong {
        UncollectedSong(
            song: CoreRecordMapping.song(from: record.song), playCount: Int(record.playCount),
            frequency: record.frequency, frequencyLabel: record.frequencyLabel,
            ownPlayCount: Int(record.ownPlayCount),
            variants: record.variants.map {
                UncollectedVariant(song: CoreRecordMapping.song(from: $0.song), playCount: Int($0.playCount))
            })
    }

    func lyricCoverage(publishedSongIds: [String]) async throws -> LyricCoverageRecord {
        try await snapshot.withStore { store in
            try store.lyricCoverage(publishedSongIds: publishedSongIds)
        }
    }

    func lyricSongIds(publishedSongIds: [String], brandId: String?) async throws -> [String] {
        try await snapshot.withStore { store in
            try store.lyricSongIds(publishedSongIds: publishedSongIds, brandId: brandId)
        }
    }
}
