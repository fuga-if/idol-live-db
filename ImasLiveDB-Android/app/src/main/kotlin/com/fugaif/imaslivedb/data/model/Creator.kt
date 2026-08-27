package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 作詞・作曲・編曲の表記と、その読み。
 *
 * 読みは**人 (表記) の属性**であって曲の属性ではない。同じ作家が数十曲に出るので、
 * 曲側に持たせると同じ読みが何十行にも複製され、直すときに全部を追うことになる。
 * 会場をまとめた Venue と同じ理由で別表にする。
 *
 * [name] は songs.composer / lyricist / arranger に入っている**表記そのもの**で、
 * 区切り文字では割らない。割ると括弧の内側で壊れるため
 * (「BNEI(中川浩二、上田夢人)」が「BNEI(中川浩二」と「上田夢人)」になる)。
 * 検索は表記まるごとの読みに対して部分一致するので、割らなくても「うえだ」で当たる。
 */
@Entity(
    tableName = "creators",
    indices = [Index(name = "idx_creators_name", value = ["name"])]
)
data class Creator(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "name_kana")
    val nameKana: String,

    /**
     * 曲側に現れる表記の揺れ (改行区切り)。
     *
     * 同じ人が社名の変遷と括弧の全角半角で最大 9 通りに割れていた
     * (BNEI(佐藤貴文) / BNSI（佐藤貴文） / NBGI(佐藤貴文) / 佐藤貴文 …)。
     * 曲から作家を引くときはここを見る。
     */
    @ColumnInfo(name = "aliases")
    val aliases: String? = null
) {
    /** 検索・突き合わせ対象になる表記 (正規名 + 別表記)。 */
    val allSpellings: List<String>
        get() = listOf(name) + (aliases?.split("\n")?.filter { it.isNotBlank() } ?: emptyList())
}
