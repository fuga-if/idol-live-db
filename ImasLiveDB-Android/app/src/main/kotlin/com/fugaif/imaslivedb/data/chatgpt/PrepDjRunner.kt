package com.fugaif.imaslivedb.data.chatgpt

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.model.JstDay
import uniffi.imas_core.PrepDjPlan

/**
 * 予習 DJ。コアだけで組んだ流れと、ChatGPT プランで語りを付けた流れの 2 つの口。iOS `PrepDJRunner`。
 *
 * 並べ方・語りの検証・注文の上限は全部コア (`domain::prep_dj` / `agent::tools::prep_dj`)。
 */
class PrepDjRunner(
    private val tasks: ChatGptPlanTaskRunner,
    private val snapshots: SnapshotStoreProvider,
) {
    /** 入口に出す名前 (「予習 DJ」「復習 DJ」)。null なら入口を出さない (どの公演に出すかはコアが決める)。 */
    suspend fun entryLabel(showId: String): String? =
        snapshots.query { store -> store.prepDjEntryLabel(showId) }

    /** コアだけで組んだ流れ (つないでいなくても出る)。組めない公演は null。初回は予測の下ごしらえで重い (query が Default で回す)。 */
    suspend fun basePlan(showId: String): PrepDjPlan? =
        snapshots.query { store -> store.prepDjPlan(showId) }

    /** ChatGPT プランで語りつきの流れを組む。使える流れにならなければ、コアの文言で失敗を投げる。 */
    suspend fun modelPlan(showId: String, order: String, onProgress: (String) -> Unit): PrepDjPlan {
        val today = JstDay.today()
        val request = snapshots.query { store -> store.prepDjRequest(showId, order, today) }
            ?: throw ChatGptPlanTaskException("この公演の流れは組めません")
        return tasks.run(request, onProgress) { input, items, text ->
            val step = snapshots.query { store -> store.prepDjStep(showId, input, items, text, today) }
            val plan = step.plan
            when {
                step.nextInput.isNotEmpty() -> ChatGptPlanTaskRunner.Outcome.Next(step.nextInput)
                plan != null -> ChatGptPlanTaskRunner.Outcome.Finished(plan)
                else -> throw ChatGptPlanTaskException(step.failureMessage ?: "うまく組めませんでした")
            }
        }
    }
}
