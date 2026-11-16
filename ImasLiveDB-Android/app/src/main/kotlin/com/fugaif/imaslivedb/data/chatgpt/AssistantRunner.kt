package com.fugaif.imaslivedb.data.chatgpt

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.repository.PlaylistRepository
import uniffi.imas_core.AiPlaylistRef
import uniffi.imas_core.AssistantPlan
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
    /** @param history 前の番の [AssistantPlan.history] (最初は空)。 */
    suspend fun run(history: List<String>, order: String, onProgress: (String) -> Unit): AssistantPlan {
        val today = JstDay.today()
        val request = assistantRequest(history, order, today)
            ?: throw ChatGptPlanTaskException("会話が長くなりました。新しい会話を始めてください")
        // 「〜に足して」の足す先は、コアが名前から決める。端末にあるプレイリストを射影して渡す。
        val refs = playlists.summaries().map { AiPlaylistRef(it.playlist.id, it.playlist.name) }
        return tasks.run(request, onProgress) { input, items, text ->
            val step = snapshots.query { store -> store.assistantStep(input, items, text, today, refs) }
            step.plan?.let { ChatGptPlanTaskRunner.Outcome.Finished(it) }
                ?: ChatGptPlanTaskRunner.Outcome.Next(step.nextInput)
        }
    }
}
