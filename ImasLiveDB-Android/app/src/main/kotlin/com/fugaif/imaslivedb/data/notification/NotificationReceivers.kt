package com.fugaif.imaslivedb.data.notification

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.fugaif.imaslivedb.MainActivity
import com.fugaif.imaslivedb.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

private const val TAG = "ImasNotification"

/**
 * BroadcastReceiver の中で DB を触る再スケジュールを回すための足場。
 *
 * onReceive はメインスレッドかつ数秒で戻らないと ANR になるので、goAsync() で
 * 生存期間を伸ばしつつ IO へ逃がす。finish() を必ず呼ばないとプロセスが
 * 生かされたままになるため finally で締める。
 */
private fun BroadcastReceiver.rescheduleAsync(context: Context) {
    val appContext = context.applicationContext
    val pendingResult = goAsync()
    CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
        try {
            NotificationScheduler.rescheduleAll(appContext)
        } catch (e: Exception) {
            Log.e(TAG, "notif_reschedule_failed", e)
        } finally {
            pendingResult.finish()
        }
    }
}

/**
 * 予約時刻に叩かれて通知を 1 本出す。
 *
 * 出したあとに全体を積み直すのは、iOS の「誕生日は毎年繰り返し」を再現するため。
 * AlarmManager に年次繰り返しは無いので、発火のたびに次の 1 回 (翌年分) を積む。
 * ついでにアプリを開かないユーザーでも予定表が古びない (月曜ミームの 8 週分も
 * ここで補充されていく)。
 */
class NotificationAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != NotificationScheduler.ACTION_FIRE) return

        val id = intent.getStringExtra(NotificationScheduler.EXTRA_ID)
        val title = intent.getStringExtra(NotificationScheduler.EXTRA_TITLE)
        val channelId = intent.getStringExtra(NotificationScheduler.EXTRA_CHANNEL_ID)
        if (id == null || title == null || channelId == null) return
        val body = intent.getStringExtra(NotificationScheduler.EXTRA_BODY)

        postNotification(context, id, title, body, channelId)

        // 発火した 1 件を消化した状態から積み直す。
        rescheduleAsync(context)
    }

    private fun postNotification(
        context: Context,
        id: String,
        title: String,
        body: String?,
        channelId: String
    ) {
        // 予約後にユーザーが通知を切っていることがある。切られていれば何もしない。
        if (!NotificationScheduler.areNotificationsEnabled(context)) return
        // 予約から発火までの間にアプリが更新されているとチャンネルが無いことがある
        // (無いチャンネル宛の通知は黙って捨てられる)。出す直前に必ず用意する。
        NotificationScheduler.ensureChannels(context)

        val contentIntent = PendingIntent.getActivity(
            context,
            id.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            // アプリアイコンのモノクロ版 ('@' のシルエット)。ステータスバーの
            // アイコンは system が単色に塗り潰すので、元から単色のこれを使う。
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        if (!body.isNullOrEmpty()) {
            builder.setContentText(body)
            // 長いライブ名が「…」で切れないよう、展開時は全文を出す。
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
        }
        // TODO: 画像ギャラリー基盤が入ったら、PlannedNotification.imageIdolId の
        //       ユーザー取込画像を NotificationCompat.BigPictureStyle で添える
        //       (iOS の UNNotificationAttachment 相当)。運営同梱画像は使わない。

        try {
            NotificationManagerCompat.from(context).notify(id.hashCode(), builder.build())
        } catch (e: SecurityException) {
            // areNotificationsEnabled を見た後に権限が失効した場合の保険。
            Log.e(TAG, "notif_post_failed id=$id", e)
        }
    }
}

/**
 * 予約が失われる/ずれる出来事のあとに積み直す。
 *
 * - BOOT_COMPLETED: AlarmManager の予約は端末の再起動で全部消える
 * - MY_PACKAGE_REPLACED: アプリ更新でも同じく消える
 * - TIME_SET / TIMEZONE_CHANGED: 「9:00」「日曜 20:00」は壁時計基準なので、
 *   絶対時刻で積んだ予約を計算し直す必要がある
 */
class NotificationBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> rescheduleAsync(context)
        }
    }
}
