package com.fugaif.imaslivedb.data.notification

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.ZonedDateTime

/**
 * ローカル通知の予約と貼り替え。iOS `NotificationService.rescheduleAll` の移植。
 *
 * ## なぜ AlarmManager か (WorkManager ではない)
 *
 * - 通知の時刻は「誕生日の 9:00」「日曜 20:00」のように **壁時計に紐づく**。
 *   WorkManager の OneTimeWorkRequest が表現できるのは initialDelay = 経過時間だけで、
 *   端末の時刻変更やタイムゾーン移動で狙った時刻からずれる。AlarmManager は RTC で
 *   絶対時刻を直接指定できる。
 * - 毎回 60 件を丸ごと貼り替える (iOS と同じく「全消去 → 全再スケジュール」)。
 *   WorkManager は 1 件ごとに内部 DB へ書くので、貼り替えがそのままディスク I/O の
 *   かたまりになる。AlarmManager の予約はシステム側に載るだけで安い。
 * - やることは「通知を 1 本出す」だけ。ネットワーク待ちも再試行も要らないので、
 *   WorkManager の制約・バックオフ機構はまるごと過剰。
 *
 * ## なぜ exact alarm を使わないか (SCHEDULE_EXACT_ALARM を要求しない)
 *
 * - Android 12+ の `setExact*` は SCHEDULE_EXACT_ALARM (ユーザーがシステム設定で個別に
 *   許可する必要がある) を要求し、13+ の USE_EXACT_ALARM は「アラーム/カレンダーが
 *   主目的のアプリ」限定という Play のポリシーがある。ライブ DB は該当しないので、
 *   審査リスクを取ってまで秒精度を買う理由がない。
 * - 誕生日の 9:00 も日曜 20:00 も、数分ずれて価値が落ちる種類の通知ではない。
 * - ただし素の `set()` は Doze 中に次のメンテナンスウィンドウまで丸ごと繰り延べられ、
 *   朝 9 時の通知が夕方に出かねない。そこで [AlarmManager.setAndAllowWhileIdle] を使う:
 *   追加の権限は不要、Doze 中でも発火する、代わりにアプリあたり数分に 1 回までの
 *   レート制限がかかる。本アプリの通知は 1 日数件なので制限には当たらない。
 *
 * ## 再スケジュールの契機
 *
 * - アプリ起動時 (MainActivity) … iOS の ImasLiveDBApp と同じ
 * - 設定トグルの変更時 … iOS の MyPageView と同じ
 * - 端末再起動 / アプリ更新 / 時刻・タイムゾーン変更 ([NotificationBootReceiver])
 *   … AlarmManager の予約はこれらで消える、またはずれるため
 * - 通知が発火した直後 ([NotificationAlarmReceiver])
 *   … iOS の「誕生日は毎年繰り返し」を、次の 1 回を積み直すことで再現する。
 *     AlarmManager に「毎年」は無いので、発火のたびに翌年分を積む。
 */
object NotificationScheduler {

    private const val TAG = "ImasNotification"

    /** 発火時に [NotificationAlarmReceiver] が受け取る action。 */
    const val ACTION_FIRE = "com.fugaif.imaslivedb.NOTIFICATION_FIRE"

    const val EXTRA_ID = "id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_CHANNEL_ID = "channel_id"

    /**
     * 予約を全消去してから、設定が ON の通知を組み直して積む。
     * 通知が許可されていない場合は積まない (iOS の `guard status == .authorized` と同じ)。
     */
    suspend fun rescheduleAll(context: Context): Unit = withContext(Dispatchers.IO) {
        val app = context.applicationContext
        val prefs = NotificationPrefs(app)

        // 未許可なら「積んであるものを消して終わり」。許可を切った直後に残骸が
        // 発火し続けるのを防ぐ (通知自体はシステムが握り潰すが、予約は残るため)。
        if (!areNotificationsEnabled(app)) {
            cancelAllScheduled(app, prefs)
            return@withContext
        }

        ensureChannels(app)

        val module = AppModule.from(app)
        val now = ZonedDateTime.now()

        // カテゴリごとに独立したグループとして組み立てる (iOS と同じ 3 グループ)。
        // 1. 担当アイドル誕生日
        val birthdayPlans = if (prefs.isEnabled(NotificationCategory.OSHI_BIRTHDAY)) {
            runCatching { NotificationPlanner.birthdayPlans(module.userMarkRepository.pickedIdols(), now) }
                .onFailure { Log.e(TAG, "notif_birthday_fetch_failed", it) }
                .getOrDefault(emptyList())
        } else {
            emptyList()
        }
        // 2. 月曜ミーム (回ごとにレア文言を抽選するため個別に積む)
        val mondayPlans = if (prefs.isEnabled(NotificationCategory.MONDAY)) {
            NotificationPlanner.mondayMemePlans(now)
        } else {
            emptyList()
        }
        // 3. ライブ1週間前 + 4. チケット締切/当落 (近い順ソート済み)
        val eventPlans = runCatching {
            NotificationPlanner.eventPlans(
                sources = eventSources(module),
                liveWeekEnabled = prefs.isEnabled(NotificationCategory.LIVE_WEEK),
                ticketEnabled = prefs.isEnabled(NotificationCategory.TICKET),
                now = now
            )
        }.onFailure { Log.e(TAG, "notif_event_fetch_failed", it) }.getOrDefault(emptyList())

        // 合計 60 件 cap。単純連結 + 先頭 60 件だと誕生日が枠を食い尽くしうるので、
        // カテゴリを round-robin で混ぜてどのカテゴリも枠を独占しないようにする。
        val capped = NotificationPlanner.roundRobinMerge(
            listOf(birthdayPlans, mondayPlans, eventPlans),
            NotificationPlanner.MAX_SCHEDULED
        )

        cancelAllScheduled(app, prefs)

        // 過去時刻のアラームは「即発火」になる。組み立て側でも未来だけを通しているが、
        // 端末の時刻がずれていた場合に通知が一気に降ってくるのを防ぐ最後の関門。
        val nowMillis = System.currentTimeMillis()
        val armed = capped.filter { it.triggerAtMillis > nowMillis }
        armed.forEach { schedule(app, it) }
        prefs.setScheduledIds(armed.map { it.id })

        Log.i(TAG, "notif_rescheduled total=${armed.size}")
    }

    /**
     * 通知が出せる状態か。
     * Android 13+ は POST_NOTIFICATIONS のランタイム権限、それ以前とチャンネル単位の
     * 無効化はシステム設定側のスイッチで決まるので、両方を見る。
     */
    fun areNotificationsEnabled(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
            if (granted != PackageManager.PERMISSION_GRANTED) return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /**
     * 通知チャンネルを用意する。作成済みなら何も起きない (id が同じなら再作成されない)。
     * 発火側の Receiver からも呼ぶ: 通知を出す時点でチャンネルが無いと黙って捨てられるため。
     */
    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        NotificationCategory.entries.forEach { category ->
            val channel = NotificationChannel(
                category.channelId,
                category.channelName,
                // 音は鳴らすが画面を占有しない。ファン向けのリマインドであって緊急ではない。
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = category.channelDescription }
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * お気に入り ∪ 参加マークのイベントを、チケット日程まで揃った形で返す。
     *
     * 一覧クエリ (`fetchEventsWithDateRangeByIds` 等) は ticket_deadline /
     * ticket_lottery_date を SELECT していないので、iOS が `fetchFullEvents` で
     * 取り直しているのと同じ理由でイベント本体を引き直す。
     */
    private suspend fun eventSources(module: AppModule): List<EventNotificationSource> {
        val marks = module.userMarkRepository
        val byId = LinkedHashMap<String, EventWithDateRange>()
        (marks.favoriteEvents() + marks.attendedEvents()).forEach { byId.putIfAbsent(it.event.id, it) }
        return byId.values.mapNotNull { withDate ->
            val full = module.eventRepository.fetchEvent(withDate.event.id) ?: return@mapNotNull null
            EventNotificationSource(event = full, firstDate = withDate.firstDate)
        }
    }

    private fun schedule(context: Context, plan: PlannedNotification) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = fireIntent(context, plan.id).apply {
            putExtra(EXTRA_ID, plan.id)
            putExtra(EXTRA_TITLE, plan.title)
            putExtra(EXTRA_BODY, plan.body)
            putExtra(EXTRA_CHANNEL_ID, plan.category.channelId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            plan.id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // 権限不要で Doze も越える組み合わせ。精度は数分の幅を許容する (クラス冒頭の理由)。
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, plan.triggerAtMillis, pendingIntent)
    }

    /** 積んである予約を全部取り消す。iOS の `removeAllPendingNotificationRequests()` 相当。 */
    private fun cancelAllScheduled(context: Context, prefs: NotificationPrefs) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        prefs.scheduledIds().forEach { id ->
            // 登録時と「同じ」PendingIntent でないと取り消せない。PendingIntent の同一性は
            // extras を見ず action / data / component / requestCode で決まるので、
            // data に id を埋めた fireIntent を作り直せば必ず同じものを掴める。
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id.hashCode(),
                fireIntent(context, id),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            ) ?: return@forEach
            alarmManager?.cancel(pendingIntent)
            pendingIntent.cancel()
        }
        prefs.setScheduledIds(emptyList())
    }

    /**
     * 通知 1 件に対応する Intent。
     * data の URI に id を入れているのは、PendingIntent を通知ごとに別物として
     * 扱わせるため (extras は同一性判定に使われないので、これが無いと 60 件が
     * 1 件に潰れて最後の 1 本しか鳴らない)。
     */
    private fun fireIntent(context: Context, id: String): Intent =
        Intent(context, NotificationAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            data = Uri.parse("imas-notif://$id")
        }
}
