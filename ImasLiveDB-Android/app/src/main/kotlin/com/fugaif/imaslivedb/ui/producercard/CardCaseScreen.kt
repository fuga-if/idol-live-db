package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import uniffi.imas_core.cardMeetingViews
import uniffi.imas_core.CardMeetingView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardInbox
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasListSummary
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeadBar
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPortraitOshi
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasStubDate
import com.fugaif.imaslivedb.ui.designsystem.ImasStubRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipe
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeAction
import com.fugaif.imaslivedb.ui.designsystem.ImasSwipeKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardCaseEntry
import uniffi.imas_core.CardCaseSection
import uniffi.imas_core.EncodedProducerCard
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.cardCaseSections

/**
 * 名刺入れ。受け取った名刺を、受け取った公演ごと (公演の半券の下) に束ねて新しい順に並べる。
 * iOS `CardCaseView` の移植。
 *
 * 束ね方・並び順はコア (`cardCaseSections`)。行頭の帯は相手の担当の色、自分と担当が同じなら
 * 朱の札「担当被り」。行は右に引くとメモ、左に引くと削除。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardCaseScreen(onBack: () -> Unit, onOpenCard: (String) -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val scope = rememberCoroutineScope()

    var cards by remember { mutableStateOf<List<ReceivedProducerCard>>(emptyList()) }
    var decoded by remember { mutableStateOf<Map<String, ProducerCard>>(emptyMap()) }
    var sections by remember { mutableStateOf<List<CardCaseSection>>(emptyList()) }
    var directory by remember { mutableStateOf(ProducerCardDirectory()) }
    // 行の画像 (名刺の id → 画像)。ファイルを見るので読むときに IO で引く。
    var images by remember { mutableStateOf<Map<String, ReceivedCardImages>>(emptyMap()) }
    var myOshi by remember { mutableStateOf<Set<String>>(emptySet()) }
    // 束の行 (会った記録の id) → 会った記録。記録の無い名刺は名刺の id のまま (記録は無し)。
    var meetings by remember { mutableStateOf<Map<String, CardMeetingView>>(emptyMap()) }
    var myCard by remember { mutableStateOf<EncodedProducerCard?>(null) }
    var loaded by remember { mutableStateOf(false) }

    var memoTarget by remember { mutableStateOf<ReceivedProducerCard?>(null) }
    var showingExchange by remember { mutableStateOf(false) }
    var showingPaper by remember { mutableStateOf(false) }
    var addMenuOpen by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        val repo = module.producerCardRepository
        val all = repo.receivedCards()
        val map = all.mapNotNull { row -> row.card?.let { row.id to it } }.toMap()
        // 束の行は会った記録ごと (記録の無い名刺は名刺の行から)。
        val views = cardMeetingViews(repo.meetings().map { it.record })
        val met = views.map { it.cardId }.toSet()
        val entries = views.map { CardCaseEntry(it.id, it.showId, it.showDate, it.metAt) } +
            all.filter { it.id !in met }.map { CardCaseEntry(it.id, it.showId, it.showDate, it.receivedAt) }
        val record = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull()
        val built = cardCaseSections(entries)
        directory = ProducerCardDirectory.load(module, map.values.flatMap { it.oshiIdolIds }, built.mapNotNull { it.showId })
        myOshi = record?.oshiIds.orEmpty().toSet()
        if (myCard == null && record != null) {
            repo.myCard()?.let { myCard = ProducerCardAssembler.encode(it, record) }
        }
        images = withContext(Dispatchers.IO) {
            all.associate { row -> row.id to ReceivedCardImages.load(context, row.id, map[row.id]?.oshiIdolIds.orEmpty()) }
        }
        cards = all
        meetings = views.associateBy { it.id }
        decoded = map
        sections = built
        loaded = true
    }

    LaunchedEffect(Unit) { load() }
    // 紙の名刺の書類カメラを電波のあるうちに入れておく (会場は圏外のことが多い)。
    LaunchedEffect(Unit) { prefetchPaperCardCamera(context) }
    LaunchedEffect(Unit) { ProducerCardInbox.changes.collect { load() } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("名刺入れ") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                },
                actions = {
                    Box {
                        IconButton(onClick = { addMenuOpen = true }) { Icon(Icons.Filled.Add, contentDescription = "名刺を足す") }
                        DropdownMenu(expanded = addMenuOpen, onDismissRequest = { addMenuOpen = false }) {
                            DropdownMenuItem(
                                text = { Text("QR を読む") },
                                leadingIcon = { Icon(Icons.Filled.QrCodeScanner, contentDescription = null) },
                                onClick = { addMenuOpen = false; showingExchange = true }
                            )
                            DropdownMenuItem(
                                text = { Text("紙の名刺を取り込む") },
                                leadingIcon = { Icon(Icons.Filled.PhotoCamera, contentDescription = null) },
                                onClick = { addMenuOpen = false; showingPaper = true }
                            )
                        }
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).background(DS.bg)) {
            when {
                !loaded -> item { ImasInlineLoading(Modifier.padding(vertical = DS.Space.section)) }
                cards.isEmpty() -> item {
                    ImasEmptyState(
                        icon = Icons.Filled.Inbox,
                        title = "まだ名刺がありません",
                        message = "会場で相手の P名刺の QR を読むか、紙の名刺を撮って取り込むと、受け取った公演ごとにここへしまわれます。",
                        actionTitle = "QR を読む",
                        onAction = { showingExchange = true }
                    )
                }
                else -> {
                    item { ImasListSummary<String>(count = cards.size, unit = "枚") }
                    sections.forEach { section ->
                        item(key = "section_${section.showId ?: section.date}") { SectionHeader(section, directory) }
                        val rows = section.entryIds.mapNotNull { id ->
                            val meeting = meetings[id]
                            cards.firstOrNull { it.id == (meeting?.cardId ?: id) }?.let { Triple(id, it, meeting) }
                        }
                        items(rows, key = { it.first }) { (_, card, meeting) ->
                            CardCaseRow(
                                card = card,
                                meeting = meeting,
                                content = decoded[card.id],
                                images = images[card.id] ?: ReceivedCardImages(),
                                directory = directory,
                                myOshi = myOshi,
                                onOpen = { onOpenCard(card.id) },
                                onMemo = { memoTarget = card },
                                onDelete = {
                                    scope.launch {
                                        runCatching { ProducerCardInbox.delete(context, card) }
                                            .onFailure { error = it.message ?: "削除できませんでした" }
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    memoTarget?.let { CardMemoEditorSheet(card = it, onDismiss = { memoTarget = null }) }
    if (showingExchange) {
        ProducerCardExchangeSheet(myCard = myCard, initialRead = true, onDismiss = { showingExchange = false })
    }
    if (showingPaper) {
        PaperCardImportSheet(onDismiss = { showingPaper = false })
    }
    ImasErrorAlert(message = error, onDismiss = { error = null }, title = "名刺を消せませんでした")
}

/** 束の頭 (公演の半券)。 */
@Composable
private fun SectionHeader(section: CardCaseSection, directory: ProducerCardDirectory) {
    val show = section.showId?.let { directory.shows[it] }
    val count = "${section.entryIds.size}枚"
    ImasStubRow(
        date = ImasStubDate(section.date),
        title = show?.label ?: "公演に紐づかない名刺",
        subtitle = listOfNotNull(show?.venue, count).joinToString(" · "),
        modifier = Modifier
            .padding(start = DS.Space.screen, end = DS.Space.screen, top = DS.Space.gapLoose)
            .semantics { heading() }
    )
}

@Composable
private fun CardCaseRow(
    card: ReceivedProducerCard,
    meeting: CardMeetingView?,
    content: ProducerCard?,
    images: ReceivedCardImages,
    directory: ProducerCardDirectory,
    myOshi: Set<String>,
    onOpen: () -> Unit,
    onMemo: () -> Unit,
    onDelete: () -> Unit
) {
    val lead = content?.oshiIdolIds?.firstNotNullOfOrNull { directory.idols[it] }
    val shared = content?.oshiIdolIds?.any { it in myOshi } == true
    val paper = card.sourceValue == ReceivedProducerCard.Source.PAPER
    val oshiIcon = lead?.let {
        ImasRowPortraitOshi(
            label = it.shortName, seed = it.color, brand = it.brandId,
            imageUrl = images.oshi[it.id]
        )
    }
    // 自作の名刺の画像があればその小さな見本、名刺の写真があれば正方形の枠 (X のアイコンは丸。どちらも右下に
    // 担当のアイコンを重ねる)、無ければ担当のアイコン。
    val face = content?.let { c -> images.face?.takeIf { ProducerCardDisplay.design(c, it).usesFaceImage } }
    val portrait = images.portraitUrl
    val leading = when {
        face != null -> ImasRowLeading.CardFace(face.front, oshiIcon)
        portrait != null -> ImasRowLeading.Portrait(portrait, oshiIcon, round = images.portraitRound)
        oshiIcon != null -> ImasRowLeading.Avatar(
            label = oshiIcon.label, seed = oshiIcon.seed, brand = oshiIcon.brand,
            imageUrl = oshiIcon.imageUrl, isPick = true
        )
        else -> ImasRowLeading.Icon(if (paper) Icons.Filled.Description else Icons.Filled.Badge, tone = ImasIconTileTone.NEUTRAL)
    }
    var subtitle = content?.let { ProducerCardDisplay.summaryLine(it, directory) }.orEmpty()
    if (paper) subtitle = if (subtitle.isEmpty()) "紙の名刺" else "紙の名刺 · $subtitle"
    val memo = card.memo?.takeIf { it.isNotEmpty() }

    ImasSwipe(
        leading = listOf(ImasSwipeAction(kind = ImasSwipeKind.MEMO, title = "メモ", action = onMemo)),
        trailing = listOf(ImasSwipeAction(kind = ImasSwipeKind.DELETE, title = "削除", action = onDelete)),
        background = DS.surface
    ) {
        ImasRow(
            title = content?.name ?: "読めない名刺",
            subtitle = subtitle.ifEmpty { null },
            leading = leading,
            leadBar = lead?.let { ImasRowLeadBar(seed = it.color, brand = it.brandId) },
            trailing = if (shared) ImasRowTrailing.Badge("担当被り", ImasBadgeKind.NEW) else ImasRowTrailing.None,
            position = ImasRowPosition.FOLLOWING,
            modifier = Modifier.background(DS.surface).imasRowPress(onClick = onOpen),
            detail = if (memo == null && meeting?.badge == null && meeting?.ordinalLabel == null) null else {
                {
                    if (meeting?.badge != null || meeting?.ordinalLabel != null) {
                        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                            meeting.badge?.let { ImasBadge(it, kind = ImasBadgeKind.POSITIVE) }
                            meeting.ordinalLabel?.let { ImasBadge(it) }
                        }
                    }
                    memo?.let { Text(it, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color, maxLines = 1) }
                }
            }
        )
    }
}

/** 受け取った名刺のメモ。iOS `CardMemoEditorView` の移植。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardMemoEditorSheet(card: ReceivedProducerCard, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var memo by remember { mutableStateOf(card.memo.orEmpty()) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun save() {
        isSaving = true
        scope.launch {
            val trimmed = memo.trim()
            runCatching { ProducerCardInbox.update(context, card.copy(memo = trimmed.ifEmpty { null })) }
                .onSuccess { onDismiss() }
                .onFailure { error = it.message ?: "保存できませんでした" }
            isSaving = false
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        Box {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(
                    ImasSheetToolbarKind.Edit(canSave = !isSaving, isSaving = isSaving, onCancel = onDismiss, onSave = ::save),
                    title = card.card?.name ?: "メモ"
                )
                Column(Modifier.padding(horizontal = DS.Space.screen)) {
                    ImasFormCard {
                        ImasFormTextArea(
                            label = "メモ", text = memo, onTextChange = { memo = it },
                            prompt = "物販列で隣。蒼い鳥の話で盛り上がった", autofocus = true
                        )
                    }
                    ImasNote("メモは端末の中だけに置きます。相手には見えません。", Modifier.padding(top = DS.Space.gapLoose))
                }
            }
            ImasSavingOverlay(isSaving = isSaving, label = "保存中")
        }
    }
    ImasErrorAlert(message = error, onDismiss = { error = null }, title = "メモを保存できませんでした")
}
