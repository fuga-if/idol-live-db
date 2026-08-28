package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Anniversary
import com.fugaif.imaslivedb.data.model.CalAnniversaryRow
import com.fugaif.imaslivedb.data.model.CalBirthdayRow
import com.fugaif.imaslivedb.data.model.CalReleaseRow
import com.fugaif.imaslivedb.data.model.CalShowRow
import com.fugaif.imaslivedb.data.model.CalStaffBirthdayRow
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.Staff
import com.fugaif.imaslivedb.data.model.TicketCalendarRow
import com.fugaif.imaslivedb.data.model.TicketDateKind
import com.fugaif.imaslivedb.data.model.TicketPeriodRow
import uniffi.imas_core.CalendarEntryRecord
import uniffi.imas_core.CalendarTicketKind
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit

/**
 * カレンダー (公演/リリース/誕生日/事務員誕生日/記念日/チケット日程) の読み取り口。
 *
 * 第一経路は共有コア (imas-core) の `calendarEntries`。表示範囲の絞り込み・誕生日と記念日の
 * 年展開・同日内の並び順はすべてコアが確定させる (SQL 時代の 5 クエリが 1 呼び出しになる)。
 * コアが返すのは公演とチケットの素の値、それ以外は **id だけ**なので、実体化はここで行う
 * (iOS `CoreCalendarRepository` と同じ分担)。
 *
 * スナップショットが使えないビルド/タイミングでは Room の月単位クエリへフォールバックする。
 * フォールバックは仕様の正本ではないので、挙動を足すときはコア側を直すこと。
 */
class CalendarRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null
) {

    /**
     * [start]〜[end] (両端含む) に出現するカレンダーエントリと、公演の追加情報。
     * 並びはコアが確定させた表示順。
     *
     * 呼び出し側が渡すのは月グリッドの実描画範囲 (6 行 × 7 列 = 42 日) で、暦月ちょうどでは
     * ない。グリッドは前後の月の日も描き、週表示は月をまたぐので、暦月で切ると端の日だけ
     * 空になるため (iOS `CalendarView.monthGridInterval` と同じ範囲)。
     *
     * 公演の追加情報 (開始時刻・会場・ブランド色) はコアの射影 `CalendarEntryRecord.Show`
     * には載っているが、表示用の `CalShowRow` には無い列。週の時間グリッドは開始時刻が
     * 無いと縦位置を決められないので、行の型を変えずに別マップで運ぶ
     * (`data/model` の行定義は共有物なので、カレンダーの都合で列を足さない)。
     *
     * Room フォールバックは月単位のクエリしか持たないので、範囲の中心にあたる月で代用する
     * (端の数日が欠けるが、この経路はスナップショットが載るまでの一時的な受け皿)。
     * 追加情報もあちらでは取れないので空になり、全公演が「時刻未定」レーンに出る。
     */
    suspend fun fetchRange(start: LocalDate, end: LocalDate): CalendarMonthData {
        snapshots?.query { store -> store.calendarEntries(start.toString(), end.toString()) }
            ?.let { return CalendarMonthData(hydrate(it), showDetails(it)) }
        val middle = YearMonth.from(start.plusDays(ChronoUnit.DAYS.between(start, end) / 2))
        return CalendarMonthData(fetchEntriesFromRoom(middle), emptyMap())
    }

    /** コアの公演射影から、行に載らない列だけを show_id 引きのマップに落とす。 */
    private fun showDetails(records: List<CalendarEntryRecord>): Map<String, CalendarShowDetail> =
        records.filterIsInstance<CalendarEntryRecord.Show>().associate { record ->
            record.showId to CalendarShowDetail(
                startTime = record.startTime,
                venue = record.venue,
                brandColor = record.brandColor
            )
        }

    // ---- スナップショット経路: id → 実体 ----

    /**
     * コアの射影を表示用エントリへ実体化する。
     *
     * 実体が引けなかった行は落とす (id だけ残ったマスタ不整合の行を出さない)。
     * 参照する実体は種別ごとに 1 回ずつまとめて引く (エントリごとに DB を叩かない)。
     */
    private suspend fun hydrate(records: List<CalendarEntryRecord>): List<CalendarEntry> {
        if (records.isEmpty()) return emptyList()

        val songs = hydrateSongs(records)
        val idols = hydrateIdols(records)
        // 事務員と記念日はスナップショット対象外。該当が 1 件も無い月が大半なので、
        // そのときは DB を触らない。
        val staff: Map<String, Staff> = if (records.any { it is CalendarEntryRecord.StaffBirthday }) {
            db.calendarDao().fetchAllStaff().associateBy { it.id }
        } else {
            emptyMap()
        }
        val anniversaries: Map<String, Anniversary> = if (records.any { it is CalendarEntryRecord.Anniversary }) {
            db.calendarDao().fetchAllAnniversaries().associateBy { it.id }
        } else {
            emptyMap()
        }

        return records.mapNotNull { record ->
            when (record) {
                is CalendarEntryRecord.Show -> CalendarEntry.Show(
                    date = record.date,
                    row = CalShowRow(
                        showId = record.showId,
                        date = record.date,
                        showName = record.name,
                        eventId = record.eventId,
                        eventName = record.eventName,
                        brandId = record.brandId
                    )
                )

                is CalendarEntryRecord.Release -> {
                    // song_ids の並び (title_kana 昇順) が表示順。1 曲も引けない日は行ごと出さない。
                    val rows = record.songIds.mapNotNull { id ->
                        songs[id]?.let { CalReleaseRow(it.id, it.title, record.date, it.brandId) }
                    }
                    rows.takeIf { it.isNotEmpty() }
                        ?.let { CalendarEntry.Release(date = record.date, songs = it) }
                }

                is CalendarEntryRecord.Birthday -> idols[record.idolId]?.let { idol ->
                    CalendarEntry.Birthday(
                        date = record.occursOn,
                        row = CalBirthdayRow(idol.id, idol.name, idol.brandId, idol.birthday.orEmpty())
                    )
                }

                is CalendarEntryRecord.StaffBirthday -> staff[record.staffId]?.let { s ->
                    CalendarEntry.StaffBirthday(
                        date = record.occursOn,
                        row = CalStaffBirthdayRow(s.id, s.name, s.brandId, s.birthday.orEmpty(), s.role)
                    )
                }

                is CalendarEntryRecord.Anniversary -> {
                    // occursOn は「表示範囲の年に展開した当日」なので、その年の周年数になる
                    // (コアは起点年より前を展開しないので負にならない)。
                    val ann = anniversaries[record.anniversaryId]
                    val years = record.occursOn.take(4).toIntOrNull()?.let { ann?.anniversaryYears(it) }
                    if (ann == null || years == null) {
                        null
                    } else {
                        CalendarEntry.Anniversary(
                            date = record.occursOn,
                            row = CalAnniversaryRow(ann.id, ann.label, ann.date, ann.brandId, ann.kind),
                            years = years
                        )
                    }
                }

                is CalendarEntryRecord.Ticket -> CalendarEntry.Ticket(
                    date = record.date,
                    row = TicketCalendarRow(
                        eventId = record.eventId,
                        eventName = record.eventName,
                        brandColor = record.brandColor,
                        date = record.date,
                        kind = when (record.kind) {
                            CalendarTicketKind.DEADLINE -> TicketDateKind.DEADLINE
                            CalendarTicketKind.LOTTERY -> TicketDateKind.LOTTERY
                        },
                        url = record.url
                    )
                )

                is CalendarEntryRecord.TicketPeriod -> CalendarEntry.TicketPeriod(
                    date = record.start,
                    row = TicketPeriodRow(
                        eventId = record.eventId,
                        eventName = record.eventName,
                        brandColor = record.brandColor,
                        start = record.start,
                        end = record.end,
                        url = record.url
                    )
                )
            }
        }
    }

    private suspend fun hydrateSongs(records: List<CalendarEntryRecord>): Map<String, Song> {
        val ids = records.filterIsInstance<CalendarEntryRecord.Release>().flatMap { it.songIds }
        if (ids.isEmpty()) return emptyMap()
        return hydrateInOrder(ids, Song::id) { db.songDao().fetchSongsByIds(it) }.associateBy { it.id }
    }

    private suspend fun hydrateIdols(records: List<CalendarEntryRecord>): Map<String, Idol> {
        val ids = records.filterIsInstance<CalendarEntryRecord.Birthday>().map { it.idolId }
        if (ids.isEmpty()) return emptyMap()
        return hydrateInOrder(ids, Idol::id) { db.idolDao().fetchIdolsByIds(it) }.associateBy { it.id }
    }

    // ---- フォールバック: 旧 SQL 経路 ----

    /**
     * スナップショット未ロード時の受け皿。月単位の 5 クエリを引き、コアと同じ並び
     * (日付 → 種別順位: 公演 < リリース < 記念日 < 誕生日 < 事務員誕生日) に整える。
     *
     * チケット日程はここでは出ない。events のチケット列を読む SQL がもともと無く、
     * この経路のためだけに書き起こすと消したはずの二重実装が戻るため
     * (スナップショットが載れば出る)。
     */
    private suspend fun fetchEntriesFromRoom(month: YearMonth): List<CalendarEntry> {
        val dao = db.calendarDao()
        val ym = "%04d-%02d".format(month.year, month.monthValue)
        val mm = "%02d".format(month.monthValue)
        // (ソートキー, 種別順位, エントリ)。ソートキーは記念日だけ「起点日」で、それ以外は
        // 出現日 — コアの並びと同じ規則にしないと同日内の順序がフォールバックだけずれる。
        val keyed = mutableListOf<Triple<String, Int, CalendarEntry>>()

        for (row in dao.showsInMonth(ym)) {
            keyed += Triple(row.date, RANK_SHOW, CalendarEntry.Show(row.date, row))
        }
        for ((date, rows) in dao.releasesInMonth(ym).groupBy { it.releaseDate }) {
            keyed += Triple(date, RANK_RELEASE, CalendarEntry.Release(date, rows))
        }
        for (row in dao.birthdaysInMonth(mm)) {
            occurrenceOf(row.birthday, month)?.let {
                keyed += Triple(it, RANK_BIRTHDAY, CalendarEntry.Birthday(it, row))
            }
        }
        for (row in dao.staffBirthdaysInMonth(mm)) {
            occurrenceOf(row.birthday, month)?.let {
                keyed += Triple(it, RANK_STAFF_BIRTHDAY, CalendarEntry.StaffBirthday(it, row))
            }
        }
        for (row in dao.anniversariesInMonth(mm)) {
            val years = Anniversary(row.id, row.brandId, row.label, row.date, row.kind)
                .anniversaryYears(month.year) ?: continue
            occurrenceOf("--" + row.date.drop(5), month)?.let {
                keyed += Triple(row.date, RANK_ANNIVERSARY, CalendarEntry.Anniversary(it, row, years))
            }
        }

        keyed.sortWith(compareBy<Triple<String, Int, CalendarEntry>> { it.first }.thenBy { it.second })
        return keyed.map { it.third }
    }

    /** "--MM-DD" を [month] の実在日へ。その月に無い日 (非閏年の 2/29 等) は落とす。 */
    private fun occurrenceOf(monthDay: String, month: YearMonth): String? {
        val day = monthDay.removePrefix("--").substringAfter('-').toIntOrNull() ?: return null
        if (day !in 1..month.lengthOfMonth()) return null
        return "%04d-%02d-%02d".format(month.year, month.monthValue, day)
    }

    private companion object {
        // 同日内の表示順位。コア (domain/calendar_queries.rs) の定数と同じ数値。
        const val RANK_SHOW = 2
        const val RANK_RELEASE = 3
        const val RANK_ANNIVERSARY = 4
        const val RANK_BIRTHDAY = 5
        const val RANK_STAFF_BIRTHDAY = 6
    }
}

/**
 * 月ぶんのカレンダーデータ。並びが確定したエントリ列と、公演の追加情報。
 * 追加情報を別に持つ理由は [CalendarRepository.fetchMonth] を参照。
 */
data class CalendarMonthData(
    val entries: List<CalendarEntry>,
    /** show_id → 追加情報。フォールバック経路では空。 */
    val showDetails: Map<String, CalendarShowDetail>
)

/** `CalShowRow` に無い公演の列 (週の時間グリッド・日詳細で使う)。 */
data class CalendarShowDetail(
    /** "HH:MM"。未定・未登録は null (= 終日レーン行き)。 */
    val startTime: String?,
    val venue: String?,
    /** ブランドカラー hex。コアが JOIN 済みの値をそのまま運ぶ。 */
    val brandColor: String?
)
