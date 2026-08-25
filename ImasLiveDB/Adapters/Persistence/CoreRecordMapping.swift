import Foundation

/// 共有コア (imas-core) の FFI レコード ⇄ iOS ドメインモデルの変換を 1 箇所に集めた場所。
///
/// なぜ 1 ファイルに集めるか:
/// - 同じ `IdolRecord → Idol` の変換を各 `Core*Repository` が持つと、DB 列が増えたときに
///   片方だけ直して「画面によって値が欠ける」事故になる。変換規則の正は 1 つに保つ。
/// - FFI は数値を Int64/UInt32 で返す・NULL 可否が iOS 側モデルと食い違う (例: `IdolRecord.brandId`
///   は Optional だが `Idol.brandId` は非 Optional) といった段差があり、その埋め方の判断
///   (既定値をどう置くか) をレビューしやすい 1 箇所にまとめたい。
enum CoreRecordMapping {

    // MARK: - アイドル / ブランド / ユニット

    static func idol(from record: IdolRecord) -> Idol {
        Idol(
            id: record.id,
            // DB 上は NOT NULL だが FFI 側は Optional。空文字に落としても
            // ブランド絞り込み (== 判定) に引っかからないだけで表示は壊れない。
            brandId: record.brandId ?? "",
            name: record.name,
            nameKana: record.nameKana,
            nameRomaji: record.nameRomaji,
            familyName: record.familyName,
            givenName: record.givenName,
            nickname: record.nickname,
            color: record.color,
            // sort_order 未設定は GRDB 時代も 0 相当で先頭に並んでいた (並び自体は core が決める)。
            sortOrder: Int(record.sortOrder ?? 0),
            birthday: record.birthday,
            bloodType: record.bloodType,
            height: record.height,
            weight: record.weight,
            birthPlace: record.birthPlace,
            age: record.age.map(Int.init),
            bust: record.bust,
            waist: record.waist,
            hip: record.hip,
            constellation: record.constellation,
            hobbies: record.hobbies,
            talents: record.talents,
            description: record.description,
            gender: record.gender,
            handedness: record.handedness,
            debutDate: record.debutDate,
            attribute: record.attribute,
            isExternal: record.isExternal,
            aliases: record.aliases
        )
    }

    static func brand(from record: BrandRecord) -> Brand {
        Brand(
            id: record.id,
            name: record.name,
            shortName: record.shortName,
            color: record.color,
            sortOrder: Int(record.sortOrder),
            iconUrl: record.iconUrl
        )
    }

    static func unit(from record: UnitRecord) -> Unit {
        Unit(
            id: record.id,
            brandId: record.brandId,
            name: record.name,
            isPermanent: record.isPermanent,
            nameAlt: record.nameAlt
        )
    }

    /// `idolUnits` だけ別レコード型で返るが中身は `UnitRecord` と同一。
    static func unit(from record: IdolUnitRecord) -> Unit {
        Unit(
            id: record.id,
            brandId: record.brandId,
            name: record.name,
            isPermanent: record.isPermanent,
            nameAlt: record.nameAlt
        )
    }

    static func unitIndex(from record: UnitIndexRecord) -> UnitIndex {
        var memberIds: [String: Set<String>] = [:]
        var byIdol: [String: Set<String>] = [:]
        for link in record.memberLinks {
            memberIds[link.unitId, default: []].insert(link.idolId)
            byIdol[link.idolId, default: []].insert(link.unitId)
        }
        return UnitIndex(
            units: record.units.map(unit(from:)),
            memberIds: memberIds,
            byIdol: byIdol,
            unitsWithSongs: Set(record.songUnitIds)
        )
    }

    // MARK: - イベント / 公演

    static func event(from record: EventListRecord) -> Event {
        Event(
            id: record.id,
            brandId: record.brandId,
            name: record.name,
            eventType: record.eventType,
            isStreaming: record.isStreaming,
            isSolo: record.isSolo,
            kind: record.kind,
            ticketOpenDate: record.ticketOpenDate,
            ticketDeadline: record.ticketDeadline,
            ticketLotteryDate: record.ticketLotteryDate,
            ticketUrl: record.ticketUrl,
            jointBrandIds: record.jointBrandIds,
            hasStreaming: record.hasStreaming,
            hasLiveViewing: record.hasLiveViewing
        )
    }

    static func event(from record: EventDetailRecord) -> Event {
        Event(
            id: record.id,
            brandId: record.brandId,
            name: record.name,
            eventType: record.eventType,
            isStreaming: record.isStreaming,
            isSolo: record.isSolo,
            kind: record.kind,
            ticketOpenDate: record.ticketOpenDate,
            ticketDeadline: record.ticketDeadline,
            ticketLotteryDate: record.ticketLotteryDate,
            ticketUrl: record.ticketUrl,
            jointBrandIds: record.jointBrandIds,
            hasStreaming: record.hasStreaming,
            hasLiveViewing: record.hasLiveViewing
        )
    }

    static func eventWithDate(from record: EventWithDateRecord) -> EventWithDate {
        EventWithDate(
            event: event(from: record.event),
            firstDate: record.firstDate,
            lastDate: record.lastDate
        )
    }

    static func eventStats(from record: EventStatsRecord) -> EventStats {
        EventStats(
            showCount: Int(record.showCount),
            totalSongs: Int(record.totalSongs),
            uniqueSongs: Int(record.uniqueSongs),
            castCount: Int(record.castCount)
        )
    }

    static func eventRelease(from record: EventReleaseRecord) -> EventRelease {
        EventRelease(
            id: record.id,
            eventId: record.eventId,
            showId: record.showId,
            productType: record.productType,
            title: record.title,
            catalogNumber: record.catalogNumber,
            releaseDate: record.releaseDate,
            jacketUrl: record.jacketUrl,
            purchaseUrl: record.purchaseUrl,
            sortOrder: Int(record.sortOrder)
        )
    }

    static func show(from record: ShowRecord) -> Show {
        Show(
            id: record.id,
            eventId: record.eventId,
            name: record.name,
            date: record.date,
            venue: record.venue,
            venueId: record.venueId,
            hall: record.hall,
            streamPlatform: record.streamPlatform,
            venueCity: record.venueCity,
            startTime: record.startTime,
            sortOrder: Int(record.sortOrder),
            performerType: record.performerType,
            hasStreaming: record.hasStreaming,
            hasLiveViewing: record.hasLiveViewing
        )
    }

    static func showWithEventName(from record: ShowWithEventNameRecord) -> ShowWithEventName {
        ShowWithEventName(
            id: record.id,
            eventId: record.eventId,
            name: record.name,
            date: record.date,
            venue: record.venue,
            eventName: record.eventName
        )
    }

    static func setlistRow(from record: SetlistEntryRecord) -> SetlistRow {
        SetlistRow(
            id: record.id,
            position: Int(record.position),
            section: record.section,
            notes: record.notes,
            unitName: record.unitName,
            songId: record.songId,
            songTitle: record.songTitle,
            appleMusicId: record.appleMusicId,
            artworkUrl: record.artworkUrl,
            previewUrl: record.previewUrl,
            songBrandId: record.songBrandId
        )
    }

    /// `PerformerRow.id` は SQL 時代も idol_id をそのまま使っていた (performer_id エイリアス)。
    /// `name` は現任 CV 名 = core の `displayName`。
    static func performerRow(from record: SetlistPerformerRecord) -> PerformerRow {
        PerformerRow(
            id: record.idolId,
            name: record.displayName,
            idolColor: record.idolColor,
            idolName: record.idolName,
            idolId: record.idolId
        )
    }

    static func castShowRow(from record: IdolShowRecord) -> CastShowRow {
        CastShowRow(
            showId: record.showId,
            eventId: record.eventId,
            eventName: record.eventName,
            showName: record.showName,
            date: record.date,
            venue: record.venue,
            // 未知の役割文字列は SQL 時代の COALESCE 既定と同じく通常出演に落とす。
            castRole: CastRole(rawValue: record.castRole) ?? .member
        )
    }

    static func castShowRow(from record: IdolSongShowRecord) -> CastShowRow {
        CastShowRow(
            showId: record.showId,
            eventId: record.eventId,
            eventName: record.eventName,
            showName: record.showName,
            date: record.date,
            venue: record.venue,
            castRole: CastRole(rawValue: record.castRole) ?? .member
        )
    }

    // MARK: - 会場

    static func venueDirectory(from record: VenueDirectoryRecord) -> VenueDirectory {
        VenueDirectory(
            venues: record.venues.map { venue in
                Venue(
                    id: venue.id,
                    name: venue.name,
                    nameKana: venue.nameKana,
                    prefecture: venue.prefecture,
                    city: venue.city,
                    aliases: venue.aliases,
                    capacity: venue.capacity.map(Int.init),
                    sortOrder: Int(venue.sortOrder)
                )
            },
            names: record.names.map { name in
                VenueName(
                    id: name.id,
                    venueId: name.venueId,
                    name: name.name,
                    validFrom: name.validFrom,
                    validTo: name.validTo
                )
            },
            halls: record.halls.map { hall in
                VenueHall(
                    id: hall.id,
                    venueId: hall.venueId,
                    name: hall.name,
                    capacity: hall.capacity.map(Int.init)
                )
            }
        )
    }

    // MARK: - 統計

    static func brandSongCount(from record: BrandSongCountRecord) -> BrandSongCount {
        BrandSongCount(
            id: record.id,
            shortName: record.shortName,
            color: record.color,
            songCount: Int(record.songCount)
        )
    }

    static func songPlayCount(from record: SongPlayCountRecord) -> SongPlayCount {
        SongPlayCount(
            id: record.id,
            title: record.title,
            playCount: Int(record.playCount),
            brandId: record.brandId
        )
    }

    static func castShowCount(from record: CastShowCountRecord) -> CastShowCount {
        CastShowCount(
            id: record.id,
            name: record.name,
            showCount: Int(record.showCount)
        )
    }

    static func yearlyShowCount(from record: YearlyShowCountRecord) -> YearlyShowCount {
        YearlyShowCount(year: record.year, showCount: Int(record.showCount))
    }

    // MARK: - 年表

    static func timelineBar(from record: TimelineBarRecord) -> TimelineBar {
        TimelineBar(
            id: record.id,
            lane: lane(from: record.lane),
            // ⚠️ イベント帯のタイトルは正式名称のまま返ってくる。表示用の作品名省略
            //    (eventDisplayName) は UserDefaults 依存なので core が持てず、呼び出し側で掛ける。
            title: record.title,
            start: Date(timeIntervalSince1970: TimeInterval(record.startEpochSeconds)),
            end: Date(timeIntervalSince1970: TimeInterval(record.endEpochSeconds)),
            marks: record.markEpochSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            seedHex: record.seedHex,
            categoryKey: record.categoryKey,
            badge: record.badge,
            target: target(from: record.target)
        )
    }

    private static func lane(from lane: TimelineBarLane) -> TimelineLane {
        switch lane {
        case .milestone: return .milestone
        case .live: return .live
        case .music: return .music
        case .other: return .other
        }
    }

    private static func target(from target: TimelineBarTarget) -> TimelineTarget {
        switch target {
        case .event(let id): return .event(id: id)
        case .seriesGroup(let name): return .seriesGroup(name)
        case .cdSeries(let name): return .cdSeries(name)
        case .releaseYear(let year): return .releaseYear(year)
        case .none: return .none
        }
    }

    // MARK: - 楽曲

    static func song(from record: SongDetailRecord) -> Song {
        Song(
            id: record.id,
            title: record.title,
            titleKana: record.titleKana,
            brandId: record.brandId,
            // DB では NULL 可だが GRDB Record は非 Optional。"unknown" は songTypeLabel が「不明」に落とす。
            songType: record.songType ?? "unknown",
            releaseDate: record.releaseDate,
            durationSec: record.durationSec.map(Int.init),
            composer: record.composer,
            lyricist: record.lyricist,
            arranger: record.arranger,
            cdSeries: record.cdSeries,
            cdTitle: record.cdTitle,
            artworkUrl: record.artworkUrl,
            previewUrl: record.previewUrl,
            appleMusicId: record.appleMusicId,
            appleMusicAlbumId: record.appleMusicAlbumId,
            isrc: record.isrc,
            lyricsUrl: record.lyricsUrl,
            parentSongId: record.parentSongId,
            singerLabel: record.singerLabel,
            unitName: record.unitName,
            unitId: record.unitId,
            seriesGroup: record.seriesGroup
        )
    }

    /// core が返す「表示順の song_id 列」を `Song` に実体化する。
    ///
    /// `songRecordsByIds` は入力 id 順で返すが未知 id を読み飛ばすため、そのまま zip すると
    /// 対応がずれる。加えて role 違いで同じ id が 2 回出る一覧 (`idolSongRecords` の role 未指定)
    /// もあるので、id → レコードの辞書を作ってから元の並びを引き直す。
    static func songs(store: SnapshotStore, orderedIds: [String]) throws -> [Song] {
        guard !orderedIds.isEmpty else { return [] }
        let byId = Dictionary(
            try store.songRecordsByIds(songIds: orderedIds).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return orderedIds.compactMap { byId[$0] }.map(song(from:))
    }

    /// 同じ規約で `Idol` を実体化する (`idolRecordsByIds` は入力 id 順・初出のみ)。
    static func idols(store: SnapshotStore, orderedIds: [String]) throws -> [Idol] {
        guard !orderedIds.isEmpty else { return [] }
        let byId = Dictionary(
            try store.idolRecordsByIds(idolIds: orderedIds).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return orderedIds.compactMap { byId[$0] }.map(idol(from:))
    }
}

// MARK: - core / GRDB の呼び出し単位フォールバック

extension CoreSnapshotManager {
    /// スナップショットがあれば core 経路、無ければ GRDB 経路。
    /// core 実行中の `SnapshotError` (メモリ警告 unload との競合等) も GRDB に落とす。
    /// それ以外のエラー (GRDB 側の失敗など) は従来どおり呼び出し元へ伝える。
    ///
    /// 各 `Core*Repository` が同じ分岐を書くとフォールバック漏れが起きるので、
    /// 切り替えの規則はここ 1 箇所に置く。
    func withStore<T: Sendable>(
        fallbackTo grdb: () async throws -> T,
        _ body: (SnapshotStore) async throws -> T
    ) async throws -> T {
        guard let store = storeIfLoaded else { return try await grdb() }
        do {
            return try await body(store)
        } catch is SnapshotError {
            return try await grdb()
        }
    }
}
