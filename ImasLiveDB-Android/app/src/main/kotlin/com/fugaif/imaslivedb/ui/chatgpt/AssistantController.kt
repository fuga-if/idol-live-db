package com.fugaif.imaslivedb.ui.chatgpt

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.fugaif.imaslivedb.data.chatgpt.AssistantExecutor
import com.fugaif.imaslivedb.data.chatgpt.AssistantRunner
import com.fugaif.imaslivedb.data.chatgpt.ChatGptPlanService
import com.fugaif.imaslivedb.data.chatgpt.ChatSessionStore
import com.fugaif.imaslivedb.ui.producercard.PaperCardCodeReader
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.AssistantPlan
import uniffi.imas_core.ChatSavedAction
import uniffi.imas_core.ChatSavedTurn
import uniffi.imas_core.ChatSession
import uniffi.imas_core.assistantAcceptsMessage
import uniffi.imas_core.assistantMaxImages
import uniffi.imas_core.chatSessionTitle

sealed interface AssistantActionOutcome {
    data object Done : AssistantActionOutcome
    data class Failed(val message: String) : AssistantActionOutcome
}

/** 1 番ぶんの返事と一覧、その場の選択・実行の結果。 */
data class AssistantReview(
    val plan: AssistantPlan,
    /** この番で描いてもらった画像 (会話には残さない)。 */
    val images: List<Bitmap> = emptyList(),
    val selected: Set<Int>,
    val outcomes: Map<Int, AssistantActionOutcome> = emptyMap(),
    val isExecuting: Boolean = false,
) {
    val pending: List<Int> get() = selected.filter { it !in outcomes }.sorted()
}

sealed interface AssistantTurnState {
    data class Running(val label: String) : AssistantTurnState
    data class Done(val review: AssistantReview) : AssistantTurnState
    data class Failed(val message: String) : AssistantTurnState

    /** 履歴から読み直した番。操作は見るだけ (実行できる形では残していない)。[imageCount] は添えた枚数 (画像そのものは無い)。 */
    data class Restored(val reply: String, val actions: List<ChatSavedAction>, val imageCount: UInt) : AssistantTurnState
}

data class AssistantTurn(
    val key: Int,
    val order: String,
    val images: List<Bitmap>,
    val state: AssistantTurnState,
    /** 画像を添えなかった発言に、直前の画像を付け直したもの (紙片には出さず、履歴にも数えない)。 */
    val carried: List<Bitmap> = emptyList(),
) {
    /** ChatGPT に送り、実行役に「添えた画像」として渡す画像。 */
    val sent: List<Bitmap> get() = images.ifEmpty { carried }
}

/**
 * チャット 1 本ぶんの状態と、返事待ち・実行・保存の持ち主。iOS の `AssistantSheet` が持つ `@State` と `Task` に当たる。
 *
 * 画面 (Composable) より長く生きる。タブとして出すチャットは `AppModule.assistantTabController` の 1 つを使い、
 * タブを離れても返事待ちと実行は続き、戻ると同じ画面が出る。シートとして出すときは、シートごとに
 * 別のインスタンスを作り、閉じたら [shutdown] で止める。
 *
 * 状態は Compose のスナップショット状態で、書き換えはメインスレッドだけ ([scope] がメイン)。
 * 判断・規則はここに無い (どの操作を初めに選ぶか・何を残すかはコア)。
 */
class AssistantController(
    private val context: Context,
    private val runner: AssistantRunner,
    private val executor: AssistantExecutor,
    private val planService: ChatGptPlanService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var runJob: Job? = null
    private var nextKey = 0

    var text by mutableStateOf("")
    var turns by mutableStateOf<List<AssistantTurn>>(emptyList())
        private set

    /** 次の発言に添える画像。 */
    var attachments by mutableStateOf<List<Bitmap>>(emptyList())
        private set

    /** いまの会話の id (端末に残すときの鍵)。新しい会話のたびに振り直す。 */
    var sessionId by mutableStateOf(UUID.randomUUID().toString())
        private set

    /** ここまでの会話 (コアが組んだ input)。次の番にそのまま渡す。 */
    private var history: List<String> = emptyList()

    val isRunning: Boolean get() = turns.lastOrNull()?.state is AssistantTurnState.Running
    val isExecuting: Boolean
        get() = turns.any { (it.state as? AssistantTurnState.Done)?.review?.isExecuting == true }

    private val canUsePlan: Boolean get() = planService.state.value.canUsePlan

    /** シートを閉じるとき。返事待ちも実行も止める。タブのインスタンスには呼ばない。 */
    fun shutdown() {
        scope.cancel()
    }

    fun removeAttachment(index: Int) {
        attachments = attachments.filterIndexed { i, _ -> i != index }
    }

    /** 写真・クリップボードの URI を開いて、上限までを添える。 */
    fun attach(uris: List<Uri>) {
        if (uris.isEmpty()) return
        val maxImages = assistantMaxImages().toInt()
        scope.launch {
            for (uri in uris) {
                if (attachments.size >= maxImages) break
                val image = PaperCardCodeReader.loadBitmap(context, uri) ?: continue
                attachments = attachments + image
            }
        }
    }

    /** いまの会話の保存形。返事まで終わった番だけ (途中・失敗の番は残さない)。 */
    private fun snapshot(): ChatSession? {
        val saved = turns.mapNotNull { turn ->
            when (val state = turn.state) {
                is AssistantTurnState.Done -> {
                    val review = state.review
                    ChatSavedTurn(
                        order = turn.order,
                        imageCount = turn.images.size.toUInt(),
                        reply = review.plan.message,
                        actions = review.plan.actions.mapIndexed { index, item ->
                            ChatSavedAction(item.title, item.target, review.outcomes[index] == AssistantActionOutcome.Done)
                        },
                    )
                }
                is AssistantTurnState.Restored -> ChatSavedTurn(turn.order, state.imageCount, state.reply, state.actions)
                is AssistantTurnState.Running, is AssistantTurnState.Failed -> null
            }
        }
        val first = saved.firstOrNull() ?: return null
        return ChatSession(
            id = sessionId,
            title = chatSessionTitle(first.order),
            updatedAt = System.currentTimeMillis() / 1000,
            history = history,
            turns = saved,
        )
    }

    private fun persist() {
        val session = snapshot() ?: return
        scope.launch(Dispatchers.IO) { ChatSessionStore.save(context, session) }
    }

    private fun update(key: Int, change: (AssistantTurn) -> AssistantTurn) {
        turns = turns.map { if (it.key == key) change(it) else it }
    }

    private fun start(turn: AssistantTurn) {
        runJob?.cancel()
        val before = history
        runJob = scope.launch {
            try {
                val outcome = runner.run(before, turn.order, turn.sent) { label ->
                    update(turn.key) { it.copy(state = AssistantTurnState.Running(label)) }
                }
                val plan = outcome.plan
                history = plan.history
                // サーバに届く操作は、利用者が自分で選ぶまで外しておく (決めるのはコア)。
                val selected = plan.actions.indices.filter { plan.actions[it].preselected }.toSet()
                update(turn.key) { it.copy(state = AssistantTurnState.Done(AssistantReview(plan, outcome.images, selected))) }
                persist()
            } catch (e: CancellationException) {
                abandon(turn.key)
                throw e
            } catch (e: Exception) {
                Log.e("Assistant", "assistant_failed: ${e.message}")
                update(turn.key) { it.copy(state = AssistantTurnState.Failed(e.message ?: "")) }
            }
        }
    }

    /** 止まった番が「考えています…」のまま残らないようにする。[cancel] が先に片付けていれば何もしない。 */
    private fun abandon(key: Int) {
        val turn = turns.firstOrNull { it.key == key } ?: return
        if (turn.state !is AssistantTurnState.Running) return
        turns = turns.filter { it.key != key }
        if (text.isEmpty()) text = turn.order
        if (attachments.isEmpty()) attachments = turn.images
    }

    fun send(order: String) {
        val images = attachments
        if (!canUsePlan || isRunning || !assistantAcceptsMessage(order, images.size.toUInt())) return
        text = ""
        attachments = emptyList()
        // 画像を添えなかった発言には、直前に画像を送った番の画像を付け直す (「さっきの画像で」と続けて頼める)。
        val carried = if (images.isEmpty()) turns.lastOrNull { it.sent.isNotEmpty() }?.sent.orEmpty() else emptyList()
        val turn = AssistantTurn(nextKey++, order.trim(), images, AssistantTurnState.Running("考えています…"), carried)
        turns = turns + turn
        start(turn)
    }

    fun retry(turn: AssistantTurn) {
        if (isRunning || turns.lastOrNull()?.key != turn.key) return
        val running = turn.copy(state = AssistantTurnState.Running("考えています…"))
        update(turn.key) { running }
        start(running)
    }

    /** 考えている途中の番をやめる。発言は入力欄に戻す。 */
    fun cancel() {
        runJob?.cancel()
        runJob = null
        val last = turns.lastOrNull() ?: return
        if (last.state !is AssistantTurnState.Running) return
        turns = turns.dropLast(1)
        text = last.order
        attachments = last.images
    }

    /** 新しい会話を始める。 */
    fun reset() {
        runJob?.cancel()
        runJob = null
        turns = emptyList()
        history = emptyList()
        attachments = emptyList()
        sessionId = UUID.randomUUID().toString()
    }

    /** 履歴の会話を開いて、続きから話せるようにする。 */
    fun openSession(id: String) {
        if (isRunning || isExecuting) return
        scope.launch {
            val saved = withContext(Dispatchers.IO) { ChatSessionStore.load(context, id) } ?: return@launch
            if (isRunning || isExecuting) return@launch
            runJob?.cancel()
            runJob = null
            sessionId = saved.id
            history = saved.history
            attachments = emptyList()
            turns = saved.turns.map {
                AssistantTurn(nextKey++, it.order, emptyList(), AssistantTurnState.Restored(it.reply, it.actions, it.imageCount))
            }
        }
    }

    fun toggle(key: Int, index: Int) {
        val review = (turns.firstOrNull { it.key == key }?.state as? AssistantTurnState.Done)?.review ?: return
        if (review.isExecuting || index in review.outcomes) return
        val selected = if (index in review.selected) review.selected - index else review.selected + index
        update(key) { it.copy(state = AssistantTurnState.Done(review.copy(selected = selected))) }
    }

    /**
     * 選んだ操作を上から順に 1 件ずつ実行する。1 件の失敗で残りを止めない。
     * 途中で止められても、済んだ操作の記録は残す。
     *
     * @param onOpened 「開く」操作があったとき、実行のあとに呼ぶ (最初の 1 件の行き先)。
     */
    fun execute(key: Int, onOpened: (AssistantExecutor.Opened) -> Unit) {
        var review = (turns.firstOrNull { it.key == key }?.state as? AssistantTurnState.Done)?.review ?: return
        if (review.isExecuting) return
        val targets = review.pending
        if (targets.isEmpty()) return
        review = review.copy(isExecuting = true)
        update(key) { it.copy(state = AssistantTurnState.Done(review)) }
        // 名刺の写真・素材は、この番の発言に添えた画像から取る。
        val attached = turns.firstOrNull { it.key == key }?.sent.orEmpty()
        val generated = review.images
        scope.launch {
            var opened: AssistantExecutor.Opened? = null
            try {
                for (index in targets) {
                    val outcome = try {
                        val result = executor.perform(review.plan.actions[index].action, attached, generated)
                        opened = opened ?: result
                        AssistantActionOutcome.Done
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        Log.e("Assistant", "assistant_action_failed: ${e.message}")
                        AssistantActionOutcome.Failed(e.message ?: "")
                    }
                    review = review.copy(outcomes = review.outcomes + (index to outcome))
                    update(key) { it.copy(state = AssistantTurnState.Done(review)) }
                }
            } finally {
                review = review.copy(isExecuting = false)
                update(key) { it.copy(state = AssistantTurnState.Done(review)) }
                val session = snapshot()
                if (session != null) {
                    withContext(NonCancellable + Dispatchers.IO) { ChatSessionStore.save(context, session) }
                }
            }
            opened?.let(onOpened)
        }
    }
}
