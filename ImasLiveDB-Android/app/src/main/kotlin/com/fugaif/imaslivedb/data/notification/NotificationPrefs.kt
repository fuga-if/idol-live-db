package com.fugaif.imaslivedb.data.notification

import android.content.Context

/**
 * 通知の 4 カテゴリ。iOS `NotificationService` / `MyPageView.notificationSection` と 1:1。
 *
 * `prefKey` は iOS の UserDefaults キーをそのまま使う。バックアップの引き継ぎや
 * ドキュメント上で「同じ設定」だと分かるようにするため、Android 側で独自に
 * 命名し直さない。
 *
 * `channelId` はカテゴリごとに分けている。iOS は通知種別を 1 つのバケツで扱うが、
 * Android は「システム設定側でカテゴリ単位に音・重要度を切れる」のが標準の作法で、
 * アプリ内トグル 4 つとちょうど対応する。
 */
enum class NotificationCategory(
    val prefKey: String,
    val channelId: String,
    val channelName: String,
    val channelDescription: String
) {
    OSHI_BIRTHDAY(
        prefKey = "notif_oshi_birthday",
        channelId = "imas_oshi_birthday",
        channelName = "担当アイドルの誕生日",
        channelDescription = "担当マークしたアイドルの誕生日に 9:00 にお知らせします。"
    ),
    LIVE_WEEK(
        prefKey = "notif_live_week",
        channelId = "imas_live_week",
        channelName = "ライブ1週間前",
        channelDescription = "お気に入り/参加マークしたライブの初日 1 週間前に 10:00 にお知らせします。"
    ),
    TICKET(
        prefKey = "notif_ticket",
        channelId = "imas_ticket",
        channelName = "チケット締切・当落",
        channelDescription = "チケット申込締切の前日 18:00 と、当落発表日の 9:00 にお知らせします。"
    ),
    MONDAY(
        prefKey = "notif_monday",
        channelId = "imas_monday",
        channelName = "月曜が近いよ",
        channelDescription = "日曜 20:00 に月曜が近いことをお知らせします。"
    );

    companion object {
        fun forChannelId(channelId: String): NotificationCategory? =
            entries.firstOrNull { it.channelId == channelId }
    }
}

/**
 * 通知設定の保存先。iOS が UserDefaults を直読みしているのと同じ位置づけで、
 * ViewModel を挟まず Scheduler と設定 UI の両方から触れるようにしてある
 * (BroadcastReceiver からも読むため、ViewModel 依存にはできない)。
 *
 * 「未設定なら既定 ON」も iOS の `notifEnabled` と同じ。初回インストール直後から
 * 通知許可さえ取れれば 4 種すべてが動く。
 */
class NotificationPrefs(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isEnabled(category: NotificationCategory): Boolean =
        prefs.getBoolean(category.prefKey, true)

    fun setEnabled(category: NotificationCategory, enabled: Boolean) {
        prefs.edit().putBoolean(category.prefKey, enabled).apply()
    }

    /**
     * 現在 AlarmManager に積んである通知 id の一覧。
     *
     * iOS の `removeAllPendingNotificationRequests()` に相当するものが AlarmManager には
     * 無く、「予約を消す」には登録時と同一の PendingIntent を作り直して cancel するしかない。
     * プロセスをまたいでも消せるように、積んだ id をここに残しておく。
     */
    fun scheduledIds(): List<String> =
        prefs.getStringSet(KEY_SCHEDULED_IDS, emptySet())?.toList() ?: emptyList()

    fun setScheduledIds(ids: List<String>) {
        // getStringSet が返す Set は SharedPreferences 内部の実体を共有しうるので、
        // 必ず新しい Set を渡す (同じインスタンスを put すると保存されないことがある)。
        prefs.edit().putStringSet(KEY_SCHEDULED_IDS, LinkedHashSet(ids)).apply()
    }

    private companion object {
        const val PREFS_NAME = "imas_notifications"
        const val KEY_SCHEDULED_IDS = "scheduled_ids"
    }
}
