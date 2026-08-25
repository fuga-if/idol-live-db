package com.fugaif.imaslivedb.data.games

import android.content.Context
import com.fugaif.imaslivedb.data.model.DailyPick
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import uniffi.imas_core.GameProgressUpdate
import uniffi.imas_core.GameRecord
import uniffi.imas_core.GameStreakState
import uniffi.imas_core.gameProgressApplyResult
import uniffi.imas_core.gameProgressDidClearToday
import uniffi.imas_core.gameProgressDisplayStreak

/** ハブが束ねるゲームの識別子。name は永続キー兼用なので変更しない。iOS GameKind の移植。 */
enum class GameKind(val displayName: String, val scoreIsPercent: Boolean) {
    introDon("イントロドン", false),
    idolQuiz("アイドル当てクイズ", false),
    songSingerQuiz("ソロ曲クイズ", false),
    colorMatch("カラーマッチ", true)
}

/**
 * 未プレイの初期値。保存値の型は imas-core の [GameRecord] そのもの
 * (uniffi 生成なので Kotlin の既定引数を持てず、初期値をここで名付ける)。
 */
fun emptyGameRecord(): GameRecord =
    GameRecord(lastScore = 0, lastOutOf = 0, bestScore = 0, bestOutOf = 0, playCount = 0)

/** 未達成の初期値。理由は [emptyGameRecord] と同じ。 */
private fun emptyStreakState(): GameStreakState =
    GameStreakState(streak = 0, totalDays = 0, lastClearedDay = null)

/**
 * 1 度でも遊んだか。コアの `GameRecord::has_played` と同じ規則だが、
 * 述語 1 行のために FFI 面を増やさず Kotlin 側の拡張として持つ。
 */
val GameRecord.hasPlayed: Boolean get() = playCount > 0

/**
 * ゲーム横断のローカル進捗ストア (SharedPreferences)。iOS GameProgressStore の移植。
 *
 * 保存の実体 (キー `game_records_v1` / `game_streak_v1` の JSON) だけがここの責務で、
 * **更新規則は imas-core の `domain::game_progress`** が持つ。ストアは
 * 「読む → コアに渡す → 返ってきた値を書く」に痩せている。
 *
 * 日付キーの生成も [DailyPick] 経由でコアに委ねる (書式を自前で組むと iOS と
 * 食い違い、保存済みの連続記録キーと突き合わなくなる)。連続達成の単位は
 * 「そのユーザーの 1 日」なので、公演日の比較に使う JST 固定の
 * [com.fugaif.imaslivedb.data.model.JstDay] とは意味が違い、統合してはいけない。
 */
class GameProgressStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _records = MutableStateFlow(loadRecords())
    val records: StateFlow<Map<GameKind, GameRecord>> = _records.asStateFlow()

    private val _streak = MutableStateFlow(loadStreak())
    val streak: StateFlow<GameStreakState> = _streak.asStateFlow()

    fun record(kind: GameKind): GameRecord = _records.value[kind] ?: emptyGameRecord()

    /** ストリークが「今日途切れていないか」。表示用 (今日/昨日までクリアなら継続扱い)。 */
    val displayStreak: Int
        get() = gameProgressDisplayStreak(_streak.value, DailyPick.dayKey(), DailyPick.previousDayKey())

    /**
     * 今日デイリーチャレンジを達成済みか。
     *
     * `lastClearedDay == 今日` の比較をストアの外で書くとコアと二重実装になるので、
     * 判定はコアに置いたままこの述語で公開する (iOS `GameProgressStore.didClearToday` と対)。
     */
    val didClearToday: Boolean
        get() = gameProgressDidClearToday(_streak.value, DailyPick.dayKey())

    /**
     * ゲーム結果を記録する。score/outOf は「獲得点 / 満点」。
     *
     * 「自己ベストを更新したか」は best を上書きする**前**に判定する必要があり、その順序ごと
     * コアの 1 呼び出しに畳んである。結果画面のバッジは戻り値の `isNewBest` を使うこと
     * (画面側で判定し直すと順序を崩した瞬間に恒久的に出なくなる)。
     */
    fun recordResult(kind: GameKind, score: Int, outOf: Int): GameProgressUpdate {
        val update = gameProgressApplyResult(
            record = record(kind),
            streak = _streak.value,
            score = score,
            outOf = outOf,
            todayKey = DailyPick.dayKey(),
            yesterdayKey = DailyPick.previousDayKey()
        )
        // 記録として成立しない回 (出題 0 問) は record/streak が入力と同値なので保存を省く。
        if (!update.didRecord) return update
        _records.value = _records.value + (kind to update.record)
        saveRecords(_records.value)
        _streak.value = update.streak
        saveStreak(update.streak)
        return update
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

    private fun loadStreak(): GameStreakState {
        val raw = prefs.getString(KEY_STREAK, null) ?: return emptyStreakState()
        return try {
            val o = JSONObject(raw)
            GameStreakState(
                streak = o.optInt("streak"),
                totalDays = o.optInt("totalDays"),
                lastClearedDay = o.optString("lastClearedDay").ifEmpty { null }
            )
        } catch (e: Exception) {
            emptyStreakState()
        }
    }

    private fun saveStreak(s: GameStreakState) {
        val json = JSONObject().apply {
            put("streak", s.streak)
            put("totalDays", s.totalDays)
            put("lastClearedDay", s.lastClearedDay ?: "")
        }
        prefs.edit().putString(KEY_STREAK, json.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "game_progress_store"
        private const val KEY_RECORDS = "game_records_v1"
        private const val KEY_STREAK = "game_streak_v1"
    }
}
