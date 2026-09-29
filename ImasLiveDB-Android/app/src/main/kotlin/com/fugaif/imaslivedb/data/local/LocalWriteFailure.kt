package com.fugaif.imaslivedb.data.local

import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * 端末にしか無いデータ (担当・参加・メモ・座席・習熟度・家計簿・マイタグ) の書き込み失敗を 1 か所で受ける。
 * iOS `LocalWriteFailure` と同じ。
 *
 * これらはクラウドにもサーバにも無いので、書けなかったことを黙っていると、保存したつもりの
 * 記録が次に開いたときに消えている。画面は握りつぶさず、[localWrite] を通して失敗をここへ渡す。
 * ログに残し、利用者にはアラートで知らせる (出すのはアプリのルート。[notices] を見ている)。
 */
object LocalWriteFailure {
    private const val TAG = "LocalWrite"

    /** 利用者に見せる知らせ。 */
    data class Notice(val title: String, val message: String)

    private val _notices = MutableSharedFlow<Notice>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )

    /** 知らせの流れ。アプリのルートが 1 つずつアラートにする。 */
    val notices: SharedFlow<Notice> = _notices.asSharedFlow()

    /** @param action 何をしようとして失敗したか (例: "メモの保存")。 */
    fun report(error: Throwable, action: String) {
        Log.e(TAG, "local_write_failed action=$action", error)
        _notices.tryEmit(notice(action))
    }

    /**
     * 失敗した操作の名前から、知らせの文面を作る (iOS と同じ文面)。
     * 書き込みは 1 トランザクションなので、失敗したら何も変わっていない。それをそのまま伝える。
     */
    fun notice(action: String): Notice = Notice(
        title = "保存できませんでした",
        message = "${action}に失敗しました。変更は保存されていません。もう一度お試しください。"
    )
}

/**
 * 端末ローカルの書き込みを 1 回行う。失敗したら [LocalWriteFailure] で知らせて null を返す
 * (呼び出し側は null なら「保存できなかった」として、入力を捨てない・画面を閉じない)。
 */
suspend fun <T> localWrite(action: String, block: suspend () -> T): T? =
    try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        LocalWriteFailure.report(e, action)
        null
    }
