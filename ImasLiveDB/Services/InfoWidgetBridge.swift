import Foundation
import WidgetKit

/// 情報ウィジェット(次のライブ / 今日の1曲 / チケット締切)用のスナップショットを
/// App Group コンテナへ書き出す。ウィジェット拡張はアプリの DB もコアも読めないため、
/// アプリ側がここで計算して JSON を置き、拡張はそれを読むだけにする。
///
/// 呼ぶのは、起動時・フォアグラウンド復帰時・スナップショットの読み直し後
/// (CloudKit 同期やローカル編集でマスタが変わったとき)。ウィジェットは作った日 (JST) 以外の
/// スナップショットを出さないので、アプリを開けば当日の内容に戻る。
enum InfoWidgetBridge {
    /// 情報スナップショットを計算して App Group へ保存し、タイムラインを更新する。
    static func sync() async {
        // 公演日・締切と比べる「今日」はアプリ本体と同じ JST。
        let today = JSTDay.today()
        async let nextShow = resolveNextShow(today: today)
        async let todaySong = resolveTodaySong()
        async let deadlines = resolveTicketDeadlines(today: today)

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

    private static func resolveNextShow(today: String) async -> NextShowInfo? {
        let container = AppContainer.shared
        guard let events = try? await container.eventReading.eventsWithFirstDate(
            brandId: nil, includeEmpty: false, liveOnly: false, kinds: [.live, .festival]
        ) else { return nil }

        // 今日以降で最も近いものを 1 件取る
        let upcoming = events
            .filter { ($0.firstDate ?? "") >= today }
            .sorted { ($0.firstDate ?? "") < ($1.firstDate ?? "") }
        guard let next = upcoming.first, let firstDate = next.firstDate else { return nil }

        // ブランドカラーを取得
        let brands = (try? await container.brandReading.brands()) ?? []
        let brandColor = brands.first(where: { $0.id == next.event.brandId })?.color

        return NextShowInfo(
            eventId: next.event.id,
            eventName: next.event.name,
            firstDate: firstDate,
            brandColorHex: brandColor
        )
    }

    // MARK: - 今日の1曲 (DailyPickSheet の曲の日と同じ曲)
    //
    // ウィジェットは曲だけを出す。アプリの起動シートは日で曲とアイドルを入れ替えるが、
    // 「今日の1曲」ウィジェットに求められているのは曲なので追随させない。
    // 曲の日にシートを開いたときは、ここで選ばれた曲と必ず同じ曲が並ぶ:
    // 候補列 (コアの dailyPickSongIds) も番号 (DailyPick) も日付キーもシートと同じものを使う。
    // 日付キーはシートと同じ端末ローカル日 (日替わりは「その人の 1 日」が単位。JST の「今日」とは別)。

    private static func resolveTodaySong() async -> TodaySongInfo? {
        let container = AppContainer.shared
        let dayKey = DailyPick.dayKey()
        let brands = ((try? await container.brandReading.brands()) ?? [])
            .filter { $0.id != "other" }
            .sorted { $0.sortOrder < $1.sortOrder }

        // 最初に候補があるブランドの 1 曲を代表として使う (ウィジェットは 1 曲のみ)。
        for brand in brands {
            guard let ids = try? await container.songReading.songIds(
                brandId: brand.id, includeCovers: false, excludeRemixes: true
            ), !ids.isEmpty else { continue }
            let index = DailyPick.songIndex(dayKey: dayKey, brandId: brand.id, count: ids.count)
            guard let song = try? await container.songReading.song(id: ids[index]) else { return nil }
            return TodaySongInfo(
                songId: song.id,
                title: song.title,
                artistLabel: song.singerLabel,
                artworkUrl: song.artworkUrl,
                brandColorHex: brand.color
            )
        }
        return nil
    }

    // MARK: - チケット締切

    private static func resolveTicketDeadlines(today: String) async -> [TicketDeadlineInfo] {
        guard let events = try? await AppContainer.shared.eventReading.events(brandId: nil) else { return [] }

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
}
