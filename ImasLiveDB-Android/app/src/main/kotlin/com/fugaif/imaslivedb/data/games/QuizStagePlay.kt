package com.fugaif.imaslivedb.data.games

import androidx.compose.runtime.Immutable

// =============================================================================
// 解答済みの 1 問の記録。iOS QuizStage.swift の `QuizStagePlay` の移植。
// ペンライト・連続正解・結果画面の「見直す」・シェア画像の行・「つづきから」の保存の元になる。
//
// 画面 (ui/games) と保存 (QuizResumeStore) の両方が使うので data 層に置く。
// 見た目のための集計だけで、採点には使わない (点・グレードはコアが返す)。
// =============================================================================

@Immutable
data class QuizStagePlay(
    val number: Int,
    val isCorrect: Boolean,
    val answerName: String,
    /** 答えの色 (アイドルのイメージカラー)。無ければペンライトは帯の色を順に使う。 */
    val answerHex: String?,
    val pickedName: String?
)

/** 連続正解の数え方 (見た目のための集計。採点には使わない)。iOS `QuizStreak` と同じ。 */
object QuizStreak {
    /** 末尾から数えた連続正解数。 */
    fun current(results: List<Boolean>): Int = results.asReversed().takeWhile { it }.size

    /** セッション中の最長。 */
    fun longest(results: List<Boolean>): Int {
        var best = 0
        var run = 0
        for (ok in results) {
            run = if (ok) run + 1 else 0
            best = maxOf(best, run)
        }
        return best
    }

    /** 直前の不正解で途切れた連続数 (途切れていなければ null)。 */
    fun brokeAt(results: List<Boolean>): Int? {
        if (results.lastOrNull() != false) return null
        return current(results.dropLast(1))
    }
}

val List<QuizStagePlay>.streak: Int get() = QuizStreak.current(map { it.isCorrect })
val List<QuizStagePlay>.longestStreak: Int get() = QuizStreak.longest(map { it.isCorrect })
val List<QuizStagePlay>.streakBrokeAt: Int? get() = QuizStreak.brokeAt(map { it.isCorrect })

/** 「セトリ 3 / 10 曲目まで点灯」。 */
fun List<QuizStagePlay>.setlistCaption(total: Int): String = "セトリ $size / $total 曲目まで点灯"
