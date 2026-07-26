import Foundation
import WidgetKit

/// 情報ウィジェット(次のライブ / 今日の1曲 / チケット締切)用のスナップショットを
/// App Group コンテナへ書き出す。ウィジェット拡張はアプリの GRDB を読めないため、
/// アプリ側がここで計算して JSON を置き、拡張はそれを読むだけにする。
/// 起動時・DB 更新後に呼ぶ。
enum InfoWidgetBridge {
    /// 情報スナップショットを計算して App Group へ保存し、タイムラインを更新する。
    static func sync(database: AppDatabase) async {
        let today = Self.dateKey()
        async let nextShow = Self.resolveNextShow(database: database, today: today)
        async let todaySong = Self.resolveTodaySong(database: database, today: today)
        async let deadlines = Self.resolveTicketDeadlines(database: database, today: today)

        let snapshot = InfoWidgetSnapshot(
            nextShow: await nextShow,
            todaySong: await todaySong,
            ticketDeadlines: await deadlines,
            generatedDate: today
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 次のライブ

    private static func resolveNextShow(database: AppDatabase, today: String) async -> NextShowInfo? {
        guard let events = try? database.fetchEventsWithFirstDate(
            brandId: nil, includeEmpty: false, liveOnly: false, kinds: [.live, .festival]
        ) else { return nil }

        // 今日以降で最も近いものを 1 件取る
        let upcoming = events
            .filter { ($0.firstDate ?? "") >= today }
            .sorted { ($0.firstDate ?? "") < ($1.firstDate ?? "") }
        guard let next = upcoming.first, let firstDate = next.firstDate else { return nil }

        // ブランドカラーを取得
        let brands = (try? database.fetchBrands()) ?? []
        let brandColor = brands.first(where: { $0.id == next.event.brandId })?.color

        return NextShowInfo(
            eventId: next.event.id,
            eventName: next.event.name,
            firstDate: firstDate,
            brandColorHex: brandColor
        )
    }

    // MARK: - 今日の1曲 (DailySongVoteSheet と同じロジック)

    private static func resolveTodaySong(database: AppDatabase, today: String) async -> TodaySongInfo? {
        let brands = ((try? database.fetchBrands()) ?? [])
            .filter { $0.id != "other" }
            .sorted { $0.sortOrder < $1.sortOrder }

        // 各ブランドから決定論的に1曲選ぶ。アプリ内の DailySongVoteSheet と
        // 同じ曲になる必要があるので、選び方は DailyPick に集約している。
        var chosen: (brand: Brand, songId: String)?
        for brand in brands {
            guard let ids = try? database.fetchSongIds(brandId: brand.id, includeCovers: false, excludeRemixes: true),
                  !ids.isEmpty else { continue }
            let idx = DailyPick.songIndex(dayKey: today, brandId: brand.id, count: ids.count)
            // 最初に見つかったブランドの1曲を代表として使う(ウィジェットは1曲のみ)
            chosen = (brand, ids[idx])
            break
        }
        guard let pick = chosen else { return nil }

        guard let song = try? database.fetchSong(id: pick.songId) else { return nil }
        let brandColor = pick.brand.color

        return TodaySongInfo(
            songId: song.id,
            title: song.title,
            artistLabel: song.singerLabel,
            artworkUrl: song.artworkUrl,
            brandColorHex: brandColor
        )
    }

    // MARK: - チケット締切

    private static func resolveTicketDeadlines(database: AppDatabase, today: String) async -> [TicketDeadlineInfo] {
        guard let events = try? database.fetchEvents(brandId: nil) else { return [] }

        return events
            .compactMap { event -> TicketDeadlineInfo? in
                guard let deadline = event.ticketDeadline,
                      deadline >= today else { return nil }
                return TicketDeadlineInfo(
                    eventId: event.id,
                    eventName: event.name,
                    deadline: deadline
                )
            }
            .sorted { $0.deadline < $1.deadline }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - ユーティリティ

    /// 端末ローカルの YYYY-MM-DD。
    static func dateKey(_ date: Date = Date()) -> String { DailyPick.dayKey(date) }
}
