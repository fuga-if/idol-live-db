package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.ShowTicket

/**
 * 公演のチケット価格 (マスタ) の読み取り。
 *
 * 通常の書き込みは CloudKit 同期 ([com.fugaif.imaslivedb.data.db.dao.SyncDao]) 経由。
 * ここでも upsert を持たせてはいるが、使い道は開発中の動作確認くらいで、通常の経路ではない。
 *
 * 並べ替えていないのはわざと: どの券を選ぶか・どう並べるか・価格帯をどう出すかの判断は
 * 共有コア (`domain/ticket_prices.rs`, `uniffi.imas_core.ticketsForKind` 等) が持つ。
 * ここで ORDER BY を書くと判断が Kotlin と Rust に二重管理になる。
 */
@Dao
interface ShowTicketDao {

    @Query("SELECT * FROM show_tickets WHERE show_id = :showId")
    suspend fun forShow(showId: String): List<ShowTicket>

    /** 複数公演ぶんをまとめて。一覧で公演ごとに引くと N 回走る。 */
    @Query("SELECT * FROM show_tickets WHERE show_id IN (:showIds)")
    suspend fun forShows(showIds: List<String>): List<ShowTicket>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(ticket: ShowTicket)
}
