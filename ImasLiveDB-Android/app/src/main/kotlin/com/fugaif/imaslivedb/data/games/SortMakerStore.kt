package com.fugaif.imaslivedb.data.games

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import uniffi.imas_core.SortMakerChoice
import uniffi.imas_core.SortMakerState
import uniffi.imas_core.sortMakerReplay

// =============================================================================
// ソートメーカーの対象・途中保存。iOS SortMakerSession.swift の移植。
//
// 並べ替えの状態はコア (`sortMakerReplay`) が「シード + 答えの列」から毎回作り直すので、
// 保存するのは対象の id 列・シード・答えだけ。1 戦答えるたびに書き、曲とアイドルで 1 件ずつ持つ。
// 終わったセッションも消さずに残し、ハブと設定画面の「前回の結果」に使う。
// =============================================================================

/** 何を並べるか。 */
enum class SortMakerSubject {
    SONG,
    IDOL;

    /** ハブ・ナビタイトル・共有文の見出し。 */
    val title: String
        get() = when (this) {
            SONG -> "好きな曲ソート"
            IDOL -> "好きなアイドルソート"
        }

    /** 「128曲」「52人」の助数詞。 */
    val counter: String
        get() = when (this) {
            SONG -> "曲"
            IDOL -> "人"
        }

    /** ティアー表のナビタイトル。 */
    val tierTitle: String
        get() = when (this) {
            SONG -> "曲のティアー表"
            IDOL -> "アイドルのティアー表"
        }

    /** 永続化キー用の短い文字列。 */
    val key: String
        get() = when (this) {
            SONG -> "song"
            IDOL -> "idol"
        }

    companion object {
        fun fromKey(key: String?): SortMakerSubject? = entries.firstOrNull { it.key == key }
    }
}

/** 何を作るか。対象の選び方はソートとティアー表で共通 (SortMakerSetupScreen)。 */
enum class SortMakerPurpose {
    SORT,
    TIER
}

/** 上位何位まで決めるか。値は `topK` (0 = 全順位)。 */
enum class SortMakerDepth(val rawValue: Int) {
    TOP10(10),
    ALL(0);

    val label: String
        get() = when (this) {
            TOP10 -> "ベスト10"
            ALL -> "全順位"
        }

    companion object {
        fun fromRawValue(v: Int): SortMakerDepth = entries.firstOrNull { it.rawValue == v } ?: TOP10
    }
}

/** 1 戦の答え ⇔ 保存する 1 文字 ("L"/"R"/"T")。 */
private fun SortMakerChoice.toCode(): Char = when (this) {
    SortMakerChoice.LEFT -> 'L'
    SortMakerChoice.RIGHT -> 'R'
    SortMakerChoice.TIE -> 'T'
}

private fun Char.toChoiceOrNull(): SortMakerChoice? = when (this) {
    'L' -> SortMakerChoice.LEFT
    'R' -> SortMakerChoice.RIGHT
    'T' -> SortMakerChoice.TIE
    else -> null
}

/** 保存しておくセッション。 */
data class SortMakerSession(
    val subject: SortMakerSubject,
    /** 対象の id 列 (曲 id / アイドル id)。コアの添字はこの並びの位置。 */
    val itemIds: List<String>,
    val seed: ULong,
    /** 0 = 全順位。 */
    val topK: Int,
    /** 設定画面で絞った範囲の説明 (「シャニマス・ソロ曲」)。結果と共有文に出す。 */
    val scopeLabel: String,
    /** 答えの列。L / R / T の 1 文字ずつ。 */
    val answers: String,
    /** 終わった時点の上位 3 件の表示名 (ハブの「前回の 1 位」用)。 */
    val topNames: List<String> = emptyList(),
    val isFinished: Boolean = false,
    val savedAt: Long = System.currentTimeMillis()
) {
    val choices: List<SortMakerChoice> get() = answers.mapNotNull { it.toChoiceOrNull() }

    fun appendChoice(choice: SortMakerChoice): SortMakerSession = copy(answers = answers + choice.toCode())

    fun withoutLastAnswer(): SortMakerSession =
        copy(answers = answers.dropLast(1), isFinished = false, topNames = emptyList())

    /** コアで今の状態を作り直す。 */
    fun replay(): SortMakerState =
        sortMakerReplay(itemCount = itemIds.size.toUInt(), topK = topK.toUInt(), seed = seed, answers = choices)
}

/**
 * 途中経過のローカル保存 (SharedPreferences の JSON)。保存の形は [QuizResumeStore] と同じ流儀。
 * iOS は UserDefaults の `sort_maker_sessions_v1`。
 */
class SortMakerStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _sessions = MutableStateFlow(load())
    val sessions: StateFlow<Map<SortMakerSubject, SortMakerSession>> = _sessions.asStateFlow()

    fun session(subject: SortMakerSubject): SortMakerSession? = _sessions.value[subject]

    fun save(s: SortMakerSession) {
        _sessions.value = _sessions.value + (s.subject to s)
        persist()
    }

    fun clear(subject: SortMakerSubject) {
        if (!_sessions.value.containsKey(subject)) return
        _sessions.value = _sessions.value - subject
        persist()
    }

    private fun persist() {
        val array = JSONArray()
        _sessions.value.values.forEach { array.put(encode(it)) }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    private fun load(): Map<SortMakerSubject, SortMakerSession> {
        val raw = prefs.getString(KEY, null) ?: return emptyMap()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { decode(array.getJSONObject(it)) }
                .associateBy { it.subject }
        } catch (e: Exception) {
            // 壊れた保存は捨てる (「つづきから」が出せないだけで、遊ぶのには困らない)。
            emptyMap()
        }
    }

    companion object {
        private const val PREFS_NAME = "sort_maker_store"
        private const val KEY = "sort_maker_sessions_v1"

        internal fun encode(s: SortMakerSession): JSONObject = JSONObject().apply {
            put("subject", s.subject.key)
            put("itemIds", JSONArray(s.itemIds))
            // ULong は JSON の数値に収まらないので文字列で持つ。
            put("seed", s.seed.toString())
            put("topK", s.topK)
            put("scopeLabel", s.scopeLabel)
            put("answers", s.answers)
            put("topNames", JSONArray(s.topNames))
            put("isFinished", s.isFinished)
            put("savedAt", s.savedAt)
        }

        internal fun decode(o: JSONObject): SortMakerSession? {
            val subject = SortMakerSubject.fromKey(o.optString("subject")) ?: return null
            val seed = o.optString("seed").toULongOrNull() ?: return null
            val itemIds = o.optJSONArray("itemIds") ?: JSONArray()
            val topNames = o.optJSONArray("topNames") ?: JSONArray()
            return SortMakerSession(
                subject = subject,
                itemIds = (0 until itemIds.length()).map { itemIds.getString(it) },
                seed = seed,
                topK = o.optInt("topK"),
                scopeLabel = o.optString("scopeLabel"),
                answers = o.optString("answers"),
                topNames = (0 until topNames.length()).map { topNames.getString(it) },
                isFinished = o.optBoolean("isFinished"),
                savedAt = o.optLong("savedAt")
            )
        }
    }
}
