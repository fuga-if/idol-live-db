package com.fugaif.imaslivedb.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * ウィジェットの定期更新を実際に走らせる Receiver。
 *
 * 受け取るもの:
 * - [WidgetUpdateScheduler.ACTION_DAILY_REFRESH] … 予約した日付変わりの更新
 * - BOOT_COMPLETED / MY_PACKAGE_REPLACED / TIME_SET / TIMEZONE_CHANGED
 *   … AlarmManager の予約が消える、または狙った時刻がずれる出来事。積み直すだけ
 *   (通知側 `NotificationBootReceiver` と同じ理由・同じ顔ぶれ)。
 *
 * どの経路でも最後に予約を積み直す。AlarmManager に「毎日」は無いので、
 * 発火のたびに次の 1 回を積むのが繰り返しの実体になる。
 */
class WidgetUpdateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        val isRefresh = intent.action == WidgetUpdateScheduler.ACTION_DAILY_REFRESH
        // Room の読み出しとウィジェットの描き直しは非同期。goAsync でブロードキャストを
        // 生かしたまま待つ (finish を呼ばないとプロセスが即殺されて更新が中断する)。
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                if (isRefresh) WidgetUpdateScheduler.refreshAll(appContext)
                WidgetUpdateScheduler.scheduleNextMidnight(appContext)
            } catch (t: Throwable) {
                // 更新に失敗してもホーム画面には前回の絵が残る。次の予約だけは死守する。
                Log.w(TAG, "widget_refresh_failed", t)
                runCatching { WidgetUpdateScheduler.scheduleNextMidnight(appContext) }
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        const val TAG = "ImasWidget"
    }
}
