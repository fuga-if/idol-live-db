package com.fugaif.imaslivedb.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.updateAll
import com.fugaif.imaslivedb.data.model.JstDay
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * ウィジェットを「日付が変わったら」描き直すための予約。
 *
 * ## なぜ AlarmManager か (WorkManager でも updatePeriodMillis でもなく)
 *
 * - 更新したいのは **壁時計の 0 時ちょうど**。WorkManager が表現できるのは
 *   「今から N 時間後」だけで、端末の時刻変更やタイムゾーン移動で狙った時刻からずれる。
 *   AlarmManager は RTC で絶対時刻を直接指定できる。
 * - `appwidget-provider` の `updatePeriodMillis` は最短 30 分の**周期**で、しかも起点は
 *   ウィジェットを置いた時刻。「0 時に 1 回」を表現できないうえ、1 日 48 回起こされる。
 * - WorkManager は制約 (ネットワーク待ち・充電中) と再試行のための仕組みで、
 *   1 回ぶんの予約ごとに内部 DB へ書く。ここでやるのは「描き直す」だけなので、
 *   その機構はまるごと過剰。依存も増える (Glance は WorkManager を要求しない)。
 * - 何より、このアプリの通知が既に AlarmManager で同じことをしている
 *   ([com.fugaif.imaslivedb.data.notification.NotificationScheduler])。同じ目的に
 *   2 つのスケジューラを同居させない方が、予約が消える条件 (再起動・時刻変更) の
 *   扱いも 1 か所で済む。
 *
 * ## なぜ exact alarm を使わないか
 *
 * `setExact*` は Android 12+ で SCHEDULE_EXACT_ALARM (ユーザーの個別許可) を要求する。
 * ウィジェットの「あと N 日」が 0 時ちょうどに変わるか 0 時数分過ぎに変わるかは
 * 誰も困らないので、権限不要で Doze も越える [AlarmManager.setAndAllowWhileIdle] を使う
 * (通知側と同じ判断)。
 *
 * ## 予約が消える/ずれる契機
 *
 * 端末再起動・アプリ更新・時刻/タイムゾーン変更で予約は消えるかずれる。
 * [WidgetUpdateReceiver] がそれらを受けて積み直す。ウィジェットが 1 個も無くなったら
 * ([ImasWidgetReceiver.onDisabled]) 予約も消す。
 */
object WidgetUpdateScheduler {

    private const val TAG = "ImasWidget"

    /** 日付が変わったときの更新。自アプリの AlarmManager からしか来ない。 */
    const val ACTION_DAILY_REFRESH = "com.fugaif.imaslivedb.WIDGET_DAILY_REFRESH"

    private const val REQUEST_CODE = 0x7715

    /** 境界をまたいだことを確実にするための余白。数十秒ずれても誰も困らない。 */
    private const val BOUNDARY_MARGIN_SECONDS = 30L

    /** 5 種のウィジェットの provider。設置数の確認に使う。 */
    private val PROVIDERS: List<Class<out GlanceAppWidgetReceiver>> = listOf(
        OshiImageWidgetReceiver::class.java,
        OshiLauncherWidgetReceiver::class.java,
        NextLiveWidgetReceiver::class.java,
        TodaySongWidgetReceiver::class.java,
        TicketDeadlineWidgetReceiver::class.java
    )

    /**
     * 次の「日付が変わる瞬間」に更新を予約する (同じ PendingIntent なので何度呼んでも 1 件)。
     * ウィジェットが 1 個も置かれていなければ何もしない。
     */
    fun scheduleNextMidnight(context: Context) {
        val appContext = context.applicationContext
        if (!hasAnyWidget(appContext)) return
        val alarmManager = appContext.getSystemService(AlarmManager::class.java) ?: return
        val triggerAt = nextDayBoundary().toInstant().toEpochMilli()
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, refreshIntent(appContext))
        Log.i(TAG, "widget_refresh_scheduled at=$triggerAt")
    }

    /** 予約を取り消す (最後の 1 個が外されたとき)。 */
    fun cancel(context: Context) {
        val appContext = context.applicationContext
        val alarmManager = appContext.getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(refreshIntent(appContext))
    }

    /** ホーム画面に 1 個でもこのアプリのウィジェットが置かれているか。 */
    fun hasAnyWidget(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context) ?: return false
        return PROVIDERS.any { provider ->
            manager.getAppWidgetIds(ComponentName(context, provider))?.isNotEmpty() == true
        }
    }

    /**
     * 置いてあるウィジェットを全部描き直す。
     * 情報 3 種は日付が変われば中身が変わる。担当画像は次の 1 枚へ送る
     * (自動スライドショーの実体。理由は [advanceAllOshiWidgets])。
     */
    suspend fun refreshAll(context: Context) {
        val appContext = context.applicationContext
        NextLiveWidget.updateAll(appContext)
        TodaySongWidget.updateAll(appContext)
        TicketDeadlineWidget.updateAll(appContext)
        advanceAllOshiWidgets(appContext)
    }

    /**
     * 次に「日付が変わる」瞬間。
     *
     * このアプリには日付の基準が 2 つある — ライブの開催日・チケット締切は JST 固定
     * ([JstDay])、今日の 1 曲は端末ローカル日 ([com.fugaif.imaslivedb.data.model.DailyPick])。
     * 日本にいる端末では同じ瞬間だが、海外では別の時刻に来る。**近い方**を次の予約にして、
     * 発火のたびに積み直せば、どちらの境界も取りこぼさない。
     */
    private fun nextDayBoundary(now: ZonedDateTime = ZonedDateTime.now()): ZonedDateTime {
        val deviceZone = ZoneId.systemDefault()
        val localMidnight = now.toLocalDate().plusDays(1).atStartOfDay(deviceZone)
        val jstMidnight = now.withZoneSameInstant(JstDay.zone)
            .toLocalDate().plusDays(1).atStartOfDay(JstDay.zone)
            .withZoneSameInstant(deviceZone)
        val nearest = if (localMidnight.isBefore(jstMidnight)) localMidnight else jstMidnight
        return nearest.plusSeconds(BOUNDARY_MARGIN_SECONDS)
    }

    /**
     * 予約 1 件ぶんの PendingIntent。
     * 明示 Intent (コンポーネント指定) なので他アプリからは叩けない。
     */
    private fun refreshIntent(context: Context): PendingIntent {
        val intent = Intent(context, WidgetUpdateReceiver::class.java).apply {
            action = ACTION_DAILY_REFRESH
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

/**
 * 5 種のウィジェット共通の Receiver。Glance の受け口に「更新予約の面倒を見る」だけを足す。
 *
 * - [onUpdate] … ウィジェットが置かれた/更新された。ここで予約を積む
 *   (置いた直後から日付変わりに追随させるため。同じ予約は上書きされるので重複しない)。
 * - [onDisabled] … その種類の最後の 1 個が外された。**全種類**が無くなったときだけ予約を消す。
 */
abstract class ImasWidgetReceiver : GlanceAppWidgetReceiver() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        WidgetUpdateScheduler.scheduleNextMidnight(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        if (!WidgetUpdateScheduler.hasAnyWidget(context)) WidgetUpdateScheduler.cancel(context)
    }
}
