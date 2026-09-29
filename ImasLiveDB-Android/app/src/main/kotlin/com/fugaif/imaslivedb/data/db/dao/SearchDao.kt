package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.SongSpelling

/** 曲のあいまい検索 (「もしかして」) の母集団。 */
@Dao
interface SearchDao {

    /**
     * あいまい検索 (「もしかして」) の母集団。
     *
     * 編集距離は全件と突き合わせないと出せないので LIMIT を掛けられない。代わりに
     * 綴り 2 列だけの射影にして、Song 実体は当たった数十件だけ後から引く。
     *
     * brand_id = 'other' (歌枠カバー等) は除く。曲一覧が既定でこれを隠しているので、
     * あいまい候補にだけ出てくると「一覧に無い曲が『もしかして』に並ぶ」ことになる。
     * IS NOT にしているのは brand_id が NULL の曲を落とさないため (<> だと NULL は偽)。
     */
    @Query("SELECT id, title, title_kana FROM songs WHERE brand_id IS NOT 'other'")
    suspend fun fetchSongSpellings(): List<SongSpelling>
}
