package com.fugaif.imaslivedb.ui.producercard

import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.ProducerCardShowInfo
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.data.producercard.ProducerCardInbox
import com.fugaif.imaslivedb.data.repository.LedgerShowOption
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasFormCard
import com.fugaif.imaslivedb.ui.designsystem.ImasFormField
import com.fugaif.imaslivedb.ui.designsystem.ImasFormLink
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextArea
import com.fugaif.imaslivedb.ui.designsystem.ImasFormTextField
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasSavingOverlay
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.ledger.LedgerShowPickerSheet
import com.fugaif.imaslivedb.ui.songs.IdolMultiPickerPage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import kotlinx.coroutines.launch
import uniffi.imas_core.CardLink
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.ScannedCode
import uniffi.imas_core.cardLinkView
import uniffi.imas_core.classifyScannedCode
import uniffi.imas_core.producerCardLimits
import uniffi.imas_core.producerCardPayload

/**
 * 紙の名刺を取り込む。iOS `PaperCardImportView` の移植。表と裏を撮り (名刺の形に切り抜かれる)、刷られた QR を読む。
 *
 * - アプリの名刺の QR が刷られていれば、その名刺をそのまま入れる (写真も添える)。
 * - X などのリンクの QR なら、名刺のリンクにする。
 * - 文字は読まない (名前は自分で入れる方が速くて確実)。担当はアイドルの選択で付ける。
 *
 * 紙の名刺もコアで P名刺の形 (`producerCardPayload`) にして、同じ名刺入れに入れる。写真は端末の中だけ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaperCardImportSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val scope = rememberCoroutineScope()
    val limits = remember { producerCardLimits() }

    var photos by remember { mutableStateOf<List<Bitmap>>(emptyList()) }
    var isReading by remember { mutableStateOf(false) }

    /** 刷られていたアプリの名刺。 */
    var appCard by remember { mutableStateOf<Pair<String, ProducerCard>?>(null) }
    var links by remember { mutableStateOf<List<CardLink>>(emptyList()) }
    var otherCodes by remember { mutableStateOf<List<String>>(emptyList()) }

    var name by remember { mutableStateOf("") }
    var oshiIds by remember { mutableStateOf<List<String>>(emptyList()) }
    var allIdols by remember { mutableStateOf<List<Idol>>(emptyList()) }
    var brands by remember { mutableStateOf<List<Brand>>(emptyList()) }
    var pickingOshi by remember { mutableStateOf(false) }

    var show by remember { mutableStateOf<ProducerCardShowInfo?>(null) }
    var showOptions by remember { mutableStateOf<List<LedgerShowOption>>(emptyList()) }
    var pickingShow by remember { mutableStateOf(false) }
    var memo by remember { mutableStateOf("") }

    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        showOptions = runCatching { module.expenseRepository.attendedShowOptions() }.getOrDefault(emptyList())
        val record = runCatching { ProducerCardAssembler.loadMyRecord(module) }.getOrNull()
        val candidate = record?.let { ProducerCardInbox.exchangeShowCandidates(it).firstOrNull() }
        show = showOptions.firstOrNull { it.id == candidate }?.toShowInfo()
        brands = runCatching { module.statsRepository.fetchBrands() }.getOrDefault(emptyList())
        allIdols = runCatching { module.idolRepository.fetchIdols() }.getOrDefault(emptyList())
    }

    /** 撮った写真から QR を拾い、名刺 / リンク / それ以外に分ける (分け方はコア)。 */
    fun accept(uris: List<Uri>) {
        if (uris.isEmpty()) return
        scope.launch {
            isReading = true
            val images = uris.take(2).mapNotNull { PaperCardCodeReader.loadBitmap(context, it) }
            if (images.isEmpty()) {
                isReading = false
                return@launch
            }
            photos = images
            val codes = PaperCardCodeReader.codes(images)
            isReading = false
            var foundCard: Pair<String, ProducerCard>? = null
            val foundLinks = mutableListOf<CardLink>()
            val others = mutableListOf<String>()
            for (code in codes) {
                when (val kind = classifyScannedCode(code)) {
                    is ScannedCode.Card -> if (foundCard == null) foundCard = kind.payload to kind.card
                    is ScannedCode.Link -> {
                        val link = kind.link
                        if (link != null && link !in foundLinks && foundLinks.size < limits.maxLinks.toInt()) {
                            foundLinks += link
                        } else if (link == null) {
                            others += kind.url
                        }
                    }
                    is ScannedCode.Text -> others += kind.text
                }
            }
            appCard = foundCard
            links = foundLinks
            otherCodes = others
        }
    }

    val openCamera = rememberPaperCardCamera(onFinish = ::accept)
    val pickPhotos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(2)) { accept(it) }

    val trimmedName = name.trim()
    val canSave = photos.isNotEmpty() && !isSaving &&
        (appCard != null || (trimmedName.isNotEmpty() && trimmedName.length <= limits.maxNameChars.toInt()))

    fun save() {
        isSaving = true
        scope.launch {
            try {
                val found = appCard
                val payload = found?.first ?: producerCardPayload(
                    ProducerCard(
                        name = trimmedName, message = "", sinceYear = null, oshiIdolIds = oshiIds, links = links,
                        showCount = null, songCount = null, nextShowId = null, attended = emptyList(),
                        attendedTruncated = false, issuedOn = JstDay.today()
                    )
                )
                // QR の無い紙の名刺は名前だけで中身を作るので、同じ名前の別人と重ねない (常に新しく足す)。
                var saved = ProducerCardInbox.store(
                    context, payload, emptyList(), ReceivedProducerCard.Source.PAPER, show, dedupe = found != null
                )
                val trimmedMemo = memo.trim()
                if (trimmedMemo.isNotEmpty() && saved.memo == null) {
                    saved = saved.copy(memo = trimmedMemo)
                    ProducerCardInbox.update(context, saved)
                }
                photos.zip(ProducerCardFiles.Side.entries).forEach { (image, side) ->
                    ProducerCardFiles.savePhoto(context, image, saved.id, side)
                }
                ProducerCardInbox.changed()
                onDismiss()
            } catch (e: Exception) {
                error = e.message ?: "保存できませんでした"
            } finally {
                isSaving = false
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg
    ) {
        if (pickingOshi) {
            IdolMultiPickerPage(
                idols = allIdols,
                brands = brands,
                selected = oshiIds.toSet(),
                onBack = { pickingOshi = false },
                onToggle = { id ->
                    // 選んだ順に並べる (前からいた人を先に、増えた人を後ろに)。上限は名刺の担当の数。
                    oshiIds = if (id in oshiIds) oshiIds - id
                    else (oshiIds + id).take(limits.maxOshi.toInt())
                },
                onClear = { oshiIds = emptyList() }
            )
            return@ModalBottomSheet
        }
        Box {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(
                    ImasSheetToolbarKind.Edit(canSave = canSave, isSaving = isSaving, onCancel = onDismiss, onSave = ::save),
                    title = "紙の名刺"
                )
                Column(
                    Modifier.padding(horizontal = DS.Space.screen),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
                ) {
                    ImasFormCard {
                        ImasFormField(label = "表と裏", imprint = "PHOTO") {
                            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
                                if (photos.isNotEmpty()) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                                        photos.forEachIndexed { index, image ->
                                            ImasCard(
                                                style = ImasCardStyle.INSET,
                                                padding = DS.Space.none,
                                                modifier = Modifier.weight(1f).semantics {
                                                    contentDescription = if (index == 0) "表の写真" else "裏の写真"
                                                }
                                            ) {
                                                Image(
                                                    bitmap = image.asImageBitmap(),
                                                    contentDescription = null,
                                                    contentScale = ContentScale.FillWidth,
                                                    modifier = Modifier.fillMaxWidth()
                                                )
                                            }
                                        }
                                    }
                                }
                                if (cardCameraAvailable(context)) {
                                    IconLabel(Icons.Filled.PhotoCamera, if (photos.isEmpty()) "カメラで撮る" else "撮り直す", onClick = openCamera)
                                }
                                IconLabel(Icons.Filled.PhotoLibrary, "写真から選ぶ") {
                                    pickPhotos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                }
                            }
                        }
                    }

                    if (photos.isNotEmpty()) {
                        FoundCard(appCard?.second, links, otherCodes)
                        if (appCard == null) {
                            ImasFormCard {
                                ImasFormTextField(
                                    label = "名前", imprint = "NAME", text = name, onTextChange = { name = it },
                                    prompt = "かるたP",
                                    error = if (name.length > limits.maxNameChars.toInt()) "${limits.maxNameChars}文字までです" else null
                                )
                                ImasFormField(label = "担当", imprint = "OSHI") {
                                    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                                        val byId = allIdols.associateBy { it.id }
                                        oshiIds.mapNotNull { byId[it] }.forEach { idol ->
                                            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                                                ImasAvatar(
                                                    label = idol.shortName, seed = idol.color, brand = idol.brandId,
                                                    size = DS.Size.avatarSmall, isPick = true
                                                )
                                                Text(idol.name, style = ImasTextRole.ROW_TITLE.style, color = DS.ink)
                                            }
                                        }
                                        IconLabel(Icons.Filled.Add, if (oshiIds.isEmpty()) "担当を付ける" else "担当を選び直す") {
                                            pickingOshi = true
                                        }
                                    }
                                }
                            }
                        }
                        ImasFormCard {
                            ImasFormLink(
                                label = "受け取った公演", imprint = "SHOW", icon = Icons.Filled.ConfirmationNumber,
                                value = show?.label, placeholder = "公演に紐づけない", onClick = { pickingShow = true }
                            )
                            ImasFormTextArea(label = "メモ", text = memo, onTextChange = { memo = it }, prompt = "どこで会ったか・何を話したか")
                        }
                    }
                    ImasNote("写真は端末の中だけに置きます。文字は読み取らないので、名前は入力してください。")
                }
            }
            ImasSavingOverlay(isSaving = isSaving || isReading, label = if (isReading) "QR を探しています" else "保存中")
        }
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

@Composable
private fun FoundCard(appCard: ProducerCard?, links: List<CardLink>, otherCodes: List<String>) {
    ImasFormCard {
        ImasFormField(label = "読み取れたもの", imprint = "FOUND") {
            Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                appCard?.let { Text("P名刺の QR: ${it.name}", style = ImasTextRole.VALUE.style, color = DS.ink) }
                links.forEach { link ->
                    val view = cardLinkView(link)
                    Text("${view.label} ${view.display}", style = ImasTextRole.VALUE.style, color = DS.ink)
                }
                otherCodes.forEach { Text(it, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color, maxLines = 2) }
                if (appCard == null && links.isEmpty() && otherCodes.isEmpty()) {
                    Text("QR は見つかりませんでした", style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color)
                }
            }
        }
    }
}

/** 記号 + 文字の押せる行 (「カメラで撮る」「写真から選ぶ」)。 */
@Composable
private fun IconLabel(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier.imasRowPress(onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = DS.ink)
        Text(label, style = ImasTextRole.ROW_LABEL.style, color = DS.ink)
    }
}
