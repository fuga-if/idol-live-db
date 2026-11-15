package com.fugaif.imaslivedb.data.chatgpt

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import uniffi.imas_core.PlanTaskRequest
import uniffi.imas_core.chatgptResponsesBody
import uniffi.imas_core.naturalSearchProgressLabel

/** 仕事の失敗 (画面にそのまま出す文言を持つ)。 */
class ChatGptPlanTaskException(message: String) : Exception(message)

/**
 * 利用者の ChatGPT プランで回す仕事 1 回ぶんを、関数呼び出しの往復ごと回す。iOS `ChatGPTPlanTaskRunner`。
 *
 * 何を指示するか・どのツールを渡すか・何往復まで許すか・関数の実行・答えの検証は全部コア
 * (`agent::tools::plan_loop` と、仕事ごとの `natural_search` / `prep_dj`)。ここは HTTP を運び、
 * 1 往復ごとに [step] (コアの 1 呼び出し) を呼ぶだけ。
 */
class ChatGptPlanTaskRunner(private val session: ChatGptPlanService) {
    /** 1 往復ぶんの結末。 */
    sealed interface Outcome<out R> {
        data class Finished<R>(val result: R) : Outcome<R>

        /** 次のリクエストの input。 */
        data class Next(val input: List<String>) : Outcome<Nothing>
    }

    /**
     * @param onProgress いま何を調べているかの一言 (コアの文言)。
     * @param step この往復で送った input・応答で確定した出力項目・本文を受けて、コアに次を決めさせる。
     */
    suspend fun <R> run(
        request: PlanTaskRequest,
        onProgress: (String) -> Unit,
        step: suspend (input: List<String>, outputItems: List<String>, text: String) -> Outcome<R>,
    ): R {
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
                // やり直すかどうかはコアが決めている (1 回だけ)。往復には数えない。
                includeReasoning = false
                continue
            } catch (e: ChatGptFailureException) {
                session.settle(e.failure)
                throw e
            }
            round++

            // 止められたストリームはエラー無しで終わるので、ここで止める。
            currentCoroutineContext().ensureActive()

            when (val outcome = step(input, outputItems.toList(), text.toString())) {
                is Outcome.Finished -> return outcome.result
                is Outcome.Next -> input = outcome.input
            }
        }
        throw ChatGptPlanTaskException(request.tooManyRoundsMessage)
    }
}
