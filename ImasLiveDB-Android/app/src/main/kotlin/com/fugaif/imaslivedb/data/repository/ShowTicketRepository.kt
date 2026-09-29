package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.ShowTicket

/**
 * 公演のチケット価格 (マスタ) の読み取り口。
 *
 * **みんなで共有する事実**なので端末ローカルの収支 ([ExpenseRepository]) とは別の表に持つ。
 * 券種の選び方・並び・価格帯・入力検査の判断は一切ここに持たせない — 呼び出し側が
 * 生の行を共有コア (`uniffi.imas_core.ticketsForKind` 等、または [ShowTicket.toCore]) へ
 * 渡して判断させる。
 */
class ShowTicketRepository(private val db: AppDatabase) {

    private val dao get() = db.showTicketDao()

    /** その公演の券種 (生の行)。 */
    suspend fun forShow(showId: String): List<ShowTicket> = dao.forShow(showId)

    /** 複数公演ぶんをまとめて (公演 id → 券種)。一覧で公演ごとに引くと N 回走る。 */
    suspend fun forShows(showIds: List<String>): Map<String, List<ShowTicket>> {
        if (showIds.isEmpty()) return emptyMap()
        return dao.forShows(showIds).groupBy { it.showId }
    }
}
