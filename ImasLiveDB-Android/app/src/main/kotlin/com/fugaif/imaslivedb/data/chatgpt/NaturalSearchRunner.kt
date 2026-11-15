package com.fugaif.imaslivedb.data.chatgpt

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.model.JstDay
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import uniffi.imas_core.NaturalSearchAnswer
import uniffi.imas_core.chatgptResponsesBody
import uniffi.imas_core.naturalSearchProgressLabel
import uniffi.imas_core.naturalSearchRequest

class NaturalSearchException(message: String) : Exception(message)

/**
 * 自然文検索 1 回ぶんを、関数呼び出しの往復ごと回す。iOS `NaturalSearchRunner`。
 *
 * 何を指示するか・どのツールを渡すか・何往復まで許すか・関数の実行・答えのどれを画面に出してよいかは
 * 全部コア (`agent::tools::natural_search`)。ここは HTTP を運び、1 往復ごとにコアを 1 回呼ぶだけ。
 */
class NaturalSearchRunner(
    private val session: ChatGptPlanService,
    private val snapshots: SnapshotStoreProvider,
) {
    /** @param onProgress いま何を調べているかの一言 (コアの文言)。 */
    suspend fun run(query: String, onProgress: (String) -> Unit): NaturalSearchAnswer {
        val today = JstDay.today()
        val request = naturalSearchRequest(query, today)
            ?: throw NaturalSearchException("この長さの文は探せません")
        val model = session.resolvedModel()

        var input = request.input
        var includeReasoning = true
        var round = 0u

        while (round < request.maxRounds) {
            val token = session.validAccessToken()
            val body = chatgptResponsesBody(
                model, request.instructions, input, request.toolsJson, request.textFormatJson, includeReasoning,
            )
            val outputItems = mutableListOf<String>()
            val text = StringBuilder()
            try {
                ChatGptPlanClient.stream(body, token, includeReasoning).collect { event ->
                    when (event) {
                        is ChatGptStreamItem.Delta -> text.append(event.text)
                        is ChatGptStreamItem.ToolCallStarted -> onProgress(naturalSearchProgressLabel(event.name))
                        is ChatGptStreamItem.OutputItem -> outputItems.add(event.json)
                    }
                }
            } catch (e: RetryWithoutReasoning) {
                // 往復には数えない。
                includeReasoning = false
                continue
            } catch (e: ChatGptFailureException) {
                session.settle(e.failure)
                throw e
            }
            round++

            // 止められたストリームはエラー無しで終わるので、ここで止める。
            currentCoroutineContext().ensureActive()

            val sent = input
            val items = outputItems.toList()
            val answerText = text.toString()
            val step = snapshots.query { store -> store.naturalSearchStep(sent, items, answerText, today) }
            step.answer?.let { return it }
            input = step.nextInput
        }
        throw NaturalSearchException(request.tooManyRoundsMessage)
    }
}
