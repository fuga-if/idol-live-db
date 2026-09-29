package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.UserMark
import uniffi.imas_core.AttendanceMarkRecord
import uniffi.imas_core.collectionAttendedShows

/**
 * 「回収」を数えるための参加マーク解決 (iOS
 * `ImasLiveDB/Adapters/Persistence/CollectionAttendance.swift` と対になる Android 側)。
 *
 * `user_marks` はスナップショットに無い (書き込みが頻繁でプラットフォームが正) ので、
 * **引くのはここ・選ぶ規則は共有コア** という分担にする:
 *
 * - どのマークを回収に数えるか (既定は現地のみ / 設定で配信・LV も) … コアの
 *   `collectionAttendedShows`。show 単位・event 単位のどちらのマークも参加形態の
 *   条件を通してから渡す (イベント単位だけ素通しにしない — 両方に同じ規則を掛ける)。
 * - どの催しが回収の対象か (リアルライブだけ) … コアの `attended_real_live_shows`
 *   (`showSetlistRowMeta` / `songCollectedCountMap` の内側で済ませている)。
 *
 * 以前は「現地のみ」の条件が `SongDao.fetchAttendedLiveShowIds` という別 SQL (常に現地のみ固定で、
 * 設定「配信参加も回収に含める」を見ない) にも複製されていた (削除済み)。セトリの回収表示で
 * 3 つ目の複製が増えるところだったので、参加マークを使う経路はすべてここへ寄せる。
 */
object CollectionAttendance {

    /** 回収に数える参加 show id (参加形態の条件を適用済み)。 */
    suspend fun showIds(db: AppDatabase, includeStream: Boolean): List<String> =
        collectionAttendedShows(marks(db, UserMark.SHOW), includeStream)

    /**
     * 回収に数える参加 event id (参加形態の条件を適用済み)。配下の公演への展開は
     * 共有コア側の仕事 ([uniffi.imas_core.SnapshotStore.showSetlistRowMeta] 等)。
     */
    suspend fun eventIds(db: AppDatabase, includeStream: Boolean): List<String> =
        collectionAttendedShows(marks(db, UserMark.EVENT), includeStream)

    private suspend fun marks(db: AppDatabase, entityType: String): List<AttendanceMarkRecord> =
        db.userMarkDao().attendedMarks(entityType, UserMark.ATTENDED)
            .map { AttendanceMarkRecord(entityId = it.entityId, attendanceType = it.textValue) }
}
