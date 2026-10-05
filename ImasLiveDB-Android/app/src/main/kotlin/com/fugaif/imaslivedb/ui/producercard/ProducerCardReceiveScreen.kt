package com.fugaif.imaslivedb.ui.producercard

import android.content.Context
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.model.ProducerCardShowInfo
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import com.fugaif.imaslivedb.data.producercard.IncomingProducerCard
import com.fugaif.imaslivedb.data.producercard.NearbyCardExchange
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardInbox
import com.fugaif.imaslivedb.data.producercard.ProducerCardMyRecord
import com.fugaif.imaslivedb.data.repository.LedgerShowOption
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormLink
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowPosition
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasValueRow
import com.fugaif.imaslivedb.ui.ledger.LedgerShowPickerSheet
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardFileImage
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.decodeProducerCard
import uniffi.imas_core.producerCardCommon

/** 公演の候補 → 名刺に出す公演 (会場は候補に無いので出さない)。 */
internal fun LedgerShowOption.toShowInfo() =
    ProducerCardShowInfo(id = id, eventId = eventId, date = date, label = label, venue = null)

/**
 * 受け取りの確認。相手の名刺を見せ、受け取った公演を確かめて ✓ で名刺入れへ。iOS `ProducerCardReceiveView` の移植。
 *
 * QR を読んだとき・名刺のリンク (App Links) を開いたとき・名刺ファイルを開いたときの共通の画面。
 * QR から来たときは近くの相手の端末から担当の画像が届くのを待つ (届かなくても保存できる)。
 *
 * @param nearby 近くの相手から画像を受け取る口 (QR を読んだときだけ)。
 * @param onDone 終わったとき (しまえたら相手の名前と名刺入れの id、やめたら null)。
 */
@Composable
fun ProducerCardReceiveContent(
    incoming: IncomingProducerCard,
    nearby: NearbyCardExchange?,
    onDone: (Pair<String, String>?) -> Unit
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val scope = rememberCoroutineScope()
    val haptics = rememberImasHaptics()
    val card: ProducerCard? = remember(incoming.payload) { decodeProducerCard(incoming.payload) }

    var record by remember { mutableStateOf<ProducerCardMyRecord?>(null) }
    var directory by remember { mutableStateOf(ProducerCardDirectory()) }
    var images by remember { mutableStateOf<List<CardFileImage>>(emptyList()) }
    var imageUrls by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var show by remember { mutableStateOf<ProducerCardShowInfo?>(null) }
    var showOptions by remember { mutableStateOf<List<LedgerShowOption>>(emptyList()) }
    var pickingShow by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    /** 届いた画像をプレビューできるよう一時フォルダに書く (しまうときは名刺入れの置き場へ)。 */
    suspend fun accept(new: List<CardFileImage>) {
        if (new.isEmpty()) return
        images = new
        imageUrls = writePreviewImages(context, new)
    }

    LaunchedEffect(incoming) {
        accept(incoming.images)
        nearby?.received?.value?.takeIf { it.payload == incoming.payload }?.let { accept(it.images) }
        val rec = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull()
        record = rec
        showOptions = runCatching { module.expenseRepository.attendedShowOptions() }.getOrDefault(emptyList())
        val candidate = rec?.let { ProducerCardInbox.exchangeShowCandidates(it).firstOrNull() }
        val idols = card?.oshiIdolIds.orEmpty() + rec?.oshiIds.orEmpty()
        directory = ProducerCardDirectory.load(module, idols, listOfNotNull(candidate, card?.nextShowId))
        if (show == null && candidate != null) show = directory.shows[candidate]
    }

    // 近くの相手から画像が届いたら差し替える。
    val nearbyReceived = nearby?.received?.collectAsState()?.value
    LaunchedEffect(nearbyReceived) {
        nearbyReceived?.takeIf { it.payload == incoming.payload }?.let { accept(it.images) }
    }
    val phase = nearby?.phase?.collectAsState()?.value

    fun save() {
        val c = card ?: return
        isSaving = true
        scope.launch {
            try {
                val saved = ProducerCardInbox.store(context, incoming.payload, images, ReceivedProducerCard.Source.APP, show)
                haptics.impactMedium()
                onDone(c.name to saved.id)
            } catch (e: Exception) {
                error = e.message ?: "保存できませんでした"
            } finally {
                isSaving = false
            }
        }
    }

    Box {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
            ImasSheetToolbar(
                ImasSheetToolbarKind.Edit(
                    canSave = card != null && !isSaving, isSaving = isSaving,
                    onCancel = { onDone(null) }, onSave = ::save
                ),
                title = "名刺を受け取る"
            )
            Column(
                Modifier.padding(horizontal = DS.Space.screen),
                verticalArrangement = Arrangement.spacedBy(DS.Space.section)
            ) {
                if (card != null) {
                    ProducerCardView(
                        card = card, directory = directory, sharedWith = record?.oshiIds.orEmpty().toSet(),
                        imageUrl = { imageUrls[it] }
                    )
                    record?.let { CommonSummary(card, it, directory) }
                    ImasFormCard {
                        ImasFormLink(
                            label = "受け取った公演", imprint = "SHOW", icon = Icons.Filled.ConfirmationNumber,
                            value = show?.label, placeholder = "公演に紐づけない", onClick = { pickingShow = true }
                        )
                    }
                    if (nearby != null && incoming.via == IncomingProducerCard.Via.SCAN) {
                        ImasNote(nearbyNote(phase, images.isEmpty()))
                    }
                } else {
                    ImasCard {
                        ImasEmptyState(
                            icon = Icons.Filled.ErrorOutline,
                            title = "名刺を読めませんでした",
                            message = "新しい版のアプリで作られた名刺かもしれません。アプリを最新にしてからもう一度読んでください。"
                        )
                    }
                }
            }
        }
        ImasSavingOverlay(isSaving = isSaving, label = "保存中")
    }

    if (pickingShow) {
        LedgerShowPickerSheet(
            options = showOptions,
            onPick = { option ->
                show = option?.toShowInfo()
                pickingShow = false
            },
            onDismiss = { pickingShow = false }
        )
    }
    ImasErrorAlert(message = error, onDismiss = { error = null }, title = "名刺入れに入れられませんでした")
}

private fun nearbyNote(phase: NearbyCardExchange.Phase?, noImages: Boolean): String = when (phase) {
    NearbyCardExchange.Phase.SEARCHING, NearbyCardExchange.Phase.CONNECTED, NearbyCardExchange.Phase.WAITING ->
        "近くの相手の Android から担当の画像を受け取っています…。繋がると、あなたの名刺も相手の名刺入れに渡ります (× でやめると相手には渡りません)。"
    NearbyCardExchange.Phase.RECEIVED ->
        if (noImages) "相手の名刺を受け取りました (担当の画像は設定されていません)。" else "担当の画像を受け取りました。"
    else ->
        "近くに相手の Android が見つかりませんでした。名刺は QR の中身だけで保存できます。担当の画像は、相手に「名刺ファイルで送る」で送ってもらうと届きます。"
}

/** 受け取りの確認の「あなたとの共通点」(同じ担当・同じ公演にいた回数)。共通点はコア。 */
@Composable
private fun CommonSummary(card: ProducerCard, record: ProducerCardMyRecord, directory: ProducerCardDirectory) {
    val common = remember(card, record) { producerCardCommon(card, record.oshiIds, record.summary.attendedPast) }
    val sharedNames = common.sharedOshiIds.mapNotNull { directory.idols[it]?.name }
    if (sharedNames.isEmpty() && common.sharedShowIds.isEmpty()) return
    ImasSection("あなたとの共通点", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            if (sharedNames.isNotEmpty()) {
                ImasValueRow(key = "同じ担当", value = sharedNames.joinToString("・"), position = ImasRowPosition.FIRST)
            }
            if (common.sharedShowIds.isNotEmpty()) {
                ImasValueRow(
                    key = "同じ公演にいた", value = "${common.sharedShowIds.size}回", monospaced = true,
                    position = if (sharedNames.isEmpty()) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                )
            }
        }
    }
}

/** 届いた画像を一時フォルダに書き、担当の id → 画面に渡す在り処を返す。 */
private suspend fun writePreviewImages(context: Context, images: List<CardFileImage>): Map<String, String> =
    withContext(Dispatchers.IO) {
        val dir = File(File(context.cacheDir, "producer_card_incoming"), UUID.randomUUID().toString()).apply { mkdirs() }
        images.mapIndexedNotNull { i, image ->
            val file = File(dir, "$i.jpg")
            runCatching { file.writeBytes(image.jpeg) }.getOrNull() ?: return@mapIndexedNotNull null
            image.idolId to Uri.fromFile(file).toString()
        }.toMap()
    }

/** 名刺のリンク・名刺ファイルを開いたときのシート (アプリのどこからでも)。iOS `ProducerCardReceiveSheet` と対。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProducerCardReceiveSheet(incoming: IncomingProducerCard, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        ProducerCardReceiveContent(incoming = incoming, nearby = null, onDone = { onDismiss() })
    }
}

/**
 * アプリのルートに置く、外から届いた名刺の受け口 (iOS `ContentView` の `incomingCard` / 名刺ファイルの知らせ)。
 * 名刺交換の画面が開いている間はその中で受け取るので、ここには来ない ([ProducerCardIncoming.present])。
 */
@Composable
fun ProducerCardIncomingHost() {
    val pending = com.fugaif.imaslivedb.data.producercard.ProducerCardIncoming.pending.collectAsState().value
    val fileFailed = com.fugaif.imaslivedb.data.producercard.ProducerCardIncoming.fileFailed.collectAsState().value
    pending?.let { incoming ->
        ProducerCardReceiveSheet(incoming) { com.fugaif.imaslivedb.data.producercard.ProducerCardIncoming.consume() }
    }
    if (fileFailed) {
        com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert(
            message = "P名刺のファイルではないか、壊れています。もう一度送ってもらってください。",
            onDismiss = { com.fugaif.imaslivedb.data.producercard.ProducerCardIncoming.dismissFileFailed() },
            title = "名刺ファイルを開けませんでした"
        )
    }
}
