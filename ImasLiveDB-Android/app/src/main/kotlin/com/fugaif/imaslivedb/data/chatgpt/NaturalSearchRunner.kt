package com.fugaif.imaslivedb.data.chatgpt

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.model.JstDay
import uniffi.imas_core.NaturalSearchAnswer
import uniffi.imas_core.naturalSearchRequest

/** 自然文検索 1 回ぶん。往復は [ChatGptPlanTaskRunner]、判断はコア (`agent::tools::natural_search`)。iOS `NaturalSearchRunner`。 */
class NaturalSearchRunner(
    private val tasks: ChatGptPlanTaskRunner,
    private val snapshots: SnapshotStoreProvider,
) {
    /** @param onProgress いま何を調べているかの一言 (コアの文言)。 */
    suspend fun run(query: String, onProgress: (String) -> Unit): NaturalSearchAnswer {
        val today = JstDay.today()
        val request = naturalSearchRequest(query, today)
            ?: throw ChatGptPlanTaskException("この長さの文は探せません")
        return tasks.run(request, onProgress) { input, items, text ->
            val step = snapshots.query { store -> store.naturalSearchStep(input, items, text, today) }
            step.answer?.let { ChatGptPlanTaskRunner.Outcome.Finished(it) }
                ?: ChatGptPlanTaskRunner.Outcome.Next(step.nextInput)
        }
    }
}
