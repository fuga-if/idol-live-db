package com.fugaif.imaslivedb.ui.components

import com.fugaif.imaslivedb.data.model.Song
import uniffi.imas_core.compactSingerLabel
import uniffi.imas_core.songCreditLabel

/**
 * 1 行に出す歌唱者の表記。全体曲の長い表記 (`765 MILLION ALLSTARS 天海春香、…`) を畳む。
 *
 * 回帰 (2026-10-31): 関連曲・投票・タグの曲行などが `singerLabel` を生で出していて、
 * 全体曲では全員の名前が行を埋めていた。規則はコア (`songCreditLabel` / `compactSingerLabel`)。
 * 全員の顔ぶれは曲の詳細の「歌唱アイドル」が持つ。iOS の `Song.creditLine` / `singerLine` と同じ。
 */

/** ユニット名 → 名義 (畳んだ `singerLabel`)。どちらも無ければ null。 */
val Song.creditLine: String?
    get() = songCreditLabel(unitName, singerLabel, "").ifEmpty { null }

/** 名義 (畳んだ `singerLabel`) → ユニット名。これまで `singerLabel ?: unitName` だった行用。 */
val Song.singerLine: String?
    get() {
        val label = singerLabel?.trim()?.takeIf { it.isNotEmpty() } ?: return unitName
        val compact = compactSingerLabel(label)
        // 畳んだときはユニット名を先に使う (表記の括弧が崩れている曲でも名義が正しく出る)。
        if (compact != label && !unitName.isNullOrEmpty()) return unitName
        return compact
    }
