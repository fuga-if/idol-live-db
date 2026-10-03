package com.fugaif.imaslivedb.data.lyrics

import com.fugaif.imaslivedb.data.model.Idol

/**
 * パート分けを描くための歌唱者の引き表。iOS `LyricPartCast` と同じ。
 * 歌詞タブ・歌詞プレイヤー・再生中バーで同じ引き方にする。
 *
 * 行が持つのはアイドルの id だけ ([LyricLine.singers])。色と名前はここで原唱者から引く。
 * 原唱者にいない id は出さない (曲の編成に無い人の帯を作らない)。
 */
class LyricPartCast(val artists: List<Idol>) {
    private val byId: Map<String, Idol> = artists.associateBy { it.id }

    fun colors(ids: List<String>): List<String> = ids.mapNotNull { byId[it]?.color }
    fun names(ids: List<String>): List<String> = ids.mapNotNull { byId[it]?.shortName }

    /** 原唱者の並びに揃える (付け外しの後に呼ぶ)。 */
    fun ordered(ids: List<String>): List<String> {
        val order = artists.map { it.id }
        return ids.sortedBy { order.indexOf(it).let { i -> if (i < 0) Int.MAX_VALUE else i } }
    }

    companion object {
        val EMPTY = LyricPartCast(emptyList())
    }
}
