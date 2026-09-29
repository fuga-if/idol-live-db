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
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.random.Random
import uniffi.imas_core.NotificationKind
import uniffi.imas_core.NotificationPlanInput
import uniffi.imas_core.PlannedNotificationRecord

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
     * 「全消去 → 全再スケジュール」を直列化する。
     * 起動直後は MainActivity とアラーム発火の Receiver が同時に走りうる。
     * 途中で別の実行が割り込むと、予約 id の台帳 (NotificationPrefs.scheduledIds) と
     * 実際に積まれたアラームが食い違い、消し漏れた通知が残る。
     */
    private val rescheduleMutex = Mutex()

    /**
     * 予約を全消去してから、設定が ON の通知を組み直して積む。
     * 通知が許可されていない場合は積まない (iOS の `guard status == .authorized` と同じ)。
     */
    suspend fun rescheduleAll(context: Context, reason: RescheduleReason = RescheduleReason.REFRESH): Unit =
        rescheduleAll(context, reason, ::buildPlan)

    /** [plan] を差し替えられる入口 (テスト用)。本番は [buildPlan]。 */
    internal suspend fun rescheduleAll(
        context: Context,
        reason: RescheduleReason,
        plan: suspend (Context, NotificationPrefs, ZonedDateTime) -> List<PlannedNotificationRecord>
    ): Unit = withContext(Dispatchers.IO) {
        rescheduleMutex.withLock { rescheduleAllLocked(context, reason, plan) }
    }

    /** 再予約を頼む理由。予定表を作れなかったときの扱いが変わる (iOS と同じ)。 */
    enum class RescheduleReason {
        /** 起動時・許可した直後・設定を ON にしたとき・発火や再起動の後。 */
        REFRESH,
        /** 通知の設定を OFF にしたとき。 */
        SETTING_TURNED_OFF
    }

    /** 今の予約をどうするか。 */
    enum class PendingUpdate { KEEP, CLEAR, REPLACE }

    /**
     * 権限が無ければ消す (鳴らしてはいけない)。予定表を作れたら全部消して積み直す。
     * 作れなかったときは、OFF にした直後なら消す (OFF にした通知が鳴り続けないように)。
     * それ以外は今の予約を残す (読み込みの一時的な失敗で、鳴るはずの通知を消さない)。
     * iOS `NotificationService.pendingUpdate` と同じ。
     */
    internal fun pendingUpdate(authorized: Boolean, planBuilt: Boolean, reason: RescheduleReason): PendingUpdate =
        when {
            !authorized -> PendingUpdate.CLEAR
            planBuilt -> PendingUpdate.REPLACE
            reason == RescheduleReason.SETTING_TURNED_OFF -> PendingUpdate.CLEAR
            else -> PendingUpdate.KEEP
        }

    private suspend fun rescheduleAllLocked(
        context: Context,
        reason: RescheduleReason,
        plan: suspend (Context, NotificationPrefs, ZonedDateTime) -> List<PlannedNotificationRecord>
    ) {
        val app = context.applicationContext
        val prefs = NotificationPrefs(app)

        val authorized = areNotificationsEnabled(app)
        val now = ZonedDateTime.now()
        val plans = if (authorized) {
            ensureChannels(app)
            runCatching { plan(app, prefs, now) }
                .onFailure { Log.e(TAG, "notif_plan_failed", it) }
                .getOrNull()
        } else {
            null
        }

        // 未許可なら消して終わり (許可を切った直後に残骸が発火し続けるのを防ぐ)。
        // 予定表を作れなかったら、OFF にした直後だけ消し、それ以外は今の予約を残す。
        when (pendingUpdate(authorized, plans != null, reason)) {
            PendingUpdate.KEEP -> return
            PendingUpdate.CLEAR -> {
                cancelAllScheduled(app, prefs)
                return
            }
            PendingUpdate.REPLACE -> cancelAllScheduled(app, prefs)
        }
        if (plans == null) return

        // 過去時刻のアラームは「即発火」になる。組み立て側でも未来だけを通しているが、
        // 端末の時刻がずれていた場合に通知が一気に降ってくるのを防ぐ最後の関門。
        val nowMillis = System.currentTimeMillis()
        val armed = plans.map { it to triggerAtMillis(it, now.zone) }.filter { (_, at) -> at > nowMillis }
        armed.forEach { (plan, at) -> schedule(app, plan, at) }
        prefs.setScheduledIds(armed.map { (plan, _) -> plan.id })

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
     * 予定表を組む。何を・いつ・どの文言で積むか (誕生日・月曜のミーム・ライブ 1 週間前・
     * チケット、60 件の上限とカテゴリ間の round-robin) は全部コアの予定表 (notificationPlan)。
     * ここは設定とマークを詰めて 1 回呼ぶだけ。読めなければ投げる (呼び元が予約を残す)。
     */
    private suspend fun buildPlan(
        context: Context,
        prefs: NotificationPrefs,
        now: ZonedDateTime
    ): List<PlannedNotificationRecord> {
        val module = AppModule.from(context)
        val input = NotificationPlanInput(
            today = now.toLocalDate().toString(),
            nowMinutes = (now.hour * 60 + now.minute).toUInt(),
            birthdayEnabled = prefs.isEnabled(NotificationCategory.OSHI_BIRTHDAY),
            mondayEnabled = prefs.isEnabled(NotificationCategory.MONDAY),
            liveWeekEnabled = prefs.isEnabled(NotificationCategory.LIVE_WEEK),
            ticketEnabled = prefs.isEnabled(NotificationCategory.TICKET),
            pickIdolIds = module.userMarkRepository.pickedIdolIds().toList(),
            eventIds = markedEventIds(module),
            seed = Random.nextLong().toULong()
        )
        return module.snapshotStoreProvider.query { store -> store.notificationPlan(input) }
    }

    /** お気に入り ∪ 参加マーク (公演単位のマークはそのイベント) のイベント id。 */
    private suspend fun markedEventIds(module: AppModule): List<String> {
        val events = module.eventRepository
        return (events.fetchFavoriteEvents() + events.fetchAttendedEvents()).map { it.event.id }.distinct()
    }

    /**
     * 予定表の日時 (その地の暦の日付 + 時・分) を端末のゾーンで絶対時刻に直す。
     *
     * `repeatsYearly` (毎年くり返してよい誕生日) も、AlarmManager に年次の繰り返しは無いので
     * 次の 1 回だけを積む。発火のたびに [NotificationAlarmReceiver] が全体を積み直し、
     * そのときコアが翌年の同じ月日を返すので、アプリを開かなくても翌年も鳴る。
     */
    private fun triggerAtMillis(plan: PlannedNotificationRecord, zone: ZoneId): Long =
        LocalDate.parse(plan.date)
            .atTime(plan.hour.toInt(), plan.minute.toInt())
            .atZone(zone)
            .toInstant()
            .toEpochMilli()

    private fun schedule(context: Context, plan: PlannedNotificationRecord, triggerAtMillis: Long) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = fireIntent(context, plan.id).apply {
            putExtra(EXTRA_ID, plan.id)
            putExtra(EXTRA_TITLE, plan.title)
            putExtra(EXTRA_BODY, plan.body)
            putExtra(EXTRA_CHANNEL_ID, plan.kind.category.channelId)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            plan.id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // 権限不要で Doze も越える組み合わせ。精度は数分の幅を許容する (クラス冒頭の理由)。
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
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

/** コアの通知の種類 → チャンネル (設定の単位)。 */
private val NotificationKind.category: NotificationCategory
    get() = when (this) {
        NotificationKind.OSHI_BIRTHDAY -> NotificationCategory.OSHI_BIRTHDAY
        NotificationKind.MONDAY -> NotificationCategory.MONDAY
        NotificationKind.LIVE_WEEK -> NotificationCategory.LIVE_WEEK
        NotificationKind.TICKET -> NotificationCategory.TICKET
    }
