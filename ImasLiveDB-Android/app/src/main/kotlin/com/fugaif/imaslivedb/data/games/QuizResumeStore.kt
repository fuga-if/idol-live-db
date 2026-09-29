package com.fugaif.imaslivedb.data.games

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import uniffi.imas_core.QuizTally

// =============================================================================
// 途中でやめたクイズの「つづきから」。iOS QuizResume.swift の移植。
//
// 出題はどれもシード付きでコアが一括生成するので、途中の状態は「シード + 設定 + 何問目まで
// 答えたか + 積み上げ」だけ保存すれば、同じ出題を作り直して続きから再開できる
// (問題そのものは保存しない)。
// 1 問答えるたびに保存し、最後まで遊ぶか新しく始めたら消す。ゲームごとに 1 件。
// イントロドンは音源の再生状態を持つので対象外。
// =============================================================================

/** 保存しておく途中経過。 */
data class QuizSuspended(
    val kind: GameKind,
    /** 出題を作り直すシード。 */
    val seed: ULong,
    val brandIds: List<String>,
    /** 次に出す問題の位置。 */
    val nextIndex: Int,
    /** コアの積み上げ (`QuizTally`)。メンバーカラーの並べるは当てた人数 / 答えた人数。 */
    val asked: Int,
    val correct: Int,
    val points: Int,
    /** ペンライト・連続正解・見直すの元。 */
    val plays: List<QuizStagePlay>,
    /** 全問数 (一覧の「Q.06 / 10」)。 */
    val total: Int,
    /** メンバーカラーの難易度 (0/1/2)。 */
    val difficulty: Int? = null,
    /** メンバーカラーの遊び方 ("choice" = 4択 / "match" = 並べる)。 */
    val colorMode: String? = null,
    /** 保存した時刻 (epoch ミリ秒)。一覧の「つづきから」はいちばん新しいものを出す。 */
    val savedAt: Long = System.currentTimeMillis()
) {
    val tally: QuizTally
        get() = QuizTally(
            asked = asked.coerceAtLeast(0).toUInt(),
            correct = correct.coerceAtLeast(0).toUInt(),
            points = points.coerceAtLeast(0).toUInt()
        )

    /** いま出題中の番号 (一覧の「Q.06」)。 */
    val currentNumber: Int get() = minOf(plays.size + 1, total)
}

/**
 * 途中経過のローカル保存 (SharedPreferences の JSON)。保存の形は [GameProgressStore] と同じ流儀。
 * iOS は UserDefaults の `quiz_suspended_v1`。
 */
class QuizResumeStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _sessions = MutableStateFlow(load())
    val sessions: StateFlow<Map<GameKind, QuizSuspended>> = _sessions.asStateFlow()

    fun suspended(kind: GameKind): QuizSuspended? = _sessions.value[kind]

    fun save(s: QuizSuspended) {
        _sessions.value = _sessions.value + (s.kind to s)
        persist()
    }

    fun clear(kind: GameKind) {
        if (!_sessions.value.containsKey(kind)) return
        _sessions.value = _sessions.value - kind
        persist()
    }

    private fun persist() {
        val array = JSONArray()
        _sessions.value.values.forEach { array.put(encode(it)) }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    private fun load(): Map<GameKind, QuizSuspended> {
        val raw = prefs.getString(KEY, null) ?: return emptyMap()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { decode(array.getJSONObject(it)) }
                .associateBy { it.kind }
        } catch (e: Exception) {
            // 壊れた保存は捨てる (続きから出せないだけで、遊ぶのには困らない)。
            emptyMap()
        }
    }

    companion object {
        private const val PREFS_NAME = "quiz_resume_store"
        private const val KEY = "quiz_suspended_v1"

        internal fun encode(s: QuizSuspended): JSONObject = JSONObject().apply {
            put("kind", s.kind.name)
            // ULong は JSON の数値に収まらないので文字列で持つ。
            put("seed", s.seed.toString())
            put("brandIds", JSONArray(s.brandIds))
            put("nextIndex", s.nextIndex)
            put("asked", s.asked)
            put("correct", s.correct)
            put("points", s.points)
            put("total", s.total)
            s.difficulty?.let { put("difficulty", it) }
            s.colorMode?.let { put("colorMode", it) }
            put("savedAt", s.savedAt)
            put("plays", JSONArray().apply {
                s.plays.forEach { p ->
                    put(JSONObject().apply {
                        put("number", p.number)
                        put("isCorrect", p.isCorrect)
                        put("answerName", p.answerName)
                        p.answerHex?.let { put("answerHex", it) }
                        p.pickedName?.let { put("pickedName", it) }
                    })
                }
            })
        }

        internal fun decode(o: JSONObject): QuizSuspended? {
            val kind = GameKind.entries.firstOrNull { it.name == o.optString("kind") } ?: return null
            val seed = o.optString("seed").toULongOrNull() ?: return null
            val brands = o.optJSONArray("brandIds") ?: JSONArray()
            val plays = o.optJSONArray("plays") ?: JSONArray()
            return QuizSuspended(
                kind = kind,
                seed = seed,
                brandIds = (0 until brands.length()).map { brands.getString(it) },
                nextIndex = o.optInt("nextIndex"),
                asked = o.optInt("asked"),
                correct = o.optInt("correct"),
                points = o.optInt("points"),
                plays = (0 until plays.length()).map { i ->
                    val p = plays.getJSONObject(i)
                    QuizStagePlay(
                        number = p.optInt("number"),
                        isCorrect = p.optBoolean("isCorrect"),
                        answerName = p.optString("answerName"),
                        answerHex = if (p.has("answerHex")) p.optString("answerHex") else null,
                        pickedName = if (p.has("pickedName")) p.optString("pickedName") else null
                    )
                },
                total = o.optInt("total"),
                difficulty = if (o.has("difficulty")) o.optInt("difficulty") else null,
                colorMode = if (o.has("colorMode")) o.optString("colorMode") else null,
                savedAt = o.optLong("savedAt")
            )
        }
    }
}

/** いちばん最近中断したもの (ゲーム一覧の「つづきから」)。 */
val Map<GameKind, QuizSuspended>.latest: QuizSuspended? get() = values.maxByOrNull { it.savedAt }
