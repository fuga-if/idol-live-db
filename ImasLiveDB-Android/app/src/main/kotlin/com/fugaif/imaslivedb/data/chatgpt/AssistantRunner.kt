package com.fugaif.imaslivedb.data.chatgpt

import android.graphics.Bitmap
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.repository.PlaylistRepository
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import uniffi.imas_core.AiDeviceContext
import uniffi.imas_core.AiPlaylistRef
import uniffi.imas_core.AssistantPlan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.assistantMaxImages
import uniffi.imas_core.assistantRequest

/**
 * アプリ内の会話 1 番ぶん。往復は [ChatGptPlanTaskRunner]、判断はコア (`agent::tools::assistant`)。iOS `AssistantRunner`。
 *
 * 返るのは返事と「これからやること」の一覧で、ここでは何も実行しない。
 * 実行は利用者が一覧を見て押してから ([AssistantExecutor])。
 */
class AssistantRunner(
    private val tasks: ChatGptPlanTaskRunner,
    private val snapshots: SnapshotStoreProvider,
    private val playlists: PlaylistRepository,
) {
    /**
     * @param history 前の番の [AssistantPlan.history] (最初は空)。
     * @param images 発言に添える画像。長辺 2048px の JPEG base64 にして渡す (縮め方はコール表と同じ)。
     */
    suspend fun run(history: List<String>, order: String, images: List<Bitmap>, onProgress: (String) -> Unit): AssistantPlan {
        val today = JstDay.today()
        // 端末の側の事情 (足す先のプレイリスト・習熟度の段階の名前) を射影して渡す。決めるのはコア。
        val refs = playlists.summaries().map { AiPlaylistRef(it.playlist.id, it.playlist.name) }
        val device = AiDeviceContext(refs, AppPreferences.masteryScale.labels)
        val encoded = withContext(Dispatchers.Default) {
            images.take(assistantMaxImages().toInt()).mapNotNull(::jpegBase64)
        }
        val request = assistantRequest(history, order, encoded, today, device)
            ?: throw ChatGptPlanTaskException("会話が長くなりました。新しい会話を始めてください")
        return tasks.run(request, onProgress) { input, items, text ->
            val step = snapshots.query { store -> store.assistantStep(input, items, text, today, device) }
            step.plan?.let { ChatGptPlanTaskRunner.Outcome.Finished(it) }
                ?: ChatGptPlanTaskRunner.Outcome.Next(step.nextInput)
        }
    }
}
