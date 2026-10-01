package com.fugaif.imaslivedb.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color

/**
 * 習熟度の段階の定義 (ラベルと数)。iOS `Models/MasteryScale.swift` の移植。
 *
 * **保存されるのは序数だけ** (`user_marks.kind = "mastery"` の `text_value`)。
 * ラベルはここが持ち、設定で差し替えても既存の記録には触らない。段数から導ける規則
 * (次の段 / 重み / 段数を変えたときの寄せ先) と群化・集計は共有コア
 * (`imas-core` の `domain/mastery.rs`) にある。ここは**文言と色だけ**。
 */
data class MasteryScale(val labels: List<String>) {

    /** 段数。コアに渡す `steps`。 */
    val steps: UByte get() = labels.size.coerceIn(1, 8).toUByte()

    /** 表示名。`0` は未設定。 */
    fun label(level: UByte): String {
        if (level.toInt() == 0) return "未設定"
        val i = level.toInt() - 1
        return labels.getOrNull(i) ?: "LV.$level"
    }

    /** 一覧のチップに出す短い名前。 */
    fun shortLabel(level: UByte): String {
        val full = label(level)
        return if (full.length <= 6) full else full.take(5) + "…"
    }

    companion object {
        /**
         * 既定は 3 段。
         *
         * 依頼元は 4 段 (1回聞いた / 耳に馴染んだ / だいたい覚えた / 覚えた) だったが、
         * 「耳に馴染んだ」が読んだときの言い方として微妙で、さらに**行の操作面に
         * 収まらず途中で切れる**。短く言い切れる 3 段にした。語彙の好みは人によるので
         * 設定で変えられる。
         */
        val defaultLabels = listOf("聞いた", "覚えた", "完璧")
        val standard = MasteryScale(defaultLabels)

        /** 段数を変えるときの出発点。どれも 4 文字以内にして操作面で切れないようにする。 */
        val presets: List<Pair<String, MasteryScale>> = listOf(
            "2段" to MasteryScale(listOf("聞いた", "覚えた")),
            "3段" to MasteryScale(defaultLabels),
            "4段" to MasteryScale(listOf("聞いた", "だいたい", "覚えた", "完璧")),
        )
    }
}

/**
 * 段の色。ヒートマップ的に並べる以上、**段ごとに色相を変えない**。
 * 色相を変えると「濃い＝進んでいる」が列で読めなくなる。
 * システムの accent は塗らない (DS 原則: 色はエンティティ側から来る) ので、
 * 習熟度専用の 1 色を濃度で割る。
 */
object MasteryPalette {
    // ライトは上の段ほど濃く、ダークは上の段ほど明るい側へ伸ばす (iOS のランプと同値)。
    private val rampLight = listOf(
        Color(0xFFD7E5F4), Color(0xFF9DC4E6), Color(0xFF5392CE), Color(0xFF1C5FA3),
    )
    private val rampDark = listOf(
        Color(0xFF17304A), Color(0xFF27547F), Color(0xFF4287C6), Color(0xFF7FBAF0),
    )

    /** `level` (1..=steps) の面の色。`0` (未設定) は面を持たない。 */
    @Composable
    @ReadOnlyComposable
    fun fill(level: UByte, steps: UByte): Color {
        if (level.toInt() == 0) return Color.Transparent
        val ramp = if (LocalImasColors.current.dark) rampDark else rampLight
        return ramp[rampIndex(level, steps)]
    }

    /** その面の上に乗せる文字色。薄い段は濃い文字、濃い段は抜き文字。 */
    @Composable
    @ReadOnlyComposable
    fun ink(level: UByte, steps: UByte): Color {
        if (level.toInt() == 0) return DS.ink3
        val upper = rampIndex(level, steps) >= 2
        // ライトは上位 2 段が濃いので白抜き、ダークは上位が明るいので黒文字。
        return if (LocalImasColors.current.dark) {
            if (upper) Color(0xFF06121F) else Color.White
        } else {
            if (upper) Color.White else Color(0xFF12293D)
        }
    }

    /** 段数が 4 でないときは 4 段のランプ上へ等間隔に写す (最上段は必ず一番濃い)。 */
    private fun rampIndex(level: UByte, steps: UByte): Int {
        val s = steps.toInt().coerceAtLeast(1)
        val l = level.toInt().coerceIn(1, s)
        val idx = ((l - 1).toDouble() / (s - 1).coerceAtLeast(1) * 3.0 + 0.5).toInt()
        return idx.coerceIn(0, 3)
    }
}
