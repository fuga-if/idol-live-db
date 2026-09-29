package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider

/**
 * 編集フィード (`GET /edits`) の対象レコードの可読タイトルを解決する。iOS `editFeedReading` の簡易移植。
 * 詳細画面への遷移は持たず、可読タイトルの解決のみを担う。
 *
 * 何をタイトルにするか (曲名・アイドル名・ライブ名・公演の正式な呼び名) はコアの
 * editRecordTarget が決める。まだ届いていないレコードは null (タイトル無しで出す)。
 */
class EditFeedRepository(private val snapshots: SnapshotStoreProvider) {

    /** recordType / recordName から人間可読なタイトルを解決する。解決できなければ null。 */
    suspend fun recordTitle(recordType: String, recordName: String): String? =
        snapshots.query { store -> store.editRecordTarget(recordType, recordName).title }
}
