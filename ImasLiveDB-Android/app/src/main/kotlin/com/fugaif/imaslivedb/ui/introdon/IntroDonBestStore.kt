package com.fugaif.imaslivedb.ui.introdon

import android.content.Context

/**
 * イントロドンの自己ベスト記録 (モード別スコア・全曲チャレンジのベストタイム)。
 * iOS の UserDefaults キー設計 (bestScoreKey/bestTimeKey) を SharedPreferences に移植。
 */
class IntroDonBestStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun scoreKey(settings: IntroDonSettings): String = when (settings.mode) {
        IntroDonMode.RUSH -> "score_rush_${settings.rushTimeLimitSec}s"
        IntroDonMode.ALL_SONGS -> "score_allsongs"
        else -> "score_${settings.introDurationMs}ms_${settings.questionCount}q"
    }

    private fun timeKey(settings: IntroDonSettings): String {
        val brands = if (settings.selectedBrandIds.isEmpty()) "all" else settings.selectedBrandIds.sorted().joinToString(",")
        return "time_$brands"
    }

    fun bestScore(settings: IntroDonSettings): Int = prefs.getInt(scoreKey(settings), 0)

    /** score が自己ベスト以上なら更新して true を返す。 */
    fun submitScore(settings: IntroDonSettings, score: Int): Boolean {
        val key = scoreKey(settings)
        val prev = prefs.getInt(key, 0)
        return if (score > prev) {
            prefs.edit().putInt(key, score).apply()
            true
        } else {
            false
        }
    }

    fun bestTimeMs(settings: IntroDonSettings): Long = prefs.getLong(timeKey(settings), 0L)

    /** elapsedMs が自己ベスト (より短い) なら更新して true を返す。 */
    fun submitTime(settings: IntroDonSettings, elapsedMs: Long): Boolean {
        val key = timeKey(settings)
        val prev = prefs.getLong(key, 0L)
        return if (elapsedMs > 0 && (prev == 0L || elapsedMs < prev)) {
            prefs.edit().putLong(key, elapsedMs).apply()
            true
        } else {
            false
        }
    }

    companion object {
        private const val PREFS_NAME = "introdon_best_scores"
    }
}
