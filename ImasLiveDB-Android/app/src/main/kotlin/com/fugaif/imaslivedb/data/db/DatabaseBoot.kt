package com.fugaif.imaslivedb.data.db

import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 起動時に端末の DB を開く流れ (iOS `DatabaseBoot` と同じ)。開けるまで画面は DB を読まない。
 *
 * Room は初めて触られたときに DB を開いて移行を流す。そこで失敗すると、触った処理の中で
 * 例外になってアプリが落ち、起動のたびに落ち続けた。ここで先に開き、開けなければ
 * 復旧画面を出す。復旧は「もう一度試す」だけにする。DB を消して作り直すと、端末にしか
 * ないデータ (担当・マイタグ・家計簿) が戻らなくなるので、そういう手段は出さない。
 *
 * @param open DB を開く処理。テストは失敗や成功を差し替える。
 */
class DatabaseBoot(private val open: suspend () -> Unit) {

    sealed interface State {
        data object Preparing : State
        data object Ready : State
        /** 開けなかった。[detail] は利用者に見せる詳細。 */
        data class Failed(val detail: String) : State
    }

    private val _state = MutableStateFlow<State>(State.Preparing)
    val state: StateFlow<State> = _state.asStateFlow()

    /** 開いている途中に呼ばれても、二重に開かない。 */
    private val opening = Mutex()

    /**
     * DB を開く。開き終えた後に呼んでも何もしない。失敗の後に呼ぶと開き直す
     * (復旧画面の「もう一度試す」)。
     */
    suspend fun prepare() = opening.withLock {
        if (_state.value == State.Ready) return@withLock
        _state.value = State.Preparing
        _state.value = try {
            open()
            State.Ready
        } catch (e: CancellationException) {
            // 取り消しは失敗ではない。次に呼ばれたときに開き直す。
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "database_prepare_failed", e)
            State.Failed(e.message ?: e.toString())
        }
    }

    private companion object {
        const val TAG = "DatabaseBoot"
    }
}
