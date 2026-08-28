package com.fugaif.imaslivedb.ui.schedule

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import com.fugaif.imaslivedb.data.model.CalShowRow
import com.fugaif.imaslivedb.data.repository.CalendarShowDetail
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/**
 * 公演を端末のカレンダーアプリへ登録する (iOS の `CalendarExportService` に対応)。
 *
 * `ACTION_INSERT` はカレンダーアプリの新規作成画面を開くだけなので **権限が要らない**。
 * 読み取り (`READ_CALENDAR`) を使う「端末の予定を重ねて表示」とは別の機能で、
 * 追加だけならユーザーに権限ダイアログを見せずに済む。最終的な保存はユーザーが
 * カレンダーアプリ側で押すため、アプリが黙って予定を書き込むこともない。
 */
object DeviceCalendar {

    /** 公演の日付は日本の開催日なので、開始/終了時刻は JST で組む。 */
    private val JST: ZoneId = ZoneId.of("Asia/Tokyo")

    /** 終了時刻のデータが無いので、iOS と同じく 2 時間の予定として登録する。 */
    private const val DEFAULT_DURATION_MINUTES = 120L

    /**
     * カレンダーアプリの「予定を追加」画面を開く。
     *
     * 予定名には**正式なライブ名**を使う (省略表示の設定は一覧の見やすさのためのもので、
     * 端末カレンダーに残るのは後から検索する名前だから)。
     *
     * @return カレンダーアプリが見つからず開けなかった場合 false。
     */
    fun addShow(context: Context, row: CalShowRow, detail: CalendarShowDetail?): Boolean {
        val date = runCatching { LocalDate.parse(row.date) }.getOrNull() ?: return false
        val startMinutes = parseTimeMinutes(detail?.startTime)
        val title = listOfNotNull(row.eventName, row.showName.takeIf { it.isNotBlank() })
            .distinct()
            .joinToString(" ")

        val intent = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, title)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        detail?.venue?.takeIf { it.isNotBlank() }
            ?.let { intent.putExtra(CalendarContract.Events.EVENT_LOCATION, it) }

        if (startMinutes == null) {
            // 開始時刻が未登録の公演は終日予定にする。0:00〜2:00 の予定にすると嘘になるため。
            val begin = date.atStartOfDay(JST).toInstant().toEpochMilli()
            intent.putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true)
                .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
                .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, begin)
        } else {
            val start = date.atTime(LocalTime.of(startMinutes / 60, startMinutes % 60)).atZone(JST)
            intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start.toInstant().toEpochMilli())
                .putExtra(
                    CalendarContract.EXTRA_EVENT_END_TIME,
                    start.plusMinutes(DEFAULT_DURATION_MINUTES).toInstant().toEpochMilli()
                )
        }

        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
