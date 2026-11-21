package com.fugaif.imaslivedb.ui.chatgpt

import android.content.ClipboardManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.fugaif.imaslivedb.data.chatgpt.AssistantExecutor
import com.fugaif.imaslivedb.data.chatgpt.AssistantScreen
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChatAccessoryItem
import com.fugaif.imaslivedb.ui.designsystem.ImasChatAccessoryMenu
import com.fugaif.imaslivedb.ui.designsystem.ImasChatBubble
import com.fugaif.imaslivedb.ui.designsystem.ImasChatComposer
import com.fugaif.imaslivedb.ui.designsystem.ImasChatGeneratedImage
import com.fugaif.imaslivedb.ui.designsystem.ImasChatReply
import com.fugaif.imaslivedb.ui.designsystem.ImasChatThinking
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSelectableRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.share.ShareCardFiles
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.launch
import uniffi.imas_core.AiActionReach
import uniffi.imas_core.AiPlannedAction
import uniffi.imas_core.assistantAccepts
import uniffi.imas_core.assistantAcceptsMessage
import uniffi.imas_core.assistantMaxImages
import uniffi.imas_core.assistantExamples
import uniffi.imas_core.assistantMaxOrderChars

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
    onOpenScreen: (AssistantScreen) -> Unit = { AssistantScreenOpen.request(it) },
) {
    // シートは閉じたら止める。タブとは別の持ち主を作る。
    val context = LocalContext.current
    val controller = remember { AppModule.from(context).newAssistantController() }
    DisposableEffect(controller) { onDispose { controller.shutdown() } }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg,
    ) {
        AssistantScreen(initialOrder = initialOrder, isTab = false, onClose = onDismiss, controller = controller, onOpen = onOpen, onOpenScreen = onOpenScreen)
    }
}

/**
 * チャットの中身。シートの中 ([AssistantSheet]) でも、タブの中身 (`isTab`) でも同じものを出す。iOS の
 * `AssistantSheet(isTab:)` と同じ 1 つの画面で、`isTab` のときは閉じるボタンを出さず、「開く」操作のあとも閉じない
 * (タブは本体のナビに並んでいるので、行き先のタブへ移るだけでよい)。
 */
@Composable
fun AssistantScreen(
    initialOrder: String,
    isTab: Boolean,
    onClose: () -> Unit,
    controller: AssistantController,
    onOpen: (NaturalSearchKind, String) -> Unit = { kind, id -> NaturalSearchOpen.request(kind, id) },
    onOpenScreen: (AssistantScreen) -> Unit = { AssistantScreenOpen.request(it) },
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val session by module.chatGptPlanService.state.collectAsState()
    var showsHistory by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()

    val turns = controller.turns
    val isRunning = controller.isRunning
    val isExecuting = controller.isExecuting
    val maxImages = remember { assistantMaxImages().toInt() }

    val pickPhotos = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(maxImages.coerceAtLeast(2)),
    ) { controller.attach(it) }

    /** クリップボードに画像の URI があるときだけ添える。無ければ何もしない。 */
    fun pasteImages() {
        val clip = (context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.primaryClip ?: return
        val uris = (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
            .filter { context.contentResolver.getType(it)?.startsWith("image/") == true }
        controller.attach(uris)
    }

    /** 実行のあと「開く」操作があれば、行き先へ移る。タブのときは閉じるものが無い (本体の側が行き先のタブへ移る)。 */
    fun opened(result: AssistantExecutor.Opened) {
        when (result) {
            is AssistantExecutor.Opened.Detail -> { if (!isTab) onClose(); onOpen(result.target.kind, result.target.id) }
            // 一覧のタブへ移ったので、上に被さっているこのシートは閉じる。
            AssistantExecutor.Opened.List -> if (!isTab) onClose()
            // 持ち物の画面 (直した P名刺もここで見せる)。本体のナビが開くので、シートは閉じる。
            is AssistantExecutor.Opened.Screen -> { if (!isTab) onClose(); onOpenScreen(result.screen) }
        }
    }

    LaunchedEffect(Unit) {
        if (controller.turns.isEmpty() && session.canUsePlan && assistantAccepts(initialOrder)) controller.send(initialOrder)
    }
    LaunchedEffect(turns.size, isRunning) { scroll.animateScrollTo(scroll.maxValue) }

    ImasFormBackdrop(Modifier.fillMaxSize().imePadding()) {
        Column(Modifier.fillMaxSize()) {
            ImasSheetToolbar(
                ImasSheetToolbarKind.Chat(
                    onHistory = if (session.canUsePlan) ({ showsHistory = true }) else null,
                    onNew = if (session.canUsePlan) ({ controller.reset() }) else null,
                    canStartNew = turns.isNotEmpty() && !isRunning && !isExecuting,
                    canOpenHistory = !isRunning && !isExecuting,
                    onClose = if (isTab) null else ({ onClose() }),
                ),
                title = "チャット",
            )
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
                    turns.isEmpty() -> Examples(onExample = { controller.send(it) })
                    else -> {
                        turns.forEach { turn ->
                            TurnView(
                                turn = turn,
                                onRetry = { controller.retry(turn) },
                                onToggle = { index -> controller.toggle(turn.key, index) },
                                onExecute = { controller.execute(turn.key) { result -> opened(result) } },
                            )
                        }
                    }
                }
            }
            if (session.canUsePlan) {
                ImasChatComposer(
                    prompt = "聞きたいこと・やってほしいこと",
                    text = controller.text,
                    onTextChange = { new ->
                        val limit = assistantMaxOrderChars().toInt()
                        controller.text = if (new.length > limit) new.take(limit) else new
                    },
                    canSend = !isRunning && assistantAcceptsMessage(controller.text, controller.attachments.size.toUInt()),
                    onSend = { controller.send(controller.text) },
                    attachments = controller.attachments,
                    onRemoveAttachment = { index -> controller.removeAttachment(index) },
                    isRunning = isRunning,
                    onStop = { controller.cancel() },
                    accessory = {
                        ImasChatAccessoryMenu(
                            items = listOf(
                                ImasChatAccessoryItem("写真を選ぶ") {
                                    pickPhotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                },
                                ImasChatAccessoryItem("貼り付ける") { pasteImages() },
                            ),
                            enabled = controller.attachments.size < maxImages,
                        )
                    },
                )
            }
        }
    }
    if (showsHistory) {
        ChatHistorySheet(
            currentId = controller.sessionId,
            onDismiss = { showsHistory = false },
            onOpen = { controller.openSession(it) },
            onDelete = { id -> if (id == controller.sessionId) controller.reset() },
        )
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
    turn: AssistantTurn,
    onRetry: () -> Unit,
    onToggle: (Int) -> Unit,
    onExecute: () -> Unit,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        ImasChatBubble(turn.order, images = turn.images)
        when (val state = turn.state) {
            is AssistantTurnState.Running -> ImasChatThinking(state.label)
            is AssistantTurnState.Done -> ReviewView(state.review, onToggle, onExecute)
            is AssistantTurnState.Restored -> {
                if (state.imageCount > 0u) {
                    ImasNote("画像 ${state.imageCount} 枚を添えました (画像は残していません)。", icon = Icons.Filled.Image)
                }
                RestoredView(state)
            }
            is AssistantTurnState.Failed -> ImasNotice(
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
private fun ReviewView(review: AssistantReview, onToggle: (Int) -> Unit, onExecute: () -> Unit) {
    val plan = review.plan
    if (plan.message.isNotEmpty()) {
        ImasChatReply(plan.message, modifier = Modifier.fillMaxWidth())
    }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    review.images.forEach { image ->
        ImasChatGeneratedImage(image, onShare = { scope.launch { ShareCardFiles.share(context, image, "chat_image") } })
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
                if (plan.externalContent) {
                    ImasNote("Web や X を読んだ番の操作は、初めは 1 つも選んでいません。頼んだものだけ選んでください。", icon = Icons.Filled.Warning)
                } else if (plan.actions.any { !it.preselected && it.reach != AiActionReach.SHARED }) {
                    ImasNote("外す・消す・置き換える・もう入っていそうな操作は、初めは選ばれていません。", icon = Icons.Filled.Warning)
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

/** 履歴から読み直した番。返事と、そのとき頼んだことの記録。 */
@Composable
private fun RestoredView(state: AssistantTurnState.Restored) {
    if (state.reply.isNotEmpty()) {
        ImasChatReply(state.reply, modifier = Modifier.fillMaxWidth())
    }
    if (state.actions.isNotEmpty()) {
        ImasSection("頼んだこと", count = "${state.actions.size}件", style = ImasSectionHeaderStyle.SMALL) {
            ImasCardList {
                state.actions.forEach { action ->
                    ImasRow(
                        title = action.title,
                        subtitle = action.target,
                        trailing = ImasRowTrailing.Value(if (action.done) "済み" else "未実行"),
                        density = ImasRowDensity.COMPACT,
                    )
                }
            }
            if (state.actions.any { !it.done }) {
                ImasNote(
                    "読み直した会話の操作は、ここからは実行できません。やるなら、もう一度頼んでください。",
                    modifier = Modifier.padding(top = DS.Space.header),
                    icon = Icons.Filled.Warning,
                )
            }
        }
    }
}

private fun trailingLabel(item: AiPlannedAction, outcome: AssistantActionOutcome?): String = when (outcome) {
    AssistantActionOutcome.Done -> "済み"
    is AssistantActionOutcome.Failed -> "失敗"
    null -> when (item.reach) {
        AiActionReach.DEVICE -> "端末"
        AiActionReach.SHARED -> "サーバ"
        AiActionReach.SCREEN -> "表示"
    }
}

private fun failures(review: AssistantReview): List<String> =
    review.outcomes.keys.sorted().mapNotNull { index ->
        val failed = review.outcomes[index] as? AssistantActionOutcome.Failed ?: return@mapNotNull null
        "${review.plan.actions[index].title}: ${failed.message}"
    }

