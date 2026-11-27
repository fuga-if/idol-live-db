package com.fugaif.imaslivedb.data.local

import android.content.Context
import com.fugaif.imaslivedb.BuildConfig

/**
 * Google Play のアプリ内レビューを出すタイミングを決める (iOS `ReviewPrompt` と同じ条件)。
 *
 * 依頼そのものは [com.fugaif.imaslivedb.ui.components.ReviewPromptHost] が Play の
 * ReviewManager で出す。ここは「いつ声を掛けるか」だけを持つ。
 *
 * 設計の前提:
 * - **Play 側にも上限がある** (回数は非公開) が、それは最後の砦であって、こちらが
 *   むやみに呼んでよい理由にはならない。枠を浪費すると、本当に出したい場面で出ない。
 * - **作業の途中では聞かない**。参加ライブを登録した「一区切り」を数えるだけで、
 *   聞くのは次に起動して落ち着いた画面を見ているとき。
 * - **初回起動では聞かない**。まだアプリの価値が分かっていない人に聞いても意味がない。
 */
class ReviewPrompt(
    context: Context,
    private val currentVersion: String = BuildConfig.VERSION_NAME,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 起動時に呼ぶ。初回起動日を記録するだけ。 */
    fun registerLaunch() {
        if (!prefs.contains(KEY_FIRST_LAUNCH)) prefs.edit().putLong(KEY_FIRST_LAUNCH, now()).apply()
    }

    /** 「一区切りついた」瞬間に呼ぶ (参加ライブの登録)。数えるだけで、依頼は出さない。 */
    fun noteMilestone() {
        prefs.edit().putInt(KEY_MILESTONES, prefs.getInt(KEY_MILESTONES, 0) + 1).apply()
    }

    /**
     * 今レビューを依頼してよいか。`true` を返したときは「聞いた」ものとして記録する
     * (呼び出し側が実際に依頼するのが前提)。
     *
     * ⚠️ Play が実際にダイアログを出したかは**アプリからは分からない**。出なかった場合も
     * 「聞いた」扱いになるが、それでよい。ここで再挑戦を許すと、上限に阻まれている相手に
     * 何度も呼び続けることになり、枠が空いた瞬間に脈絡のない場面で出てしまう。
     */
    fun shouldAsk(): Boolean {
        if (prefs.getInt(KEY_MILESTONES, 0) < REQUIRED_MILESTONES) return false
        // 同じバージョンで二度は聞かない。
        if (prefs.getString(KEY_LAST_ASKED_VERSION, null) == currentVersion) return false

        val now = now()
        val firstLaunch = prefs.getLong(KEY_FIRST_LAUNCH, 0L)
        if (firstLaunch <= 0L || now - firstLaunch < REQUIRED_DAYS * DAY_MS) return false
        val lastAsked = prefs.getLong(KEY_LAST_ASKED, 0L)
        if (lastAsked > 0L && now - lastAsked < COOLDOWN_DAYS * DAY_MS) return false

        prefs.edit().putLong(KEY_LAST_ASKED, now).putString(KEY_LAST_ASKED_VERSION, currentVersion).apply()
        return true
    }

    private companion object {
        /** 好機を何回踏んだら聞くか。1 回目 (初めて参加ライブを登録した直後) は見送る。 */
        const val REQUIRED_MILESTONES = 3
        /** 初回起動から何日経てば聞いてよいか。 */
        const val REQUIRED_DAYS = 3L
        /** 一度聞いたら次に聞くまでの最短日数。Play の上限より手前で自制する。 */
        const val COOLDOWN_DAYS = 120L
        const val DAY_MS = 86_400_000L

        const val PREFS_NAME = "review_prompt"
        const val KEY_FIRST_LAUNCH = "first_launch_at"
        const val KEY_MILESTONES = "milestone_count"
        const val KEY_LAST_ASKED = "last_asked_at"
        const val KEY_LAST_ASKED_VERSION = "last_asked_version"
    }
}
