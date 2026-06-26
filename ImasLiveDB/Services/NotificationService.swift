import Foundation
import UserNotifications
import os

// MARK: - NotificationService

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            Logger.notification.error("notif_auth_failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Reschedule All

    /// 既存の pending 通知を全消去し、設定がONの通知を再スケジュールする。
    /// 未認可の場合は何もしない。最大60件cap（誕生日・月曜は repeat のため少数、イベント系は近い順）。
    func rescheduleAll(database: AppDatabase) async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        center.removeAllPendingNotificationRequests()

        var requests: [UNNotificationRequest] = []

        // 1. 担当アイドル誕生日 (repeats annually)
        if notifEnabled("notif_oshi_birthday") {
            let birthdayRequests = await buildBirthdayRequests(database: database)
            requests += birthdayRequests
        }

        // 2. 月曜ミーム (今後数週の日曜 20:00。回ごとにレア文言を抽選するため個別スケジュール)
        if notifEnabled("notif_monday") {
            requests += buildMondayMemeRequests()
        }

        // 3. ライブ1週間前 + 4. チケット締切/当落 (非repeat, 近い順にcap)
        let eventRequests = await buildEventRequests(database: database)
        requests += eventRequests

        // 合計60件cap（誕生日・月曜は少数なので後ろをトリム）
        let capped = Array(requests.prefix(60))

        for request in capped {
            do {
                try await center.add(request)
            } catch {
                Logger.notification.error("notif_add_failed \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        Logger.notification.info("notif_rescheduled total=\(capped.count, privacy: .public)")
    }

    // MARK: - Birthday Notifications

    private func buildBirthdayRequests(database: AppDatabase) async -> [UNNotificationRequest] {
        do {
            let idolIds = try database.fetchMarkedEntityIds(entity: .idol, kind: .myPick)
            let idols = try database.fetchIdols(ids: idolIds)
            return idols.compactMap { birthdayRequest(for: $0) }
        } catch {
            Logger.notification.error("notif_birthday_fetch_failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func birthdayRequest(for idol: Idol) -> UNNotificationRequest? {
        guard let birthday = idol.birthday else { return nil }

        // "--MM-DD" または "MM-DD" 形式をパース
        let raw = birthday.hasPrefix("--") ? String(birthday.dropFirst(2)) : birthday
        let parts = raw.split(separator: "-")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              (1...12).contains(month),
              (1...31).contains(day) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "🎂 今日は\(idol.name)の誕生日！"
        content.body = "\(idol.name)、お誕生日おめでとう！"
        content.sound = .default
        if let att = customImageAttachment(idolId: idol.id, identifier: "bday_img_\(idol.id)") {
            content.attachments = [att]
        }

        var components = DateComponents()
        components.month = month
        components.day = day
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(
            identifier: "bday_\(idol.id)",
            content: content,
            trigger: trigger
        )
    }

    // MARK: - Monday Meme Notification

    /// 園田智代子の「月曜が近いよ」ミーム。基本は「月曜が近いよ」、たまにレアで
    /// 「どぅいどぅいどぅ〜」。回ごとに抽選するため、今後8週分の日曜20:00を個別に積む。
    private func buildMondayMemeRequests() -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let now = Date()
        // 直近の「次の日曜 20:00」を求める。
        var comps = DateComponents()
        comps.weekday = 1  // Sunday
        comps.hour = 20
        comps.minute = 0
        guard var next = calendar.nextDate(after: now, matching: comps,
                                           matchingPolicy: .nextTime) else { return [] }

        var requests: [UNNotificationRequest] = []
        for i in 0..<8 {
            // レア抽選: SSR級 約0.2% (1/500) で「どぅいどぅいどぅ〜」、通常は「月曜が近いよ」。
            let rare = Int.random(in: 0..<500) == 0
            let content = UNMutableNotificationContent()
            content.title = rare ? "どぅいどぅいどぅ〜" : "月曜が近いよ"
            content.sound = .default
            if let att = customImageAttachment(idolId: "sc_園田智代子", identifier: "monday_img_\(i)") {
                content.attachments = [att]
            }
            let triggerComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
            requests.append(UNNotificationRequest(
                identifier: "monday_meme_\(i)",
                content: content,
                trigger: trigger
            ))
            guard let following = calendar.date(byAdding: .day, value: 7, to: next) else { break }
            next = following
        }
        return requests
    }

    // MARK: - Event Notifications (ライブ1週間前 / チケット締切 / 当落)

    private func buildEventRequests(database: AppDatabase) async -> [UNNotificationRequest] {
        let liveWeekEnabled = notifEnabled("notif_live_week")
        let ticketEnabled = notifEnabled("notif_ticket")
        guard liveWeekEnabled || ticketEnabled else { return [] }

        do {
            // お気に入り ∪ 参加マーク のイベントを対象にする
            let favoriteIds = Set(try database.fetchMarkedEntityIds(entity: .event, kind: .favorite))
            let attendedEvents = try database.fetchAttendedEventsWithDate()
            let attendedIds = Set(attendedEvents.map(\.id))
            let allIds = Array(favoriteIds.union(attendedIds))

            guard !allIds.isEmpty else { return [] }

            let eventsWithDate = try database.fetchEventsByIds(allIds)
            // ticketDeadline / ticketLotteryDate を含む完全な Event を一括取得。
            let fullEvents = try database.fetchFullEvents(ids: allIds)
            let eventById = Dictionary(uniqueKeysWithValues: fullEvents.map { ($0.id, $0) })

            let now = Date()
            var requests: [UNNotificationRequest] = []

            for ew in eventsWithDate {
                guard let firstDateStr = ew.firstDate,
                      let firstDate = parseDate(firstDateStr),
                      firstDate > now else { continue }

                // ticketDeadline/ticketLotteryDate を持つ完全な Event を優先参照。
                let event = eventById[ew.id] ?? ew.event

                // ライブ1週間前 (初日の7日前 10:00)
                if liveWeekEnabled {
                    if let req = liveWeekRequest(event: event, firstDate: firstDate, now: now) {
                        requests.append(req)
                    }
                }

                // チケット締切
                if ticketEnabled {
                    // ticketDeadline 前日 18:00
                    if let deadlineStr = event.ticketDeadline,
                       let deadline = parseDate(deadlineStr),
                       deadline > now {
                        if let req = ticketDeadlineRequest(event: event, deadline: deadline, now: now) {
                            requests.append(req)
                        }
                    }

                    // 当落発表日 当日 09:00
                    if let lotteryStr = event.ticketLotteryDate,
                       let lotteryDate = parseDate(lotteryStr),
                       lotteryDate > now {
                        if let req = lotteryRequest(event: event, lotteryDate: lotteryDate, now: now) {
                            requests.append(req)
                        }
                    }
                }
            }

            // 近い順にソートして返す（後でcapされる）
            return requests.sorted { lhs, rhs in
                let lt = (lhs.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                let rt = (rhs.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                return lt < rt
            }
        } catch {
            Logger.notification.error("notif_event_fetch_failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func liveWeekRequest(event: Event, firstDate: Date, now: Date) -> UNNotificationRequest? {
        guard let triggerDate = Calendar.current.date(byAdding: .day, value: -7, to: firstDate),
              triggerDate > now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "もうすぐライブ！"
        content.body = "\(event.name) まであと1週間！準備はOK？"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: triggerDate) ?? triggerDate
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: "live_\(event.id)",
            content: content,
            trigger: trigger
        )
    }

    private func ticketDeadlineRequest(event: Event, deadline: Date, now: Date) -> UNNotificationRequest? {
        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: deadline),
              dayBefore > now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "チケット申込は明日まで！"
        content.body = "\(event.name) のチケット申込締切は明日です。お忘れなく！"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: dayBefore) ?? dayBefore
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: "ticketdl_\(event.id)",
            content: content,
            trigger: trigger
        )
    }

    private func lotteryRequest(event: Event, lotteryDate: Date, now: Date) -> UNNotificationRequest? {
        guard lotteryDate > now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "当落発表日です！"
        content.body = "\(event.name) の当落発表日。ドキドキしながら確認してみよう！"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: lotteryDate) ?? lotteryDate
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(
            identifier: "lottery_\(event.id)",
            content: content,
            trigger: trigger
        )
    }

    // MARK: - Helpers

    /// ユーザーがアプリ内で取り込んだアイドル画像を通知添付にする。
    /// 版権セーフ: 運営が同梱するのではなく、ユーザー自身のローカル画像のみ使う。
    /// UNNotificationAttachment はファイルを所有(移動)しうるため temp にコピーして渡す。
    private func customImageAttachment(idolId: String, identifier: String) -> UNNotificationAttachment? {
        guard let src = CustomImageService.shared.imageURL(for: idolId),
              FileManager.default.fileExists(atPath: src.path) else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("notif_\(identifier).jpg")
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.copyItem(at: src, to: tmp)
            return try UNNotificationAttachment(identifier: identifier, url: tmp, options: nil)
        } catch {
            return nil
        }
    }

    /// UserDefaults から設定を読む。未設定（nil）なら既定 true。
    private func notifEnabled(_ key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// "YYYY-MM-DD" → Date (Calendar.current)
    private func parseDate(_ str: String) -> Date? {
        let parts = str.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps)
    }
}
