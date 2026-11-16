package com.fugaif.imaslivedb.ui.chatgpt

import android.content.ClipboardManager
import android.graphics.Bitmap
import android.net.Uri
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.fugaif.imaslivedb.data.chatgpt.AssistantExecutor
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChatAccessoryItem
import com.fugaif.imaslivedb.ui.designsystem.ImasChatAccessoryMenu
import com.fugaif.imaslivedb.ui.designsystem.ImasChatBubble
import com.fugaif.imaslivedb.ui.designsystem.ImasChatComposer
import com.fugaif.imaslivedb.ui.designsystem.ImasChatThinking
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.producercard.PaperCardCodeReader
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.imas_core.AiActionReach
import uniffi.imas_core.AiPlannedAction
import uniffi.imas_core.AssistantPlan
import uniffi.imas_core.assistantAccepts
import uniffi.imas_core.assistantAcceptsMessage
import uniffi.imas_core.assistantMaxImages
import uniffi.imas_core.assistantExamples
import uniffi.imas_core.assistantMaxOrderChars

private sealed interface Outcome {
    data object Done : Outcome
    data class Failed(val message: String) : Outcome
}

/** 1 番ぶんの返事と一覧、その場の選択・実行の結果。 */
private data class Review(
    val plan: AssistantPlan,
    val selected: Set<Int>,
    val outcomes: Map<Int, Outcome> = emptyMap(),
    val isExecuting: Boolean = false,
) {
    val pending: List<Int> get() = selected.filter { it !in outcomes }.sorted()
}

private sealed interface TurnState {
    data class Running(val label: String) : TurnState
    data class Done(val review: Review) : TurnState
    data class Failed(val message: String) : TurnState
}

private data class Turn(val key: Int, val order: String, val images: List<Bitmap>, val state: TurnState)

/**
 * チャット。利用者の ChatGPT プランで、データベースを引いて答え、頼まれた操作を一覧にする。iOS `AssistantSheet`。
 *
 * 返事の事実はコアの読み取りツールで引いたもの。操作は、返事の下に「これからやること」として
 * 出て、利用者が選んで押すまで何も変わらない。一覧に出るのはコアが検査した操作だけ
 * (`domain::ai_actions`) で、サーバに届く操作は初めは選ばれていない。
 *
 * @param initialOrder 最初の発言。空なら何も送らずに開く。
 * @param onOpen 「開く」操作の行き先。既定は [NaturalSearchOpen] へ依頼する (シートは本体のナビの外にあるので、
 *   実行のあとシートを閉じて本体の側で開く)。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssistantSheet(
    initialOrder: String,
    onDismiss: () -> Unit,
    onOpen: (NaturalSearchKind, String) -> Unit = { kind, id -> NaturalSearchOpen.request(kind, id) },
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val session by module.chatGptPlanService.state.collectAsState()
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var turns by remember { mutableStateOf<List<Turn>>(emptyList()) }
    /** ここまでの会話 (コアが組んだ input)。次の番にそのまま渡す。 */
    var history by remember { mutableStateOf<List<String>>(emptyList()) }
    var nextKey by remember { mutableStateOf(0) }
    var runJob by remember { mutableStateOf<Job?>(null) }
    /** 次の発言に添える画像。 */
    var attachments by remember { mutableStateOf<List<Bitmap>>(emptyList()) }
    val scroll = rememberScrollState()

    val isRunning = turns.lastOrNull()?.state is TurnState.Running
    val maxImages = remember { assistantMaxImages().toInt() }

    /** 写真・クリップボードの URI を開いて、上限までを添える。 */
    fun attach(uris: List<Uri>) {
        if (uris.isEmpty()) return
        scope.launch {
            for (uri in uris) {
                if (attachments.size >= maxImages) break
                val image = PaperCardCodeReader.loadBitmap(context, uri) ?: continue
                attachments = attachments + image
            }
        }
    }

    val pickPhotos = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(maxImages.coerceAtLeast(2)),
    ) { attach(it) }

    /** クリップボードに画像の URI があるときだけ添える。無ければ何もしない。 */
    fun pasteImages() {
        val clip = (context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.primaryClip ?: return
        val uris = (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
            .filter { context.contentResolver.getType(it)?.startsWith("image/") == true }
        attach(uris)
    }

    fun update(key: Int, change: (Turn) -> Turn) {
        turns = turns.map { if (it.key == key) change(it) else it }
    }

    fun start(turn: Turn) {
        runJob?.cancel()
        val before = history
        runJob = scope.launch {
            try {
                val plan = module.assistantRunner.run(before, turn.order, turn.images) { label ->
                    update(turn.key) { it.copy(state = TurnState.Running(label)) }
                }
                history = plan.history
                // サーバに届く操作は、利用者が自分で選ぶまで外しておく。
                val selected = plan.actions.indices.filter { plan.actions[it].preselected }.toSet()
                update(turn.key) { it.copy(state = TurnState.Done(Review(plan, selected))) }
            } catch (e: CancellationException) {
                // やめた。発言は cancel() が消している。
                throw e
            } catch (e: Exception) {
                Log.e("Assistant", "assistant_failed: ${e.message}")
                update(turn.key) { it.copy(state = TurnState.Failed(e.message ?: "")) }
            }
        }
    }

    fun send(order: String) {
        val images = attachments
        if (!session.canUsePlan || isRunning || !assistantAcceptsMessage(order, images.size.toUInt())) return
        text = ""
        attachments = emptyList()
        val turn = Turn(nextKey++, order.trim(), images, TurnState.Running("考えています…"))
        turns = turns + turn
        start(turn)
    }

    fun retry(turn: Turn) {
        if (isRunning || turns.lastOrNull()?.key != turn.key) return
        val running = turn.copy(state = TurnState.Running("考えています…"))
        update(turn.key) { running }
        start(running)
    }

    /** 考えている途中の番をやめる。発言は入力欄に戻す。 */
    fun cancel() {
        runJob?.cancel()
        runJob = null
        val last = turns.lastOrNull() ?: return
        if (last.state !is TurnState.Running) return
        turns = turns.dropLast(1)
        text = last.order
        attachments = last.images
    }

    fun reset() {
        runJob?.cancel()
        runJob = null
        turns = emptyList()
        history = emptyList()
        attachments = emptyList()
    }

    fun toggle(key: Int, index: Int) {
        val review = (turns.firstOrNull { it.key == key }?.state as? TurnState.Done)?.review ?: return
        if (review.isExecuting || index in review.outcomes) return
        val selected = if (index in review.selected) review.selected - index else review.selected + index
        update(key) { it.copy(state = TurnState.Done(review.copy(selected = selected))) }
    }

    fun close() {
        runJob?.cancel()
        onDismiss()
    }

    /** 選んだ操作を上から順に 1 件ずつ実行する。1 件の失敗で残りを止めない。 */
    fun execute(key: Int) {
        var review = (turns.firstOrNull { it.key == key }?.state as? TurnState.Done)?.review ?: return
        if (review.isExecuting) return
        val targets = review.pending
        if (targets.isEmpty()) return
        review = review.copy(isExecuting = true)
        update(key) { it.copy(state = TurnState.Done(review)) }
        scope.launch {
            var opened: AssistantExecutor.Opened? = null
            for (index in targets) {
                val outcome = try {
                    val result = module.assistantExecutor.perform(review.plan.actions[index].action)
                    opened = opened ?: result
                    Outcome.Done
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.e("Assistant", "assistant_action_failed: ${e.message}")
                    Outcome.Failed(e.message ?: "")
                }
                review = review.copy(outcomes = review.outcomes + (index to outcome))
                update(key) { it.copy(state = TurnState.Done(review)) }
            }
            review = review.copy(isExecuting = false)
            update(key) { it.copy(state = TurnState.Done(review)) }
            when (val result = opened) {
                is AssistantExecutor.Opened.Detail -> { close(); onOpen(result.target.kind, result.target.id) }
                // 一覧のタブへ移ったので、上に被さっているこのシートは閉じる。
                AssistantExecutor.Opened.List -> close()
                null -> Unit
            }
        }
    }

    LaunchedEffect(Unit) {
        if (turns.isEmpty() && session.canUsePlan && assistantAccepts(initialOrder)) send(initialOrder)
    }
    LaunchedEffect(turns.size, isRunning) { scroll.animateScrollTo(scroll.maxValue) }
    DisposableEffect(Unit) { onDispose { runJob?.cancel() } }

    ModalBottomSheet(
        onDismissRequest = { close() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg,
    ) {
        ImasFormBackdrop(Modifier.fillMaxSize().imePadding()) {
            Column(Modifier.fillMaxSize()) {
                ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = { close() }), title = "チャット")
                Column(
                    Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .verticalScroll(scroll)
                        .padding(horizontal = DS.Space.screen)
                        .padding(bottom = DS.Space.section),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                ) {
                    when {
                        !session.canUsePlan -> ImasEmptyState(
                            icon = Icons.Outlined.ChatBubbleOutline,
                            title = "ChatGPT とつなぐと使えます",
                            message = "マイページの「ChatGPT とつなぐ」から、ChatGPT Plus / Pro のアカウントでログインしてください",
                        )
                        turns.isEmpty() -> Examples(onExample = { send(it) })
                        else -> {
                            turns.forEach { turn ->
                                TurnView(
                                    turn = turn,
                                    onRetry = { retry(turn) },
                                    onToggle = { index -> toggle(turn.key, index) },
                                    onExecute = { execute(turn.key) },
                                )
                            }
                            if (!isRunning) {
                                ImasButton(
                                    title = "新しい会話にする",
                                    onClick = { reset() },
                                    icon = Icons.Filled.Edit,
                                    role = ImasButtonRole.PLAIN,
                                    size = ImasButtonSize.SMALL,
                                )
                            }
                        }
                    }
                }
                if (session.canUsePlan) {
                    ImasChatComposer(
                        prompt = "聞きたいこと・やってほしいこと",
                        text = text,
                        onTextChange = { new ->
                            val limit = assistantMaxOrderChars().toInt()
                            text = if (new.length > limit) new.take(limit) else new
                        },
                        canSend = !isRunning && assistantAcceptsMessage(text, attachments.size.toUInt()),
                        onSend = { send(text) },
                        attachments = attachments,
                        onRemoveAttachment = { index ->
                            attachments = attachments.filterIndexed { i, _ -> i != index }
                        },
                        isRunning = isRunning,
                        onStop = { cancel() },
                        accessory = {
                            ImasChatAccessoryMenu(
                                items = listOf(
                                    ImasChatAccessoryItem("写真を選ぶ") {
                                        pickPhotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                    },
                                    ImasChatAccessoryItem("貼り付ける") { pasteImages() },
                                ),
                                enabled = attachments.size < maxImages,
                            )
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun Examples(onExample: (String) -> Unit) {
    val examples = remember { assistantExamples() }
    ImasSection("たとえば", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            examples.forEach { example ->
                ImasNavRow(
                    title = example,
                    icon = Icons.Outlined.ChatBubbleOutline,
                    iconTone = ImasIconTileTone.NEUTRAL,
                    showsChevron = false,
                    onClick = { onExample(example) },
                )
            }
        }
        ImasNote(
            "答えはデータベースを引いて作ります。頼んだ操作は、一覧で確かめて押すまで実行しません。",
            modifier = Modifier.padding(top = DS.Space.header),
            icon = Icons.Filled.Check,
        )
    }
}

@Composable
private fun TurnView(
    turn: Turn,
    onRetry: () -> Unit,
    onToggle: (Int) -> Unit,
    onExecute: () -> Unit,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        ImasChatBubble(turn.order, images = turn.images)
        when (val state = turn.state) {
            is TurnState.Running -> ImasChatThinking(state.label)
            is TurnState.Done -> ReviewView(state.review, onToggle, onExecute)
            is TurnState.Failed -> ImasNotice(
                kind = ImasNoticeKind.ERROR,
                title = "答えられませんでした",
                message = state.message,
                actionTitle = "もう一度",
                onAction = onRetry,
            )
        }
    }
}

@Composable
private fun ReviewView(review: Review, onToggle: (Int) -> Unit, onExecute: () -> Unit) {
    val plan = review.plan
    if (plan.message.isNotEmpty()) {
        ImasText(plan.message, role = ImasTextRole.BODY, modifier = Modifier.fillMaxWidth())
    }
    if (plan.actions.isNotEmpty()) {
        ImasSection("これからやること", count = "${plan.actions.size}件", style = ImasSectionHeaderStyle.SMALL) {
            ImasCardList {
                plan.actions.forEachIndexed { index, item ->
                    ImasSelectableRow(
                        title = item.title,
                        subtitle = item.target,
                        trailing = ImasRowTrailing.Value(trailingLabel(item, review.outcomes[index])),
                        isSelected = index in review.selected,
                        isDisabled = review.isExecuting || index in review.outcomes,
                        onClick = { onToggle(index) },
                    )
                }
            }
            Column(Modifier.padding(top = DS.Space.header), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                if (plan.actions.any { it.reach == AiActionReach.SHARED }) {
                    ImasNote(
                        "「サーバ」と付いたものは送信され、数が他の人にも見えます。やるものだけ選んでください。",
                        icon = Icons.Filled.ArrowUpward,
                    )
                }
                if (plan.actions.any { !it.preselected && it.reach != AiActionReach.SHARED }) {
                    ImasNote("外す・消す・置き換える操作は、初めは選ばれていません。", icon = Icons.Filled.Warning)
                }
                failures(review).forEach { message -> ImasNote(message, icon = Icons.Filled.Warning) }
                if (review.isExecuting) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { ImasInlineLoading(tint = DS.sys) }
                } else if (review.pending.isNotEmpty()) {
                    ImasButton(
                        title = "選んだ ${review.pending.size} 件を実行する",
                        onClick = onExecute,
                        icon = Icons.Filled.Check,
                        role = ImasButtonRole.PRIMARY,
                        size = ImasButtonSize.MEDIUM,
                    )
                }
            }
        }
    }
    if (plan.rejected > 0u) {
        ImasNote("${plan.rejected} 件の操作は、データベースで確かめられなかったので外しました。", icon = Icons.Filled.Warning)
    }
}

private fun trailingLabel(item: AiPlannedAction, outcome: Outcome?): String = when (outcome) {
    Outcome.Done -> "済み"
    is Outcome.Failed -> "失敗"
    null -> when (item.reach) {
        AiActionReach.DEVICE -> "端末"
        AiActionReach.SHARED -> "サーバ"
        AiActionReach.SCREEN -> "表示"
    }
}

private fun failures(review: Review): List<String> =
    review.outcomes.keys.sorted().mapNotNull { index ->
        val failed = review.outcomes[index] as? Outcome.Failed ?: return@mapNotNull null
        "${review.plan.actions[index].title}: ${failed.message}"
    }

