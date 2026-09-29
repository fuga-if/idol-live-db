package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Anniversary
import com.fugaif.imaslivedb.data.model.Staff

@Dao
interface CalendarDao {

    // ---- 実体化 (スナップショット経路) ----
    // 共有コアの calendarEntries は staff_id / anniversary_id しか返さず、スナップショットに
    // この 2 つのレコード取得 API が無い。iOS CoreCalendarRepository と同じ判断で、実体は
    // ローカル DB の全件読みで解決する (どちらも数十件のマスタなので分割の必要が無い)。

    @Query("SELECT * FROM staff")
    suspend fun fetchAllStaff(): List<Staff>

    @Query("SELECT * FROM anniversaries")
    suspend fun fetchAllAnniversaries(): List<Anniversary>
}
