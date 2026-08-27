package com.fugaif.imaslivedb.data.notification

import com.fugaif.imaslivedb.data.model.Event
import com.fugaif.imaslivedb.data.model.Idol
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters
import kotlin.random.Random

/**
 * 予約する通知 1 件分。文言と発火時刻まで決まった、副作用のない値。
 *
 * ここまでを純粋に保つのは、iOS の `UNNotificationRequest` 組み立てと 1:1 で
 * 突き合わせられるようにするため。Android 固有の AlarmManager / Notification は
 * [NotificationScheduler] 側だけが知る。
 */
data class PlannedNotification(
    /** iOS の `UNNotificationRequest.identifier` と同じ文字列 (bday_ / monday_meme_ / live_ ...)。 */
    val id: String,
    val category: NotificationCategory,
    val title: String,
    val body: String?,
    val triggerAtMillis: Long,
    /**
     * 通知に添える画像の元になるアイドル id。
     *
     * iOS はユーザーが自分で取り込んだ画像 (CustomImageService) を
     * `UNNotificationAttachment` にして添える。版権セーフのため、運営が同梱した
     * 画像は使わずユーザーのローカル画像だけを使う、というのが iOS 側の決め。
     *
     * Android にはまだ画像ギャラリー基盤が無いので今は未使用。基盤ができたら
     * [NotificationScheduler] の通知組み立てで
     * `NotificationCompat.BigPictureStyle` にこの id の画像を載せる。
     */
    val imageIdolId: String?
)

/** イベント通知の入力。開催日 (初日) は一覧クエリ側、チケット日程は Event 本体が持つ。 */
data class EventNotificationSource(
    val event: Event,
    val firstDate: String?
)

/**
 * 通知の予定表を組み立てる純粋ロジック。iOS `NotificationService` の写経。
 *
 * 共有コア (imas-core) には通知まわりの規則が無いので Kotlin 側に置く。
 * 置き場所を変えるときは iOS 側と同時に動かすこと (60 件 cap と round-robin の
 * 配分規則が両 OS でずれると、片方だけ通知が来ないという分かりにくい差になる)。
 */
object NotificationPlanner {

    /** 一度に予約する通知の上限。iOS と同じ 60 件。 */
    const val MAX_SCHEDULED = 60

    /** 月曜ミームを積む週数。iOS と同じ 8 週分。 */
    const val MONDAY_MEME_WEEKS = 8

    /** 月曜ミームのレア文言の確率。iOS と同じ 1/500。 */
    const val MONDAY_MEME_RARE_DENOMINATOR = 500

    /** 園田智代子。月曜ミームの主。画像添付が入ったときの参照先。 */
    const val CHIYOKO_IDOL_ID = "sc_園田智代子"

    /** 2/29 のように年によって存在しない日があるので、成立する年まで先を見る幅。 */
    private const val ANNUAL_LOOKAHEAD_YEARS = 8

    /**
     * 複数カテゴリの列を round-robin で 1 列に混ぜ、cap 件で打ち切る。
     * 各グループ内の相対順序は保つ (誕生日は取得順、イベントは近い順ソート済み)。
     *
     * 単純連結 + 先頭 cap 件だと、担当を大量にマークしたユーザーで誕生日が 60 枠を
     * 食い尽くし、ライブ/チケット通知が 0 件になる。カテゴリ間で均等に配る。
     * iOS `NotificationService.roundRobinMerge` と同じ手順。
     */
    fun <T> roundRobinMerge(groups: List<List<T>>, cap: Int): List<T> {
        val result = ArrayList<T>(minOf(cap, groups.sumOf { it.size }))
        val indices = IntArray(groups.size)
        var remaining = groups.sumOf { it.size }
        while (result.size < cap && remaining > 0) {
            for (g in groups.indices) {
                if (result.size >= cap) break
                val i = indices[g]
                if (i >= groups[g].size) continue
                result.add(groups[g][i])
                indices[g]++
                remaining--
            }
        }
        return result
    }

    // MARK: - 担当アイドルの誕生日

    fun birthdayPlans(idols: List<Idol>, now: ZonedDateTime): List<PlannedNotification> =
        idols.mapNotNull { birthdayPlan(it, now) }

    private fun birthdayPlan(idol: Idol, now: ZonedDateTime): PlannedNotification? {
        val birthday = idol.birthday ?: return null

        // マスタの誕生日は "--MM-DD" (RFC 6350 の gDate)。素の "MM-DD" も受ける。
        val raw = if (birthday.startsWith("--")) birthday.substring(2) else birthday
        // 空要素を落とすのは Swift の String.split が既定でそうするから (挙動を揃える)。
        val parts = raw.split("-").filter { it.isNotEmpty() }
        if (parts.size != 2) return null
        val month = parts[0].toIntOrNull() ?: return null
        val day = parts[1].toIntOrNull() ?: return null
        if (month !in 1..12 || day !in 1..31) return null

        val trigger = nextAnnualOccurrence(month, day, hour = 9, minute = 0, now = now) ?: return null
        return PlannedNotification(
            id = "bday_${idol.id}",
            category = NotificationCategory.OSHI_BIRTHDAY,
            title = "🎂 今日は${idol.name}の誕生日！",
            body = "${idol.name}、お誕生日おめでとう！",
            triggerAtMillis = trigger.toInstant().toEpochMilli(),
            imageIdolId = idol.id
        )
    }

    /**
     * 指定の月日の次の到来を返す。
     *
     * iOS は `UNCalendarNotificationTrigger(repeats: true)` で「毎年」を OS に任せられるが、
     * AlarmManager に年次の繰り返しは無い。次の 1 回だけを積み、発火のたびに積み直すことで
     * 同じ挙動にする ([NotificationScheduler] の再スケジュール契機を参照)。
     *
     * 2/29 は閏年にしか存在しない。iOS の日付マッチングも閏年だけ発火するので、
     * ここも「成立する年まで進める」で揃える。
     */
    private fun nextAnnualOccurrence(
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        now: ZonedDateTime
    ): ZonedDateTime? {
        var year = now.year
        repeat(ANNUAL_LOOKAHEAD_YEARS) {
            if (YearMonth.of(year, month).isValidDay(day)) {
                val candidate = LocalDate.of(year, month, day).atTime(hour, minute).atZone(now.zone)
                if (candidate.isAfter(now)) return candidate
            }
            year++
        }
        return null
    }

    // MARK: - 月曜ミーム

    /**
     * 園田智代子の「月曜が近いよ」ミーム。基本は「月曜が近いよ」、たまにレアで
     * 「どぅいどぅいどぅ〜」。回ごとに抽選するため、今後 8 週分の日曜 20:00 を個別に積む。
     *
     * [isRare] を差し込めるようにしてあるのは、乱数を外から固定して文言の出方を
     * 確かめられるようにするため。
     */
    fun mondayMemePlans(
        now: ZonedDateTime,
        isRare: () -> Boolean = { Random.nextInt(MONDAY_MEME_RARE_DENOMINATOR) == 0 }
    ): List<PlannedNotification> {
        // 直近の「次の日曜 20:00」。今が日曜 20:00 ちょうど以前なら今日、過ぎていれば来週。
        var next = now.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY))
            .withHour(20).withMinute(0).withSecond(0).withNano(0)
        if (!next.isAfter(now)) next = next.plusWeeks(1)

        return (0 until MONDAY_MEME_WEEKS).map { i ->
            // レア抽選: SSR級 約0.2% (1/500) で「どぅいどぅいどぅ〜」、通常は「月曜が近いよ」。
            val rare = isRare()
            PlannedNotification(
                id = "monday_meme_$i",
                category = NotificationCategory.MONDAY,
                title = if (rare) "どぅいどぅいどぅ〜" else "月曜が近いよ",
                body = null,
                triggerAtMillis = next.plusWeeks(i.toLong()).toInstant().toEpochMilli(),
                imageIdolId = CHIYOKO_IDOL_ID
            )
        }
    }

    // MARK: - イベント (ライブ1週間前 / チケット締切 / 当落)

    /**
     * お気に入り ∪ 参加マークのイベントから、ライブ 1 週間前とチケット通知を組み立てる。
     * 返り値は発火が近い順 (この後 cap で切られるので、切られるなら遠い方から落ちる)。
     */
    fun eventPlans(
        sources: List<EventNotificationSource>,
        liveWeekEnabled: Boolean,
        ticketEnabled: Boolean,
        now: ZonedDateTime
    ): List<PlannedNotification> {
        if (!liveWeekEnabled && !ticketEnabled) return emptyList()

        val plans = mutableListOf<PlannedNotification>()
        for (source in sources) {
            // 開催が済んだライブには何も出さない (初日が未来のものだけ)。
            val firstDate = parseDate(source.firstDate, now) ?: continue
            if (!firstDate.isAfter(now)) continue

            val event = source.event
            if (liveWeekEnabled) {
                liveWeekPlan(event, firstDate, now)?.let(plans::add)
            }
            if (ticketEnabled) {
                parseDate(event.ticketDeadline, now)
                    ?.takeIf { it.isAfter(now) }
                    ?.let { deadline -> ticketDeadlinePlan(event, deadline, now)?.let(plans::add) }
                parseDate(event.ticketLotteryDate, now)
                    ?.takeIf { it.isAfter(now) }
                    ?.let { lottery -> lotteryPlan(event, lottery)?.let(plans::add) }
            }
        }
        return plans.sortedBy { it.triggerAtMillis }
    }

    /** 初日の 7 日前 10:00。 */
    private fun liveWeekPlan(event: Event, firstDate: ZonedDateTime, now: ZonedDateTime): PlannedNotification? {
        val triggerDay = firstDate.minusDays(7)
        if (!triggerDay.isAfter(now)) return null
        return PlannedNotification(
            id = "live_${event.id}",
            category = NotificationCategory.LIVE_WEEK,
            title = "もうすぐライブ！",
            body = "${event.name} まであと1週間！準備はOK？",
            triggerAtMillis = triggerDay.atHour(10).toInstant().toEpochMilli(),
            imageIdolId = null
        )
    }

    /** 申込締切の前日 18:00。当日 18:00 ではなく前日なのは、締切当日の朝に気付けるようにするため。 */
    private fun ticketDeadlinePlan(event: Event, deadline: ZonedDateTime, now: ZonedDateTime): PlannedNotification? {
        val dayBefore = deadline.minusDays(1)
        if (!dayBefore.isAfter(now)) return null
        return PlannedNotification(
            id = "ticketdl_${event.id}",
            category = NotificationCategory.TICKET,
            title = "チケット申込は明日まで！",
            body = "${event.name} のチケット申込締切は明日です。お忘れなく！",
            triggerAtMillis = dayBefore.atHour(18).toInstant().toEpochMilli(),
            imageIdolId = null
        )
    }

    /** 当落発表日の当日 9:00。 */
    private fun lotteryPlan(event: Event, lotteryDate: ZonedDateTime): PlannedNotification? =
        PlannedNotification(
            id = "lottery_${event.id}",
            category = NotificationCategory.TICKET,
            title = "当落発表日です！",
            body = "${event.name} の当落発表日。ドキドキしながら確認してみよう！",
            triggerAtMillis = lotteryDate.atHour(9).toInstant().toEpochMilli(),
            imageIdolId = null
        )

    /**
     * 同じ日の指定時刻ちょうど。
     * DST のある地域では atStartOfDay が 00:00 にならないことがあるので、
     * 分・秒までまとめて 0 に潰してから時だけ差し替える。
     */
    private fun ZonedDateTime.atHour(hour: Int): ZonedDateTime =
        withHour(hour).withMinute(0).withSecond(0).withNano(0)

    /** "YYYY-MM-DD" → 端末のタイムゾーンでのその日の 00:00。壊れた値は null。 */
    private fun parseDate(value: String?, now: ZonedDateTime): ZonedDateTime? {
        val parts = value?.split("-")?.filter { it.isNotEmpty() } ?: return null
        if (parts.size != 3) return null
        val year = parts[0].toIntOrNull() ?: return null
        val month = parts[1].toIntOrNull() ?: return null
        val day = parts[2].toIntOrNull() ?: return null
        if (month !in 1..12) return null
        if (!YearMonth.of(year, month).isValidDay(day)) return null
        return LocalDate.of(year, month, day).atStartOfDay(now.zone)
    }
}
