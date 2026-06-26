package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.model.UserMark
import java.time.Instant

/** 担当/お気に入り等のユーザーマークを管理 (端末ローカル)。 */
class UserMarkRepository(private val db: AppDatabase) {

    private val dao get() = db.userMarkDao()

    suspend fun isOn(type: String, id: String, kind: String): Boolean = dao.isOn(type, id, kind)

    /** ON/OFF をトグルして新しい状態を返す。 */
    suspend fun toggle(type: String, id: String, kind: String): Boolean {
        val now = !dao.isOn(type, id, kind)
        if (now) {
            dao.upsert(UserMark(type, id, kind, true, null, Instant.now().toString()))
        } else {
            dao.delete(type, id, kind)
        }
        return now
    }

    /** 担当アイドル一覧。 */
    suspend fun pickedIdols(): List<Idol> =
        db.songDao().let { _ -> fetchIdols(dao.idsFor(UserMark.IDOL, UserMark.PICK)) }

    /** お気に入りアイドル一覧。 */
    suspend fun favoriteIdols(): List<Idol> =
        fetchIdols(dao.idsFor(UserMark.IDOL, UserMark.FAVORITE))

    /** お気に入り曲一覧。 */
    suspend fun favoriteSongs(): List<Song> =
        db.songDao().let { sdao ->
            val ids = dao.idsFor(UserMark.SONG, UserMark.FAVORITE)
            ids.mapNotNull { sdao.fetchSong(it) }
        }

    private suspend fun fetchIdols(ids: List<String>): List<Idol> {
        val idao = db.idolDao()
        return ids.mapNotNull { idao.fetchIdol(it) }
    }
}
