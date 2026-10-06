package com.fugaif.imaslivedb.ui.producercard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import coil3.compose.AsyncImage
import com.fugaif.imaslivedb.data.model.ProducerCardShowInfo
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardInbox
import com.fugaif.imaslivedb.data.repository.LedgerShowOption
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasCardStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasValueRow
import com.fugaif.imaslivedb.ui.ledger.LedgerShowPickerSheet
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCard
import com.fugaif.imaslivedb.ui.designsystem.ImasProducerCardDetails
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardCommon
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.producerCardCommon

/**
 * 受け取った名刺 1 枚。iOS `ReceivedCardDetailView` の移植。相手の名刺 (自分の名刺と同じ部品)・
 * あなたとの共通点・メモ・紙の名刺の写真。
 *
 * 共通点 (同じ担当・同じ公演にいた回数・はじめて同じ会場) はコア (`producerCardCommon`)。
 * 公演の行を押すとその公演のセトリへ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceivedCardDetailScreen(
    cardId: String,
    onBack: () -> Unit,
    onOpenIdol: (String) -> Unit,
    onOpenShow: (String) -> Unit
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()

    var row by remember { mutableStateOf<ReceivedProducerCard?>(null) }
    var card by remember { mutableStateOf<ProducerCard?>(null) }
    var common by remember { mutableStateOf<CardCommon?>(null) }
    var directory by remember { mutableStateOf(ProducerCardDirectory()) }
    var images by remember { mutableStateOf(ReceivedCardImages()) }
    var myOshi by remember { mutableStateOf<Set<String>>(emptySet()) }
    var showOptions by remember { mutableStateOf<List<LedgerShowOption>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }

    var editingMemo by remember { mutableStateOf(false) }
    var pickingShow by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        val found = module.producerCardRepository.receivedCard(cardId)
        if (found == null) {
            row = null
            loaded = true
            return
        }
        val decoded = found.card
        val record = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull()
        val c = if (decoded != null && record != null) {
            producerCardCommon(decoded, record.oshiIds, record.summary.attendedPast)
        } else null
        val showIds = listOfNotNull(found.showId, decoded?.nextShowId, c?.sharedShowIds?.firstOrNull())
        directory = ProducerCardDirectory.load(module, decoded?.oshiIdolIds.orEmpty(), showIds)
        showOptions = runCatching { module.expenseRepository.attendedShowOptions() }.getOrDefault(emptyList())
        images = withContext(Dispatchers.IO) { ReceivedCardImages.load(context, found.id, decoded?.oshiIdolIds.orEmpty()) }
        myOshi = record?.oshiIds.orEmpty().toSet()
        common = c
        row = found
        card = decoded
        loaded = true
    }

    LaunchedEffect(cardId) { load() }
    LaunchedEffect(cardId) { ProducerCardInbox.changes.collect { load() } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(card?.name ?: "名刺") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る") }
                },
                actions = {
                    Box {
                        IconButton(onClick = { menuOpen = true }) { Icon(Icons.Filled.MoreHoriz, contentDescription = "その他") }
                        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                            DropdownMenuItem(
                                text = { Text("受け取った公演を変える") },
                                leadingIcon = { Icon(Icons.Filled.ConfirmationNumber, contentDescription = null) },
                                onClick = { menuOpen = false; pickingShow = true }
                            )
                            DropdownMenuItem(
                                text = { Text("この名刺を削除", color = DS.danger) },
                                leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null, tint = DS.danger) },
                                onClick = { menuOpen = false; confirmDelete = true }
                            )
                        }
                    }
                }
            )
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            val r = row
            val c = card
            when {
                r != null && c != null -> {
                    val content = rememberProducerCardContent(
                        card = c, directory = directory, sharedWith = myOshi,
                        imageUrls = images.oshi,
                        portraitUrl = images.portraitUrl,
                        portraitSource = images.portraitSource,
                        face = images.face,
                        payload = r.payload
                    )
                    ImasProducerCard(content)
                    ImasProducerCardDetails(
                        content,
                        onOpenLink = { link -> runCatching { uriHandler.openUri(link.url) } },
                        onOpenOshi = { oshi -> onOpenIdol(oshi.id) }
                    )
                    CommonSection(r, common, directory, onOpenShow, onPickShow = { pickingShow = true })
                    ImasSection("メモ", actionTitle = "編集", actionIcon = Icons.Filled.Edit, onAction = { editingMemo = true }) {
                        ImasCard {
                            val memo = r.memo
                            Text(
                                memo ?: "どこで会ったか・何を話したかを残しておけます。",
                                style = if (memo == null) ImasTextRole.NOTE.style else ImasTextRole.BODY.style,
                                color = if (memo == null) ImasTextRole.NOTE.color else ImasTextRole.BODY.color,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                    PhotoSection(images.paperPhotos)
                }
                loaded -> ImasCard {
                    ImasEmptyState(
                        icon = Icons.Filled.ErrorOutline,
                        title = "名刺を読めませんでした",
                        message = "新しい版のアプリで作られた名刺かもしれません。アプリを最新にすると読めることがあります。"
                    )
                }
                else -> ImasInlineLoading()
            }
        }
    }

    if (editingMemo) row?.let { CardMemoEditorSheet(card = it, onDismiss = { editingMemo = false }) }
    if (pickingShow) {
        LedgerShowPickerSheet(
            options = showOptions,
            onPick = { option ->
                pickingShow = false
                val current = row ?: return@LedgerShowPickerSheet
                scope.launch {
                    runCatching { ProducerCardInbox.update(context, current.copy(showId = option?.id, showDate = option?.date)) }
                        .onFailure { error = it.message ?: "保存できませんでした" }
                }
            },
            onDismiss = { pickingShow = false }
        )
    }
    ImasConfirmDestructive(
        title = "この名刺を削除しますか？",
        isPresented = confirmDelete,
        onDismiss = { confirmDelete = false },
        message = "名刺入れから消えます。写真と受け取った画像も消えます。",
        onConfirm = {
            confirmDelete = false
            val current = row ?: return@ImasConfirmDestructive
            scope.launch {
                runCatching { ProducerCardInbox.delete(context, current) }
                    .onSuccess { onBack() }
                    .onFailure { error = it.message ?: "削除できませんでした" }
            }
        }
    )
    ImasErrorAlert(message = error, onDismiss = { error = null }, title = "名刺を直せませんでした")
}

@Composable
private fun CommonSection(
    row: ReceivedProducerCard,
    common: CardCommon?,
    directory: ProducerCardDirectory,
    onOpenShow: (String) -> Unit,
    onPickShow: () -> Unit
) {
    val sharedNames = common?.sharedOshiIds.orEmpty().mapNotNull { directory.idols[it]?.name }
    val sharedShows = common?.sharedShowIds.orEmpty()
    val first: ProducerCardShowInfo? = sharedShows.firstOrNull()?.let { directory.shows[it] }
    val received = row.showId?.let { directory.shows[it] }
    ImasSection("あなたとの共通点") {
        ImasCardList {
            ImasValueRow(
                key = "同じ担当", value = if (sharedNames.isEmpty()) "なし" else sharedNames.joinToString("・"),
                position = ImasRowPosition.FIRST
            )
            ImasValueRow(key = "同じ公演にいた", value = "${sharedShows.size}回", monospaced = true, position = ImasRowPosition.FOLLOWING)
            if (first != null) {
                ImasValueRow(
                    key = "はじめて同じ会場", value = "${first.date.take(4)} · ${first.label}", isLink = true,
                    position = ImasRowPosition.FOLLOWING, onClick = { onOpenShow(first.id) }
                )
            }
            if (received != null) {
                ImasValueRow(
                    key = "受け取った公演", value = received.label, isLink = true,
                    position = ImasRowPosition.FOLLOWING, onClick = { onOpenShow(received.id) }
                )
            } else {
                ImasValueRow(
                    key = "受け取った公演", value = "選ぶ", isLink = true,
                    position = ImasRowPosition.FOLLOWING, onClick = onPickShow
                )
            }
        }
    }
}

@Composable
private fun PhotoSection(photos: List<String>) {
    if (photos.isEmpty()) return
    ImasSection("紙の名刺", footer = "写真は端末の中だけに置いています。") {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            photos.forEach { url ->
                ImasCard(style = ImasCardStyle.INSET) {
                    AsyncImage(
                        model = url,
                        contentDescription = "紙の名刺の写真",
                        contentScale = ContentScale.FillWidth,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }
    }
}
