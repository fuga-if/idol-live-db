package com.fugaif.imaslivedb.data.lyrics

import com.fugaif.imaslivedb.data.model.Idol

/**
 * パート分けを描くための歌唱者の引き表。iOS `LyricPartCast` と同じ。
 * 歌詞タブ・歌詞プレイヤー・再生中バーで同じ引き方にする。
 *
 * 行が持つのはアイドルの id だけ ([LyricLine.singers] / [LyricLine.partBreaks])。色と名前はここで原唱者から引く。
 * 原唱者にいない id は出さない (曲の編成に無い人の帯を作らない)。
 */
class LyricPartCast(val artists: List<Idol>) {
    private val byId: Map<String, Idol> = artists.associateBy { it.id }

    fun colors(ids: List<String>): List<String> = ids.mapNotNull { byId[it]?.color }
    fun names(ids: List<String>): List<String> = ids.mapNotNull { byId[it]?.shortName }

    /**
     * 行の字の下に引く、歌う人の色の線 (ひと続きごと)。[mapRange] で表示する本文の中の位置に置き直す
     * (歌詞プレイヤーは被せの括弧を外した本文を出すので)。歌う人のいない範囲は出さない。
     */
    fun marks(line: LyricLine, mapRange: ((Int, Int) -> Pair<Int, Int>?)? = null): List<LyricPartMark> {
        if (line.allSingers.isEmpty()) return emptyList()
        return line.partSegments.mapNotNull { segment ->
            val cs = colors(segment.singers)
            if (cs.isEmpty()) return@mapNotNull null
            // mapRange が無ければそのまま。あれば呼んだ結果を使う (呼んで null ならこの印は出さない。
            // 置き直せなかった = 被せの中など、表示する本文に対応する場所が無い)。
            val range: Pair<Int, Int>? = if (mapRange != null) {
                mapRange(segment.start.toInt(), segment.end.toInt())
            } else {
                segment.start.toInt() to segment.end.toInt()
            }
            range?.let { LyricPartMark(it.first, it.second, cs) }
        }
    }

    /** 行のひと続きごとの名前 (行の途中で歌う人が変わるところで分ける)。 */
    fun groups(line: LyricLine): List<List<String>> =
        if (line.partBreaks.isEmpty()) listOf(names(line.singers)) else line.partSegments.map { names(it.singers) }

    /** 原唱者の並びに揃える (付け外しの後に呼ぶ)。 */
    fun ordered(ids: List<String>): List<String> {
        val order = artists.map { it.id }
        return ids.sortedBy { order.indexOf(it).let { i -> if (i < 0) Int.MAX_VALUE else i } }
    }

    companion object {
        val EMPTY = LyricPartCast(emptyList())
    }
}

/** 歌う人のひと続き (`start..end` は本文のコードポイント位置、`colors` は歌う人の担当色)。字の下に色の線を引く。 */
data class LyricPartMark(val start: Int, val end: Int, val colors: List<String>)

/** [pos] (コードポイント位置) に掛かる色の線。 */
fun List<LyricPartMark>.colorsAt(pos: Int): List<String> =
    firstOrNull { pos >= it.start && pos < it.end }?.colors ?: emptyList()
