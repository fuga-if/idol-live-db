package com.fugaif.imaslivedb.data.games

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** ハブが束ねるゲームの識別子。name は永続キー兼用なので変更しない。iOS GameKind の移植。 */
enum class GameKind(val displayName: String, val scoreIsPercent: Boolean) {
    introDon("イントロドン", false),
    idolQuiz("アイドル当てクイズ", false),
    songSingerQuiz("ソロ曲クイズ", false),
    colorMatch("カラーマッチ", true)
}

/** 1 ゲーム分の記録。 */
data class GameRecord(
    val lastScore: Int = 0,
    val lastOutOf: Int = 0,
    val bestScore: Int = 0,
    val bestOutOf: Int = 0,
    val playCount: Int = 0
) {
    val hasPlayed: Boolean get() = playCount > 0
}

/** 連続デイリー達成日数の状態。 */
data class StreakState(
    val streak: Int = 0,
    val totalDays: Int = 0,
    val lastClearedDay: String? = null
)

/**
 * ゲーム横断のローカル進捗ストア (SharedPreferences)。iOS GameProgressStore の移植。
 * 各ゲームの直近/最高スコア・プレイ回数、デイリーチャレンジのストリークを記録する。
 */
class GameProgressStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _records = MutableStateFlow(loadRecords())
    val records: StateFlow<Map<GameKind, GameRecord>> = _records.asStateFlow()

    private val _streak = MutableStateFlow(loadStreak())
    val streak: StateFlow<StreakState> = _streak.asStateFlow()

    fun record(kind: GameKind): GameRecord = _records.value[kind] ?: GameRecord()

    /** ストリークが「今日途切れていないか」。表示用 (今日/昨日までクリアなら継続扱い)。 */
    val displayStreak: Int
        get() {
            val s = _streak.value
            val last = s.lastClearedDay ?: return 0
            return if (last == today() || last == yesterday()) s.streak else 0
        }

    /** ゲーム結果を記録する。score/outOf は「獲得点 / 満点」。デイリー達成とストリークも同時更新。 */
    fun recordResult(kind: GameKind, score: Int, outOf: Int) {
        if (outOf <= 0) return
        val current = record(kind)
        val newRate = score.toDouble() / outOf
        val bestRate = if (current.bestOutOf > 0) current.bestScore.toDouble() / current.bestOutOf else -1.0
        val isNewBest = newRate > bestRate
        val updated = current.copy(
            lastScore = score,
            lastOutOf = outOf,
            playCount = current.playCount + 1,
            bestScore = if (isNewBest) score else current.bestScore,
            bestOutOf = if (isNewBest) outOf else current.bestOutOf
        )
        _records.value = _records.value + (kind to updated)
        saveRecords(_records.value)
        registerDailyClear()
    }

    private fun registerDailyClear() {
        val s = _streak.value
        val t = today()
        if (s.lastClearedDay == t) return // 1 日 1 回だけカウント
        val newStreak = if (s.lastClearedDay == yesterday()) s.streak + 1 else 1
        val updated = StreakState(streak = newStreak, totalDays = s.totalDays + 1, lastClearedDay = t)
        _streak.value = updated
        saveStreak(updated)
    }

    // MARK: - 永続化

    private fun loadRecords(): Map<GameKind, GameRecord> {
        val raw = prefs.getString(KEY_RECORDS, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            GameKind.entries.mapNotNull { kind ->
                if (!json.has(kind.name)) return@mapNotNull null
                val o = json.getJSONObject(kind.name)
                kind to GameRecord(
                    lastScore = o.optInt("lastScore"),
                    lastOutOf = o.optInt("lastOutOf"),
                    bestScore = o.optInt("bestScore"),
                    bestOutOf = o.optInt("bestOutOf"),
                    playCount = o.optInt("playCount")
                )
            }.toMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun saveRecords(records: Map<GameKind, GameRecord>) {
        val json = JSONObject()
        records.forEach { (kind, rec) ->
            json.put(kind.name, JSONObject().apply {
                put("lastScore", rec.lastScore)
                put("lastOutOf", rec.lastOutOf)
                put("bestScore", rec.bestScore)
                put("bestOutOf", rec.bestOutOf)
                put("playCount", rec.playCount)
            })
        }
        prefs.edit().putString(KEY_RECORDS, json.toString()).apply()
    }

    private fun loadStreak(): StreakState {
        val raw = prefs.getString(KEY_STREAK, null) ?: return StreakState()
        return try {
            val o = JSONObject(raw)
            StreakState(
                streak = o.optInt("streak"),
                totalDays = o.optInt("totalDays"),
                lastClearedDay = o.optString("lastClearedDay").ifEmpty { null }
            )
        } catch (e: Exception) {
            StreakState()
        }
    }

    private fun saveStreak(s: StreakState) {
        val json = JSONObject().apply {
            put("streak", s.streak)
            put("totalDays", s.totalDays)
            put("lastClearedDay", s.lastClearedDay ?: "")
        }
        prefs.edit().putString(KEY_STREAK, json.toString()).apply()
    }

    // MARK: - 日付ヘルパ (端末ローカル YYYY-MM-DD)

    private fun today(): String = LocalDate.now().format(DAY_FORMAT)
    private fun yesterday(): String = LocalDate.now().minusDays(1).format(DAY_FORMAT)

    companion object {
        private const val PREFS_NAME = "game_progress_store"
        private const val KEY_RECORDS = "game_records_v1"
        private const val KEY_STREAK = "game_streak_v1"
        private val DAY_FORMAT: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
    }
}
